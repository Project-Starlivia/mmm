// 文書の頭（YAML frontmatter）に置く設定。
//
// **宣言の持ち主は .md 自身**。以前は window.prompt で聞いて IndexedDB に
// 置いていたので、別マシンで開くと「その md の画像がどこにあるか」だけが
// 消えていた（実体はただの .md、と言い切っているのに）。
//
// ここは純関数だけ。DOM もコアも知らない。「どこからどこまでが頭か」は
// コアが答える（DocView.head）。ここが答えるのは、その中の 1 行の綴りだけ。
//
// **YAML パーサは入れない。** 読んで書き戻すと、他ツールが書いたコメント・
// 引用符・キーの順序が消える。「未編集行のバイト列は決して再整形されない」
// というコアの約束を、TS 側で破ることになる。読むのは 1 キー、書くのも 1 行。

import type { DocView, HeadSpan } from "../coreApi.ts";
import type { TextEdit } from "../edits.ts";
import { bare, imageDest, parseImage } from "../map/cards.ts";

/** 頭に置く「画像フォルダの場所」の設定名。**綴りはここ 1 つ** */
export const IMAGE_FOLDER = "image-folder";

// トップレベルのキーだけを見る。字下げされた `  image-folder:` は
// 別のキーの子なので、この文書の設定ではない
const KEY_LINE = new RegExp(`^${IMAGE_FOLDER}[ \\t]*:(.*)$`);

/** 中身の範囲。中身が無い頭では bodyTo が bodyFrom より手前にある */
const bodyEnd = (head: HeadSpan): number => Math.max(head.bodyFrom, head.bodyTo);

/**
 * YAML の値 1 つ。**コメントを落としてから**引用符を剥がす。
 *
 * 逆順（引用符を先に剥がす）だと `"./My Images/" # main` のように
 * 両方が同時に来る形を取りこぼす — 末尾が `"` でなく `n`（`main` の頭
 * 文字が来る前）になるので引用符ぶんの分岐に入れず、コメント落としの
 * 分岐に流れて `"..."` を剥がさないまま返してしまっていた。
 */
function unquote(raw: string): string {
  const hash = raw.search(/\s#/);
  const v = (hash === -1 ? raw : raw.slice(0, hash)).trim();
  const q = v[0];
  if (v.length >= 2 && (q === '"' || q === "'") && v[v.length - 1] === q) {
    const inner = v.slice(1, -1);
    return q === '"' ? inner.replace(/\\(["\\])/g, "$1") : inner;
  }
  return v;
}

/** 値を YAML の 1 行として書く形。囲む必要が無ければ裸で書く。 */
function quote(value: string): string {
  if (!/[\s#:]/.test(value)) return value;
  return `"${value.replace(/(["\\])/g, "\\$1")}"`;
}

/** 頭から画像フォルダの宣言を読む。無ければ null */
export function imageFolder(text: string, head: HeadSpan | null): string | null {
  if (!head) return null;
  for (const line of text.slice(head.bodyFrom, bodyEnd(head)).split("\n")) {
    const m = KEY_LINE.exec(line);
    if (m) return unquote(m[1]);
  }
  return null;
}

/**
 * 宣言を書き換える編集を 1 つ返す。3 つの場合がある。
 * - キーがある → **その行だけ**差し替える（他のキー・コメント・順序は不変）
 * - 頭はあるがキーが無い → 閉じ `---` の直前に 1 行足す
 * - 頭が無い → 文書の先頭に頭を作る
 */
export function setImageFolder(
  text: string,
  head: HeadSpan | null,
  value: string,
): TextEdit {
  const line = `${IMAGE_FOLDER}: ${quote(value)}`;
  if (!head) return { from: 0, to: 0, insert: `---\n${line}\n---\n\n` };
  let at = head.bodyFrom;
  for (const raw of text.slice(head.bodyFrom, bodyEnd(head)).split("\n")) {
    if (KEY_LINE.test(raw)) return { from: at, to: at + raw.length, insert: line };
    at += raw.length + 1;
  }
  // 中身の無い頭は、開きの次の行がそのまま閉じの行。1 行だけ入れる
  if (head.bodyTo < head.bodyFrom) {
    return { from: head.bodyFrom, to: head.bodyFrom, insert: `${line}\n` };
  }
  // 最後の中身の行末（改行の手前）。ここから改行込みで足せば閉じの手前に入る
  return { from: head.bodyTo, to: head.bodyTo, insert: `\n${line}` };
}

/**
 * 宣言の綴りを決める唯一の場所。末尾に `/` を足し、`.` は `./` にする。
 * 絶対パスと URL は md からの相対ではないので null（呼び出し側は何もしない）。
 *
 * **空（trim 後が空文字）も null。** 空値は「宣言」ではなく「書きかけの
 * 行」— 値を選んで消した直後の頭がこれにあたる。ここを `./` に倒すと、
 * 「消して打ち直す」1 呼吸のあいだ宣言が md と同じ場所を指したことになり、
 * その隙に `followDeclaration`（main.ts）が宣言フォルダの外の画像まで
 * retarget の対象に巻き込んでしまう。400ms の debounce が守るのは打鍵の
 * 連続だけで、このリズムは素通りするので、ここで null にして
 * `followDeclaration` の早期 return に委ねる。
 */
export function normalizePath(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed === "") return null;
  let path = trimmed.replace(/\\/g, "/");
  if (path === ".") path = "./";
  if (path.startsWith("/") || /^[a-z]+:\/\//i.test(path)) return null;
  return path.endsWith("/") ? path : `${path}/`;
}

/**
 * `path` が `folder` の下にあるなら、フォルダからの残りを返す。外なら null。
 *
 * 同じ場所を指す綴りが `./x` と `x` の 2 通りあるので、**必ず裸に寄せてから**
 * 比べる。md に書くのは `./x`、カード側が持つのは `x` と非対称なため、
 * どちらか片方だけを見ると既定の `./` で必ず外れる。
 */
export function under(path: string, folder: string): string | null {
  const prefix = bare(folder);
  const rest = bare(path);
  if (!rest.startsWith(prefix)) return null;
  const tail = rest.slice(prefix.length);
  return tail === "" ? null : tail;
}

/**
 * 宣言フォルダの引っ越しに、本文の画像リンクを追従させる。
 *
 * 対象は「**いま宣言しているフォルダの下にある**画像リンク」だけ。`./img/`
 * から動かすなら `./other/b.webp` は動かない。宣言が `./` のときだけ全部が
 * 対象になるが、それは「画像は md と同じ場所にある」と宣言している状態
 * なので、意味のとおり。
 *
 * 頭とフェンスの中は見ない（どちらも区間はコアが答える）。外部 URL は
 * `parseImage` が弾く。
 *
 * 返す編集は文書順。**後ろから**適用すること — 前から当てると、後続の
 * オフセットが挿入ぶんだけずれる。
 */
export function retarget(doc: DocView, from: string, to: string): TextEdit[] {
  const out: TextEdit[] = [];
  if (from === to) return out;
  const inSkipped = (at: number): boolean =>
    (doc.head !== null && at >= doc.head.from && at < doc.head.to) ||
    doc.fences.some((f) => at >= f.from && at < f.to);
  let at = 0;
  for (const line of doc.text.split("\n")) {
    const start = at;
    at += line.length + 1;
    if (inSkipped(start)) continue;
    const img = parseImage(line);
    if (!img) continue;
    const rest = under(img.raw, from);
    if (rest === null) continue;
    const next = `${to}${rest}`;
    // img.from/to は `<…>` の**内側**を指す。既に囲まれていれば中身だけ
    // 差し替えれば済み、囲まれていなければ差し替え先に `<…>` を含める
    // （空白を含むフォルダへ引っ越すと、裸のままでは IMG_LINE が二度と
    // 読めなくなる — カードが消え、次の retarget でも拾えなくなる）
    const insert = img.bracketed ? next : imageDest(next);
    out.push({ from: start + img.from, to: start + img.to, insert });
  }
  return out;
}

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

import type { HeadSpan } from "../coreApi.ts";
import type { TextEdit } from "../edits.ts";
import { bare } from "../map/cards.ts";

/** 頭に置く「画像フォルダの場所」の設定名。**綴りはここ 1 つ** */
export const IMAGE_FOLDER = "image-folder";

// トップレベルのキーだけを見る。字下げされた `  image-folder:` は
// 別のキーの子なので、この文書の設定ではない
const KEY_LINE = new RegExp(`^${IMAGE_FOLDER}[ \\t]*:(.*)$`);

/** 中身の範囲。中身が無い頭では bodyTo が bodyFrom より手前にある */
const bodyEnd = (head: HeadSpan): number => Math.max(head.bodyFrom, head.bodyTo);

/** YAML の値 1 つ。囲まれていれば剥がし、裸なら ` #` から後ろを落とす。 */
function unquote(raw: string): string {
  const v = raw.trim();
  const q = v[0];
  if (v.length >= 2 && (q === '"' || q === "'") && v[v.length - 1] === q) {
    const inner = v.slice(1, -1);
    return q === '"' ? inner.replace(/\\(["\\])/g, "$1") : inner;
  }
  const hash = v.search(/\s#/);
  return (hash === -1 ? v : v.slice(0, hash)).trim();
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
 * 宣言の綴りを決める唯一の場所。末尾に `/` を足し、空と `.` は `./` にする。
 * 絶対パスと URL は md からの相対ではないので null（呼び出し側は何もしない）。
 */
export function normalizePath(value: string): string | null {
  let path = value.trim().replace(/\\/g, "/");
  if (path === "" || path === ".") path = "./";
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

// 文書の頭（YAML frontmatter）に置く設定。
//
// **宣言の持ち主は .md 自身**。以前は window.prompt で聞いて IndexedDB に
// 置いていたので、別マシンで開くと「その md の画像がどこにあるか」だけが
// 消えていた（実体はただの .md、と言い切っているのに）。
//
// ここは純関数だけ。DOM は知らず、コアには読みの形（View）だけを聞く。
// 「どこからどこまでが頭か」はコアが答える（`core.View.frontmatter`）。
// ここが答えるのは、その中の 1 行の綴りと、その 1 行を書き換える編集だけ。
//
// **YAML パーサは入れない。** 読んで書き戻すと、他ツールが書いたコメント・
// 引用符・キーの順序が消える。読むのは 1 キー、書くのも 1 行。

import type * as core from "../coreApi.ts";
import { bare } from "../map/cards.ts";

/** 頭に置く「画像フォルダの場所」の設定名。**綴りはここ 1 つ** */
export const IMAGE_FOLDER = "image-folder";

// トップレベルのキーだけを見る。字下げされた `  image-folder:` は
// 別のキーの子なので、この文書の設定ではない
const KEY_LINE = new RegExp(`^${IMAGE_FOLDER}[ \\t]*:(.*)$`);

/**
 * YAML の値 1 つ。**引用符で始まっていれば、閉じ引用符までが値**
 * （中の ` #` はコメントではない）。それ以外（裸）は ` #` から後ろを
 * コメントとして落とす。この 1 つの規則で 4 つの形すべてを覆う:
 * 裸 / 裸+コメント / 引用符 / 引用符+コメント。
 *
 * 「コメントを先に落としてから引用符を剥がす」順だと、`"./My Folder #1/"`
 * のように**引用符の中に ` #` を含む値**を、閉じ引用符の手前で切ってしまい
 * 壊す（quote() は空白・`#`・`:` のどれかを含む値を引用符で囲むので、
 * 囲まれた値の中に `#` が来る形は普通に起こる）。逆に「引用符を先に
 * 剥がす」だけだと、引用符の後ろにコメントが続く形（`"..." # main`）を
 * 取りこぼす。**閉じ引用符の位置を実際に探す**ことでどちらも起きない。
 */
function unquote(raw: string): string {
  const v = raw.trim();
  const q = v[0];
  if (q === '"' || q === "'") {
    // 閉じ引用符を探す。`"` は quote() が `\"` / `\\` で書くので、その
    // エスケープぶんは飛ばす（`'` は YAML 側でエスケープを持たない）
    let i = 1;
    while (i < v.length && v[i] !== q) {
      if (q === '"' && v[i] === "\\" && i + 1 < v.length) i++;
      i++;
    }
    if (i < v.length) {
      const inner = v.slice(1, i);
      return q === '"' ? inner.replace(/\\(["\\])/g, "$1") : inner;
    }
    // 閉じ引用符が無い壊れた記法。ベストエフォートでそのまま返す
    return v;
  }
  const hash = v.search(/\s#/);
  return (hash === -1 ? v : v.slice(0, hash)).trim();
}

/** 値を YAML の 1 行として書く形。囲む必要が無ければ裸で書く */
function quote(value: string): string {
  if (!/[\s#:]/.test(value)) return value;
  return `"${value.replace(/(["\\])/g, "\\$1")}"`;
}

/** 頭（frontmatter の原文。`---` は含まない）から画像フォルダの宣言を読む。無ければ null */
export function imageFolder(frontmatter: string | null): string | null {
  if (frontmatter === null) return null;
  for (const line of frontmatter.split("\n")) {
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
 *
 * 頭の原文は開きの `---` の次の行から始まり、行ごとに `\n` を付けて
 * 繋いだもの（core が読んだライブラリの形）。だから原文の行数ぶんだけ
 * 本文の行を進めれば、その次の行が閉じの `---`。
 */
export function setImageFolder(text: string, frontmatter: string | null, value: string): core.Edit {
  const line = `${IMAGE_FOLDER}: ${quote(value)}`;
  if (frontmatter === null) return { from: 0, to: 0, insert: `---\n${line}\n---\n\n` };
  const lines = text.split("\n");
  let at = lines[0].length + 1;
  const count = frontmatter.split("\n").length - 1;
  for (const raw of lines.slice(1, 1 + count)) {
    if (KEY_LINE.test(raw)) return { from: at, to: at + raw.length, insert: line };
    at += raw.length + 1;
  }
  return { from: at, to: at, insert: `${line}\n` };
}

/**
 * 宣言フォルダの引っ越しに、本文の画像を追従させる操作列。
 *
 * 対象は「**いま宣言しているフォルダの下にある**画像」だけ。`./img/` から
 * 動かすなら `./other/b.webp` は動かない。宣言が `./` のときは md の下に
 * ある相対パスが全部対象になるが、それは「画像は md と同じ場所にある」と
 * 宣言している状態なので、意味のとおり。外部 URL は `under` が外す。
 */
export function retarget(view: core.View, from: string, to: string): core.Op[] {
  const out: core.Op[] = [];
  if (from === to) return out;
  const walk = (n: core.Node): void => {
    for (const b of n.blocks) {
      if (b.content.kind !== "image") continue;
      const rest = under(b.content.src, from);
      if (rest === null) continue;
      out.push({ kind: "setBlock", id: b.id, content: { ...b.content, src: `${to}${rest}` } });
    }
    n.children.forEach(walk);
  };
  for (const r of view.roots) walk(r.node);
  return out;
}

/**
 * 宣言の綴りを揃える。空・絶対パス・URL は null（宣言として読めない）。
 * `\` は `/` に、`.` は `./` に、末尾には `/` を揃える。
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
 *
 * URL と絶対パスは md からの相対ではないので、どのフォルダの下でもない。
 * 残りが上へ出る（`..`）ものも下ではない — 宣言が `./` のとき、`../x.webp`
 * まで「md と同じ場所の下」に数えてしまう。
 */
export function under(path: string, folder: string): string | null {
  const prefix = bare(folder);
  const rest = bare(path);
  if (rest.startsWith("/") || /^[a-z]+:\/\//i.test(rest)) return null;
  if (!rest.startsWith(prefix)) return null;
  const tail = rest.slice(prefix.length);
  if (tail === "" || tail.split("/").includes("..")) return null;
  return tail;
}

// 文書の頭（YAML frontmatter）に置く設定。
//
// **宣言の持ち主は .md 自身**。以前は window.prompt で聞いて IndexedDB に
// 置いていたので、別マシンで開くと「その md の画像がどこにあるか」だけが
// 消えていた（実体はただの .md、と言い切っているのに）。
//
// ここは純関数だけ。DOM もコアも知らない。「どこからどこまでが頭か」は
// コアが答える（`core.View.frontmatter`）。ここが答えるのは、その中の 1 行の綴りだけ。
//
// **YAML パーサは入れない。** 読んで書き戻すと、他ツールが書いたコメント・
// 引用符・キーの順序が消える。読むのは 1 キー。書くのは操作の段。

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
 */
export function under(path: string, folder: string): string | null {
  const prefix = bare(folder);
  const rest = bare(path);
  if (!rest.startsWith(prefix)) return null;
  const tail = rest.slice(prefix.length);
  return tail === "" ? null : tail;
}

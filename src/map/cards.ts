// 中身（Block）→ カード行。**分類だけ**の層 — 何をカードとして見せるかを決め、
// 寸法（metrics）も DOM も知らない。
//
// md の読みは core が済ませている。ここが見るのは core が「これは画像・リンク・
// コード・SVG だ」と言った Block だけで、原文はもう無い。
// 水平線と Details はカードにしない（Details は spec「今は隠すだけ」）。

import type * as core from "../coreApi.ts";

/** ラベルの下に積むカード 1 行 */
export type CardRow =
  | { kind: "link"; title: string; url: string }
  | { kind: "img"; path: string; name: string }
  | { kind: "svg"; markup: string }
  | { kind: "code"; lang: string; lines: string[] };

/**
 * 先頭の `./` を落とした形。`./x` と `x` は同じ場所を指すので、比べる前に
 * 必ずこの形へ寄せる。**カードが持つのも、画像の鍵（app/assets.ts）になるのもこの形**
 */
export const bare = (path: string): string => path.replace(/^\.\//, "");

/** コードのプレビューは何行まで。超えたら最後の行を `…` にする */
const CODE_MAX_LINES = 6;

/** `http(s)` のリンクだけ。題が空ならホスト名が題 */
function linkCard(text: string, href: string): CardRow | null {
  if (!/^https?:\/\//.test(href)) return null;
  let host: string;
  try {
    host = new URL(href).hostname;
  } catch {
    return null;
  }
  return { kind: "link", title: text === "" ? host : text, url: href };
}

/**
 * 相対パスのローカル画像だけ。外部の画像（http / data）は出さない — 外へ通信しない。
 * scheme は 2 文字以上（1 文字は Windows のドライブ `C:\`）。
 */
function imageCard(src: string): CardRow | null {
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(src);
  if (scheme && scheme[1].length > 1) return null;
  const path = bare(src);
  if (path === "") return null;
  // Windows のパスは `\` 区切りでも来る。split は必ず 1 つ以上返すが、型は言い切らない
  const name = path.split(/[\\/]/).pop() ?? path;
  return { kind: "img", path, name };
}

/** 行に割る。core の text は末尾に改行を持つので 1 つ剥がす。タブは 2 幅 */
function codeCard(info: string, text: string): CardRow {
  const body =
    text === ""
      ? []
      : text
          .replace(/\n$/, "")
          .split("\n")
          .map((l) => l.replace(/\t/g, "  "));
  const lines =
    body.length > CODE_MAX_LINES
      ? [...body.slice(0, CODE_MAX_LINES - 1), "…"]
      : body.length > 0
        ? body
        : [""];
  return { kind: "code", lang: info, lines };
}

function cardOf(b: core.Content): CardRow | null {
  switch (b.kind) {
    case "image":
      return imageCard(b.src);
    case "link":
      return linkCard(b.text, b.href);
    case "code":
      return codeCard(b.info, b.text);
    case "svg":
      return { kind: "svg", markup: b.markup };
    case "thematicBreak":
    case "details":
      return null;
  }
}

/** ノード 1 つぶんのカード行。並びは Block のまま。id は今は使わない（選ぶ段で使う） */
export function cardRows(blocks: core.Block[]): CardRow[] {
  const out: CardRow[] = [];
  for (const b of blocks) {
    const row = cardOf(b.content);
    if (row !== null) out.push(row);
  }
  return out;
}

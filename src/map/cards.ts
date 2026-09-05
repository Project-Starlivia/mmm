// 中身（Block）→ カード行。**分類だけ**の層 — 何をカードとして見せるかを決め、
// 寸法（metrics）も DOM も知らない。
//
// md の読みは core が済ませている。ここが見るのは core が「これは画像・リンク・
// コード・SVG・水平線・details だ」と言った Block だけで、原文はもう無い。

import type * as core from "../coreApi.ts";

/** ラベルの下に積むカード 1 行 */
export type CardRow =
  | { kind: "link"; title: string; url: string }
  | { kind: "image"; path: string; name: string }
  | { kind: "svg"; markup: string }
  | { kind: "code"; lang: string; lines: string[] }
  /** 装飾の水平線。書かれた場所にそのまま 1 本の線 */
  | { kind: "break" }
  /** `<details>`。GitHub と同じく、閉じていれば summary（無ければ Details）だけ、
   *  開いていれば中身の字も。開閉は md の `open` に従う（map だけの状態は持たない） */
  | { kind: "details"; open: boolean; summary: string | null; lines: string[] };

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
  return { kind: "image", path, name };
}

/**
 * 字を行に割る。末尾の改行は行にならない。タブは 2 幅。CODE_MAX_LINES を超えたら
 * 最後の行を `…` にし、空なら 1 行（場所は取る）。コードも details の中身も同じ割り方
 */
function linesOf(text: string): string[] {
  const body =
    text === ""
      ? []
      : text
          .replace(/\n$/, "")
          .split("\n")
          .map((l) => l.replace(/\t/g, "  "));
  return body.length > CODE_MAX_LINES
    ? [...body.slice(0, CODE_MAX_LINES - 1), "…"]
    : body.length > 0
      ? body
      : [""];
}

function cardOf(b: core.Content): CardRow | null {
  switch (b.kind) {
    case "image":
      return imageCard(b.src);
    case "link":
      return linkCard(b.text, b.href);
    case "svg":
      return { kind: "svg", markup: b.markup };
    case "code":
      return { kind: "code", lang: b.info, lines: linesOf(b.text) };
    case "thematicBreak":
      return { kind: "break" };
    case "details":
      return { kind: "details", open: b.open, summary: b.summary, lines: linesOf(b.body) };
    // View には来ない（core/view の project が Opaque を落とす）。ts から送る側でだけ使う形
    case "opaque":
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

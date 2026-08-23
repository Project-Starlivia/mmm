// 添付コンテンツ → カード行。テキスト処理だけの層（DOM を知らない）。
//
// ノードの見出し行の下に続く本文のうち、URL / [text](url) / ローカル画像 /
// コードフェンス / インライン SVG をカード行としてラベルの下に出す
// (mmm.md そのに)。ラベル自身が URL のノードはただのノードのまま。

import type { NodeInfo } from "../coreApi.ts";

export interface LinkInfo {
  title: string;
  url: string;
  host: string;
}

/** One card row under the label, from the attached content.
 *  from/to はそのカードの元テキストの範囲。`text.slice(from, to)` が
 *  そのカードそのものになる（選択・編集・移動はすべてこれに乗る）。 */
export type CardRow =
  | { kind: "link"; link: LinkInfo; from: number; to: number }
  | { kind: "img"; path: string; name: string; from: number; to: number }
  | { kind: "svg"; markup: string; from: number; to: number }
  | { kind: "code"; lang: string; lines: string[]; from: number; to: number };

/**
 * カードの指し方。文書上の位置ではなく「ノード id + そのノードの中で
 * 何枚目か」で指す — 位置だと別のノードを 1 行編集しただけでずれるが、
 * ノード id はコアが編集をまたいで維持するので外れない。
 */
export interface CardRef {
  node: number;
  index: number;
}

const LINK_ROW = 26; // height of one link-card row under the label
const IMG_H = 64; // thumbnail height inside an image row
const IMG_ROW = IMG_H + 12; // height of one image row under the label
export const IMG_MIN_W = 200; // image/svg content is at least this wide (before node padding)
export const CODE_LINE = 15; // height of one preview line in a code row
export const CODE_PAD = 8; // vertical padding inside a code row
const CODE_MAX_LINES = 6; // longer blocks are cut with a trailing …

/** カード行 1 つぶんの高さ */
export const rowH = (r: CardRow): number =>
  r.kind === "img" || r.kind === "svg"
    ? IMG_ROW
    : r.kind === "code"
      ? r.lines.length * CODE_LINE + CODE_PAD * 2
      : LINK_ROW;

/**
 * カード 1 行の、行の枠から中身までの上下の余白。選択の枠も、その場で
 * 直す入力欄も、同じ場所を指さないと 2px ずれる — 実際にずれた。
 * 数字を 2 か所に置かないための唯一の定義。
 */
export const cardInset = (r: CardRow): number =>
  r.kind === "code" ? 5 : r.kind === "link" ? 4 : 6;

/**
 * カード 1 行が、中身の箱から左右へはみ出す量。コードだけは背景をノードの
 * 縁近くまで塗るので、その分だけ広い。上下の `cardInset` と同じ理由で
 * ここが唯一の定義 — 選択の枠が本体より内側に出て、小さく見えていた。
 */
export const cardBleed = (r: CardRow): number => (r.kind === "code" ? 5 : 0);

/** Label of the form `[text](https://...)` or a bare URL. */
export function parseLink(label: string): LinkInfo | null {
  const t = label.trim();
  const md = /^\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)$/.exec(t);
  let title = "";
  let url = "";
  if (md) {
    title = md[1];
    url = md[2];
  } else if (/^https?:\/\/\S+$/.test(t)) {
    url = t;
  } else {
    return null;
  }
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    return null;
  }
  if (title === "") title = host;
  return { title, url, host };
}

/** Content line of the form `![alt](path)` with a LOCAL (relative) path.
 * External images (http/data URLs) are ignored — no external traffic.
 * `<path with space>` is CommonMark's escape for a destination containing
 * whitespace, so only the unescaped form forbids spaces. */
export function parseImage(line: string): { path: string; name: string } | null {
  const m = /^!\[[^\]]*\]\((?:<([^>]+)>|([^)\s]+))\)$/.exec(line.trim());
  if (!m) return null;
  let path = m[1] ?? m[2];
  // A real URI scheme (http:, data:, ...) is always 2+ letters before the
  // colon; a single letter is a Windows drive (`C:\...`), which is a local
  // path, not an external one.
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(path);
  if (scheme && scheme[1].length > 1) return null;
  if (path.startsWith("./")) path = path.slice(2);
  if (path === "") return null;
  // Windows のパスは `\` 区切りでも来る（ドライブレターや `..\..\x.png`）
  const name = path.split(/[\\/]/).pop()!;
  return { path, name };
}

/** 文書のどこかにローカル画像があるか（画像フォルダの要否はここから導く） */
export function hasLocalImage(text: string): boolean {
  return text.split("\n").some((l) => parseImage(l) !== null);
}

/**
 * 本文からカード行を抜き出す（1 ノードぶん）。`base` はこの本文が文書の
 * どこから始まるかで、コードブロックの位置を文書の座標へ戻すのに使う。
 *
 * 行分割は LF だけで行う。アプリの中の改行は常に LF なので結果は同じで、
 * かつ 1 行の長さ +1 がそのまま次の行頭になる（CR を挟む切り方だと、
 * その 1 文字ぶん位置がずれる）。
 */
function rowsOfContent(text: string, base: number): CardRow[] {
  const lines = text.split("\n");
  const lineAt: number[] = [];
  for (let i = 0, off = base; i < lines.length; i++) {
    lineAt.push(off);
    off += lines[i].length + 1;
  }
  /** 行 k の終わり（改行の手前）= どのカードの to もこれ */
  const endOf = (k: number): number => lineAt[k] + lines[k].length;
  const list: CardRow[] = [];
  for (let li = 0; li < lines.length; li++) {
    const t = lines[li].trim();
    // fenced code block
    const fence = /^(`{3,}|~{3,})\s*(\S*)\s*$/.exec(t);
    if (fence) {
      const body: string[] = [];
      // 閉じフェンスは開きと同じ文字で、同じ長さ以上（CommonMark）。
      // フェンス 1 本につき不変なので、本体を走査するループの外で 1 回だけ作る。
      const closeRe = new RegExp(`^\\${fence[1][0]}{${fence[1].length},}$`);
      let j = li + 1;
      for (; j < lines.length; j++) {
        const c = lines[j].trim();
        if (c[0] === fence[1][0] && closeRe.test(c)) {
          break;
        }
        body.push(lines[j].replace(/\t/g, "  "));
      }
      // 開きフェンスから閉じフェンスまで丸ごと。言語の指定も閉じ方も
      // 直せるようにする（結果フェンスでなくなれば、カードは消えるだけ）
      const from = lineAt[li];
      const to = endOf(Math.min(j, lines.length - 1));
      li = j; // past the closing fence (or EOF)
      const preview =
        body.length > CODE_MAX_LINES
          ? [...body.slice(0, CODE_MAX_LINES - 1), "…"]
          : body.length > 0
            ? body
            : [""];
      list.push({ kind: "code", lang: fence[2], lines: preview, from, to });
      continue;
    }
    // inline <svg>…</svg> block (rendered via data URL — static, safe)
    if (t.startsWith("<svg")) {
      const buf: string[] = [lines[li]];
      let j = li;
      while (!buf[buf.length - 1].includes("</svg>") && j + 1 < lines.length) {
        j++;
        buf.push(lines[j]);
      }
      if (buf[buf.length - 1].includes("</svg>")) {
        list.push({
          kind: "svg",
          markup: buf.join("\n"),
          from: lineAt[li],
          to: endOf(j),
        });
        li = j;
        continue;
      }
    }
    const im = parseImage(lines[li]);
    if (im) {
      list.push({
        kind: "img",
        path: im.path,
        name: im.name,
        from: lineAt[li],
        to: endOf(li),
      });
    } else {
      const l = parseLink(lines[li]);
      if (l)
        list.push({ kind: "link", link: l, from: lineAt[li], to: endOf(li) });
    }
  }
  return list;
}

/**
 * そのノード（nodes[i]）の本文の終わり: 次ノードの見出し行頭、無ければ
 * そのノードの部分木の終わり。カード行を切り出す境界（cardRows）と、
 * カードの移動先を「そのノードの末尾」に決める境界（main.ts の
 * moveCardTo/insertContentLine）は同じ場所を指す — この式をここ以外に
 * 書かない。
 */
export function contentEnd(nodes: NodeInfo[], i: number): number {
  const n = nodes[i];
  return i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd
    ? nodes[i + 1].hs
    : n.subEnd;
}

/**
 * 全ノードのカード行。skip に入っている id（折り畳みで描かれないノード）は
 * パースしない — 箱を作らないノードの分は捨て仕事になるだけ。
 */
export function cardRows(
  doc: string,
  nodes: NodeInfo[],
  skip: Set<number>,
): Map<number, CardRow[]> {
  const out = new Map<number, CardRow[]>();
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i];
    // hidden nodes stay compact: label only, no content cards
    if (!n.hasContent || n.hidden || skip.has(n.id)) {
      out.set(n.id, []);
      continue;
    }
    const nlPos = doc.indexOf("\n", n.he);
    const cStart = nlPos === -1 ? -1 : nlPos + 1;
    const cEnd = contentEnd(nodes, i);
    if (cStart > 0 && cStart < cEnd) {
      out.set(n.id, rowsOfContent(doc.slice(cStart, cEnd), cStart));
    } else {
      out.set(n.id, []);
    }
  }
  return out;
}

// 添付コンテンツ → カード行。テキスト処理だけの層（DOM を知らない）。
//
// ノードの見出し行の下に続く本文のうち、URL / [text](url) / ローカル画像 /
// コードフェンス / インライン SVG をカード行としてラベルの下に出す。
// ラベル自身が URL のノードはただのノードのまま。
//
// **フェンスの区間はコアが渡してくる**（DocView.fences）。「どこからどこまでが
// フェンスか」は文書の意味であって見せ方ではないので、ここでは判定しない。

import type { DocView, FenceSpan, NodeInfo } from "../coreApi.ts";

export interface LinkInfo {
  title: string;
  url: string;
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
  // URL として読めないものはリンクにしない。読めたホスト名は、題が
  // 無いときの題になる
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    return null;
  }
  return { title: title === "" ? host : title, url };
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

/**
 * コードカード 1 枚。範囲は開きフェンスから閉じフェンスまで丸ごと —
 * 言語の指定も閉じ方もその場で直せるようにするため（結果フェンスで
 * なくなれば、カードが消えるだけ）。
 */
function codeCard(text: string, f: FenceSpan): CardRow {
  const body =
    f.bodyTo > f.bodyFrom
      ? text
          .slice(f.bodyFrom, f.bodyTo)
          .split("\n")
          .map((l) => l.replace(/\t/g, "  "))
      : [];
  const lines =
    body.length > CODE_MAX_LINES
      ? [...body.slice(0, CODE_MAX_LINES - 1), "…"]
      : body.length > 0
        ? body
        : [""];
  return { kind: "code", lang: f.info, lines, from: f.from, to: f.to };
}

/**
 * 本文 [from, to) からカード行を抜き出す（1 ノードぶん）。オフセットは
 * ずっと文書全体のもので、行を切り出して数え直さない。
 *
 * フェンスの区間は**コアが渡してくる**ので、ここで「これはフェンスか」を
 * 判定しない。行分割は LF だけ — アプリの中の改行は常に LF。
 */
function rowsOfContent(
  text: string,
  from: number,
  to: number,
  fenceAt: Map<number, FenceSpan>,
): CardRow[] {
  const list: CardRow[] = [];
  /** その行の終わり（改行の手前）。範囲の終わりで打ち切る */
  const endOf = (p: number): number => {
    const brk = text.indexOf("\n", p);
    return brk === -1 || brk > to ? to : brk;
  };
  let p = from;
  while (p < to) {
    const fence = fenceAt.get(p);
    if (fence) {
      list.push(codeCard(text, fence));
      p = fence.to + 1; // 閉じフェンス行の次の行頭（文書末なら to を越える）
      continue;
    }
    const end = endOf(p);
    const line = text.slice(p, end);
    // inline <svg>…</svg> block (rendered via data URL — static, safe)
    if (line.trim().startsWith("<svg")) {
      let last = end;
      while (!text.slice(p, last).includes("</svg>") && last < to) {
        last = endOf(last + 1);
      }
      if (text.slice(p, last).includes("</svg>")) {
        list.push({ kind: "svg", markup: text.slice(p, last), from: p, to: last });
        p = last + 1;
        continue;
      }
    }
    const image = parseImage(line);
    if (image) {
      list.push({ kind: "img", path: image.path, name: image.name, from: p, to: end });
    } else {
      const link = parseLink(line);
      if (link) list.push({ kind: "link", link, from: p, to: end });
    }
    p = end + 1;
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
  return i + 1 < nodes.length && nodes[i + 1].from < n.to
    ? nodes[i + 1].from
    : n.to;
}

/**
 * 全ノードのカード行。skip に入っている id（折り畳みで描かれないノード）は
 * パースしない — 箱を作らないノードの分は捨て仕事になるだけ。
 */
export function cardRows(
  doc: DocView,
  skip: Set<number>,
): Map<number, CardRow[]> {
  const fenceAt = new Map<number, FenceSpan>();
  for (const f of doc.fences) fenceAt.set(f.from, f);
  const out = new Map<number, CardRow[]>();
  for (let i = 0; i < doc.nodes.length; i++) {
    const n = doc.nodes[i];
    // hidden nodes stay compact: label only, no content cards
    if (!n.hasContent || n.hidden || skip.has(n.id)) {
      out.set(n.id, []);
      continue;
    }
    const brk = doc.text.indexOf("\n", n.headEnd);
    const start = brk === -1 ? -1 : brk + 1;
    const end = contentEnd(doc.nodes, i);
    out.set(
      n.id,
      start > 0 && start < end
        ? rowsOfContent(doc.text, start, end, fenceAt)
        : [],
    );
  }
  return out;
}

/** そのノードの本文の終わり。id から引くときはこちら。 */
export function contentEndOf(nodes: NodeInfo[], id: number): number | null {
  const i = nodes.findIndex((n) => n.id === id);
  return i === -1 ? null : contentEnd(nodes, i);
}

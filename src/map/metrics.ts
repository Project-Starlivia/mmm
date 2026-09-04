// ノードの寸法。文字の実測（canvas measureText）とラベル行の規格。
//
// ノードの「ラベル行」の寸法は**ここが唯一の定義**。
// この 1 行を、少なくとも 3 者が同じ値で見なければならない:
//   1. レイアウト（nodeSize が箱の大きさを決める）
//   2. SVG の描画（text 要素の font-size と x）
//   3. 編集用の <input> オーバーレイ（幅・高さ・padding・font-size）
// 以前はこれが 3 箇所に散っていて、通常ノードは 13px/12、畳んだノードは
// 計測 10px・CSS 11px・input 13px と食い違い、折り畳んだノードを編集すると
// 文字がずれていた。font-size は CSS ではなく属性で入れて、CSS 側に
// 同じ数字を持たせない。

import type * as core from "../coreApi.ts";
import type { CardRow } from "./cards.ts";

export const HIDDEN_MAX_W = 150; // 畳んだノードはこれより広くならない

// ---- カード行の寸法。**ここが唯一の定義** ----

const LINK_ROW = 26; // リンクカード 1 行の高さ
const IMG_H = 64; // 画像行の中のサムネイルの高さ
const IMG_ROW = IMG_H + 12; // 画像行の高さ
export const IMG_MIN_W = 200; // 画像 / svg の中身はこれより狭くならない（余白抜き）
export const CODE_LINE = 15; // コードのプレビュー 1 行の高さ
export const CODE_PAD = 8; // コード行の上下の余白

/** カード行 1 つぶんの高さ */
export const rowH = (r: CardRow): number =>
  r.kind === "img" || r.kind === "svg"
    ? IMG_ROW
    : r.kind === "code"
      ? r.lines.length * CODE_LINE + CODE_PAD * 2
      : LINK_ROW;

/**
 * カード 1 行の、行の枠から中身までの上下の余白。描くのも書き出すのも
 * 同じ場所を指さないと 2px ずれる — 実際にずれた。数字を 2 か所に置かないための唯一の定義。
 */
export const cardInset = (r: CardRow): number =>
  r.kind === "code" ? 5 : r.kind === "link" ? 4 : 6;

/**
 * カード 1 行が、中身の箱から左右へはみ出す量。コードだけは背景をノードの
 * 縁近くまで塗るので、その分だけ広い。
 */
export const cardBleed = (r: CardRow): number => (r.kind === "code" ? 5 : 0);

/**
 * 字の綴りは **style.css の `--font` / `--mono` ひとつ**。幅を測る canvas は
 * 文字列しか受け取らないので、そこから組み直す。起動後に 1 度だけ読む
 * （テーマを変えても字は変わらないので、読み直す理由が無い）。
 */
const families = new Map<string, string>();
function family(name: string, fallback: string): string {
  const hit = families.get(name);
  if (hit !== undefined) return hit;
  const css = getComputedStyle(document.documentElement)
    .getPropertyValue(name)
    .trim();
  const out = css === "" ? fallback : css;
  families.set(name, out);
  return out;
}

/** その行のラベルを測るための字 */
export const labelFont = (row: LabelRow): string =>
  `${row.fontPx}px ${family("--font", "sans-serif")}`;

export const cardFont = (): string => `12px ${family("--font", "sans-serif")}`;
export const monoFont = (): string => `11px ${family("--mono", "monospace")}`;

export interface LabelRow {
  fontPx: number;
  padX: number; // 文字開始位置 = 箱の左 + padX
  rowH: number; // ラベル行の高さ
}
export const ROW_NORMAL: LabelRow = {
  fontPx: 13,
  padX: 12,
  rowH: 30,
};
export const ROW_HIDDEN: LabelRow = {
  fontPx: 11,
  // 通常ノードの余白比（padX/文字 = 0.92、行高/文字 = 2.31）に寄せてある。
  // 小さく見せたいからと詰めすぎると、+N バッジが窮屈になって読めない
  padX: 9,
  rowH: 24,
};
/** Implicit は字を持たない。空の見出しと同じく空の字として扱う（種類は無い） */
export const labelOf = (n: core.Node): string => n.label ?? "";

export const rowOf = (n: core.Node): LabelRow => (n.fold === null ? ROW_NORMAL : ROW_HIDDEN);

/** ラベルが空のときに表示するプレースホルダ。表示箇所すべてがこれ 1 つを見る。 */
export const EMPTY_LABEL = "(empty)";
export const displayLabel = (label: string): string => (label === "" ? EMPTY_LABEL : label);

// 実測用のキャンバスは**最初に測るときに**作る。読み込んだだけで DOM に
// 触ると、このファイルを辿るだけのモジュール（レイアウトやドロップ判定）が
// ブラウザの外で読めなくなる
let measureCtx: CanvasRenderingContext2D | null = null;

// measureText は render() でいちばん回る呼び出し。ラベルはレンダをまたいで
// 繰り返し出てくるので、font + 文字列で幅を覚える
const widthCache = new Map<string, number>();
const WIDTH_CACHE_MAX = 4000; // rename 中の途中文字列などで無限に伸びるので上限

export function measure(font: string, text: string): number {
  const key = font + "\u0000" + text;
  const hit = widthCache.get(key);
  if (hit !== undefined) return hit;
  measureCtx ??= document.createElement("canvas").getContext("2d");
  if (!measureCtx) throw new Error("文字を測る 2d コンテキストを作れない");
  measureCtx.font = font;
  const w = measureCtx.measureText(text).width;
  if (widthCache.size >= WIDTH_CACHE_MAX) widthCache.clear();
  widthCache.set(key, w);
  return w;
}

/**
 * 幅 maxW に収まるところで「…」を付けて詰める。
 * **通常のノードは詰めない** — 使うのは折り畳み表示だけ（そこは「小さく畳む」
 * ことが目的なので、長いラベルをそのまま出すと意味が無くなる）。
 * slice はサロゲートペアを割らないよう、切り口が上位サロゲートなら 1 つ戻す。
 */
export function clipLabel(label: string, font: string, maxW: number): string {
  if (measure(font, label) <= maxW) return label;
  let lo = 0;
  let hi = label.length;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (measure(font, label.slice(0, mid) + "…") <= maxW) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  const cut = label.charCodeAt(lo - 1);
  if (cut >= 0xd800 && cut <= 0xdbff) lo -= 1; // ペアの前半で切らない
  return label.slice(0, lo) + "…";
}

/** 折り畳んだ子孫の数を示すバッジ（無ければ空） */
export const collapsedBadge = (buried: number): string =>
  buried > 0 ? `  +${buried}` : "";

/**
 * 畳んだノードの表示ラベル。幅で詰める（文字数だと CJK で箱からはみ出す）。
 * バッジは詰めの対象にしない — 「+3」が読めなくなっては意味がない。
 */
export function hiddenLabel(n: core.Node, buried: number): string {
  const raw = displayLabel(labelOf(n));
  const badge = collapsedBadge(buried);
  const budget = HIDDEN_MAX_W - ROW_HIDDEN.padX * 2 - measure(labelFont(ROW_HIDDEN), badge);
  return clipLabel(raw, labelFont(ROW_HIDDEN), budget) + badge;
}

/**
 * 箱の上から数えて、i 枚目のカード行の上端はどこか。カードはラベル行の下に
 * 積むので、i = rows.length なら積み終わり = 箱の高さそのものになる。
 * 「行 i は縦のどこか」を数えるのはここだけ — 描画も当たり判定も落とし先も
 * 同じ積み方を見る（散らばっていた頃、余白が 2px ずれた）。
 */
export function rowTop(rows: CardRow[], i: number): number {
  let y = ROW_NORMAL.rowH;
  for (let k = 0; k < i; k++) y += rowH(rows[k]);
  return y;
}

/** ノードの箱の大きさ。ラベルとカード行から決まる */
export function nodeSize(n: core.Node, rows: CardRow[], buried: number): { w: number; h: number } {
  if (n.fold !== null) {
    // 畳み表示: ラベルを詰めた幅だけ。カード類は持たない
    const w =
      Math.ceil(Math.min(measure(labelFont(ROW_HIDDEN), hiddenLabel(n, buried)), HIDDEN_MAX_W)) +
      ROW_HIDDEN.padX * 2;
    return { w, h: ROW_HIDDEN.rowH };
  }
  const label = displayLabel(labelOf(n));
  let w = measure(labelFont(ROW_NORMAL), label);
  for (const r of rows) {
    if (r.kind === "img" || r.kind === "svg") {
      w = Math.max(w, IMG_MIN_W);
    } else if (r.kind === "code") {
      for (const ln of r.lines) {
        w = Math.max(w, measure(monoFont(), ln) + 12);
      }
    } else {
      w = Math.max(w, measure(cardFont(), r.title) + 22);
    }
  }
  // w はここまで content 幅（左右パディング抜き）。最終的な箱の幅は
  // これに ROW_NORMAL.padX*2 を足したもの — IMG_MIN_W 等の「最低幅」も
  // content 側の基準であって、箱の実測幅そのものではない。
  return { w: Math.ceil(w) + ROW_NORMAL.padX * 2, h: rowTop(rows, rows.length) };
}

// ノードの寸法。文字の実測（canvas measureText）とラベル行の規格。
//
// ノードの「ラベル行」の寸法は**ここが唯一の定義**。
// この 1 行を、少なくとも 3 者が同じ値で見なければならない:
//   1. レイアウト（nodeSize が箱の大きさを決める）
//   2. SVG の描画（text 要素の font-size と x）
//   3. 編集用の <input> オーバーレイ（幅・高さ・padding・font-size）
// 以前はこれが 3 箇所に散っていて、通常ノードは 13px/12、hidden ノードは
// 計測 10px・CSS 11px・input 13px と食い違い、折り畳んだノードを編集すると
// 文字がずれていた。font-size は CSS ではなく属性で入れて、CSS 側に
// 同じ数字を持たせない。

import type { NodeInfo } from "../coreApi.ts";
import { type CardRow, rowH, IMG_MIN_W } from "./cards.ts";

export const MAX_LABEL_W = 340;
export const HIDDEN_MAX_W = 150; // hidden nodes never grow past this

const UI_FAMILY = '"Segoe UI", "Hiragino Sans", "Noto Sans JP", Meiryo, sans-serif';
export const CARD_FONT = `12px ${UI_FAMILY}`;
export const MONO_FONT = '11px "Cascadia Code", Consolas, "JetBrains Mono", monospace';

export interface LabelRow {
  fontPx: number;
  font: string; // measure() 用（fontPx から作る）
  padX: number; // 文字開始位置 = 箱の左 + padX
  rowH: number; // ラベル行の高さ
}
export const ROW_NORMAL: LabelRow = {
  fontPx: 13,
  font: `13px ${UI_FAMILY}`,
  padX: 12,
  rowH: 30,
};
export const ROW_HIDDEN: LabelRow = {
  fontPx: 11,
  font: `11px ${UI_FAMILY}`,
  // 通常ノードの余白比（padX/文字 = 0.92、行高/文字 = 2.31）に寄せてある。
  // 小さく見せたいからと詰めすぎると、+N バッジが窮屈になって読めない
  padX: 9,
  rowH: 24,
};
export const rowOf = (n: NodeInfo): LabelRow => (n.hidden ? ROW_HIDDEN : ROW_NORMAL);

/** ラベルが空のときに表示するプレースホルダ。表示箇所すべてがこれ 1 つを見る。 */
export const EMPTY_LABEL = "（空）";
export const displayLabel = (label: string): string => (label === "" ? EMPTY_LABEL : label);

const measureCtx = document.createElement("canvas").getContext("2d")!;

// measureText is the hottest call in render(); labels repeat across
// renders, so cache widths per font+string
const widthCache = new Map<string, number>();
const WIDTH_CACHE_MAX = 4000; // rename 中の途中文字列などで無限に伸びるので上限

export function measure(font: string, text: string): number {
  const key = font + "\u0000" + text;
  const hit = widthCache.get(key);
  if (hit !== undefined) return hit;
  measureCtx.font = font;
  const w = measureCtx.measureText(text).width;
  if (widthCache.size >= WIDTH_CACHE_MAX) widthCache.clear();
  widthCache.set(key, w);
  return w;
}

/**
 * 幅 maxW に収まるところで「…」を付けて詰める。
 * slice はサロゲートペアを割らないよう、切り口が上位サロゲートなら 1 つ戻す。
 */
export function clipLabel(label: string, font = ROW_NORMAL.font, maxW = MAX_LABEL_W): string {
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
 * hidden ノードの表示ラベル。幅で詰める（文字数だと CJK で箱からはみ出す）。
 * バッジは詰めの対象にしない — 「+3」が読めなくなっては意味がない。
 */
export function hiddenLabel(n: NodeInfo, buried: number): string {
  const raw = displayLabel(n.label);
  const badge = collapsedBadge(buried);
  const budget = HIDDEN_MAX_W - ROW_HIDDEN.padX * 2 - measure(ROW_HIDDEN.font, badge);
  return clipLabel(raw, ROW_HIDDEN.font, budget) + badge;
}

/** ノードの箱の大きさ。ラベルとカード行から決まる */
export function nodeSize(n: NodeInfo, rows: CardRow[], buried: number): { w: number; h: number } {
  if (n.hidden) {
    // 折り畳み表示: ラベルを詰めた幅だけ。カード類は持たない
    const w =
      Math.ceil(
        Math.min(measure(ROW_HIDDEN.font, hiddenLabel(n, buried)), HIDDEN_MAX_W),
      ) +
      ROW_HIDDEN.padX * 2;
    return { w, h: ROW_HIDDEN.rowH };
  }
  const label = displayLabel(n.label);
  let w = Math.min(measure(ROW_NORMAL.font, label), MAX_LABEL_W);
  let h = ROW_NORMAL.rowH;
  for (const r of rows) {
    h += rowH(r);
    if (r.kind === "img" || r.kind === "svg") {
      w = Math.max(w, IMG_MIN_W);
    } else if (r.kind === "code") {
      for (const ln of r.lines) {
        w = Math.max(w, Math.min(measure(MONO_FONT, ln), MAX_LABEL_W) + 12);
      }
    } else {
      w = Math.max(w, Math.min(measure(CARD_FONT, r.link.title), MAX_LABEL_W) + 22);
    }
  }
  // w はここまで content 幅（左右パディング抜き）。最終的な箱の幅は
  // これに ROW_NORMAL.padX*2 を足したもの — IMG_MIN_W 等の「最低幅」も
  // content 側の基準であって、箱の実測幅そのものではない。
  return { w: Math.ceil(w) + ROW_NORMAL.padX * 2, h };
}

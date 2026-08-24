// 矢印キーで選択がどこへ動くか。DOM も MindMap も知らない純粋な層。
//
// 「行き先」と「選択の広げ方」を分けてある。**Shift の有無で行き先は変わらない**
// — Shift はそこを選択に足すだけなので、道筋と広げ方を別々に覚えなくてよい。

import type { NodeInfo } from "../coreApi.ts";
import type { Layout } from "./layout.ts";

const ARROWS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"] as const;

export type ArrowKey = (typeof ARROWS)[number];

/** 矢印キーか。`key.startsWith("Arrow")` を `as ArrowKey` で締めていたのを、
 *  型が実際に分かる形にしたもの。 */
export const isArrowKey = (key: string): key is ArrowKey =>
  ARROWS.some((a) => a === key);

/**
 * `anchor` から矢印 1 回ぶんの行き先。行けなければ -1。
 *
 * - 上下 … **同じ深さの列**を文書順（= 画面の上から下）に辿り、端でループする。
 *   兄弟に限らず**いとこも含む** — 見えている限り、その階層は 1 本の列。
 *   親が畳まれて埋もれたノードは列に入れない（選べないものへは飛べない）
 * - 左 … 親へ
 * - 右 … 最初の子へ。子が無ければ先頭へ回る（上下が列の中で回るのと同じで、
 *   行き止まりで無反応になるより一周できるほうが迷わない）
 *
 * `nodes` は**全ノード**（畳んで埋もれたものも含む）。埋もれた子へ飛ばない
 * 判定に、見えているかどうかの照合が要る。
 */
export function arrowTarget(
  nodes: NodeInfo[],
  layout: Layout,
  anchor: number,
  key: ArrowKey,
): number {
  const order = layout.visible.map((n) => n.id);
  if (order.length === 0) return -1;
  // 何も選んでいないなら、まず先頭へ
  if (anchor === -1) return order[0];
  const cur = layout.visible.find((n) => n.id === anchor);
  if (!cur) return -1;

  if (key === "ArrowUp" || key === "ArrowDown") {
    const level = layout.visible.filter((n) => n.depth === cur.depth);
    const i = level.findIndex((n) => n.id === anchor);
    if (i === -1) return -1;
    const step = key === "ArrowUp" ? -1 : 1;
    return level[(i + step + level.length) % level.length].id;
  }
  if (key === "ArrowLeft") return cur.parent;
  const kid = nodes.find((n) => n.parent === anchor && layout.boxes.has(n.id));
  return kid?.id ?? order[0];
}

/**
 * Shift+矢印での選択の広げ方。行き先が**既に選ばれていれば**、いま居た側を
 * 外して縮める（行きすぎたぶんを引っ込められる）。
 */
export function extendSelection(
  selection: Set<number>,
  anchor: number,
  next: number,
): number[] {
  const out = new Set(selection);
  if (out.has(next) && selection.size > 1) out.delete(anchor);
  else out.add(next);
  return [...out];
}

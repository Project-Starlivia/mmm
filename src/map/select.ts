// 選択。何を選んでいるかの値と、入力（クリック・矩形・矢印）でそれがどう変わるか。
// DOM も地図も知らない — 地図は入力を値にして渡し、返った値を塗るだけ。
// 決めは docs/superpowers/specs/2026-09-04-select-design.md と spec.md「Mindmap 側」。
//
// id は文書順の通し番号なので、数の順がそのまま文書順。

import { dirOf, type Rect } from "./geometry.ts";
import type { Layout } from "./layout.ts";

/** 選んでいるノード（文書順）と、範囲選択・矢印の基点 */
export interface Selection {
  ids: number[];
  anchor: number | null;
}

export const NONE: Selection = { ids: [], anchor: null };

export type Modifier = "none" | "shift" | "mod";

const sorted = (ids: Iterable<number>): number[] => [...new Set(ids)].sort((a, b) => a - b);

const last = (ids: number[]): number | null => (ids.length === 0 ? null : ids[ids.length - 1]);

/** 選ぶ。`shift` は anchor から文書順に範囲（anchor は動かない）、`mod` は足す・外す */
export function click(sel: Selection, id: number, mod: Modifier, order: number[]): Selection {
  if (mod === "mod") {
    const ids = sel.ids.includes(id) ? sel.ids.filter((x) => x !== id) : sorted([...sel.ids, id]);
    return { ids, anchor: ids.includes(id) ? id : last(ids) };
  }
  if (mod === "shift" && sel.anchor !== null) {
    const a = order.indexOf(sel.anchor);
    const b = order.indexOf(id);
    if (a !== -1 && b !== -1) {
      const [lo, hi] = a < b ? [a, b] : [b, a];
      return { ids: sorted(order.slice(lo, hi + 1)), anchor: sel.anchor };
    }
  }
  return { ids: [id], anchor: id };
}

/** 矩形（world）に触れる箱を全部。anchor は文書順の最後 */
export function rubber(L: Layout, r: Rect): Selection {
  const ids = L.order.filter((id) => {
    const b = L.boxes.get(id);
    return b !== undefined && b.x < r.x + r.w && r.x < b.x + b.w && b.y < r.y + r.h && r.y < b.y + b.h;
  });
  return { ids, anchor: last(ids) };
}

/** world の点がどの箱に居るか。重なりは文書順の後ろが上。外なら null */
export function hit(L: Layout, x: number, y: number): number | null {
  for (let i = L.order.length - 1; i >= 0; i--) {
    const id = L.order[i];
    const b = L.boxes.get(id);
    if (b && x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h) return id;
  }
  return null;
}

export const all = (L: Layout): Selection => ({ ids: sorted(L.order), anchor: last(L.order) });

export type ArrowKey = "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight";

export const isArrowKey = (key: string): key is ArrowKey =>
  key === "ArrowUp" || key === "ArrowDown" || key === "ArrowLeft" || key === "ArrowRight";

/** 根からの深さ。Layout は持たないので親を辿って数える。この module の中でしか使わない。
 *  未知の id は根と同じ 0（`arrow` は先に `L.boxes.get(anchor)` で弾くので届かない） */
function depthOf(L: Layout, id: number): number {
  let d = 0;
  let b = L.boxes.get(id);
  while (b && b.parent) {
    d++;
    b = L.boxes.get(b.parent.id);
  }
  return d;
}

/**
 * 矢印 1 回ぶんの行き先。行けなければ null。何も選んでいなければ先頭。
 *
 * - 上下 … **同じ深さの列**を文書順に辿り、端でループする。兄弟に限らずいとこも含む
 * - 左右 … **画面の向き**で読む。根と右の枝は ← が親・→ が子、左の枝は鏡像。
 *   子が無ければ先頭へ回る（行き止まりで無反応になるより一周できるほうが迷わない）
 */
export function arrow(L: Layout, anchor: number | null, key: ArrowKey): number | null {
  const order = L.order;
  if (order.length === 0) return null;
  if (anchor === null) return order[0];
  const cur = L.boxes.get(anchor);
  if (!cur) return null;
  if (key === "ArrowUp" || key === "ArrowDown") {
    const depth = depthOf(L, anchor);
    const level = order.filter((id) => depthOf(L, id) === depth);
    const i = level.indexOf(anchor);
    const step = key === "ArrowUp" ? -1 : 1;
    return level[(i + step + level.length) % level.length];
  }
  // 側を符号に読むのは dirOf だけ、という不変条件を守る
  const dir = cur.parent ? dirOf(cur.parent.side) : 1;
  const toParent = key === (dir === -1 ? "ArrowRight" : "ArrowLeft");
  if (toParent) return cur.parent ? cur.parent.id : null;
  const kid = order.find((id) => L.boxes.get(id)?.parent?.id === anchor);
  return kid ?? order[0];
}

/** Shift+矢印。行き先を足す。行き先が既に選ばれていれば、いま居た側を外して縮める */
export function extend(sel: Selection, next: number): Selection {
  // arrow は深さが 1 つしか無い列や、子の無いノードから回った先で anchor
  // 自身を返すことがある。そのまま外すと anchor が選択から消えてしまう
  if (next === sel.anchor) return sel;
  if (sel.ids.includes(next) && sel.ids.length > 1 && sel.anchor !== null) {
    return { ids: sel.ids.filter((x) => x !== sel.anchor), anchor: next };
  }
  return { ids: sorted([...sel.ids, next]), anchor: next };
}

/** 親の id。根なら null */
export const parentOf = (L: Layout, id: number): number | null => L.boxes.get(id)?.parent?.id ?? null;

/** 同じ親の子（根なら根どうし）を文書順に */
const siblingsOf = (L: Layout, id: number): number[] => {
  const p = parentOf(L, id);
  return L.order.filter((x) => parentOf(L, x) === p);
};

export function prevSibling(L: Layout, id: number): number | null {
  const s = siblingsOf(L, id);
  const i = s.indexOf(id);
  return i > 0 ? s[i - 1] : null;
}

export function nextSibling(L: Layout, id: number): number | null {
  const s = siblingsOf(L, id);
  const i = s.indexOf(id);
  return i >= 0 && i < s.length - 1 ? s[i + 1] : null;
}

/** id の祖先に ids のどれかが居るか（= 一緒に消える） */
function under(L: Layout, id: number, ids: Set<number>): boolean {
  let cur: number | null = id;
  while (cur !== null) {
    if (ids.has(cur)) return true;
    cur = parentOf(L, cur);
  }
  return false;
}

/**
 * 消した後に選ぶ隣。消す並びの次に残るノード、無ければ前に残るノード、無ければ null。
 * 消える部分木（選んだものの子孫）は隣に数えない。文書順は親が子より先なので、
 * 「前」にはいつも親が含まれる（先頭の根を消したときだけ前が無い）
 */
export function neighbor(L: Layout, ids: number[]): number | null {
  const gone = new Set(ids);
  const first = L.order.findIndex((x) => gone.has(x));
  if (first === -1) return null;
  const stays = (x: number): boolean => !under(L, x, gone);
  const after = L.order.slice(first + 1).find(stays);
  if (after !== undefined) return after;
  return L.order.slice(0, first).reverse().find(stays) ?? null;
}

/** ちょうど 1 つ選んでいる id。宛先が 1 つに決まる操作はこれを見る */
export const solo = (sel: Selection): number | null =>
  sel.ids.length === 1 && sel.anchor !== null ? sel.anchor : null;

// 選択。何を選んでいるかの値と、入力（クリック・矩形・矢印）でそれがどう変わるか。
// DOM も地図も知らない — 地図は入力を値にして渡し、返った値を塗るだけ。
// 決めは docs/superpowers/specs/2026-09-04-select-design.md と spec.md「Mindmap 側」。
//
// id は文書順の通し番号なので、数の順がそのまま文書順。

import { dirOf, type Rect } from "./geometry.ts";
import type * as core from "../coreApi.ts";

/** 選んでいるノード（文書順）と、範囲選択・矢印の基点 */
export interface Selection {
  ids: number[];
  anchor: number | null;
}

export const NONE: Selection = { ids: [], anchor: null };

/** 何を選んでいるか — ノードの並びか、カード 1 枚か。片方だけ（spec.md「C カード」） */
export type Choice = { kind: "nodes"; sel: Selection } | { kind: "card"; id: number };

export const NOTHING: Choice = { kind: "nodes", sel: NONE };

/** ノードの選択として見る。カードを選んでいれば空 */
export const nodesOf = (c: Choice): Selection => (c.kind === "nodes" ? c.sel : NONE);

/** カードの選択として見る。ノードを選んでいれば null */
export const cardOf = (c: Choice): number | null => (c.kind === "card" ? c.id : null);

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
export function rubber(L: core.Layout, r: Rect): Selection {
  const ids = L.order.filter((id) => {
    const b = L.boxes.get(id);
    return b !== undefined && b.x < r.x + r.w && r.x < b.x + b.w && b.y < r.y + r.h && r.y < b.y + b.h;
  });
  return { ids, anchor: last(ids) };
}

/** 点から矩形までの、軸ごとの距離。中なら 0 */
const gapTo = (r: Rect, x: number, y: number): { dx: number; dy: number } => ({
  dx: Math.max(r.x - x, 0, x - (r.x + r.w)),
  dy: Math.max(r.y - y, 0, y - (r.y + r.h)),
});

const inside = (r: Rect, x: number, y: number): boolean => {
  const g = gapTo(r, x, y);
  return g.dx === 0 && g.dy === 0;
};

/**
 * 見た目の箱の外まで当たりを広げる幅（world px）。`pad` は四方、`edge` は子の見えない
 * 端のノードが枝の伸びる向きにさらに伸ばす分（根は向きが無いので伸びない）。
 * 見た目どおりは EXACT、⋯ の Easy grab は GRAB
 */
export interface Reach {
  pad: number;
  edge: number;
}

export const EXACT: Reach = { pad: 0, edge: 0 };

/**
 * 当たりの広げ幅（Easy grab）。見た目は変えず、判定だけ箱の外へ広げる。world px。
 * pad は四方 — 兄弟の隙間（gap.y）は丸ごと飲み、親子の隙間（gap.x）はほぼ埋まる。
 * edge は子の見えない端のノードが、枝の伸びる向きにさらに伸ばす分
 */
export const GRAB: Reach = { pad: 41, edge: 63 };

const grown = (b: Rect, pad: number): Rect => ({ x: b.x - pad, y: b.y - pad, w: b.w + pad * 2, h: b.h + pad * 2 });

/** 箱 1 つの当たりの範囲。`near` は pad の分、`far` はそれに端の伸びを足したもの（near ⊆ far） */
export function reachOf(b: core.Box, r: Reach, parents: Set<number>): { near: Rect; far: Rect } {
  const near = grown(b, r.pad);
  const out = b.parent && !parents.has(b.node.id) ? r.edge : 0;
  const left = b.parent && dirOf(b.parent.side) === -1;
  return { near, far: { ...near, x: near.x - (left ? out : 0), w: near.w + out } };
}

/**
 * world の点がどの箱に居るか。当たりは見た目の箱を `reach` の分だけ広げた範囲。
 * 複数の範囲に入れば見た目の箱に近い方 — ふつうは直線距離。ただし端の伸び（far）
 * だけで届く箱が居るときは行で読む: y の近さ、同じなら x の近さ（端の伸びは横に長く、
 * 直線距離では隣の行の箱に負けてしまうため）。同じ近さなら文書順の後ろ。外なら null
 */
export function hit(L: core.Layout, x: number, y: number, reach: Reach): number | null {
  const parents = new Set([...L.boxes.values()].flatMap((b) => (b.parent ? [b.parent.id] : [])));
  const found: { id: number; dx: number; dy: number; byFar: boolean }[] = [];
  for (const id of L.order) {
    const b = L.boxes.get(id);
    if (!b) continue;
    const r = reachOf(b, reach, parents);
    if (!inside(r.far, x, y)) continue;
    found.push({ id, ...gapTo(b, x, y), byFar: !inside(r.near, x, y) });
  }
  if (found.length === 0) return null;
  const rowwise = found.some((f) => f.byFar);
  const key = rowwise
    ? (f: { dx: number; dy: number }): [number, number] => [f.dy, f.dx]
    : (f: { dx: number; dy: number }): [number, number] => [Math.hypot(f.dx, f.dy), 0];
  // 文書順の後ろが勝つよう、同じ近さでは後ろで置き換える
  let best = found[0];
  for (const f of found.slice(1)) {
    const [a, b] = [key(f), key(best)];
    if (a[0] < b[0] || (a[0] === b[0] && a[1] <= b[1])) best = f;
  }
  return best.id;
}

export const all = (L: core.Layout): Selection => ({ ids: sorted(L.order), anchor: last(L.order) });

export type ArrowKey = "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight";

export const isArrowKey = (key: string): key is ArrowKey =>
  key === "ArrowUp" || key === "ArrowDown" || key === "ArrowLeft" || key === "ArrowRight";

/** 根からの深さ。core.Layout は持たないので親を辿って数える。この module の中でしか使わない。
 *  未知の id は根と同じ 0（`arrow` は先に `L.boxes.get(anchor)` で弾くので届かない） */
function depthOf(L: core.Layout, id: number): number {
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
export function arrow(L: core.Layout, anchor: number | null, key: ArrowKey): number | null {
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
export const parentOf = (L: core.Layout, id: number): number | null => L.boxes.get(id)?.parent?.id ?? null;

/** 同じ親の子（根なら根どうし）を文書順に */
const siblingsOf = (L: core.Layout, id: number): number[] => {
  const p = parentOf(L, id);
  return L.order.filter((x) => parentOf(L, x) === p);
};

export function prevSibling(L: core.Layout, id: number): number | null {
  const s = siblingsOf(L, id);
  const i = s.indexOf(id);
  return i > 0 ? s[i - 1] : null;
}

export function nextSibling(L: core.Layout, id: number): number | null {
  const s = siblingsOf(L, id);
  const i = s.indexOf(id);
  return i >= 0 && i < s.length - 1 ? s[i + 1] : null;
}

/** ちょうど 1 つ選んでいる id。宛先が 1 つに決まる操作はこれを見る */
export const solo = (sel: Selection): number | null =>
  sel.ids.length === 1 && sel.anchor !== null ? sel.anchor : null;

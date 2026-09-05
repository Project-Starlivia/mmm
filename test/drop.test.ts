// resolveDrop / dropOp — 落とし先の算術。DOM も Mindmap も知らない。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { type Drop, dropOp, resolveDrop } from "../src/map/drop.ts";
import { type Box, type Layout, type SizeOf, layoutMap } from "../src/map/layout.ts";
import { centerOf } from "../src/map/geometry.ts";

/** 全部 100 × 30 */
const size: SizeOf = () => ({ w: 100, h: 30 });

const node = (id: number, label: string | null, children: core.Node[] = []): core.Node => ({
  id,
  label,
  fold: null,
  blocks: [],
  children,
});

const root = (n: core.Node, sides: core.Side[] = []): core.Root => ({ node: n, sides });

/** r(1) → a(2), b(3)。両方右側 */
const L: Layout = layoutMap([root(node(1, "r", [node(2, "a"), node(3, "b")]), ["Right", "Right"])], size);

const box = (id: number): Box => {
  const b = L.boxes.get(id);
  assert.ok(b, `box ${id} が無い`);
  return b;
};

const drop = (at: { x: number; y: number }, dragging: Set<number> = new Set()): Drop | null =>
  resolveDrop({ at, layout: L, dragging });

test("箱の中心 → その子", () => {
  assert.deepEqual(drop(centerOf(box(2))), { kind: "node", id: 2, pos: 0 });
});

test("箱の上下の帯 → 直前 / 直後", () => {
  const a = box(2);
  const c = centerOf(a);
  assert.deepEqual(drop({ x: c.x, y: a.y - 10 }), { kind: "node", id: 2, pos: 1 });
  // 下は GAP.y ぶんしか空いていない（b がすぐ下）ので、a に近い範囲で当てる
  assert.deepEqual(drop({ x: c.x, y: a.y + a.h + 3 }), { kind: "node", id: 2, pos: 2 });
});

test("箱の外側ゾーン（成長する側）→ 子", () => {
  const a = box(2);
  const c = centerOf(a);
  // 帯（SLOP）の外・外側ゾーン（REACH）の内で当てる
  assert.deepEqual(drop({ x: a.x + a.w + 30, y: c.y }), { kind: "node", id: 2, pos: 0 });
});

test("根の外側 / 根の箱の中（中心より右） → 側・右（子が居る側）", () => {
  const r = box(1);
  const c = centerOf(r);
  assert.deepEqual(drop({ x: r.x + r.w + 10, y: c.y }), { kind: "side", root: 1, left: false });
  assert.deepEqual(drop({ x: r.x + r.w - 5, y: c.y }), { kind: "side", root: 1, left: false });
});

test("根の左外側（子が居ない側） → 側・左", () => {
  const r = box(1);
  const c = centerOf(r);
  assert.deepEqual(drop({ x: r.x - 10, y: c.y }), { kind: "side", root: 1, left: true });
});

test("遠い空所 → null", () => {
  assert.equal(drop({ x: 5000, y: 5000 }), null);
});

test("掴んでいる部分木は落とし先から外れる", () => {
  // a(2) を掴んだままその中心へ落としても、a 自身は候補に出ない
  assert.deepEqual(drop(centerOf(box(2)), new Set([2])), { kind: "node", id: 3, pos: 1 });
});

test("dropOp — node の 3 形と side", () => {
  assert.deepEqual(dropOp({ kind: "node", id: 2, pos: 0 }, [5]), {
    kind: "moveNode",
    ids: [5],
    at: { kind: "in", node: 2, side: null },
  });
  assert.deepEqual(dropOp({ kind: "node", id: 2, pos: 1 }, [5]), {
    kind: "moveNode",
    ids: [5],
    at: { kind: "before", node: 2 },
  });
  assert.deepEqual(dropOp({ kind: "node", id: 2, pos: 2 }, [5]), {
    kind: "moveNode",
    ids: [5],
    at: { kind: "after", node: 2 },
  });
  assert.deepEqual(dropOp({ kind: "side", root: 1, left: true }, [5]), {
    kind: "moveNode",
    ids: [5],
    at: { kind: "in", node: 1, side: "Left" },
  });
});

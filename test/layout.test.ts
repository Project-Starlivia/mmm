// View の木 → 箱の配置。寸法は数で渡すので、DOM 無しで置き方だけを固定できる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { GAP, type Layout, type SizeOf, edgeEnds, layoutMap, rootBox } from "../src/map/layout.ts";

/** 全部 100 × 30 */
const size: SizeOf = () => ({ w: 100, h: 30 });

const node = (
  id: number,
  label: string | null,
  children: core.Node[] = [],
  fold: core.Fold | null = null,
): core.Node => ({ id, label, fold, blocks: [], children });

const tree = (n: core.Node, sides: core.Side[] = []): core.Tree => ({ node: n, sides });

const box = (L: Layout, id: number) => {
  const b = L.boxes.get(id);
  if (!b) throw new Error(`box ${id} が無い`);
  return b;
};

test("根は x = 0 で親を持たず、子は右へ GAP.x 離れて親に繋がる", () => {
  const L = layoutMap([tree(node(1, "r", [node(2, "a")]))], size);
  assert.equal(box(L, 1).x, 0);
  assert.equal(box(L, 1).parent, null);
  assert.equal(box(L, 2).x, 100 + GAP.x);
  assert.deepEqual(box(L, 2).parent, { id: 1, side: "Right" });
});

test("親は第 1 子と最終子の中心の中点に立つ", () => {
  const L = layoutMap([tree(node(1, "r", [node(2, "a"), node(3, "b"), node(4, "c")]))], size);
  // 子の中心は 15, 55, 95（高さ 30 + 隙間 10）。中点 55 → 上端 40
  assert.equal(box(L, 1).y, 40);
  assert.equal(box(L, 2).y, 0);
  assert.equal(box(L, 4).y, 80);
});

test("側は根の子が sides から受け、孫は親から継ぐ", () => {
  const L = layoutMap(
    [tree(node(1, "r", [node(2, "a"), node(3, "b", [node(4, "c")])]), ["Right", "Left"])],
    size,
  );
  assert.equal(box(L, 3).x, -GAP.x - 100);
  assert.deepEqual(box(L, 3).parent, { id: 1, side: "Left" });
  assert.equal(box(L, 4).x, box(L, 3).x - GAP.x - 100);
  assert.deepEqual(box(L, 4).parent, { id: 3, side: "Left" });
});

test("sides が足りなければ右", () => {
  const L = layoutMap([tree(node(1, "r", [node(2, "a"), node(3, "b")]), ["Left"])], size);
  assert.equal(box(L, 2).parent?.side, "Left");
  assert.equal(box(L, 3).parent?.side, "Right");
});

test("畳んだノードの下は置かず、埋もれた子孫の数だけ残る", () => {
  const folded = node(2, "a", [node(3, "b", [node(4, "c")])], { open: false, summary: null });
  const L = layoutMap([tree(node(1, "r", [folded]))], size);
  assert.deepEqual(L.order, [1, 2]);
  assert.equal(L.boxes.has(3), false);
  assert.equal(box(L, 2).buried, 2);
  assert.equal(box(L, 1).buried, 0);
});

test("順は文書順（親が先、子はその後）", () => {
  const L = layoutMap([tree(node(1, "r", [node(2, "a", [node(3, "x")]), node(4, "b")]))], size);
  assert.deepEqual(L.order, [1, 2, 3, 4]);
});

test("木は縦に積まれ、隙間は GAP.root", () => {
  const L = layoutMap([tree(node(1, "a")), tree(node(2, "b"))], size);
  assert.equal(box(L, 1).y, 0);
  assert.equal(box(L, 2).y, 30 + GAP.root);
  assert.equal(rootBox(L)?.node.id, 1);
});

test("Implicit は label が null のまま sizeOf に渡る", () => {
  const seen: (string | null)[] = [];
  const spy: SizeOf = (n) => {
    seen.push(n.label);
    return { w: 100, h: 30 };
  };
  layoutMap([tree(node(1, "r", [node(2, null, [node(3, "x")])]))], spy);
  assert.ok(seen.includes(null));
});

test("線は親の育つ辺から出て、子の親を向いた辺へ入る", () => {
  const L = layoutMap([tree(node(1, "r", [node(2, "a"), node(3, "b")]), ["Right", "Left"])], size);
  const right = edgeEnds(L, 2);
  const left = edgeEnds(L, 3);
  assert.ok(right && left);
  assert.equal(right.from.x, 100);
  assert.equal(right.to.x, 100 + GAP.x);
  assert.equal(left.from.x, 0);
  assert.equal(left.to.x, -GAP.x);
  assert.equal(edgeEnds(L, 1), null);
});

test("空なら空", () => {
  const L = layoutMap([], size);
  assert.deepEqual(L.order, []);
  assert.equal(rootBox(L), null);
});

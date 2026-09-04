// 選択の値と、入力でそれがどう変わるか。箱は layoutMap に組ませる（配置は layout.test.ts が固定済み）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { GAP, type Layout, type SizeOf, layoutMap } from "../src/map/layout.ts";
import { NONE, all, arrow, click, extend, hit, rubber } from "../src/map/select.ts";

/** 全部 100 × 30 */
const size: SizeOf = () => ({ w: 100, h: 30 });

const node = (id: number, label: string, children: core.Node[] = []): core.Node => ({
  id,
  label,
  fold: null,
  blocks: [],
  children,
});

const tree = (n: core.Node, sides: core.Side[] = []): core.Tree => ({ node: n, sides });

/** r(1) → a(2), b(3) → c(4)。b は左の枝 */
const L: Layout = layoutMap(
  [tree(node(1, "r", [node(2, "a"), node(3, "b", [node(4, "c")])]), ["Right", "Left"])],
  size,
);

test("クリック — 選ぶ。Shift は anchor から文書順に範囲、Mod は足す・外す", () => {
  const one = click(NONE, 3, "none", L.order);
  assert.deepEqual(one, { ids: [3], anchor: 3 });
  assert.deepEqual(click(one, 1, "shift", L.order), { ids: [1, 2, 3], anchor: 3 });
  assert.deepEqual(click(one, 1, "mod", L.order), { ids: [1, 3], anchor: 1 });
  assert.deepEqual(click({ ids: [1, 3], anchor: 1 }, 3, "mod", L.order), { ids: [1], anchor: 1 });
  // anchor が無ければ Shift も普通のクリック
  assert.deepEqual(click(NONE, 2, "shift", L.order), { ids: [2], anchor: 2 });
});

test("矩形 — 触れる箱を全部。anchor は文書順の最後", () => {
  // a は (100 + GAP.x, 0) から 100 × 30
  const x = 100 + GAP.x;
  assert.deepEqual(rubber(L, { x: x + 90, y: 20, w: 20, h: 20 }), { ids: [2], anchor: 2 });
  assert.deepEqual(rubber(L, { x: -1000, y: -1000, w: 3000, h: 3000 }), { ids: [1, 2, 3, 4], anchor: 4 });
  assert.deepEqual(rubber(L, { x: 5000, y: 5000, w: 1, h: 1 }), NONE);
});

test("点 — どの箱に居るか。外なら null", () => {
  const a = L.boxes.get(2);
  if (!a) throw new Error("a が無い");
  assert.equal(hit(L, a.x + 1, a.y + 1), 2);
  assert.equal(hit(L, a.x + a.w + 1, a.y), null);
});

test("矢印 — 上下は同じ深さの列を端でループ、何も選んでいなければ先頭", () => {
  assert.equal(arrow(L, null, "ArrowDown"), 1);
  assert.equal(arrow(L, 2, "ArrowDown"), 3);
  assert.equal(arrow(L, 3, "ArrowDown"), 2);
  assert.equal(arrow(L, 2, "ArrowUp"), 3);
  // 根の列は 1 つだけなので自分に戻る
  assert.equal(arrow(L, 1, "ArrowDown"), 1);
});

test("矢印 — 左右は画面の向き。右の枝は ← が親、左の枝は鏡像。子が無ければ先頭へ", () => {
  assert.equal(arrow(L, 2, "ArrowLeft"), 1);
  assert.equal(arrow(L, 1, "ArrowRight"), 2);
  assert.equal(arrow(L, 2, "ArrowRight"), 1); // a に子は無い → 先頭
  assert.equal(arrow(L, 3, "ArrowRight"), 1); // b は左の枝。→ が親
  assert.equal(arrow(L, 3, "ArrowLeft"), 4); // ← が子
  assert.equal(arrow(L, 1, "ArrowLeft"), null); // 根に親は無い
});

test("Shift+矢印 — 行き先を足す。既に選んでいれば、いま居た側を外して縮める", () => {
  const two = extend({ ids: [2], anchor: 2 }, 3);
  assert.deepEqual(two, { ids: [2, 3], anchor: 3 });
  assert.deepEqual(extend(two, 2), { ids: [2], anchor: 2 });
});

test("Shift+矢印 — 行き先が anchor 自身なら何もしない（同じ深さが 1 つだけ・回った先）", () => {
  assert.deepEqual(extend({ ids: [1, 2], anchor: 1 }, 1), { ids: [1, 2], anchor: 1 });
});

test("全部", () => {
  assert.deepEqual(all(L), { ids: [1, 2, 3, 4], anchor: 4 });
});

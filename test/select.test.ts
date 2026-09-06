// 選択の値と、入力でそれがどう変わるか。箱は layoutMap に組ませる（配置は layout.test.ts が固定済み）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { GAP, type Layout, type SizeOf, layoutMap } from "../src/map/layout.ts";
import { NONE, type Reach, all, arrow, click, extend, hit, nextSibling, parentOf, prevSibling, rubber, NOTHING, cardOf, nodesOf } from "../src/map/select.ts";

/** 四方に pad だけ。端の伸びは無し */
const grow = (pad: number): Reach => ({ pad, edge: 0 });

/** 全部 100 × 30 */
const size: SizeOf = () => ({ w: 100, h: 30 });

const node = (id: number, label: string, children: core.Node[] = []): core.Node => ({
  id,
  label,
  fold: null,
  blocks: [],
  children,
});

const root = (n: core.Node, sides: core.Side[] = []): core.Root => ({ node: n, sides });

/** r(1) → a(2), b(3) → c(4)。b は左の枝 */
const L: Layout = layoutMap(
  [root(node(1, "r", [node(2, "a"), node(3, "b", [node(4, "c")])]), ["Right", "Left"])],
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
  assert.equal(hit(L, a.x + 1, a.y + 1, grow(0)), 2);
  assert.equal(hit(L, a.x + a.w + 1, a.y, grow(0)), null);
});

// r は (0, 0) から 100 × 30、a は右隣 (145, 0) から。隙間は 100 〜 145
test("点 — 範囲のぶん箱の外でも当たる。角も範囲の矩形どおり", () => {
  assert.equal(hit(L, 105, 15, grow(8)), 1);
  assert.equal(hit(L, 105, 15, grow(0)), null);
  assert.equal(hit(L, 110, 15, grow(8)), null);
  assert.equal(hit(L, 107, 37, grow(8)), 1);
  assert.equal(hit(L, 109, 37, grow(8)), null);
});

// r(1) → a(2), b(3) → c(4)。みな右の枝、100 × 30。
// r (0, 20) / a (145, 0) / b (145, 40) / c (290, 40)。端（子が見えない）は a と c
const M: Layout = layoutMap(
  [root(node(1, "r", [node(2, "a"), node(3, "b", [node(4, "c")])]), ["Right", "Right"])],
  size,
);

test("端の伸び — 子の見えない端だけ、枝の向きに edge。根と親は伸びない。左の枝は左へ", () => {
  const r = { pad: 8, edge: 60 };
  assert.equal(hit(M, 390 + 8 + 30, 55, r), 4); // c の右 38 は far の中
  assert.equal(hit(M, 390 + 8 + 30, 55, grow(8)), null);
  assert.equal(hit(M, 245 + 8 + 20, 55, r), null); // b の右へは伸びない（子が居る）。c の帯(290 − 8)にも届かない
  assert.equal(hit(M, -8 - 30, 35, r), null); // 根の左へも伸びない
  assert.equal(hit(L, -290 - 8 - 30, 15, r), 4); // 左の枝の端 c は左へ伸びる
  assert.equal(hit(L, -190 + 8 + 20, 15, r), null); // 右（親側）へは伸びない。親 b の帯(−145 − 8)にも届かない
});

test("点 — 端の伸びだけで届く箱が居れば、y の近さ → x の近さで選ぶ", () => {
  // 端の a が右へ 60 伸びると、弟 b の子 c の列（x 290〜）に届く
  const r = { pad: 15, edge: 60 };
  // (285, 29): c の帯の中（dx 5, dy 11）。a は far だけで届き、y は a の行の中（dy 0）→ 行で読んで a
  assert.equal(hit(M, 285, 29, r), 2);
  // 伸びが無ければ直線距離で c
  assert.equal(hit(M, 285, 29, grow(15)), 4);
  // (285, 35): y は a も c も 5 → x が近い c
  assert.equal(hit(M, 285, 35, r), 4);
});

test("点 — 余白が被ったら近い箱。同じ距離なら文書順の後ろ", () => {
  assert.equal(hit(L, 115, 15, grow(30)), 1);
  assert.equal(hit(L, 130, 15, grow(30)), 2);
  assert.equal(hit(L, 122.5, 15, grow(30)), 2);
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

test("兄弟と親 — 同じ親の文書順で前後。根の兄弟は根どうし", () => {
  assert.equal(parentOf(L, 2), 1);
  assert.equal(parentOf(L, 1), null);
  assert.equal(prevSibling(L, 3), 2);
  assert.equal(nextSibling(L, 2), 3);
  assert.equal(prevSibling(L, 2), null);
  assert.equal(nextSibling(L, 3), null);
  assert.equal(nextSibling(L, 4), null);
});

test("選択は 1 つの値 — ノードの並びかカード 1 枚か。見方は片方が空", () => {
  assert.deepEqual(nodesOf(NOTHING), { ids: [], anchor: null });
  assert.equal(cardOf(NOTHING), null);
  assert.deepEqual(nodesOf({ kind: "nodes", sel: { ids: [2, 3], anchor: 3 } }), { ids: [2, 3], anchor: 3 });
  assert.equal(cardOf({ kind: "card", id: 7 }), 7);
  assert.deepEqual(nodesOf({ kind: "card", id: 7 }), { ids: [], anchor: null });
});

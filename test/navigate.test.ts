// 矢印キーの行き先と、Shift での広げ方。
// 「同じ深さの列を辿る（いとこも含む・端でループ）」は説明を読んでも
// 自明でないので、ここで形を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { arrowTarget, extendSelection } from "../src/map/navigate.ts";
import type { Layout } from "../src/map/layout.ts";
import type { NodeInfo } from "../src/coreApi.ts";

const node = (id: number, depth: number, parent: number): NodeInfo => ({
  id,
  depth,
  parent,
  from: id * 10,
  headEnd: id * 10 + 5,
  to: id * 10 + 9,
  hasContent: false,
  hidden: false,
  group: 0,
  left: false,
  label: `n${id}`,
});

/** 見えているノードだけを渡した最小のレイアウト（箱は空でよい大きさ） */
function layoutOf(visible: NodeInfo[]): Layout {
  return {
    visible,
    boxes: new Map(
      visible.map((n) => [n.id, { n, x: 0, y: 0, w: 10, h: 10, rows: [] }]),
    ),
    parentOf: new Map(
      visible.filter((n) => n.parent !== -1).map((n) => [n.id, n.parent]),
    ),
    buriedCount: new Map(),
    fanOf: new Map(),
  };
}

//   root(1)
//     ├ a(2)  ─ a1(4)
//     └ b(3)  ─ b1(5)
const ROOT = node(1, 1, -1);
const A = node(2, 2, 1);
const B = node(3, 2, 1);
const A1 = node(4, 3, 2);
const B1 = node(5, 3, 3);
const ALL = [ROOT, A, A1, B, B1];
const L = layoutOf(ALL);

test("下は同じ深さの次へ、上はその逆", () => {
  assert.equal(arrowTarget(ALL, L, A.id, "ArrowDown"), B.id);
  assert.equal(arrowTarget(ALL, L, B.id, "ArrowUp"), A.id);
});

test("同じ深さなら、親が違ういとこも同じ列に入る", () => {
  // a1(親 a) の次は b1(親 b)。兄弟に限ると、ここで行き止まりになる
  assert.equal(arrowTarget(ALL, L, A1.id, "ArrowDown"), B1.id);
  assert.equal(arrowTarget(ALL, L, B1.id, "ArrowUp"), A1.id);
});

test("列の端ではループする", () => {
  assert.equal(arrowTarget(ALL, L, B.id, "ArrowDown"), A.id);
  assert.equal(arrowTarget(ALL, L, A.id, "ArrowUp"), B.id);
  // 1 つしか居ない列（ルート）は自分に戻る
  assert.equal(arrowTarget(ALL, L, ROOT.id, "ArrowDown"), ROOT.id);
});

test("左は親へ、右は最初の子へ", () => {
  assert.equal(arrowTarget(ALL, L, A.id, "ArrowLeft"), ROOT.id);
  assert.equal(arrowTarget(ALL, L, A.id, "ArrowRight"), A1.id);
  assert.equal(arrowTarget(ALL, L, ROOT.id, "ArrowLeft"), -1); // 親が無い
});

test("子が無ければ、右は先頭へ回る", () => {
  // 行き止まりで無反応になるより、一周できるほうが迷わない
  assert.equal(arrowTarget(ALL, L, A1.id, "ArrowRight"), ROOT.id);
});

test("畳まれて埋もれた子へは飛ばない", () => {
  // a を畳むと a1 は見えなくなる。それでも「子が無い」ではなく
  // 「見えている子が無い」として扱い、先頭へ回る
  const folded = layoutOf([ROOT, { ...A, hidden: true }, B, B1]);
  assert.equal(arrowTarget(ALL, folded, A.id, "ArrowRight"), ROOT.id);
});

test("何も選んでいなければ、まず先頭へ", () => {
  assert.equal(arrowTarget(ALL, L, -1, "ArrowDown"), ROOT.id);
  assert.equal(arrowTarget(ALL, layoutOf([]), -1, "ArrowDown"), -1);
});

test("Shift は行き先を選択に足す", () => {
  assert.deepEqual(extendSelection(new Set([2]), 2, 3), [2, 3]);
});

test("Shift で戻ると、行きすぎたぶんが縮む", () => {
  // 2,3 を選んで anchor が 3 のとき、2 へ戻ると 3 が外れる
  assert.deepEqual(extendSelection(new Set([2, 3]), 3, 2), [2]);
});

test("1 つしか選んでいなければ、戻っても縮まない", () => {
  // 自分だけを外して空にはしない
  assert.deepEqual(extendSelection(new Set([2]), 2, 2), [2]);
});

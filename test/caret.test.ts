// md のカーソルがどのノードに掛かっているか。区間の重なりだけの層。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { caretIds } from "../src/caret.ts";

const node = (id: number, label: string | null, children: core.Node[] = []): core.Node => ({
  id,
  label,
  fold: null,
  blocks: [],
  children,
});

const view = (...trees: core.Node[]): core.View => ({
  frontmatter: null,
  trees: trees.map((n) => ({ node: n, sides: n.children.map(() => "Right" as const) })),
});

const spots = (rows: [number, number, number | null, number][]): Map<number, core.Spot> =>
  new Map(rows.map(([id, from, label, to]) => [id, { from, label, to }]));

/** "# r\n\n## a\n\nhello\n\n## b\n" */
const doc = view(node(2, "r", [node(3, "a"), node(5, "b")]));
const at = spots([
  [1, 0, null, 0],
  [2, 0, 2, 23],
  [3, 5, 8, 17],
  [5, 18, 21, 23],
]);
const point = (p: number) => [{ from: p, to: p }];

test("最も深いノードだけ。自身の文は地番の頭から最初の子の頭まで", () => {
  assert.deepEqual(caretIds(doc, at, point(1)), [2]);
  assert.deepEqual(caretIds(doc, at, point(7)), [3]);
  assert.deepEqual(caretIds(doc, at, point(12)), [3]); // hello の中
  assert.deepEqual(caretIds(doc, at, point(20)), [5]);
});

test("閉じ際は中と見なす — 継ぎ目ちょうどでは両側", () => {
  assert.deepEqual(caretIds(doc, at, point(5)), [2, 3]);
  assert.deepEqual(caretIds(doc, at, point(17)), [3]);
});

test("範囲と複数カーソルは掛かるもの全部。無ければ空", () => {
  assert.deepEqual(caretIds(doc, at, [{ from: 1, to: 20 }]), [2, 3, 5]);
  assert.deepEqual(caretIds(doc, at, [{ from: 1, to: 1 }, { from: 20, to: 20 }]), [2, 5]);
  assert.deepEqual(caretIds(doc, at, []), []);
});

test("Implicit は行が無く自身の文が空なので掛からない", () => {
  // "# r\n\n### x\n": r=2, Implicit=3, x=4
  const gap = view(node(2, "r", [node(3, null, [node(4, "x")])]));
  const s = spots([
    [1, 0, null, 0],
    [2, 0, 2, 11],
    [3, 5, null, 11],
    [4, 5, 9, 11],
  ]);
  assert.deepEqual(caretIds(gap, s, point(7)), [4]);
  assert.deepEqual(caretIds(gap, s, point(5)), [2, 4]);
});

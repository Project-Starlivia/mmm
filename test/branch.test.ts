// 書き出す範囲 = 選んだ枝。
//
// mmm では「選ぶ」がどこでも枝ごとを意味する（コピー・カット・削除・移動）。
// 書き出しだけ別の意味になっていないことを、ここで固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type NodeInfo, idOf, loadDoc } from "./_helpers.ts";
import { type Layout, branchIds } from "../src/map/layout.ts";

/**
 * `branchIds` が読むのは `visible` と `parentOf` だけ。実物の
 * `layoutMap` は幅を測るのに canvas を要るので、コアが出したノードから
 * 同じ 2 つを組んで渡す。
 */
function layoutOf(nodes: NodeInfo[], hiddenAway: number[] = []): Layout {
  const buried = new Set(hiddenAway);
  const visible = nodes.filter((n) => !buried.has(n.id));
  const parentOf = new Map<number, number>();
  for (const n of visible) {
    if (n.parent !== -1 && !buried.has(n.parent)) parentOf.set(n.id, n.parent);
  }
  return {
    visible,
    parentOf,
    boxes: new Map(),
    buriedCount: new Map(),
    fanOf: new Map(),
    seams: [],
  };
}

const MD = `# 根

## 枝 A

### A の子

#### A の孫

## 枝 B

### B の子
`;

const labelsOf = (nodes: NodeInfo[], ids: Set<number>): string[] =>
  nodes.filter((n) => ids.has(n.id)).map((n) => n.label);

test("何も選んでいなければ全体", () => {
  const { nodes } = loadDoc(MD);
  const got = branchIds(layoutOf(nodes), new Set());
  assert.deepEqual(labelsOf(nodes, got), [
    "根",
    "枝 A",
    "A の子",
    "A の孫",
    "枝 B",
    "B の子",
  ]);
});

test("枝を選ぶと、その子孫が全部入る。兄弟は入らない", () => {
  const { nodes } = loadDoc(MD);
  const got = branchIds(layoutOf(nodes), new Set([idOf(nodes, "枝 A")]));
  assert.deepEqual(labelsOf(nodes, got), ["枝 A", "A の子", "A の孫"]);
});

test("葉を選べば、それだけ", () => {
  const { nodes } = loadDoc(MD);
  const got = branchIds(layoutOf(nodes), new Set([idOf(nodes, "A の孫")]));
  assert.deepEqual(labelsOf(nodes, got), ["A の孫"]);
});

test("複数選ぶと合併になる", () => {
  const { nodes } = loadDoc(MD);
  const got = branchIds(
    layoutOf(nodes),
    new Set([idOf(nodes, "A の子"), idOf(nodes, "枝 B")]),
  );
  assert.deepEqual(labelsOf(nodes, got), [
    "A の子",
    "A の孫",
    "枝 B",
    "B の子",
  ]);
});

test("入れ子に選んでも重複しない（親と子を両方選ぶ）", () => {
  const { nodes } = loadDoc(MD);
  const got = branchIds(
    layoutOf(nodes),
    new Set([idOf(nodes, "枝 A"), idOf(nodes, "A の孫")]),
  );
  assert.equal(got.size, 3);
  assert.deepEqual(labelsOf(nodes, got), ["枝 A", "A の子", "A の孫"]);
});

test("根を選べば全部入る（何も選ばないのと同じ絵になる）", () => {
  const { nodes } = loadDoc(MD);
  const layout = layoutOf(nodes);
  const root = branchIds(layout, new Set([idOf(nodes, "根")]));
  assert.deepEqual(labelsOf(nodes, root), labelsOf(nodes, branchIds(layout, new Set())));
});

test("畳んで埋もれた子孫は入らない。畳んだ姿がそのまま出る", () => {
  const { nodes } = loadDoc(MD);
  // 「枝 A」を畳んだ = その下が見えていない
  const layout = layoutOf(nodes, [idOf(nodes, "A の子"), idOf(nodes, "A の孫")]);
  const got = branchIds(layout, new Set([idOf(nodes, "枝 A")]));
  assert.deepEqual(labelsOf(nodes, got), ["枝 A"]);
});

test("見えていないものを選んでも、見えているものだけが入る", () => {
  const { nodes } = loadDoc(MD);
  const layout = layoutOf(nodes, [idOf(nodes, "A の孫")]);
  const got = branchIds(layout, new Set([idOf(nodes, "A の孫")]));
  assert.equal(got.size, 0);
});

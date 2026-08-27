// rootId(視点を寄せる/指す先の既定)。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type NodeInfo, idOf, loadDoc } from "./_helpers.ts";
import { type Box, type Layout, rootId } from "../src/map/layout.ts";

/** rootId が読むのは boxes の n だけ。寸法は要らない。 */
function layoutOf(nodes: NodeInfo[]): Layout {
  const boxes = new Map<number, Box>();
  for (const n of nodes) boxes.set(n.id, { n, x: 0, y: 0, w: 0, h: 0, rows: [] });
  return {
    visible: nodes,
    boxes,
    parentOf: new Map(),
    buriedCount: new Map(),
    fanOf: new Map(),
  };
}

test("ルートは深さ1で親を持たないノード", () => {
  const { nodes } = loadDoc("# 根\n\n## 枝\n");
  assert.equal(rootId(layoutOf(nodes)), idOf(nodes, "根"));
});

test("複数の # があっても、最初の深さ1が主ルート", () => {
  const { nodes } = loadDoc("# 根\n\n# 別の根\n");
  assert.equal(rootId(layoutOf(nodes)), idOf(nodes, "根"));
});

test("箱が無ければ null（空文書）", () => {
  assert.equal(rootId(layoutOf([])), null);
});

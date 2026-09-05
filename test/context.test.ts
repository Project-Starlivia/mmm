// 右クリックの行。Intent の表で、沈む行は理由を持つ。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { type Entry, contextItems } from "../src/map/context.ts";
import { type Layout, type SizeOf, layoutMap } from "../src/map/layout.ts";

const size: SizeOf = () => ({ w: 100, h: 30 });
const node = (id: number, label: string | null, children: core.Node[] = [], fold: core.Fold | null = null): core.Node => ({
  id,
  label,
  fold,
  blocks: [],
  children,
});
const tree = (n: core.Node, sides: core.Side[] = []): core.Tree => ({ node: n, sides });
const L: Layout = layoutMap(
  [tree(node(2, "r", [node(3, "a", [], { open: false, summary: "a" }), node(4, null, [node(5, "x")])]), ["Right", "Right"])],
  size,
);

const labels = (es: Entry[]) => es.map((e) => (e === "sep" ? "—" : e.label));
const row = (es: Entry[], label: string) => {
  const e = es.find((x) => x !== "sep" && x.label === label);
  if (!e || e === "sep") throw new Error(`${label} が無い`);
  return e;
};

test("並び — Add / Rename / Hide / Flip side / Link / Code / Draw / Copy / Cut / Paste / Delete", () => {
  assert.deepEqual(labels(contextItems(L, { ids: [3], anchor: 3 })), [
    "Add", "Rename", "—", "Show (unfold)", "Flip side", "—", "Link", "Code", "Draw", "—", "Copy", "Cut", "Paste", "—", "Delete",
  ]);
});

test("Copy / Cut はキーと同じ Intent。選んでいなければ沈み、Paste は沈まない", () => {
  const es = contextItems(L, { ids: [3, 5], anchor: 5 });
  assert.deepEqual(row(es, "Copy").intent, { kind: "copy", cut: null });
  // Cut の消し方は Delete の行そのもの
  assert.deepEqual(row(es, "Cut").intent, { kind: "copy", cut: row(es, "Delete").intent });
  assert.deepEqual(row(es, "Paste").intent, { kind: "paste" });
  const none = contextItems(L, { ids: [], anchor: null });
  assert.equal(row(none, "Copy").intent, null);
  assert.equal(row(none, "Cut").intent, null);
  assert.deepEqual(row(none, "Paste").intent, { kind: "paste" });
});

test("Add は押せば子、開けば 4 つ", () => {
  const add = row(contextItems(L, { ids: [3], anchor: 3 }), "Add");
  assert.deepEqual(add.intent, { kind: "op", op: { kind: "addNode", at: { kind: "in", node: 3, side: null }, labels: [""] }, edit: true });
  assert.deepEqual(add.items?.map((i) => i.label), ["Child", "Below", "Above", "Parent"]);
  // 名前の無いノードでも Below は「足す」（Enter のように「埋める」へ化けない）
  const blank = row(contextItems(L, { ids: [4], anchor: 4 }), "Add").items?.find((i) => i.label === "Below");
  assert.deepEqual(blank?.intent, { kind: "op", op: { kind: "addNode", at: { kind: "after", node: 4 }, labels: [""] }, edit: true });
});

test("複数選択では宛先が 1 つの行が沈む。Delete は沈まない", () => {
  const es = contextItems(L, { ids: [3, 5], anchor: 5 });
  assert.equal(row(es, "Add").intent, null);
  assert.equal(row(es, "Add").why, "Select one node");
  assert.equal(row(es, "Rename").why, "Select one node");
  assert.equal(row(es, "Link").why, "Select one node");
  assert.notEqual(row(es, "Delete").intent, null);
});

test("Implicit は畳めず、根は側を持たない", () => {
  assert.equal(row(contextItems(L, { ids: [4], anchor: 4 }), "Hide (fold)").why, "Nothing to fold here");
  assert.equal(row(contextItems(L, { ids: [2], anchor: 2 }), "Flip side").why, "The root has no side");
  assert.deepEqual(row(contextItems(L, { ids: [5], anchor: 5 }), "Flip side").intent, { kind: "op", op: { kind: "flipSide", id: 5 }, edit: false });
});

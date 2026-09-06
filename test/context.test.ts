// 右クリックの行。Intent の表で、沈む行は理由を持つ。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type Entry, contextItems } from "../src/map/context.ts";
import { place } from "./tools/place.ts";

/** r(2) → Implicit(3) → x(4), a(5。summary a で畳んである。散文 6 は View に来ない）。
 *  x を先に置くのは、`### x` が `## a` の後ろに来ると a の子になって畳みの形が崩れるため */
const L = place("# r\n\n### x\n\n<details>\n<summary>a</summary>\n\n## a\n\nbody\n\n</details>\n");

const labels = (es: Entry[]) => es.map((e) => (e === "sep" ? "—" : e.label));
const row = (es: Entry[], label: string) => {
  const e = es.find((x) => x !== "sep" && x.label === label);
  if (!e || e === "sep") throw new Error(`${label} が無い`);
  return e;
};

test("並び — Add / Rename / Hide / Flip side / Link / Code / Draw / Copy / Cut / Paste / Delete", () => {
  assert.deepEqual(labels(contextItems(L, { ids: [5], anchor: 5 })), [
    "Add", "Rename", "—", "Show (unfold)", "Flip side", "—", "Link", "Code", "Draw", "—", "Copy", "Cut", "Paste", "—", "Delete",
  ]);
});

test("Copy / Cut はキーと同じ Intent。選んでいなければ沈み、Paste は沈まない", () => {
  const es = contextItems(L, { ids: [4, 5], anchor: 4 });
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
  const add = row(contextItems(L, { ids: [5], anchor: 5 }), "Add");
  assert.deepEqual(add.intent, { kind: "op", op: { kind: "addNode", at: { kind: "in", node: 5, side: null }, labels: [""] }, edit: true });
  assert.deepEqual(add.items?.map((i) => i.label), ["Child", "Below", "Above", "Parent"]);
  // 名前の無いノードでも Below は「足す」（Enter のように「埋める」へ化けない）
  const blank = row(contextItems(L, { ids: [3], anchor: 3 }), "Add").items?.find((i) => i.label === "Below");
  assert.deepEqual(blank?.intent, { kind: "op", op: { kind: "addNode", at: { kind: "after", node: 3 }, labels: [""] }, edit: true });
});

test("複数選択では宛先が 1 つの行が沈む。Delete は沈まない", () => {
  const es = contextItems(L, { ids: [4, 5], anchor: 4 });
  assert.equal(row(es, "Add").intent, null);
  assert.equal(row(es, "Add").why, "Select one node");
  assert.equal(row(es, "Rename").why, "Select one node");
  assert.equal(row(es, "Link").why, "Select one node");
  assert.notEqual(row(es, "Delete").intent, null);
});

test("Implicit も畳める。根は側を持たない", () => {
  assert.deepEqual(row(contextItems(L, { ids: [3], anchor: 3 }), "Hide (fold)").intent, { kind: "op", op: { kind: "fold", id: 3, open: false }, edit: false });
  assert.equal(row(contextItems(L, { ids: [2], anchor: 2 }), "Flip side").why, "The root has no side");
  assert.deepEqual(row(contextItems(L, { ids: [4], anchor: 4 }), "Flip side").intent, { kind: "op", op: { kind: "flipSide", id: 4 }, edit: false });
});

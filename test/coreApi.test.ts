// core の出口と入口の境界。形を確かめる側の規則を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import * as core from "../src/coreApi.ts";
import { survey } from "../src/coreApi.ts";

test("survey は持ち手 — 問い合わせで読む。地番の label が無ければ null、無い id は null", () => {
  const s = survey("# r\n\n## a\n\n```\nx\n```\n");
  assert.equal(core.empty(s), false);
  assert.equal(core.empty(survey("")), true);
  assert.deepEqual(core.spot(s, 3), { from: 5, label: 8, to: 21 }); // 地番は中身まで
  assert.deepEqual(core.spot(s, 4), { from: 11, label: null, to: 21 });
  assert.equal(core.spot(s, 9), null);
  assert.equal(core.find(s, "a"), 3);
  assert.equal(core.find(s, "z"), null);
  assert.deepEqual(core.blocks(s, 3), [4]);
});

test("isNode — 根も子孫もノード、中身の id と知らない id は違う", () => {
  const s = survey("# r\n\n```\nx\n```\n\n## a\n");
  assert.equal(core.isNode(s, 2), true);
  assert.equal(core.isNode(s, 4), true);
  assert.equal(core.isNode(s, 3), false);
  assert.equal(core.isNode(s, 9), false);
});

test("選択は core と往復する — chosen / anchorsOf / anchorsFor / ranges", () => {
  const s = survey("# r\n\n## a\n\n## b\n");
  const caret = (head: number): core.Caret => ({ ranges: [{ from: head, to: head }], head });
  assert.deepEqual(core.chosen(s, "md", caret(8), null), { kind: "nodes", sel: { ids: [3], anchor: 3 } });
  assert.deepEqual(core.chosen(s, "map", caret(8), null), core.NOTHING);
  assert.deepEqual(core.chosen(s, "map", caret(0), { kind: "nodes", at: [8, 14], anchor: 14 }), {
    kind: "nodes",
    sel: { ids: [3, 4], anchor: 4 },
  });
  assert.deepEqual(core.anchorsOf(s, 4), { kind: "nodes", at: [14], anchor: 14 });
  assert.deepEqual(core.anchorsFor(s, { kind: "nodes", sel: { ids: [3], anchor: null } }), {
    kind: "nodes",
    at: [8],
    anchor: null,
  });
  assert.deepEqual(core.ranges(s, { kind: "nodes", sel: { ids: [2, 9], anchor: 2 } }), [{ from: 0, to: 16 }]);
});

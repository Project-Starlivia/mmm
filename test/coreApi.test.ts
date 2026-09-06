// core の出口と入口の境界。形を確かめる側の規則を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import * as core from "../src/coreApi.ts";
import { edit, edited, encode, splice, survey } from "../src/coreApi.ts";

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
  assert.equal(core.name(s), "r");
  assert.equal(core.frontmatter(s), null);
  assert.equal(core.frontmatter(survey("---\nk: v\n---\n\n# r\n")), "k: v\n");
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

test("頭の宣言は core と往復する — imageFolder / setImageFolder / retarget", () => {
  const s = survey("# r\n\n![a](./img/a.webp)\n");
  assert.equal(core.imageFolder(s), null);
  const e = core.setImageFolder(s, "./img/");
  assert.deepEqual(e, { from: 0, to: 0, insert: "---\nimage-folder: ./img/\n---\n\n" });
  assert.equal(core.imageFolder(survey(splice("# r\n", [e]))), "./img/");
  assert.equal(core.retarget(s, "./img/", "../pics/").length, 1);
  assert.equal(core.normalizePath(" img "), "img/");
  assert.equal(core.normalizePath("/abs"), null);
  assert.equal(core.under("./img/a.webp", "img/"), "a.webp");
  assert.equal(core.barePath("./x"), "x");
});

test("Op は core の enum の形になる — kind が構築子名、null の鍵は落ち、鍵が無ければ裸の名前", () => {
  assert.deepEqual(encode({ kind: "rename", id: 2, label: "b" }), ["Rename", { id: 2, label: "b" }]);
  assert.deepEqual(
    encode({ kind: "addNode", at: { kind: "in", node: 2, side: null }, labels: ["n"] }),
    ["AddNode", { at: ["In", { node: 2 }], labels: ["n"] }],
  );
  assert.deepEqual(
    encode({ kind: "moveNode", ids: [3], at: { kind: "in", node: 2, side: "Left" } }),
    ["MoveNode", { ids: [3], at: ["In", { node: 2, side: "Left" }] }],
  );
  assert.deepEqual(
    encode({ kind: "addBlock", at: { kind: "in", node: 2 }, content: { kind: "thematicBreak" } }),
    ["AddBlock", { at: ["In", { node: 2 }], content: "ThematicBreak" }],
  );
  assert.deepEqual(
    encode({ kind: "setBlock", id: 3, content: { kind: "svg", markup: "<svg/>" } }),
    ["SetBlock", { id: 3, content: ["Svg", "<svg/>"] }],
  );
  assert.deepEqual(
    encode({ kind: "setBlock", id: 3, content: { kind: "opaque", text: "x\n" } }),
    ["SetBlock", { id: 3, content: ["Opaque", "x\n"] }],
  );
});

test("Edited — focus の無い鍵は null", () => {
  assert.deepEqual(edited({ edits: [{ from: 0, to: 1, insert: "x" }] }), {
    edits: [{ from: 0, to: 1, insert: "x" }],
    focus: null,
  });
});

test("edit は core を往復する — 編集を当てれば名前が替わり、focus はそのノード", () => {
  const r = edit("# a\n", { kind: "rename", id: 2, label: "b" });
  let md = "# a\n";
  for (const e of [...r.edits].reverse()) md = md.slice(0, e.from) + e.insert + md.slice(e.to);
  assert.equal(md, "# b\n");
  assert.equal(r.focus, 2);
  assert.deepEqual(edit("# a\n", { kind: "rename", id: 9, label: "b" }), { edits: [], focus: null });
});

test("edit — 同じ名前への Rename は edits が空でも focus は在る（apply が断りと見分ける契約）", () => {
  assert.deepEqual(edit("# a\n", { kind: "rename", id: 2, label: "a" }), { edits: [], focus: 2 });
});

test("splice: 編集列（前の座標・from 順・重ならない）を md に当てる", () => {
  assert.equal(splice("abcdef", [{ from: 1, to: 2, insert: "XY" }, { from: 4, to: 6, insert: "" }]), "aXYcd");
  assert.equal(splice("abc", []), "abc");
  assert.equal(splice("abc", [{ from: 0, to: 0, insert: "---\n" }]), "---\nabc");
});

// core の JSON を View に整える境界。形を確かめる側の規則を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type View, decode, decodeSurvey, edit, edited, encode, isNode, survey } from "../src/coreApi.ts";

test("None の鍵は無い → null。Implicit は label が null", () => {
  const v = decode({ trees: [{ node: { id: 2, blocks: [], children: [] }, sides: [] }] });
  assert.equal(v.frontmatter, null);
  assert.equal(v.trees[0].node.label, null);
  assert.equal(v.trees[0].node.fold, null);
});

test("Block は enum の形から kind に整う", () => {
  const v = decode({
    trees: [
      {
        node: {
          id: 2,
          label: "a",
          blocks: [
            { id: 3, content: ["Image", { alt: "", src: "p.png", title: "" }] },
            { id: 5, content: ["Link", { text: "t", href: "u", title: "" }] },
            { id: 6, content: ["Code", { info: "js", text: "1\n" }] },
            { id: 7, content: ["Svg", "<svg/>"] },
            { id: 8, content: "ThematicBreak" },
            {
              id: 9,
              content: ["Details", { text: "<details>x</details>", open: false, body: "x" }],
            },
          ],
          children: [],
        },
        sides: [],
      },
    ],
  });
  assert.deepEqual(
    v.trees[0].node.blocks.map((b) => b.content.kind),
    ["image", "link", "code", "svg", "thematicBreak", "details"],
  );
  // id はノードと同じ列。Opaque が落ちたぶん（4）は飛んだまま
  assert.deepEqual(
    v.trees[0].node.blocks.map((b) => b.id),
    [3, 5, 6, 7, 8, 9],
  );
  const last = v.trees[0].node.blocks[5].content;
  assert.deepEqual(last, {
    kind: "details",
    text: "<details>x</details>",
    open: false,
    summary: null,
    body: "x",
  });
});

test("frontmatter・fold・sides・空のラベルは値のまま通る", () => {
  const v = decode({
    frontmatter: "k: v\n",
    trees: [
      {
        node: {
          id: 2,
          label: "r",
          fold: { open: true, summary: "r" },
          blocks: [],
          children: [{ id: 3, label: "", blocks: [], children: [] }],
        },
        sides: ["Left"],
      },
    ],
  });
  assert.equal(v.frontmatter, "k: v\n");
  assert.deepEqual(v.trees[0].node.fold, { open: true, summary: "r" });
  assert.deepEqual(v.trees[0].sides, ["Left"]);
  assert.equal(v.trees[0].node.children[0].label, "");
});

test("知らない形は黙って通さない", () => {
  assert.throws(
    () =>
      decode({
        trees: [
          { node: { id: 1, blocks: [{ id: 2, content: ["Opaque", "x"] }], children: [] }, sides: [] },
        ],
      }),
    /知らない Content/,
  );
  assert.throws(
    () => decode({ trees: [{ node: { id: 1, blocks: [], children: [] }, sides: ["Up"] }] }),
    /側でない/,
  );
});

test("survey の JSON — spots の鍵は数になり、label の無い鍵は null、trails の null はそのまま", () => {
  const s = decodeSurvey({
    view: { trees: [] },
    spots: { "1": { from: 0, to: 0 }, "2": { from: 0, label: 2, to: 4 } },
    trails: [null, { mark: { from: 0, label: 2 } }, { mark: { from: 0, label: 2 }, id: 2 }],
  });
  assert.deepEqual(s.spots.get(1), { from: 0, label: null, to: 0 });
  assert.deepEqual(s.spots.get(2), { from: 0, label: 2, to: 4 });
  assert.deepEqual(s.trails, [
    null,
    { mark: { from: 0, label: 2 }, id: null },
    { mark: { from: 0, label: 2 }, id: 2 },
  ]);
});

test("survey は core を往復する — 上にノードを足しても目印は同じノードを指す", () => {
  const first = survey("# r\n\n## a\n", [], []);
  assert.equal(first.view.trees.length, 1);
  assert.deepEqual(first.spots.get(3), { from: 5, label: 8, to: 10 });
  const s = first.spots.get(3);
  if (!s || s.label === null) throw new Error("a の地番が無い");
  const next = survey(
    "# r\n\n## n\n\n## a\n",
    [{ from: 5, to: 5, insert: "## n\n\n" }],
    [{ from: s.from, label: s.label }],
  );
  assert.deepEqual(next.trails, [{ mark: { from: 11, label: 14 }, id: 4 }]);
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

test("isNode — 根も子孫もノード、中身の id と知らない id は違う", () => {
  const v: View = {
    frontmatter: null,
    trees: [
      {
        node: {
          id: 2,
          label: "r",
          fold: null,
          blocks: [{ id: 3, content: { kind: "thematicBreak" } }],
          children: [{ id: 4, label: "a", fold: null, blocks: [], children: [] }],
        },
        sides: ["Right"],
      },
    ],
  };
  assert.equal(isNode(v, 2), true);
  assert.equal(isNode(v, 4), true);
  assert.equal(isNode(v, 3), false);
  assert.equal(isNode(v, 9), false);
});

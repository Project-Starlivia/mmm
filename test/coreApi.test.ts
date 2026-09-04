// core の JSON を View に整える境界。形を確かめる側の規則を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { decode } from "../src/coreApi.ts";

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
            { id: 9, content: ["Details", "<details>x</details>"] },
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

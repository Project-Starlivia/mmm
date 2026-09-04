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
            ["Image", { alt: "", src: "p.png", title: "" }],
            ["Link", { text: "t", href: "u", title: "" }],
            ["Code", { info: "js", text: "1\n" }],
            ["Svg", "<svg/>"],
            "ThematicBreak",
            ["Details", { id: 3, text: "<details>x</details>" }],
          ],
          children: [],
        },
        sides: [],
      },
    ],
  });
  assert.deepEqual(
    v.trees[0].node.blocks.map((b) => b.kind),
    ["image", "link", "code", "svg", "thematicBreak", "details"],
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
        trees: [{ node: { id: 1, blocks: [["Opaque", "x"]], children: [] }, sides: [] }],
      }),
    /知らない Block/,
  );
  assert.throws(
    () => decode({ trees: [{ node: { id: 1, blocks: [], children: [] }, sides: ["Up"] }] }),
    /側でない/,
  );
});

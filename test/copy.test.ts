// copyText — 選んだ部分木の原文を地番で切り出す。paste.ts の対。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { copyText } from "../src/app/copy.ts";
import { survey } from "../src/coreApi.ts";

/** md を core に読ませて、copyText に要るものを揃える */
const read = (md: string) => {
  const s = survey(md, [], []);
  return (ids: number[]) => copyText(md, s.view, s.spots, ids);
};

test("copyText: 部分木を原文のまま。子・孫の行も一緒に", () => {
  // r(2) → a(3) → b(4) / c(5)
  const at = read("# r\n\n## a\n\n### b\n\nbody\n\n## c\n");
  assert.equal(at([3]), "## a\n\n### b\n\nbody\n");
  assert.equal(at([2]), "# r\n\n## a\n\n### b\n\nbody\n\n## c\n");
});

test("copyText: 複数は文書順に空行で継ぐ。選んだ祖先の中の子孫は数えない", () => {
  const at = read("# r\n\n## a\n\n### b\n\n## c\n");
  assert.equal(at([5, 3]), "## a\n\n### b\n\n## c\n");
  assert.equal(at([4, 3]), "## a\n\n### b\n");
});

test("copyText: 項目は入れ子ごと。容器の字下げは頭に残らない", () => {
  // a(2) → b(3) → c(4)
  const at = read("- a\n  - b\n    - c\n");
  assert.equal(at([3]), "- b\n    - c\n");
});

test("copyText: 選んでいなければ空。知らない id は飛ばす", () => {
  const at = read("# r\n");
  assert.equal(at([]), "");
  assert.equal(at([9]), "");
});

// 文書の頭（YAML frontmatter）— 区間の受け取りと、その中の 1 行の綴り。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { loadDoc } from "./_helpers.ts";

test("DocView.head: 頭の区間がコアから届く", () => {
  const doc = loadDoc("---\nimage-folder: ./img/\n---\n\n# r\n");
  assert.deepEqual(doc.head, { from: 0, to: 28, bodyFrom: 4, bodyTo: 24 });
});

test("DocView.head: 頭が無ければ null", () => {
  assert.equal(loadDoc("# r\n\n---\n\n## a\n").head, null);
});

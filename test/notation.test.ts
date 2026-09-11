// 記法構造は原文を 1 バイトも落とさない。**負荷の見本 7 本 523 KB で言う** —
// core の中の見本 166 通りは短くて作られたものなので、実文書に近い大きさで
// もう一度言う。#88 の「fixtures を読むものが無い」もこれで 1 つ埋まる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { notationBack, serialize } from "../src/app.ts";

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures");
const names = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));

test("見本が在る", () => {
  assert.ok(names.length > 0, "test/fixtures に .md が 1 つも無い");
});

for (const name of names) {
  const md = fs.readFileSync(path.join(dir, name), "utf8");

  test(`${name}: 触っていない記法構造を書けば、原文がそのまま返る`, () => {
    assert.equal(notationBack(md), md);
  });

  // **書きは別の道。** 木から綴る正規形は入力と違いうる（見出しの末尾空白や
  // タブが正規化される）ので、冪等であることだけを言う。
  test(`${name}: 木から綴った正規形は冪等`, () => {
    const once = serialize(md);
    assert.equal(serialize(once), once);
  });
}

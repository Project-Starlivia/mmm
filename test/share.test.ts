// 本文を URL フラグメントへ載せる往復（src/app/share.ts）。
//
// `#md=` の中身だけを扱う。DOM もクリップボードも知らない純粋な変換なので、
// テストは文字列の往復と、リンクでないものを渡したときの判断だけを見る。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { fromHash, hasImages, toHash } from "../src/app/share.ts";

test("S1: 本文が toHash → fromHash で往復する", async () => {
  const text = "# 設計メモ\n\n## a\n本文だよ\n";
  assert.equal(await fromHash(await toHash(text)), text);
});

test("S2: リンクでない hash は null", async () => {
  assert.equal(await fromHash(""), null);
  assert.equal(await fromHash("#"), null);
  assert.equal(await fromHash("#foo=bar"), null);
});

test("S3: 壊れた md= は null（例外を投げない）", async () => {
  assert.equal(await fromHash("#md=not-valid-base64url!!!"), null);
});

test("S4: 画像を貼った行があれば hasImages が true", () => {
  assert.equal(hasImages("# a\n\n![](./images/a.webp)\n"), true);
  assert.equal(hasImages("# a\n\n本文だけ\n"), false);
  // リンクは画像ではない
  assert.equal(hasImages("[a](./b.md)"), false);
});

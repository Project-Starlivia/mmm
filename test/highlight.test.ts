// コード編集欄で「囲いだけ守る」判定。DOM を持たない純粋な規則なので、
// ここで固めておく（実機では消せたか消せなかったかしか見えない）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { touchesFence } from "../src/map/highlight.ts";

const BLOCK = "```ts\nconst a = 1;\n```";
//             0123456789...
// 開き ``` = [0,3) / 言語 "ts" = [3,5) / 閉じ行は末尾 4 文字（改行込み）

test("touchesFence: 開きのバッククォートは守る", () => {
  assert.equal(touchesFence(BLOCK, 0, 3), true); // 選んで消す
  assert.equal(touchesFence(BLOCK, 1, 2), true); // 途中だけ
  assert.equal(touchesFence(BLOCK, 0, 0), true); // 手前に打ち込む
});

test("touchesFence: 言語名は守らない（直せることが編集の目的の半分）", () => {
  assert.equal(touchesFence(BLOCK, 3, 5), false); // ts を選び直す
  assert.equal(touchesFence(BLOCK, 5, 5), false); // 末尾に足す
  assert.equal(touchesFence(BLOCK, 3, 3), false); // ``` の直後に打つ
});

test("touchesFence: 中身は自由に打てる", () => {
  const bodyFrom = BLOCK.indexOf("const");
  assert.equal(touchesFence(BLOCK, bodyFrom, bodyFrom + 5), false);
  assert.equal(touchesFence(BLOCK, bodyFrom, bodyFrom), false);
});

// 本文の最終行の末尾は、閉じの手前の改行と同じ番号になる。ここを塞ぐと
// 「コードの末尾に書き足す」という一番よくある操作が通らなくなっていた。
test("touchesFence: 本文の末尾に打てる（改行と番号が重なる位置）", () => {
  const endOfBody = BLOCK.indexOf("const") + "const a = 1;".length;
  assert.equal(touchesFence(BLOCK, endOfBody, endOfBody), false);
});

test("touchesFence: その改行を消すのは止める（閉じが前の行にくっつく）", () => {
  const endOfBody = BLOCK.indexOf("const") + "const a = 1;".length;
  assert.equal(touchesFence(BLOCK, endOfBody, endOfBody + 1), true);
});

test("touchesFence: 閉じは手前の改行ごと守る", () => {
  const closeAt = BLOCK.length - 3;
  assert.equal(touchesFence(BLOCK, closeAt, BLOCK.length), true);
  assert.equal(touchesFence(BLOCK, closeAt - 1, closeAt), true); // 改行だけ消す
  assert.equal(touchesFence(BLOCK, closeAt, closeAt), true); // 閉じ行の頭に割り込む
  assert.equal(touchesFence(BLOCK, 0, BLOCK.length), true); // 全選択して消す
});

test("touchesFence: 閉じが無ければ守る対象も無い", () => {
  const half = "```ts\nconst a = 1;";
  assert.equal(touchesFence(half, half.length, half.length), false);
  assert.equal(touchesFence(half, 0, 3), true); // 開きは守る
});

test("touchesFence: そもそもフェンスでなければ何も守らない", () => {
  const plain = "ただの本文\n2 行目";
  assert.equal(touchesFence(plain, 0, plain.length), false);
});

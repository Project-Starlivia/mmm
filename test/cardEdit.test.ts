// カードの削除・移動は「どの範囲を何で置き換えるか」に尽きる。
// 1 回の replaceText に落とすので Undo も 1 回になる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { moveCard, removeCard } from "../src/map/cardEdit.ts";

/** 編集を当てた結果の本文 */
const apply = (text: string, e: { from: number; to: number; insert: string }) =>
  text.slice(0, e.from) + e.insert + text.slice(e.to);

const DOC = "a\nB\nc\n";
//           0 1 2 3 4 5
// "B" は [2,3)

test("removeCard: 行末の改行ごと持っていく（空行を残さない）", () => {
  const e = removeCard(DOC, 2, 3);
  assert.equal(apply(DOC, e), "a\nc\n");
});

test("removeCard: 末尾の行なら手前の改行を巻き取る", () => {
  const doc = "a\nB";
  const e = removeCard(doc, 2, 3);
  assert.equal(apply(doc, e), "a");
});

test("moveCard: 下へ動かす", () => {
  // "B" を "c" の後ろ（オフセット 6 = 末尾）へ
  const e = moveCard(DOC, 2, 3, 6);
  assert.ok(e);
  assert.equal(apply(DOC, e), "a\nc\nB\n");
});

test("moveCard: 上へ動かす", () => {
  // "c" を先頭（オフセット 0）へ
  const e = moveCard(DOC, 4, 5, 0);
  assert.ok(e);
  assert.equal(apply(DOC, e), "c\na\nB\n");
});

test("moveCard: 書き換えるのは動かす範囲だけ（外側は触らない）", () => {
  const doc = "x\na\nB\nc\ny\n";
  const from = doc.indexOf("B");
  const e = moveCard(doc, from, from + 1, doc.indexOf("y"));
  assert.ok(e);
  assert.equal(apply(doc, e), "x\na\nc\nB\ny\n");
  // 先頭の "x\n" と末尾の "y\n" は書き換え範囲の外にある
  assert.ok(e.from >= 2, `書き換えが先頭まで伸びている: ${e.from}`);
});

test("moveCard: 自分の中へ落としたら何もしない", () => {
  assert.equal(moveCard(DOC, 2, 3, 2), null);
  assert.equal(moveCard(DOC, 2, 3, 3), null);
});

// 「自分のすぐ下」は自分の範囲の外なので上のガードには掛からないが、
// 動かしても文書は 1 文字も変わらない。ここで null を返さないと、
// 呼び出し側が「動かせた」と信じて後続の click まで握りつぶす。
const TWO = "# r\n\nA\nB\n";
//           0123 4 56 78
test("moveCard: 動かない移動は null（同じノードの中で、次の行の頭へ）", () => {
  assert.equal(moveCard(TWO, 5, 6, 7), null); // "A" を "B" の頭へ
});

test("moveCard: 動かない移動は null（本文の末尾へ）", () => {
  assert.equal(moveCard(TWO, 7, 8, TWO.length), null); // "B" を末尾へ
});

// 見つかった不具合の回帰。下へ動かす枝が「間にあったもの」の末尾に改行がある
// 前提で組み立てていたため、改行で終わらない文書の末尾へ動かすと行が融合した。
test("moveCard: 改行で終わらない文書の末尾へ動かしても行が融合しない", () => {
  const doc = "a\nB\nc";
  const e = moveCard(doc, 2, 3, doc.length);
  assert.ok(e);
  assert.equal(apply(doc, e), "a\nc\nB");
});

test("moveCard: 文書の末尾に改行があるかどうかは変えない", () => {
  const doc = "a\nB\nc\n";
  const e = moveCard(doc, 2, 3, doc.length);
  assert.ok(e);
  assert.equal(apply(doc, e), "a\nc\nB\n");
});

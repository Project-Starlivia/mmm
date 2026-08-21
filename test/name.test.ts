// 文書の名前の導出（src/app/name.ts）。
//
// 名前は状態ではなく本文から導く。道具が出す提案は常にファイル名として
// 有効であること — 失敗してから拾いにいかない。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { initDoc } from "./_helpers.ts";
import { EMPTY_NAME, deriveName, toFileName } from "../src/app/name.ts";

const nameOf = (md: string): string => deriveName(initDoc(md).nodes);

test("N1: いちばん大きい見出しが名前になる", () => {
  assert.equal(nameOf("# 設計メモ\n\n## a\n"), "設計メモ");
  // `#` が無ければ `##` がいちばん大きい
  assert.equal(nameOf("## 覚書\n\n### b\n"), "覚書");
});

test("N2: 同じ大きさが並べば先に書いたほうが勝つ", () => {
  assert.equal(nameOf("# 先\n\n# 後\n"), "先");
});

test("N3: 大きさが優先。あとから出た `#` が前の `##` に勝つ", () => {
  assert.equal(nameOf("## 小さい\n\n# 大きい\n"), "大きい");
});

test("N4: 使えない文字は落として `-` で繋ぐ（空白は残す）", () => {
  assert.equal(toFileName("設計/検討"), "設計-検討");
  assert.equal(toFileName("A: B"), "A-B");
  // 使えない 9 文字すべて。エスケープで見失わないよう組み立てて作る
  const bad = ["\\", "/", ":", "*", "?", '"', "<", ">", "|"];
  const mixed = bad.map((c, i) => `${"abcdefghi"[i]}${c}`).join("") + "j";
  assert.equal(toFileName(mixed), "a-b-c-d-e-f-g-h-i-j");
  // 制御文字も落ちる
  assert.equal(toFileName("a\u0000b\u001fc"), "a-b-c");
  assert.equal(toFileName("設計 メモ"), "設計 メモ");
});

test("N5: 整形して何も残らなければ、文書順で最初の見出しへ落ちる", () => {
  // いちばん大きい `# ///` は空になるので、最初の見出し `## 覚書` を使う
  assert.equal(nameOf("## 覚書\n\n# ///\n"), "覚書");
});

test("N6: 見出しが無い / 全部空なら empty", () => {
  assert.equal(nameOf(""), EMPTY_NAME);
  assert.equal(nameOf("# \n"), EMPTY_NAME);
  assert.equal(nameOf("# ///\n"), EMPTY_NAME);
  assert.equal(nameOf("ただの本文\n"), EMPTY_NAME);
});

test("N7: 長すぎる名前は UTF-8 250 バイトで切る（文字は割らない）", () => {
  const long = "あ".repeat(200); // 600 バイト
  const out = toFileName(long);
  const bytes = new TextEncoder().encode(out).length;
  assert.ok(bytes <= 250, `250 バイトを超えた: ${bytes}`);
  assert.equal(out, "あ".repeat(83)); // 249 バイト（84 文字目で超える）
  // 絵文字（サロゲートペア）でも壊れた文字が出ない
  const emoji = toFileName("😀".repeat(100));
  assert.ok(!emoji.includes("\ufffd"), "壊れた文字が出た");
  assert.equal([...emoji].every((c) => c === "😀"), true);
});

test("N8: 末尾のドットと空白は落とす（Windows が黙って落とすため）", () => {
  assert.equal(toFileName("メモ..."), "メモ");
  assert.equal(toFileName("メモ  "), "メモ");
});

test("N9: MS-DOS の予約名はそのまま使えない", () => {
  assert.equal(toFileName("CON"), "CON_");
  assert.equal(toFileName("nul"), "nul_");
  assert.equal(toFileName("COM1"), "COM1_");
  assert.equal(toFileName("CONSOLE"), "CONSOLE"); // 予約なのは完全一致のときだけ
});

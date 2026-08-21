// Tauri 移行で新設された、純粋な TS ロジックのカバレッジ。
// フォルダ許可・相対計算などディスクに触る部分は Rust 側（cargo test）が持つ。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { mdPath } from "../src/app/assets.ts";
import { decideExternalChange } from "../src/app/externalChange.ts";

test("mdPath: 同階層から下は ./ を付け、既に ./ があれば重ねない", () => {
  assert.equal(mdPath("a.png"), "./a.png");
  assert.equal(mdPath("./a.png"), "./a.png");
  assert.equal(mdPath("sub/a.png"), "./sub/a.png");
});

test("mdPath: 上へ出るものは ../ のまま", () => {
  assert.equal(mdPath("../a.png"), "../a.png");
  assert.equal(mdPath("../../sub/a.png"), "../../sub/a.png");
});

test("decideExternalChange: 未編集(現在=保存済み)なら reload", () => {
  assert.equal(decideExternalChange("同じ本文", "同じ本文"), "reload");
});

test("decideExternalChange: 編集中(現在≠保存済み)なら warn", () => {
  assert.equal(decideExternalChange("編集した本文", "保存済みの本文"), "warn");
});

// assets.ts の純粋なパス計算のカバレッジ。フォルダ選択やファイル読み書きは
// ブラウザの FileSystemDirectoryHandle に聞くしかなく、単体テストの対象外。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { mdPath } from "../src/app/assets.ts";

test("mdPath: 同階層から下は ./ を付け、既に ./ があれば重ねない", () => {
  assert.equal(mdPath("a.png"), "./a.png");
  assert.equal(mdPath("./a.png"), "./a.png");
  assert.equal(mdPath("sub/a.png"), "./sub/a.png");
});

test("mdPath: 上へ出るものは ../ のまま", () => {
  assert.equal(mdPath("../a.png"), "../a.png");
  assert.equal(mdPath("../../sub/a.png"), "../../sub/a.png");
});

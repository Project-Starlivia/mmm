// assets.ts の純粋なパス計算のカバレッジ。フォルダ選択やファイル読み書きは
// ブラウザの FileSystemDirectoryHandle に聞くしかなく、単体テストの対象外。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { assetTarget, mdPath } from "../src/app/assets.ts";

test("mdPath: 同階層から下は ./ を付け、既に ./ があれば重ねない", () => {
  assert.equal(mdPath("a.png"), "./a.png");
  assert.equal(mdPath("./a.png"), "./a.png");
  assert.equal(mdPath("sub/a.png"), "./sub/a.png");
});

test("mdPath: 上へ出るものは ../ のまま", () => {
  assert.equal(mdPath("../a.png"), "../a.png");
  assert.equal(mdPath("../../sub/a.png"), "../../sub/a.png");
});

// 保存したのに読み戻せなかったバグの回帰。
// md に書くのは `./x`、カード側が持つのは `x`（cards.ts が `./` を剥がす）。
// 既定の保存パスは `./` なので、裸に寄せずに比べると必ず外れる。
test("assetTarget: 既定の `./` で、`./` 付きでも裸でも同じ場所を指す", () => {
  assert.deepEqual(assetTarget("./", "a.webp"), ["a.webp"]);
  assert.deepEqual(assetTarget("./", "./a.webp"), ["a.webp"]);
});

// 返すのは「選んだフォルダのハンドルからの相対」。宣言したぶんは
// ハンドルが既に指しているので、断片から外れる。
test("assetTarget: 宣言したぶんを除いた、フォルダからの相対を返す", () => {
  assert.deepEqual(assetTarget("assets/", "assets/a.webp"), ["a.webp"]);
  assert.deepEqual(assetTarget("assets/", "./assets/a.webp"), ["a.webp"]);
  assert.deepEqual(assetTarget("./", "sub/a.webp"), ["sub", "a.webp"]);
});

test("assetTarget: 宣言の外を指すものは受け取らない", () => {
  assert.equal(assetTarget("assets/", "other/a.webp"), null);
  assert.equal(assetTarget("assets/", "a.webp"), null);
  assert.equal(assetTarget("./", "../a.webp"), null);
  assert.equal(assetTarget("./", ""), null);
});

test("assetTarget: 上へ出る宣言は、その中に収まる限り受け取る", () => {
  assert.deepEqual(assetTarget("../pics/", "../pics/a.webp"), ["a.webp"]);
  assert.deepEqual(assetTarget("../pics/", "../pics/sub/a.webp"), ["sub", "a.webp"]);
});

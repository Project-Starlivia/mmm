// assets.ts の純粋なパス計算のカバレッジ。フォルダ選択やファイル読み書きは
// ブラウザの FileSystemDirectoryHandle に聞くしかなく、単体テストの対象外。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { assetTarget, imageType, mdPath, nameProblem } from "../src/app/assets.ts";

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

test("imageType: 絵の名前からその種類を引く", () => {
  assert.equal(imageType("a.webp"), "image/webp");
  assert.equal(imageType("a.PNG"), "image/png");
  assert.equal(imageType("a.jpeg"), "image/jpeg");
});

test("imageType: 絵でないものは null", () => {
  assert.equal(imageType("notes.txt"), null);
  assert.equal(imageType("id_rsa"), null);
  assert.equal(imageType(".env"), null);
  assert.equal(imageType("a.webp.txt"), null);
});

test("assetTarget: 絵でないものは、宣言の中にあっても読みに行かない", () => {
  // マップには何も出ないまま中身が読まれ、書き出した SVG に載ってしまう
  assert.equal(assetTarget("./", "notes.txt"), null);
  assert.equal(assetTarget("./", "sub/id_rsa"), null);
  assert.equal(assetTarget("assets/", "assets/.env"), null);
});

test("assetTarget: 上へ出る宣言は、その中に収まる限り受け取る", () => {
  assert.deepEqual(assetTarget("../pics/", "../pics/a.webp"), ["a.webp"]);
  assert.deepEqual(assetTarget("../pics/", "../pics/sub/a.webp"), ["sub", "a.webp"]);
});

test("nameProblem — 空・. と ..・使えない字を咎め、通る名前は null", () => {
  assert.equal(nameProblem("  "), "Give it a name");
  assert.equal(nameProblem("a/../b"), "Folder names cannot be . or ..");
  assert.equal(nameProblem("a:b"), "A file name cannot contain :");
  assert.equal(nameProblem("pics/shot.webp"), null);
});

test("mdPath — md に書くのは ./ 付き。上へ出る道はそのまま", () => {
  assert.equal(mdPath("x.webp"), "./x.webp");
  assert.equal(mdPath("./x.webp"), "./x.webp");
  assert.equal(mdPath("../x.webp"), "../x.webp");
});

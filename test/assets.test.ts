// assets.ts の純粋なパス計算のカバレッジ。フォルダ選択やファイル読み書きは
// ブラウザの FileSystemDirectoryHandle に聞くしかなく、単体テストの対象外。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  assetTarget,
  folderFromDoc,
  imageType,
  mdPath,
  nameProblem,
} from "../src/app/assets.ts";

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

// `directory.resolve(md)` が返すのは「フォルダ → md」の断片。md から見た
// フォルダはその逆なので、**末尾のファイル名を除いた数**だけ上へ戻る。
test("folderFromDoc: md がフォルダ直下なら ./", () => {
  assert.equal(folderFromDoc(["a.md"]), "./");
});

test("folderFromDoc: md が 1 段深ければ ../", () => {
  assert.equal(folderFromDoc(["notes", "a.md"]), "../");
  assert.equal(folderFromDoc(["a", "b", "c.md"]), "../../");
});

test("folderFromDoc: 断片が空でも ./ に倒す", () => {
  assert.equal(folderFromDoc([]), "./");
});

// 画像の名前の検査。**押す前に言う**ための問いなので、答えは「だめな理由」か
// null で、呼ぶ側（たずね箱）は打鍵のたびにこれを聞く。
// 通った値だけが nameParts へ進むので、書き込む側は二度確かめない。

test("nameProblem: 普通の名前も、フォルダを挟んだ名前も通る", () => {
  assert.equal(nameProblem("2026-08-27-120000"), null);
  assert.equal(nameProblem("sub/a"), null);
  assert.equal(nameProblem("a/b/c"), null);
});

test("nameProblem: `.webp` は付いていても付いていなくても同じ", () => {
  assert.equal(nameProblem("a.webp"), null);
  assert.equal(nameProblem("a.WEBP"), null);
});

test("nameProblem: 名前が無ければ、そう言う", () => {
  assert.equal(nameProblem(""), "Give it a name");
  assert.equal(nameProblem("   "), "Give it a name");
  // `.webp` だけ打つと中身が空になる
  assert.equal(nameProblem(".webp"), "Give it a name");
  // 区切りだけの並びも、断片が 1 つも残らない
  assert.equal(nameProblem("///"), "Give it a name");
});

test("nameProblem: `.` と `..` はフォルダ名にならない", () => {
  assert.equal(nameProblem("../a"), "Folder names cannot be . or ..");
  assert.equal(nameProblem("./a"), "Folder names cannot be . or ..");
  assert.equal(nameProblem("a/../b"), "Folder names cannot be . or ..");
});

test("nameProblem: 使えない字は、その字を挙げて言う", () => {
  assert.equal(nameProblem("a:b"), "A file name cannot contain :");
  assert.equal(nameProblem('a"b'), 'A file name cannot contain "');
  assert.equal(nameProblem("a?b"), "A file name cannot contain ?");
  assert.equal(nameProblem("sub/a*b"), "A file name cannot contain *");
});

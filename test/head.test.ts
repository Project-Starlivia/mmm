// 文書の頭（YAML frontmatter）— その中の 1 行の綴りを読む・書く。
// 「どこからどこまでが頭か」は core が答える（`View.frontmatter`）ので、
// 頭の原文は survey で本物から引く。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { survey } from "../src/coreApi.ts";
import { imageFolder, retarget, setImageFolder } from "../src/app/head.ts";

const view = (md: string) => survey(md, [], []).view;

/** md から宣言を引く */
const folderOf = (md: string): string | null => imageFolder(view(md).frontmatter);

/** md の宣言を書き換えた後の全文 */
function written(md: string, value: string): string {
  const e = setImageFolder(md, view(md).frontmatter, value);
  return md.slice(0, e.from) + e.insert + md.slice(e.to);
}

test("imageFolder: 頭から値を読む。他のキーが並んでいても", () => {
  assert.equal(folderOf("---\nimage-folder: ./img/\n---\n\n# r\n"), "./img/");
  assert.equal(folderOf("---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n"), "./img/");
});

test("imageFolder: キーが無い / 頭が無い なら null", () => {
  assert.equal(folderOf("---\ntitle: メモ\n---\n\n# r\n"), null);
  assert.equal(folderOf("# r\n"), null);
});

test("imageFolder: 裸 / 裸+コメント / 引用符 / 引用符+コメント の 4 形", () => {
  assert.equal(folderOf("---\nimage-folder: ./img/ # ここ\n---\n\n# r\n"), "./img/");
  assert.equal(folderOf('---\nimage-folder: "./My Folder #1/"\n---\n\n# r\n'), "./My Folder #1/");
  assert.equal(folderOf('---\nimage-folder: "./My Folder #1/" # ここ\n---\n\n# r\n'), "./My Folder #1/");
  assert.equal(folderOf("---\nimage-folder: './img/'\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 入れ子のキーは読まない（トップレベルだけ）", () => {
  assert.equal(folderOf("---\nmmm:\n  image-folder: ./img/\n---\n\n# r\n"), null);
});

test("setImageFolder: キーがあればその行だけ差し替える", () => {
  const md = "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n";
  assert.equal(written(md, "./assets/"), "---\ntitle: メモ\nimage-folder: ./assets/\ntags:\n  - a\n---\n\n# r\n");
});

test("setImageFolder: キーが無ければ閉じ `---` の直前に足す", () => {
  assert.equal(
    written("---\ntitle: メモ\n---\n\n# r\n", "./img/"),
    "---\ntitle: メモ\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 開きの `---` に空白が続いていても、頭の中に書く", () => {
  assert.equal(
    written("---  \ntitle: メモ\n---\n\n# r\n", "./img/"),
    "---  \ntitle: メモ\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 頭が無ければ先頭に作る", () => {
  assert.equal(written("# r\n", "./img/"), "---\nimage-folder: ./img/\n---\n\n# r\n");
});

test("setImageFolder: 空白・#・: を含む値は囲み、要らなければ裸で書く", () => {
  assert.equal(written("# r\n", "./My Images/"), '---\nimage-folder: "./My Images/"\n---\n\n# r\n');
  assert.equal(written("# r\n", "./a#b/"), '---\nimage-folder: "./a#b/"\n---\n\n# r\n');
  assert.equal(written("# r\n", "./img/"), "---\nimage-folder: ./img/\n---\n\n# r\n");
});

test("setImageFolder → imageFolder は往復する", () => {
  for (const value of ["./img/", "../pics/", "./My Images/", './a"b/', "./My Folder #1/"]) {
    assert.equal(folderOf(written("# r\n", value)), value, value);
  }
});

test("retarget: 宣言の下にある画像だけを、新しい宣言の下へ移す操作列", () => {
  const md = "# r\n\n![a](./img/a.webp)\n\n![b](img/sub/b.png)\n\n![c](./other/c.webp)\n\n![d](https://x/d.png)\n";
  const v = view(md);
  assert.deepEqual(retarget(v, "./img/", "../pics/"), [
    { kind: "setBlock", id: 3, content: { kind: "image", alt: "a", src: "../pics/a.webp", title: "" } },
    { kind: "setBlock", id: 4, content: { kind: "image", alt: "b", src: "../pics/sub/b.png", title: "" } },
  ]);
});

test("retarget: 宣言が `./` なら本文の相対パスは全部が対象", () => {
  const v = view("# r\n\n![](a.webp)\n\n![](./s/b.webp)\n\n![](../up.webp)\n");
  assert.deepEqual(
    retarget(v, "./", "./img/").map((op) => (op.kind === "setBlock" && op.content.kind === "image" ? op.content.src : null)),
    ["./img/a.webp", "./img/s/b.webp"],
  );
});

test("retarget: 動いていなければ空", () => {
  assert.deepEqual(retarget(view("# r\n\n![](./img/a.webp)\n"), "./img/", "./img/"), []);
});

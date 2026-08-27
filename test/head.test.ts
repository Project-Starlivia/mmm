// 文書の頭（YAML frontmatter）— 区間の受け取りと、その中の 1 行の綴り。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { loadDoc } from "./_helpers.ts";
import {
  IMAGE_FOLDER,
  imageFolder,
  normalizePath,
  setImageFolder,
  under,
} from "../src/app/head.ts";

test("DocView.head: 頭の区間がコアから届く", () => {
  const doc = loadDoc("---\nimage-folder: ./img/\n---\n\n# r\n");
  assert.deepEqual(doc.head, { from: 0, to: 28, bodyFrom: 4, bodyTo: 24 });
});

test("DocView.head: 頭が無ければ null", () => {
  assert.equal(loadDoc("# r\n\n---\n\n## a\n").head, null);
});

/** md を読み込んで、頭から宣言を引く小道具 */
const folderOf = (md: string): string | null => {
  const doc = loadDoc(md);
  return imageFolder(doc.text, doc.head);
};

/** md を読み込んで、宣言を書き換えた後のテキストを返す小道具 */
function written(md: string, value: string): string {
  const doc = loadDoc(md);
  const e = setImageFolder(doc.text, doc.head, value);
  return doc.text.slice(0, e.from) + e.insert + doc.text.slice(e.to);
}

test("imageFolder: 頭から値を読む", () => {
  assert.equal(folderOf("---\nimage-folder: ./img/\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 他のキーが並んでいても読む", () => {
  const md = "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n";
  assert.equal(folderOf(md), "./img/");
});

test("imageFolder: キーが無い / 頭が無い なら null", () => {
  assert.equal(folderOf("---\ntitle: メモ\n---\n\n# r\n"), null);
  assert.equal(folderOf("# r\n"), null);
  assert.equal(folderOf("---\n---\n\n# r\n"), null);
});

test("imageFolder: 引用符は剥がす", () => {
  assert.equal(folderOf('---\nimage-folder: "./My Images/"\n---\n\n# r\n'), "./My Images/");
  assert.equal(folderOf("---\nimage-folder: './img/'\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 裸の値は ` #` からがコメント", () => {
  assert.equal(folderOf("---\nimage-folder: ./img/ # ここ\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 入れ子のキーは読まない（トップレベルだけ）", () => {
  assert.equal(folderOf("---\nmmm:\n  image-folder: ./img/\n---\n\n# r\n"), null);
});

test("setImageFolder: キーがあればその行だけ差し替える", () => {
  const md = "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n";
  assert.equal(
    written(md, "./assets/"),
    "---\ntitle: メモ\nimage-folder: ./assets/\ntags:\n  - a\n---\n\n# r\n",
  );
});

test("setImageFolder: キーが無ければ閉じ `---` の直前に足す", () => {
  assert.equal(
    written("---\ntitle: メモ\n---\n\n# r\n", "./img/"),
    "---\ntitle: メモ\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 中身の無い頭にも足せる", () => {
  assert.equal(
    written("---\n---\n\n# r\n", "./img/"),
    "---\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 頭が無ければ先頭に作る", () => {
  assert.equal(
    written("# r\n", "./img/"),
    "---\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 空白・#・: を含む値は囲む", () => {
  assert.equal(written("# r\n", "./My Images/"), '---\nimage-folder: "./My Images/"\n---\n\n# r\n');
  assert.equal(written("# r\n", "./a#b/"), '---\nimage-folder: "./a#b/"\n---\n\n# r\n');
});

test("setImageFolder: 囲む必要が無ければ裸で書く", () => {
  assert.equal(written("# r\n", "./img/"), "---\nimage-folder: ./img/\n---\n\n# r\n");
});

test("setImageFolder → imageFolder は往復する", () => {
  for (const value of ["./img/", "../pics/", "./My Images/", './a"b/']) {
    assert.equal(folderOf(written("# r\n", value)), value, value);
  }
});

test("IMAGE_FOLDER: 設定名は 1 か所でしか綴られない", () => {
  assert.equal(IMAGE_FOLDER, "image-folder");
  assert.ok(written("# r\n", "./img/").includes(`${IMAGE_FOLDER}: `));
});

test("normalizePath: 末尾に / を足し、空と . は ./ にする", () => {
  assert.equal(normalizePath("img"), "img/");
  assert.equal(normalizePath("./img/"), "./img/");
  assert.equal(normalizePath(""), "./");
  assert.equal(normalizePath("."), "./");
  assert.equal(normalizePath("..\\pics"), "../pics/");
});

test("normalizePath: 相対でないものは null", () => {
  assert.equal(normalizePath("/abs/img"), null);
  assert.equal(normalizePath("https://example.com/img"), null);
});

test("under: 宣言の下なら残りを返し、外なら null", () => {
  assert.equal(under("./img/a.webp", "./img/"), "a.webp");
  assert.equal(under("img/sub/a.webp", "./img/"), "sub/a.webp");
  assert.equal(under("a.webp", "./"), "a.webp");
  assert.equal(under("./other/b.webp", "./img/"), null);
  assert.equal(under("./img/", "./img/"), null);
});

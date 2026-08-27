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
  retarget,
  setImageFolder,
  under,
} from "../src/app/head.ts";
import { parseImage } from "../src/map/cards.ts";

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

test("imageFolder: 引用符付きの値の後ろのコメントも、引用符ごと落とす", () => {
  // 引用符を先に剥がす実装だと、末尾が `"` でなく `n`（main の頭文字）に
  // なるため引用符の分岐に入れず、`"..."` が剥がれ残っていた
  assert.equal(
    folderOf('---\nimage-folder: "./My Images/" # main\n---\n\n# r\n'),
    "./My Images/",
  );
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

test("normalizePath: 末尾に / を足す。. は ./ にする", () => {
  assert.equal(normalizePath("img"), "img/");
  assert.equal(normalizePath("./img/"), "./img/");
  assert.equal(normalizePath("."), "./");
  assert.equal(normalizePath("..\\pics"), "../pics/");
});

test("normalizePath: 空（書きかけの行）は宣言として読まない", () => {
  // 値を選んで消した直後の頭がこれにあたる。./ に倒すと、その一瞬だけ
  // 宣言が md と同じ場所を指したことになり、フォルダの外の画像まで
  // followDeclaration（main.ts）の retarget に巻き込まれる（Critical 1）
  assert.equal(normalizePath(""), null);
  assert.equal(normalizePath("   "), null);
});

test("normalizePath: imageFolder の結果を通すと、値を消した直後は宣言が消える", () => {
  const raw = folderOf("---\nimage-folder:\n---\n\n# r\n");
  assert.equal(raw, ""); // キー自体はまだあるので unquote は "" を返す
  assert.equal(normalizePath(raw ?? ""), null);
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

/** retarget の結果を後ろから当てて、書き換え後のテキストを返す小道具 */
function moved(md: string, from: string, to: string): string {
  const doc = loadDoc(md);
  const edits = retarget(doc, from, to);
  let out = doc.text;
  for (let i = edits.length - 1; i >= 0; i--) {
    const e = edits[i];
    out = out.slice(0, e.from) + e.insert + out.slice(e.to);
  }
  return out;
}

test("parseImage: 行内の destination の位置を返す", () => {
  const img = parseImage("![alt](./img/a.webp)");
  assert.ok(img);
  assert.equal(img.raw, "./img/a.webp");
  assert.equal("![alt](./img/a.webp)".slice(img.from, img.to), "./img/a.webp");
  assert.equal(img.path, "img/a.webp");
  assert.equal(img.name, "a.webp");
});

test("parseImage: 字下げされた行でも位置が合う", () => {
  const line = "  ![](<./my img/a.webp>)";
  const img = parseImage(line);
  assert.ok(img);
  assert.equal(line.slice(img.from, img.to), "./my img/a.webp");
});

test("retarget: 宣言の下だけ接頭辞を差し替える", () => {
  const md = "# r\n\n![](./img/a.webp)\n\n![](./img/sub/b.png)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n![](./assets/a.webp)\n\n![](./assets/sub/b.png)\n",
  );
});

test("retarget: 宣言の外は触らない", () => {
  const md = "# r\n\n![](./img/a.webp)\n\n![](./other/b.webp)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n![](./assets/a.webp)\n\n![](./other/b.webp)\n",
  );
});

test("retarget: 外部 URL は触らない", () => {
  const md = "# r\n\n![](https://example.com/a.png)\n\n![](data:image/png;base64,AA)\n";
  assert.equal(moved(md, "./", "./img/"), md);
});

test("retarget: フェンスの中は触らない", () => {
  const md = "# r\n\n```md\n![](./img/a.webp)\n```\n\n![](./img/b.webp)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n```md\n![](./img/a.webp)\n```\n\n![](./assets/b.webp)\n",
  );
});

test("retarget: 頭の中は触らない", () => {
  // 頭の 2 行目は YAML として意味を持たないが、**画像リンクとして完全に成立
  // した行**でないと「区間ごと飛ばしている」ことの証明にならない（頭の外に
  // 同じ行があれば必ず書き換わる、というのが下の比較の意味）
  const md = "---\n![](./img/a.webp)\n---\n\n![](./img/b.webp)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "---\n![](./img/a.webp)\n---\n\n![](./assets/b.webp)\n",
  );
});

test("retarget: 裸の綴りも `./` 付きも同じ場所として動かす", () => {
  const md = "# r\n\n![](img/a.webp)\n";
  assert.equal(moved(md, "./img/", "./assets/"), "# r\n\n![](./assets/a.webp)\n");
});

test("retarget: 空白を含むフォルダへ引っ越すと `<…>` で囲み、parseImage で読み戻せる", () => {
  // 裸のまま書くと IMG_LINE（cards.ts）が読めず、カードが消えて以後の
  // retarget からも見えなくなる（Important 2）
  const md = "# r\n\n![](./img/a.webp)\n";
  const out = moved(md, "./img/", "./My Images/");
  assert.equal(out, "# r\n\n![](<./My Images/a.webp>)\n");
  const img = parseImage("![](<./My Images/a.webp>)");
  assert.ok(img);
  assert.equal(img.path, "My Images/a.webp");
});

test("retarget: 既に `<…>` で囲まれた行は二重に囲まない", () => {
  const md = "# r\n\n![](<./img/a b.webp>)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n![](<./assets/a b.webp>)\n",
  );
});

test("retarget: 同じ宣言なら編集は 0 件", () => {
  const doc = loadDoc("# r\n\n![](./img/a.webp)\n");
  assert.deepEqual(retarget(doc, "./img/", "./img/"), []);
});

test("retarget: 返す編集は文書順で、範囲が重ならない", () => {
  const doc = loadDoc("# r\n\n![](./img/a.webp)\n\n![](./img/b.webp)\n");
  const edits = retarget(doc, "./img/", "./assets/");
  assert.equal(edits.length, 2);
  assert.ok(edits[0].to <= edits[1].from);
});

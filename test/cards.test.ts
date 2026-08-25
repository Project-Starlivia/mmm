// カードは「自分がどの行から来たか」を知っている。ここが選択・編集・移動の
// 土台なので、4 種すべてで slice が元テキストに一致することを固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, idOf, initDoc, loadDoc } from "./_helpers.ts";
import { cardRows, contentEnd, linkLine } from "../src/map/cards.ts";

/** 1 ノードぶんのカードを取り出す小道具 */
function rowsOf(md: string) {
  const doc = loadDoc(md);
  const map = cardRows(doc, new Set<number>());
  const node = doc.nodes[doc.nodes.length - 1];
  return { rows: map.get(node.id) ?? [], text: doc.text };
}

test("cardRows: 4 種すべてが from/to を持ち、slice が元テキストに一致する", () => {
  const md =
    "# r\n\n## n\n\n" +
    "[題](https://example.com)\n" +
    "![](./a.webp)\n" +
    "<svg><rect/></svg>\n" +
    "```ts\nconst a = 1;\n```\n";
  const { rows, text } = rowsOf(md);
  assert.deepEqual(
    rows.map((r) => r.kind),
    ["link", "img", "svg", "code"],
  );
  assert.equal(text.slice(rows[0].from, rows[0].to), "[題](https://example.com)");
  assert.equal(text.slice(rows[1].from, rows[1].to), "![](./a.webp)");
  assert.equal(text.slice(rows[2].from, rows[2].to), "<svg><rect/></svg>");
  assert.equal(text.slice(rows[3].from, rows[3].to), "```ts\nconst a = 1;\n```");
});

test("cardRows: 情報文字列が 2 語でも 1 枚のコードカードになる", () => {
  // 以前はカード側だけがこれをフェンスと認めず、中の URL がリンクカードに
  // 化けていた。区間はコアが渡すので、MD ペインと読み方がずれようがない
  const md = "# r\n\n## n\n\n```js copy\nhttps://example.com/in-fence\n```\n";
  const { rows, text } = rowsOf(md);
  assert.deepEqual(
    rows.map((r) => r.kind),
    ["code"],
  );
  assert.equal(rows[0].kind === "code" ? rows[0].lang : "", "js copy");
  assert.equal(
    text.slice(rows[0].from, rows[0].to),
    "```js copy\nhttps://example.com/in-fence\n```",
  );
});

test("cardRows: 閉じないフェンスは文書の終わりまでを 1 枚にする", () => {
  const md = "# r\n\n## n\n\n```\nhttps://example.com/in-fence\n";
  const { rows, text } = rowsOf(md);
  assert.deepEqual(
    rows.map((r) => r.kind),
    ["code"],
  );
  assert.equal(text.slice(rows[0].from, rows[0].to).startsWith("```\n"), true);
  assert.equal(rows[0].to, text.length - 1); // 末尾の改行の手前
});

test("cardRows: 複数行の svg も丸ごと指す", () => {
  const md = "# r\n\n## n\n\n<svg>\n  <rect/>\n</svg>\n";
  const { rows, text } = rowsOf(md);
  assert.equal(rows.length, 1);
  assert.equal(text.slice(rows[0].from, rows[0].to), "<svg>\n  <rect/>\n</svg>");
});

// contentEnd は「そのノードの末尾へ落とした」カードの着地点でもある。
// 間違うと、カードが黙って子ノードの中へ入る。
const endOfNode = (md: string, label: string) => {
  const snap = initDoc(md);
  const i = snap.nodes.findIndex((n) => n.id === idOf(snap.nodes, label));
  return {
    end: contentEnd(snap.nodes, i),
    node: snap.nodes[i],
    next: snap.nodes[i + 1],
    text: core.getText(),
  };
};

test("contentEnd: 子がいれば、その見出しの手前で止まる", () => {
  const md = "# r\n\n[a](https://a.example)\n\n## kid\n\n[b](https://b.example)\n";
  const { end, text } = endOfNode(md, "r");
  assert.equal(end, text.indexOf("## kid"));
  // 末尾へ落としたカードは、子の見出しより前＝ r の本文の中に着く
  assert.ok(text.slice(0, end).includes("[a]"));
  assert.ok(!text.slice(0, end).includes("[b]"));
});

test("contentEnd: 部分木の外の見出しは境界にしない（折り畳みが間に挟まる）", () => {
  // n の本文と次の見出し h の間に `<!--` がある（h は折り畳まれた中身）。
  // 次ノードの見出しまで伸ばすと、n の末尾へ落としたカードが `<!--` の
  // 向こう側 = 折り畳みの中へ入ってしまう
  const md = "# r\n\n## n\n\n[a](https://a.example)\n\n<!--\n\n## h\n\n-->\n\n## m\n";
  const { end, node, next, text } = endOfNode(md, "n");
  assert.ok(next.from > node.to, "この文書は分岐を踏み分けていない");
  assert.equal(end, node.to);
  assert.equal(end, text.indexOf("<!--"));
});

test("contentEnd: 最後のノードなら、部分木の終わり（＝文書の終わり）", () => {
  const md = "# r\n\n## n\n\n[a](https://a.example)\n";
  const { end, node } = endOfNode(md, "n");
  assert.equal(end, node.to);
});

// ---------- linkLine ----------
//
// `Shift+L` が本文に書く 1 行。**題は空のまま残す**（名前を付けるのは
// 呼んだ人の仕事）ので、`parseLink` が見せ方として補うホスト名とは別物。

test("linkLine: 素の URL は題を空にして、そこを指す", () => {
  const got = linkLine("https://example.com/a");
  assert.deepEqual(got, { line: "[](https://example.com/a)", from: 1, to: 1 });
});

test("linkLine: 題つきならそのまま残し、題の範囲を返す", () => {
  const got = linkLine("[名前](https://example.com/a)");
  assert.ok(got);
  assert.equal(got.line, "[名前](https://example.com/a)");
  assert.equal(got.line.slice(got.from, got.to), "名前");
});

test("linkLine: 前後の空白は落とす", () => {
  assert.deepEqual(linkLine("  https://e.com  "), {
    line: "[](https://e.com)",
    from: 1,
    to: 1,
  });
});

test("linkLine: リンクでなければ null", () => {
  for (const bad of ["", "ただの文字", "example.com", "ftp://e.com", "https://e.com と文字"]) {
    assert.equal(linkLine(bad), null, JSON.stringify(bad));
  }
});

test("linkLine: 題が空でもホスト名を書き込まない（見せ方と文書は別）", () => {
  const got = linkLine("[](https://example.com)");
  assert.ok(got);
  assert.equal(got.line, "[](https://example.com)");
  assert.ok(!got.line.includes("example.com]"), "題にホスト名が入っている");
});

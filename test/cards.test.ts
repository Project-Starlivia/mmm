// カードは「自分がどの行から来たか」を知っている。ここが選択・編集・移動の
// 土台なので、4 種すべてで slice が元テキストに一致することを固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, idOf, initDoc } from "./_helpers.ts";
import { cardRows, contentEnd } from "../src/map/cards.ts";

/** 1 ノードぶんのカードを取り出す小道具 */
function rowsOf(md: string) {
  const snap = initDoc(md);
  const text = core.getText();
  const map = cardRows(text, snap.nodes, new Set<number>());
  const node = snap.nodes[snap.nodes.length - 1];
  return { rows: map.get(node.id) ?? [], text };
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
  assert.ok(next.hs > node.subEnd, "この文書は分岐を踏み分けていない");
  assert.equal(end, node.subEnd);
  assert.equal(end, text.indexOf("<!--"));
});

test("contentEnd: 最後のノードなら、部分木の終わり（＝文書の終わり）", () => {
  const md = "# r\n\n## n\n\n[a](https://a.example)\n";
  const { end, node } = endOfNode(md, "n");
  assert.equal(end, node.subEnd);
});

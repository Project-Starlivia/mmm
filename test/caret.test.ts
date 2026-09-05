// md のカーソルと地図の位置が、どのノード（またはカード）に掛かっているか。
// 区間の重なりだけの層。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { type Anchors, buried, caretIds, derive } from "../src/caret.ts";
import { NOTHING } from "../src/map/select.ts";

const node = (
  id: number,
  label: string | null,
  children: core.Node[] = [],
  blocks: core.Block[] = [],
  fold: core.Fold | null = null,
): core.Node => ({ id, label, fold, blocks, children });

const view = (...roots: core.Node[]): core.View => ({
  frontmatter: null,
  roots: roots.map((n) => ({ node: n, sides: n.children.map(() => "Right" as const) })),
});

const spots = (rows: [number, number, number | null, number][]): Map<number, core.Spot> =>
  new Map(rows.map(([id, from, label, to]) => [id, { from, label, to }]));

/** "# r\n\n## a\n\nhello\n\n## b\n" */
const doc = view(node(2, "r", [node(3, "a"), node(5, "b")]));
const at = spots([
  [1, 0, null, 0],
  [2, 0, 2, 23],
  [3, 5, 8, 17],
  [5, 18, 21, 23],
]);
const point = (p: number) => [{ from: p, to: p }];

test("最も深いノードだけ。自身の文は地番の頭から最初の子の頭まで", () => {
  assert.deepEqual(caretIds(doc, at, point(1)), [2]);
  assert.deepEqual(caretIds(doc, at, point(7)), [3]);
  assert.deepEqual(caretIds(doc, at, point(12)), [3]); // hello の中
  assert.deepEqual(caretIds(doc, at, point(20)), [5]);
});

test("閉じ際は中と見なす。点が継ぎ目ちょうどなら始まる側 1 つ", () => {
  assert.deepEqual(caretIds(doc, at, point(5)), [3]); // r の文が閉じ、a が始まる → a
  assert.deepEqual(caretIds(doc, at, point(17)), [3]); // a の文の閉じ際。b は 18 から
  assert.deepEqual(caretIds(doc, at, point(23)), [5]); // 文書の末尾で追記中も出る
});

test("範囲と複数カーソルは掛かるもの全部。無ければ空", () => {
  assert.deepEqual(caretIds(doc, at, [{ from: 1, to: 20 }]), [2, 3, 5]);
  assert.deepEqual(caretIds(doc, at, [{ from: 1, to: 1 }, { from: 20, to: 20 }]), [2, 5]);
  assert.deepEqual(caretIds(doc, at, [{ from: 5, to: 6 }]), [2, 3]); // 範囲なら継ぎ目の両側
  assert.deepEqual(caretIds(doc, at, []), []);
});

test("Implicit は行が無く自身の文が空なので掛からない", () => {
  // "# r\n\n### x\n": r=2, Implicit=3, x=4
  const gap = view(node(2, "r", [node(3, null, [node(4, "x")])]));
  const s = spots([
    [1, 0, null, 0],
    [2, 0, 2, 11],
    [3, 5, null, 11],
    [4, 5, 9, 11],
  ]);
  assert.deepEqual(caretIds(gap, s, point(7)), [4]);
  assert.deepEqual(caretIds(gap, s, point(5)), [4]);
});

/** "# r\n\n## a\n\n### x\n\n## b\n" で a が畳まれている: r=2, a=3, x=4, b=5 */
const folded: core.Fold = { open: false, summary: "a" };
const hidden = view(node(2, "r", [node(3, "a", [node(4, "x")], [], folded), node(5, "b")]));
const hiddenAt = spots([
  [1, 0, null, 0],
  [2, 0, 2, 23],
  [3, 5, 8, 17],
  [4, 11, 15, 17],
  [5, 18, 21, 23],
]);

test("buried — 畳まれたノードの子孫。畳まれたノード自身は入らない", () => {
  assert.deepEqual([...buried(hidden)], [4]);
  assert.deepEqual([...buried(doc)], []);
});

const caret = (p: number, to = p) => ({ ranges: [{ from: p, to }], head: to });

test("derive — md が持つ間はカーソルから。anchor は主カーソルの頭のノード", () => {
  assert.deepEqual(derive(doc, at, "md", caret(12), null), { kind: "nodes", sel: { ids: [3], anchor: 3 } });
  assert.deepEqual(derive(doc, at, "md", caret(1, 20), null), { kind: "nodes", sel: { ids: [2, 3, 5], anchor: 5 } });
  // anchors が在っても見ない
  assert.deepEqual(derive(doc, at, "md", caret(12), { kind: "nodes", at: [21], anchor: 21 }), {
    kind: "nodes",
    sel: { ids: [3], anchor: 3 },
  });
  // 埋もれたノードは選択に居ない
  assert.deepEqual(derive(hidden, hiddenAt, "md", caret(13), null), { kind: "nodes", sel: { ids: [], anchor: null } });
});

test("derive — 地図が持つ間は位置から。点はラベルの頭、カードは中身の頭", () => {
  const nodes: Anchors = { kind: "nodes", at: [8, 21], anchor: 21 };
  assert.deepEqual(derive(doc, at, "map", caret(1), nodes), { kind: "nodes", sel: { ids: [3, 5], anchor: 5 } });
  // 潰れて同じノードに落ちた点は 1 つに
  assert.deepEqual(derive(doc, at, "map", caret(1), { kind: "nodes", at: [8, 9], anchor: 9 }), {
    kind: "nodes",
    sel: { ids: [3], anchor: 3 },
  });
  // 無ければ何も選んでいない
  assert.deepEqual(derive(doc, at, "map", caret(1), null), NOTHING);
  // カード: a(3) の中身 code(4) が [10, 18) に書かれている（地番は手で組む）
  const carded = view(node(2, "r", [node(3, "a", [], [{ id: 4, content: { kind: "code", info: "", text: "x" } }])]));
  const cardAt = spots([
    [1, 0, null, 0],
    [2, 0, 2, 18],
    [3, 5, 8, 18],
    [4, 10, null, 18],
  ]);
  assert.deepEqual(derive(carded, cardAt, "map", caret(1), { kind: "card", at: 10 }), { kind: "card", id: 4 });
  assert.deepEqual(derive(carded, cardAt, "map", caret(1), { kind: "card", at: 3 }), NOTHING);
  // 埋もれたノードに掛かる位置は落とす
  assert.deepEqual(derive(hidden, hiddenAt, "map", caret(1), { kind: "nodes", at: [15, 21], anchor: 15 }), {
    kind: "nodes",
    sel: { ids: [5], anchor: 5 },
  });
});

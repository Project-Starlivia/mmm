// 文書から導けるものは全部 EditorState に居る。DOM 無しでトランザクションを流して固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { EditorState } from "@codemirror/state";
import { anchors, anchorsFor, anchorsOf, choice, fields, focused, holder, setAnchors, setHolder, tree } from "../src/state.ts";
import { NOTHING } from "../src/map/select.ts";

/** "# r\n\n## a\n\n## b\n": r=2 [0,2,16], a=3 [5,8,10], b=4 [11,14,16] */
const md = "# r\n\n## a\n\n## b\n";
const make = (doc: string, cursor = 0): EditorState =>
  EditorState.create({ doc, selection: { anchor: cursor }, extensions: fields });

test("tree は doc から導く。doc が変わらないトランザクションでは同じ値のまま（parse しない）", () => {
  const s = make(md);
  assert.equal(s.field(tree).view.roots.length, 1);
  assert.deepEqual(s.field(tree).spots.get(3), { from: 5, label: 8, to: 10 });
  const s2 = s.update({ effects: setHolder.of("map") }).state;
  assert.equal(s2.field(tree), s.field(tree));
  const s3 = s.update({ changes: { from: 0, to: 0, insert: "#" } }).state;
  assert.notEqual(s3.field(tree), s.field(tree));
});

test("md が持つ間、choice はカーソルから", () => {
  const s = make(md, 8);
  assert.equal(s.field(holder), "md");
  assert.deepEqual(s.field(choice), { kind: "nodes", sel: { ids: [3], anchor: 3 } });
  const moved = s.update({ selection: { anchor: 13 } }).state;
  assert.deepEqual(moved.field(choice), { kind: "nodes", sel: { ids: [4], anchor: 4 } });
});

test("地図が持つ間、choice は anchors から。上に足しても位置が写って同じノード", () => {
  const s = make(md).update({ effects: [setHolder.of("map"), setAnchors.of({ kind: "nodes", at: [8], anchor: 8 })] }).state;
  assert.deepEqual(s.field(choice), { kind: "nodes", sel: { ids: [3], anchor: 3 } });
  const grown = s.update({ changes: { from: 5, to: 5, insert: "## n\n\n" } }).state;
  assert.deepEqual(grown.field(anchors), { kind: "nodes", at: [14], anchor: 14 });
  assert.deepEqual(grown.field(choice), { kind: "nodes", sel: { ids: [4], anchor: 4 } });
  // 行頭に # を足しても、ラベルの頭は素直にずれる
  const deeper = grown.update({ changes: { from: 11, to: 11, insert: "#" } }).state;
  assert.deepEqual(deeper.field(choice), { kind: "nodes", sel: { ids: [4], anchor: 4 } });
});

test("undo（変更の逆）で戻しても選択は残る", () => {
  const s = make(md).update({ effects: [setHolder.of("map"), setAnchors.of({ kind: "nodes", at: [13], anchor: 13 })] }).state;
  const tr = s.update({ changes: { from: 5, to: 11 } }); // ## a の行を消す
  const cut = tr.state;
  assert.deepEqual(cut.field(choice), { kind: "nodes", sel: { ids: [3], anchor: 3 } }); // b は 3 番に
  const back = cut.update({ changes: tr.changes.invert(s.doc) }).state;
  assert.deepEqual(back.field(anchors), { kind: "nodes", at: [13], anchor: 13 });
  assert.deepEqual(back.field(choice), { kind: "nodes", sel: { ids: [4], anchor: 4 } });
});

test("位置が消えた点に潰れれば、そこに掛かるノード", () => {
  const s = make(md).update({ effects: [setHolder.of("map"), setAnchors.of({ kind: "nodes", at: [8], anchor: 8 })] }).state;
  const cut = s.update({ changes: { from: 5, to: 11 } }).state; // a の行ごと消す → 位置 5 = b の頭
  assert.deepEqual(cut.field(choice), { kind: "nodes", sel: { ids: [3], anchor: 3 } });
});

test("focused は同じトランザクションの後の木で位置に写す。null なら選択を空に", () => {
  const s = make(md).update({ effects: setHolder.of("map") }).state;
  // a の行を消して b（後の木では 3）を focus に
  const cut = s.update({ changes: { from: 5, to: 11 }, effects: focused.of(3) }).state;
  assert.deepEqual(cut.field(anchors), { kind: "nodes", at: [8], anchor: 8 });
  assert.deepEqual(cut.field(choice), { kind: "nodes", sel: { ids: [3], anchor: 3 } });
  // 古い木と新しい木で位置が違う例: a を伸ばすと b（id 4）の頭は 14 → 16。後の木でしか 16 は出ない
  const grown = s.update({ changes: { from: 8, to: 9, insert: "aaa" }, effects: focused.of(4) }).state;
  assert.deepEqual(grown.field(anchors), { kind: "nodes", at: [16], anchor: 16 });
  assert.deepEqual(grown.field(choice), { kind: "nodes", sel: { ids: [4], anchor: 4 } });
  const none = cut.update({ effects: focused.of(null) }).state;
  assert.deepEqual(none.field(choice), NOTHING);
});

test("anchorsOf / anchorsFor — id と位置の往復。カードは中身の頭", () => {
  // "# r\n" 0-3、"\n" 4、"## a\n" 5-9、"\n" 10、フェンスは 11 から
  const withCard = make("# r\n\n## a\n\n```\nx\n```\n");
  const t = withCard.field(tree);
  assert.deepEqual(anchorsOf(t, 3), { kind: "nodes", at: [8], anchor: 8 });
  assert.deepEqual(anchorsOf(t, 4), { kind: "card", at: 11 });
  assert.equal(anchorsOf(t, null), null);
  assert.deepEqual(anchorsFor(t, { kind: "nodes", sel: { ids: [2, 3], anchor: 3 } }), { kind: "nodes", at: [2, 8], anchor: 8 });
  assert.deepEqual(anchorsFor(t, { kind: "card", id: 4 }), { kind: "card", at: 11 });
  assert.deepEqual(anchorsFor(t, NOTHING), { kind: "nodes", at: [], anchor: null });
});

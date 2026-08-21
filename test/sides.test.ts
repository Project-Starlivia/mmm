// 左右の側（`---` = そこから下の左右が入れ替わる印）の外形仕様。
//
// - パーサーは寛容: どの `---` も一律に左右を切り替える（複数あってもよい）
// - 道具は保守的: 区切りを書くのは「空の左側へ置く」瞬間の 1 本だけ。
//   消すときは、下の左右が変わらないように偶数本ずつ（core/seps.mbt）
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, initDoc, getText, idOf, type Snapshot } from "./_helpers.ts";

/** 右列と左列を、ルート直下ノードのラベルで表す */
function columns(s: Snapshot): { R: string[]; L: string[] } {
  const root = s.nodes.find((n) => n.depth === 1);
  const kids = s.nodes.filter((n) => n.parent === root?.id);
  const R = kids.filter((n) => n.group % 2 === 0).map((n) => n.label);
  const L = kids.filter((n) => n.group % 2 !== 0).map((n) => n.label);
  return { R, L };
}

test("S1: --- が無ければ全部右、タイトル直後の --- で全部左", () => {
  assert.deepEqual(columns(initDoc("# r\n\n## a\n\n## b\n")), { R: ["a", "b"], L: [] });
  assert.deepEqual(columns(initDoc("# r\n\n---\n\n## a\n\n## b\n")), { R: [], L: ["a", "b"] });
});

test("S2: 複数の --- は一律にトグル（人間が書いたジグザグをそのまま読む）", () => {
  const s = initDoc("# r\n\n## a\n\n---\n\n## b\n\n## c\n\n---\n\n## d\n");
  assert.deepEqual(columns(s), { R: ["a", "d"], L: ["b", "c"] });
});

test("S3: 空の左側への移動が、区切りを書く唯一の経路", () => {
  const s = initDoc("# r\n\n## a\n\n## b\n");
  const out = core.moveSideEnd([idOf(s.nodes,"b")], true);
  assert.equal(getText(), "# r\n\n## a\n\n---\n\n## b\n");
  assert.deepEqual(columns(out), { R: ["a"], L: ["b"] });
});

test("S4: 左に既にあるなら合流（区切りは増えない）", () => {
  const s = initDoc("# r\n\n## a\n\n---\n\n## b\n");
  core.moveSideEnd([idOf(s.nodes,"a")], true);
  const t = getText();
  assert.equal((t.match(/^---$/gm) ?? []).length, 1, "区切りが増えた");
  assert.deepEqual(columns(initDoc(t)), { R: [], L: ["b", "a"] });
});

test("S5: ふつうの移動は区切りを増やさず、側はテキスト位置なりに決まる", () => {
  const s = initDoc("# r\n\n## a\n\n---\n\n## b\n");
  // a を b の後ろへ = 区切りの下 = 左になる
  const out = core.moveNodes([idOf(s.nodes,"a")], idOf(s.nodes,"b"), 2);
  assert.equal((getText().match(/^---$/gm) ?? []).length, 1);
  assert.deepEqual(columns(out), { R: [], L: ["b", "a"] });
});

test("S6: 中間の区間が空いたら両脇の --- が対で消え、下の左右は変わらない", () => {
  const s = initDoc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n");
  const out = core.deleteNodes([idOf(s.nodes,"b")]);
  assert.equal(getText(), "# r\n\n## a\n\n## c\n");
  assert.deepEqual(columns(out), { R: ["a", "c"], L: [] });
});

test("S7: 末尾の区間が空いたら手前の 1 本だけ消える", () => {
  const s = initDoc("# r\n\n## a\n\n---\n\n## b\n");
  core.deleteNodes([idOf(s.nodes,"b")]);
  assert.equal(getText(), "# r\n\n## a\n");
});

test("S8: 先頭の区間が空いても「タイトル直後の ---」は残る（全部左の表現）", () => {
  const s = initDoc("# r\n\n## a\n\n---\n\n## b\n");
  const out = core.deleteNodes([idOf(s.nodes,"a")]);
  assert.equal(getText(), "# r\n\n---\n\n## b\n");
  assert.deepEqual(columns(out), { R: [], L: ["b"] });
});

test("S9: side end は undo 1 回で戻る（`---` ごと）", () => {
  const s = initDoc("# r\n\n## a\n\n## b\n");
  const before = getText();
  core.moveSideEnd([idOf(s.nodes,"b")], true);
  core.undo();
  assert.equal(getText(), before);
});

test("S10: addSideEnd — 右はいちばん下の右の後ろ、左は空なら --- ごと", () => {
  initDoc("# r\n\n## a\n");
  core.addSideEnd(true, "");
  assert.equal(getText(), "# r\n\n## a\n\n---\n\n## \n");
  initDoc("# r\n\n---\n\n## b\n");
  core.addSideEnd(false, "");
  assert.equal(getText(), "# r\n\n## \n\n---\n\n## b\n");
});

test("S11: CRLF 文書でも掃除が LF を混ぜない", () => {
  const s = initDoc("# r\r\n\r\n## a\r\n\r\n---\r\n\r\n## b\r\n\r\n---\r\n\r\n## c\r\n");
  core.deleteNodes([idOf(s.nodes,"b")]);
  assert.ok(!/[^\r]\n/.test(getText()), "LF が混ざった");
  assert.equal(getText(), "# r\r\n\r\n## a\r\n\r\n## c\r\n");
});

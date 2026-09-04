// キー → 何をするか。DOM も host も知らない表。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { type Layout, type SizeOf, layoutMap } from "../src/map/layout.ts";
import { type Key, keyed, keyedCard } from "../src/map/keys.ts";
import { NONE } from "../src/map/select.ts";

/** 全部 100 × 30 */
const size: SizeOf = () => ({ w: 100, h: 30 });

const node = (
  id: number,
  label: string | null,
  children: core.Node[] = [],
  blocks: core.Block[] = [],
): core.Node => ({
  id,
  label,
  fold: null,
  blocks,
  children,
});

const tree = (n: core.Node, sides: core.Side[] = []): core.Tree => ({ node: n, sides });

/** r(2) → a(3), 空(4)。空は label "" */
const L: Layout = layoutMap([tree(node(2, "r", [node(3, "a"), node(4, "")]), ["Right", "Right"])], size);
const empty: Layout = layoutMap([], size);

const k = (key: string, mods: Partial<Key> = {}): Key => ({ key, shift: false, mod: false, alt: false, ...mods });
const one = (id: number) => ({ ids: [id], anchor: id });

test("Enter — 名前のあるノードなら下に兄弟を足して編集、空なら足さずに埋める", () => {
  assert.deepEqual(keyed(L, one(3), k("Enter")), {
    kind: "op",
    op: { kind: "addNode", at: { kind: "after", node: 3 }, labels: [""] },
    edit: true,
  });
  assert.deepEqual(keyed(L, one(4), k("Enter")), { kind: "edit", id: 4, seed: null });
  // 何も選んでいなければ拾わない
  assert.equal(keyed(L, NONE, k("Enter")), null);
});

test("Shift+Enter は上に兄弟。Tab は子。Shift+Tab は親で包む。どれも編集開始", () => {
  assert.deepEqual(keyed(L, one(3), k("Enter", { shift: true })), {
    kind: "op",
    op: { kind: "addNode", at: { kind: "before", node: 3 }, labels: [""] },
    edit: true,
  });
  assert.deepEqual(keyed(L, one(3), k("Tab")), {
    kind: "op",
    op: { kind: "addNode", at: { kind: "in", node: 3, side: null }, labels: [""] },
    edit: true,
  });
  assert.deepEqual(keyed(L, one(3), k("Tab", { shift: true })), {
    kind: "op",
    op: { kind: "wrap", id: 3, label: "" },
    edit: true,
  });
});

test("ノードが 1 つも無ければ Enter は最初の根", () => {
  assert.deepEqual(keyed(empty, NONE, k("Enter")), {
    kind: "op",
    op: { kind: "addNode", at: { kind: "in", node: 1, side: null }, labels: [""] },
    edit: true,
  });
  assert.deepEqual(keyed(empty, NONE, k("Enter", { mod: true })), {
    kind: "op",
    op: { kind: "addNode", at: { kind: "in", node: 1, side: null }, labels: [""] },
    edit: true,
  });
});

test("Mod+Enter は anchor の編集開始。いくつ選んでいても同じ", () => {
  assert.deepEqual(keyed(L, one(3), k("Enter", { mod: true })), { kind: "edit", id: 3, seed: null });
  assert.deepEqual(keyed(L, { ids: [3, 4], anchor: 4 }, k("Enter", { mod: true })), {
    kind: "edit",
    id: 4,
    seed: null,
  });
  assert.equal(keyed(L, NONE, k("Enter", { mod: true })), null);
});

test("空のノードで字を打てば、その字から編集。名前があれば何もしない。Space は除く", () => {
  assert.deepEqual(keyed(L, one(4), k("x")), { kind: "edit", id: 4, seed: "x" });
  assert.deepEqual(keyed(L, one(4), k("X", { shift: true })), { kind: "edit", id: 4, seed: "X" });
  assert.equal(keyed(L, one(3), k("x")), null);
  assert.equal(keyed(L, one(4), k(" ")), null);
  assert.equal(keyed(L, one(4), k("x", { mod: true })), null);
});

test("複数選んでいるときの Tab / Shift+Tab は段 2 で拾うようになった（本段）。先頭に前の兄弟が無ければ Tab は拾わない", () => {
  assert.equal(keyed(L, { ids: [3, 4], anchor: 4 }, k("Tab")), null);
  assert.deepEqual(keyed(L, { ids: [3, 4], anchor: 4 }, k("Tab", { shift: true })), {
    kind: "op",
    op: { kind: "moveNode", ids: [3, 4], at: { kind: "after", node: 2 } },
    edit: false,
  });
  assert.equal(keyed(L, NONE, k("Tab")), null);
});

test("複数選んでいても宛先は anchor — 1 つ選んでいるときと同じ", () => {
  // anchor に名前があれば後ろに足す
  assert.deepEqual(keyed(L, { ids: [3, 4], anchor: 3 }, k("Enter")), {
    kind: "op",
    op: { kind: "addNode", at: { kind: "after", node: 3 }, labels: [""] },
    edit: true,
  });
  // anchor が空なら「埋めるが先」も同じに効く
  assert.deepEqual(keyed(L, { ids: [3, 4], anchor: 4 }, k("Enter")), { kind: "edit", id: 4, seed: null });
  assert.deepEqual(keyed(L, { ids: [3, 4], anchor: 4 }, k("x")), { kind: "edit", id: 4, seed: "x" });
});

test("段 1 のキーはそのまま — 矢印は select、Shift+矢印は伸ばす、Esc は解除、Mod+A は全部、Home は寄せ", () => {
  assert.deepEqual(keyed(L, one(3), k("ArrowDown")), { kind: "select", sel: { ids: [4], anchor: 4 }, reveal: true });
  assert.deepEqual(keyed(L, one(3), k("ArrowDown", { shift: true })), {
    kind: "select",
    sel: { ids: [3, 4], anchor: 4 },
    reveal: true,
  });
  assert.deepEqual(keyed(L, one(3), k("Escape")), { kind: "select", sel: NONE, reveal: false });
  assert.deepEqual(keyed(L, one(3), k("a", { mod: true })), {
    kind: "select",
    sel: { ids: [2, 3, 4], anchor: 4 },
    reveal: false,
  });
  assert.deepEqual(keyed(L, one(3), k("Home")), { kind: "center" });
  // 根で ← は行き先が無い → 拾わない
  assert.equal(keyed(L, one(2), k("ArrowLeft")), null);
});

test("拾わないキーは null（ブラウザに渡す）", () => {
  assert.equal(keyed(L, one(3), k("F5")), null);
  assert.equal(keyed(L, one(3), k("Enter", { alt: true })), null);
});

test("Delete は選択を消し、隣を keep する", () => {
  assert.deepEqual(keyed(L, one(3), k("Delete")), {
    kind: "op",
    op: { kind: "delete", ids: [3] },
    edit: false,
    keep: 4,
  });
  assert.deepEqual(keyed(L, { ids: [3, 4], anchor: 4 }, k("Backspace")), {
    kind: "op",
    op: { kind: "delete", ids: [3, 4] },
    edit: false,
    keep: 2,
  });
  assert.equal(keyed(L, NONE, k("Delete")), null);
});

test("Alt+↑↓ は塊を前の兄弟の前 / 次の兄弟の後ろへ。端では拾わない", () => {
  assert.deepEqual(keyed(L, one(4), k("ArrowUp", { alt: true })), {
    kind: "op",
    op: { kind: "moveNode", ids: [4], at: { kind: "before", node: 3 } },
    edit: false,
  });
  assert.deepEqual(keyed(L, one(3), k("ArrowDown", { alt: true })), {
    kind: "op",
    op: { kind: "moveNode", ids: [3], at: { kind: "after", node: 4 } },
    edit: false,
  });
  assert.equal(keyed(L, one(3), k("ArrowUp", { alt: true })), null);
  assert.equal(keyed(L, one(4), k("ArrowDown", { alt: true })), null);
});

test("複数選択の Tab は先頭の前の兄弟の子へ、Shift+Tab は先頭の親の後ろへ", () => {
  const M: Layout = layoutMap(
    [tree(node(2, "r", [node(3, "a"), node(4, "b", [node(5, "c"), node(6, "d")])]), ["Right", "Right"])],
    size,
  );
  assert.deepEqual(keyed(M, { ids: [5, 6], anchor: 6 }, k("Tab", { shift: true })), {
    kind: "op",
    op: { kind: "moveNode", ids: [5, 6], at: { kind: "after", node: 4 } },
    edit: false,
  });
  assert.deepEqual(keyed(M, { ids: [4, 6], anchor: 6 }, k("Tab")), {
    kind: "op",
    op: { kind: "moveNode", ids: [4, 6], at: { kind: "in", node: 3, side: null } },
    edit: false,
  });
  // 先頭 a(3) に前の兄弟は無い / 根の親は無い
  assert.equal(keyed(M, { ids: [3, 4], anchor: 4 }, k("Tab")), null);
  assert.equal(keyed(M, { ids: [2, 3], anchor: 3 }, k("Tab", { shift: true })), null);
});

test("Shift+H は畳む / 畳みを外す。Implicit と無選択は拾わない", () => {
  const F: Layout = layoutMap(
    [
      tree(
        node(2, "r", [
          { id: 3, label: "a", fold: { open: false, summary: "a" }, blocks: [], children: [] },
          node(4, null, [node(5, "x")]),
        ]),
        ["Right", "Right"],
      ),
    ],
    size,
  );
  assert.deepEqual(keyed(F, one(2), k("H", { shift: true })), { kind: "op", op: { kind: "fold", id: 2, open: false }, edit: false });
  assert.deepEqual(keyed(F, one(3), k("H", { shift: true })), { kind: "op", op: { kind: "unfold", id: 3 }, edit: false });
  assert.equal(keyed(F, one(4), k("H", { shift: true })), null);
  assert.equal(keyed(F, NONE, k("H", { shift: true })), null);
});

test("Shift+L / Shift+C / Shift+D は 1 つ選んでいるときだけ拾う", () => {
  assert.deepEqual(keyed(L, one(3), k("L", { shift: true })), { kind: "link", id: 3 });
  assert.deepEqual(keyed(L, one(3), k("C", { shift: true })), { kind: "code", id: 3 });
  assert.deepEqual(keyed(L, one(3), k("D", { shift: true })), { kind: "draw", id: 3 });
  assert.equal(keyed(L, { ids: [3, 4], anchor: 4 }, k("L", { shift: true })), null);
  assert.equal(keyed(L, NONE, k("L", { shift: true })), null);
});

test("Mod+V は貼り付け。anchor が無くても拾う", () => {
  assert.deepEqual(keyed(L, one(3), k("v", { mod: true })), { kind: "paste" });
  assert.deepEqual(keyed(L, NONE, k("v", { mod: true })), { kind: "paste" });
  // 大文字でも同じ（key 自体は大文字で来ることがある）
  assert.deepEqual(keyed(L, NONE, k("V", { mod: true })), { kind: "paste" });
  // Shift+Mod+V は別の意味に空けておく（貼り付けとして拾わない）
  assert.equal(keyed(L, one(3), k("v", { mod: true, shift: true })), null);
});

// ---- keyedCard — カードを選んでいるときの表 ----
// r(2) に blocks [{ id: 3, thematicBreak }, { id: 4, code }]。持ち主は 2、隣は 3 と 4。
const C: Layout = layoutMap(
  [
    tree(
      node(2, "r", [], [
        { id: 3, content: { kind: "thematicBreak" } },
        { id: 4, content: { kind: "code", info: "", text: "x" } },
      ]),
    ),
  ],
  size,
);

test("keyedCard: Delete / Backspace はそのカードを消し、持ち主を keep する", () => {
  assert.deepEqual(keyedCard(C, 3, k("Delete")), {
    kind: "op",
    op: { kind: "delete", ids: [3] },
    edit: false,
    keep: 2,
  });
  assert.deepEqual(keyedCard(C, 4, k("Backspace")), {
    kind: "op",
    op: { kind: "delete", ids: [4] },
    edit: false,
    keep: 2,
  });
});

test("keyedCard: ↑↓ は隣のカードを選ぶ。端では拾わない", () => {
  assert.deepEqual(keyedCard(C, 3, k("ArrowDown")), { kind: "pick", id: 4 });
  assert.equal(keyedCard(C, 4, k("ArrowDown")), null);
  assert.deepEqual(keyedCard(C, 4, k("ArrowUp")), { kind: "pick", id: 3 });
  assert.equal(keyedCard(C, 3, k("ArrowUp")), null);
});

test("keyedCard: ← は持ち主のノードを選ぶ", () => {
  assert.deepEqual(keyedCard(C, 3, k("ArrowLeft")), {
    kind: "select",
    sel: { ids: [2], anchor: 2 },
    reveal: false,
  });
});

test("keyedCard: Alt+↑↓ は前後のカードの前後へ並べ替え。端では拾わない", () => {
  assert.deepEqual(keyedCard(C, 4, k("ArrowUp", { alt: true })), {
    kind: "op",
    op: { kind: "moveBlock", ids: [4], at: { kind: "before", block: 3 } },
    edit: false,
  });
  assert.equal(keyedCard(C, 3, k("ArrowUp", { alt: true })), null);
  assert.deepEqual(keyedCard(C, 3, k("ArrowDown", { alt: true })), {
    kind: "op",
    op: { kind: "moveBlock", ids: [3], at: { kind: "after", block: 4 } },
    edit: false,
  });
  assert.equal(keyedCard(C, 4, k("ArrowDown", { alt: true })), null);
});

test("keyedCard: Mod+Enter はその場編集。Escape は外す", () => {
  assert.deepEqual(keyedCard(C, 3, k("Enter", { mod: true })), { kind: "editCard", id: 3 });
  assert.deepEqual(keyedCard(C, 3, k("Escape")), { kind: "pick", id: null });
});

test("keyedCard: どのノードの blocks にも居なければ null", () => {
  assert.equal(keyedCard(C, 99, k("Delete")), null);
});

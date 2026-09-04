// キー → 何をするか。DOM も host も知らない表。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { type Layout, type SizeOf, layoutMap } from "../src/map/layout.ts";
import { type Key, keyed } from "../src/map/keys.ts";
import { NONE } from "../src/map/select.ts";

/** 全部 100 × 30 */
const size: SizeOf = () => ({ w: 100, h: 30 });

const node = (id: number, label: string | null, children: core.Node[] = []): core.Node => ({
  id,
  label,
  fold: null,
  blocks: [],
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

test("Mod+Enter は編集開始。1 つ選んでいるときだけ", () => {
  assert.deepEqual(keyed(L, one(3), k("Enter", { mod: true })), { kind: "edit", id: 3, seed: null });
  assert.equal(keyed(L, { ids: [3, 4], anchor: 4 }, k("Enter", { mod: true })), null);
  assert.equal(keyed(L, NONE, k("Enter", { mod: true })), null);
});

test("空のノードで字を打てば、その字から編集。名前があれば何もしない。Space は除く", () => {
  assert.deepEqual(keyed(L, one(4), k("x")), { kind: "edit", id: 4, seed: "x" });
  assert.deepEqual(keyed(L, one(4), k("X", { shift: true })), { kind: "edit", id: 4, seed: "X" });
  assert.equal(keyed(L, one(3), k("x")), null);
  assert.equal(keyed(L, one(4), k(" ")), null);
  assert.equal(keyed(L, one(4), k("x", { mod: true })), null);
});

test("複数選んでいるときの Tab / Enter は何もしない（段下げは次の段）", () => {
  assert.equal(keyed(L, { ids: [3, 4], anchor: 4 }, k("Tab")), null);
  assert.equal(keyed(L, { ids: [3, 4], anchor: 4 }, k("Tab", { shift: true })), null);
  assert.equal(keyed(L, NONE, k("Tab")), null);
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

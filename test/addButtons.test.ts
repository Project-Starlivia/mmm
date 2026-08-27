// 選択ノードの周りの `+` の置き場所。向きと木の意味が食い違うと、
// 「右を押したのに上に増えた」になる。目では気づきにくいので値で固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type AddDir, type AddSpot, addSpots } from "../src/map/addButtons.ts";

const BOX = { x: 100, y: 200, w: 60, h: 20 };

const dirs = (canParent: boolean): AddDir[] =>
  addSpots(BOX, { x: 10, y: 10 }, canParent).map((s) => s.dir);

/** その向きの置き場所。無ければ試験の前提が崩れているので落とす */
const spotOf = (list: AddSpot[], dir: AddDir): AddSpot => {
  const found = list.find((s) => s.dir === dir);
  if (!found) throw new Error(`${dir} が無い`);
  return found;
};

const at = (dir: AddDir): { x: number; y: number } => {
  const { x, y } = spotOf(addSpots(BOX, { x: 10, y: 10 }, true), dir);
  return { x, y };
};

test("マップが伸びる向きと木の意味が一致する", () => {
  // 右が子、左が親。上下が兄弟 — 覚えるものを「向き」1 つで済ませる
  assert.deepEqual(at("child"), { x: 170, y: 210 });
  assert.deepEqual(at("parent"), { x: 90, y: 210 });
  assert.deepEqual(at("above"), { x: 130, y: 190 });
  assert.deepEqual(at("below"), { x: 130, y: 230 });
});

test("ルートには親を足せないので、その置き場所も出さない", () => {
  // core の cmd_add_parent は深さ 1 を弾く。押せるのに何も起きない
  // ボタンを置かない
  assert.equal(dirs(true).length, 4);
  assert.deepEqual(dirs(false).sort(), ["above", "below", "child"]);
});

test("隙間は箱の外側へ開く", () => {
  const wide = addSpots(BOX, { x: 40, y: 40 }, true);
  const near = addSpots(BOX, { x: 10, y: 10 }, true);
  assert.ok(spotOf(wide, "child").x > spotOf(near, "child").x);
  assert.ok(spotOf(wide, "parent").x < spotOf(near, "parent").x);
});

test("左右と上下は、それぞれの隙間を読む", () => {
  // 兄弟の縦間隔は 10px しかない。丸を箱の外に出すと隣の箱に食い込むので、
  // 中心を縁の上に置いて丸を内外に半分ずつ張り出させる。
  //
  // **左右と上下を違えた隙間で見る。** 揃った隙間だけで試すと、左右が
  // うっかり `gap.y` を読んでいても誰も落ちない
  const spots = addSpots(BOX, { x: 10, y: 0 }, true);
  assert.equal(spotOf(spots, "above").y, BOX.y);
  assert.equal(spotOf(spots, "below").y, BOX.y + BOX.h);
  assert.equal(spotOf(spots, "child").x, BOX.x + BOX.w + 10);
  assert.equal(spotOf(spots, "parent").x, BOX.x - 10);
});

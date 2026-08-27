// 選択ノードの周りの `+` の置き場所。向きと木の意味が食い違うと、
// 「右を押したのに上に増えた」になる。目では気づきにくいので値で固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type AddDir, addSpots } from "../src/map/addButtons.ts";

type AddSpotList = ReturnType<typeof addSpots>;

const BOX = { x: 100, y: 200, w: 60, h: 20 };

const dirs = (canParent: boolean): AddDir[] =>
  addSpots(BOX, { x: 10, y: 10 }, canParent).map((s) => s.dir);

const at = (dir: AddDir): { x: number; y: number } => {
  const found = addSpots(BOX, { x: 10, y: 10 }, true).find((s) => s.dir === dir);
  if (!found) throw new Error(`${dir} が無い`);
  return { x: found.x, y: found.y };
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
  const x = (list: AddSpotList, dir: AddDir): number => {
    const found = list.find((s) => s.dir === dir);
    if (!found) throw new Error(`${dir} が無い`);
    return found.x;
  };
  assert.ok(x(wide, "child") > x(near, "child"));
  assert.ok(x(wide, "parent") < x(near, "parent"));
});

test("上下の隙間が 0 なら、丸の中心は箱の縁ちょうどに乗る", () => {
  // 兄弟の縦間隔は 10px しかない。丸を箱の外に出すと隣の箱に食い込むので、
  // 中心を縁の上に置いて丸を内外に半分ずつ張り出させる
  const spots = addSpots(BOX, { x: 10, y: 0 }, true);
  const above = spots.find((s) => s.dir === "above");
  const below = spots.find((s) => s.dir === "below");
  if (!above || !below) throw new Error("above/below が無い");
  assert.equal(above.y, BOX.y);
  assert.equal(below.y, BOX.y + BOX.h);
});

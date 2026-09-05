// 画面外にある対象を指す針。何を指すかの決めと、位置と向きの算術を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type { Rect } from "../src/map/geometry.ts";
import { indicatorFor, indicatorTarget, isVisible } from "../src/map/indicator.ts";

const PANE = { width: 800, height: 600 };
const V = { k: 1, tx: 0, ty: 0 };

/** その場所に置いた、ありふれた大きさの箱 */
const box = (x: number, y: number): Rect => ({ x, y, w: 100, h: 60 });

test("画面の中に少しでも重なっていれば見えている", () => {
  assert.ok(isVisible({ x: 0, y: 0, w: 10, h: 10 }, V, PANE));
  assert.ok(isVisible({ x: 790, y: 590, w: 100, h: 100 }, V, PANE)); // 角だけ重なる
});

test("完全に外れていれば見えていない", () => {
  assert.ok(!isVisible({ x: 900, y: 0, w: 10, h: 10 }, V, PANE)); // 右
  assert.ok(!isVisible({ x: -100, y: 0, w: 50, h: 10 }, V, PANE)); // 左
  assert.ok(!isVisible({ x: 0, y: -100, w: 10, h: 50 }, V, PANE)); // 上
  assert.ok(!isVisible({ x: 0, y: 900, w: 10, h: 10 }, V, PANE)); // 下
});

test("真右にある対象は、右の縁を指す", () => {
  const ind = indicatorFor({ x: 5000, y: 300, w: 0, h: 0 }, V, PANE);
  assert.ok(Math.abs(ind.y - 300) < 1e-9); // 高さは変わらない
  assert.ok(ind.x < PANE.width && ind.x > PANE.width / 2);
  assert.ok(Math.abs(ind.angle) < 1e-9); // 0度 = 真右
});

test("真下にある対象は、下の縁を指す", () => {
  const ind = indicatorFor({ x: 400, y: 9000, w: 0, h: 0 }, V, PANE);
  assert.ok(Math.abs(ind.x - 400) < 1e-9);
  assert.ok(ind.y < PANE.height && ind.y > PANE.height / 2);
  assert.ok(Math.abs(ind.angle - 90) < 1e-9); // 90度 = 真下
});

test("縁ぎりぎりには置かない（角に張り付かせない余白がある）", () => {
  const ind = indicatorFor({ x: 100000, y: 0, w: 0, h: 0 }, V, PANE);
  assert.ok(ind.x < PANE.width);
  assert.ok(ind.x > 0);
});

test("パン・ズームしても world 上の位置関係で向きが決まる", () => {
  const zoomed = { k: 3, tx: -1000, ty: -1000 };
  const ind = indicatorFor({ x: 5000, y: 5000, w: 0, h: 0 }, zoomed, PANE);
  // 中心から見て右下方向のまま
  assert.ok(ind.angle > 0 && ind.angle < 90);
});

test("選択が画面外なら、他が見えていても選択を指す", () => {
  const here = box(100, 100);
  const sel = box(5000, 300);
  const target = indicatorTarget({ selection: [sel], all: [here, sel], root: here }, V, PANE);
  assert.deepEqual(target, sel);
});

test("選択が複数なら、その外接箱を指す", () => {
  const a = box(5000, 300);
  const b = box(5300, 500);
  const target = indicatorTarget({ selection: [a, b], all: [a, b], root: a }, V, PANE);
  assert.deepEqual(target, { x: 5000, y: 300, w: 400, h: 260 });
});

test("選択のどれかが見えていれば指さない", () => {
  const seen = box(100, 100);
  const away = box(5000, 300);
  assert.equal(indicatorTarget({ selection: [seen, away], all: [seen, away], root: seen }, V, PANE), null);
});

test("選択が無ければ根を指す", () => {
  const root = box(-5000, 0);
  const child = box(-4800, 0);
  const target = indicatorTarget({ selection: [], all: [root, child], root }, V, PANE);
  assert.deepEqual(target, root);
});

test("選択が無いときは、根が画面外でも文書のどれかが見えていれば指さない", () => {
  const root = box(-5000, 0);
  const here = box(100, 100);
  assert.equal(indicatorTarget({ selection: [], all: [root, here], root }, V, PANE), null);
});

test("空の文書では指さない", () => {
  assert.equal(indicatorTarget({ selection: [], all: [], root: null }, V, PANE), null);
});

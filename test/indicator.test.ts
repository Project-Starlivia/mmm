// 画面外にある対象を指す針。何を指すかの決めと、位置と向きの算術を固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type { Rect } from "../src/map/geometry.ts";
import { indicatorFor, indicatorTarget, isLost, isVisible } from "../src/map/indicator.ts";

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

// ---------- 指す先 ----------

test("選択を指す", () => {
  const sel = box(5000, 300);
  assert.deepEqual(indicatorTarget([sel], box(0, 0)), sel);
});

test("選択が複数なら、その外接箱を指す", () => {
  const a = box(5000, 300);
  const b = box(5300, 500);
  assert.deepEqual(indicatorTarget([a, b], a), { x: 5000, y: 300, w: 400, h: 260 });
});

test("選択が無ければ根を指す", () => {
  const root = box(-5000, 0);
  assert.deepEqual(indicatorTarget([], root), root);
});

test("空の文書には指す先が無い", () => {
  assert.equal(indicatorTarget([], null), null);
});

// ---------- 出すか ----------

test("指す先も目印も見えなければ、見失っている", () => {
  const away = box(5000, 300);
  assert.ok(isLost(away, [away], V, PANE));
});

test("目印が 1 つでも見えていれば、見失っていない", () => {
  const away = box(-5000, 0);
  const here = box(100, 100);
  assert.ok(!isLost(away, [away, here], V, PANE));
});

test("指す先が画面に被っていれば、方角が無いので見失っていない", () => {
  // 左右に 1 つずつ選び、どちらも画面外 — 外接箱は画面ごと包む
  const left = box(-300, 270);
  const right = box(1000, 270);
  const target = indicatorTarget([left, right], left);
  assert.ok(target && !isLost(target, [left, right], V, PANE));
});

// 画面外にある対象を指す針。位置と向きの算術だけを固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { indicatorFor, isVisible } from "../src/map/indicator.ts";

const PANE = { width: 800, height: 600 };
const V = { k: 1, tx: 0, ty: 0 };

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

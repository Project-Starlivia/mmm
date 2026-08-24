// パン・ズーム・寄せの算術。符号を 1 つ間違えても「動きはする」ので、
// 目で気づけない。値として固定しておく。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MAX_ZOOM,
  MIN_ZOOM,
  fitToPane,
  panBy,
  panToShow,
  toWorld,
  zoomAt,
} from "../src/map/view.ts";

const PANE = { width: 800, height: 600 };
const V = { k: 1, tx: 60, ty: 60 };

test("world と画面は互いの逆", () => {
  const v = { k: 2.5, tx: -30, ty: 17 };
  const w = toWorld(v, 400, 300);
  assert.ok(Math.abs(w.x * v.k + v.tx - 400) < 1e-9);
  assert.ok(Math.abs(w.y * v.k + v.ty - 300) < 1e-9);
});

test("ズームしても、カーソルの下の world は動かない", () => {
  // これが崩れると、拡大するたびに見ていた場所が画面の外へ逃げる
  for (const start of [{ k: 1, tx: 60, ty: 60 }, { k: 0.3, tx: -200, ty: 90 }]) {
    for (const delta of [-300, -40, 40, 300]) {
      const before = toWorld(start, 512, 331);
      const after = toWorld(zoomAt(start, 512, 331, delta), 512, 331);
      assert.ok(
        Math.abs(before.x - after.x) < 1e-9 && Math.abs(before.y - after.y) < 1e-9,
        `k=${start.k} delta=${delta}: ${JSON.stringify(before)} → ${JSON.stringify(after)}`,
      );
    }
  }
});

test("ホイールを上へ回すと拡大、下で縮小", () => {
  assert.ok(zoomAt(V, 0, 0, -100).k > V.k);
  assert.ok(zoomAt(V, 0, 0, 100).k < V.k);
});

test("倍率は上下の限界で止まる", () => {
  let v = V;
  for (let i = 0; i < 50; i++) v = zoomAt(v, 0, 0, -500);
  assert.equal(v.k, MAX_ZOOM);
  for (let i = 0; i < 50; i++) v = zoomAt(v, 0, 0, 500);
  assert.equal(v.k, MIN_ZOOM);
});

test("パンは倍率を変えない", () => {
  const v = panBy({ k: 2, tx: 10, ty: 20 }, 5, -7);
  assert.deepEqual(v, { k: 2, tx: 15, ty: 13 });
});

const BOX = { x: 100, y: 100, w: 120, h: 30 };

test("既に見えている箱では動かない", () => {
  assert.deepEqual(panToShow(V, BOX, PANE, 40), V);
});

test("左と上へはみ出していれば、余白のぶんだけ入れる", () => {
  const v = panToShow({ k: 1, tx: -150, ty: -120 }, BOX, PANE, 40);
  assert.equal(BOX.x * v.k + v.tx, 40);
  assert.equal(BOX.y * v.k + v.ty, 40);
});

test("右と下へはみ出していれば、外縁が余白の内側に入る", () => {
  const v = panToShow({ k: 1, tx: 760, ty: 580 }, BOX, PANE, 40);
  assert.equal(BOX.x * v.k + v.tx + BOX.w * v.k, PANE.width - 40);
  assert.equal(BOX.y * v.k + v.ty + BOX.h * v.k, PANE.height - 40);
});

test("寄せても倍率は変えない（キーで辿るたびに拡大したりしない）", () => {
  const v = panToShow({ k: 0.5, tx: -900, ty: -900 }, BOX, PANE, 40);
  assert.equal(v.k, 0.5);
});

test("全部を収める見え方は、中身の中心をペインの中心に置く", () => {
  const boxes = [
    { x: 0, y: 0, w: 100, h: 40 },
    { x: 300, y: 200, w: 100, h: 40 },
  ];
  const v = fitToPane(boxes, PANE, 60);
  assert.ok(v);
  const cx = (0 + 400) / 2;
  const cy = (0 + 240) / 2;
  assert.ok(Math.abs(cx * v.k + v.tx - PANE.width / 2) < 1e-9);
  assert.ok(Math.abs(cy * v.k + v.ty - PANE.height / 2) < 1e-9);
});

test("小さい文書でも 1 倍を超えて寄らない", () => {
  const v = fitToPane([{ x: 0, y: 0, w: 10, h: 10 }], PANE, 60);
  assert.ok(v);
  assert.equal(v.k, 1);
});

test("大きい文書は収まるまで引くが、下限では止まる", () => {
  const wide = fitToPane([{ x: 0, y: 0, w: 4000, h: 100 }], PANE, 60);
  assert.ok(wide);
  assert.ok(wide.k < 1 && wide.k > MIN_ZOOM);
  const huge = fitToPane([{ x: 0, y: 0, w: 400000, h: 100 }], PANE, 60);
  assert.ok(huge);
  assert.equal(huge.k, MIN_ZOOM);
});

test("箱が無ければ見え方を決めない", () => {
  assert.equal(fitToPane([], PANE, 60), null);
});

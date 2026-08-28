// パン・ズーム・寄せの算術。符号を 1 つ間違えても「動きはする」ので、
// 目で気づけない。値として固定しておく。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MAX_ZOOM,
  MIN_ZOOM,
  centerOn,
  fitToPane,
  panBy,
  panToShow,
  pinch,
  type Span,
  toWorld,
  zoomAt,
  zoomTo,
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

test("寄せる先は箱の中心を画面の中心に置く。倍率は変えない", () => {
  const v = centerOn({ k: 2, tx: 999, ty: 999 }, BOX, PANE);
  assert.equal(v.k, 2);
  const cx = BOX.x + BOX.w / 2;
  const cy = BOX.y + BOX.h / 2;
  assert.ok(Math.abs(cx * v.k + v.tx - PANE.width / 2) < 1e-9);
  assert.ok(Math.abs(cy * v.k + v.ty - PANE.height / 2) < 1e-9);
});

const span = (ax: number, ay: number, bx: number, by: number): Span => ({
  a: { x: ax, y: ay },
  b: { x: bx, y: by },
});

test("zoomTo は、その点の下の world を動かさない", () => {
  for (const start of [{ k: 1, tx: 60, ty: 60 }, { k: 0.3, tx: -200, ty: 90 }]) {
    for (const k of [0.2, 0.5, 1, 2.5]) {
      const before = toWorld(start, 512, 331);
      const after = toWorld(zoomTo(start, 512, 331, k), 512, 331);
      assert.ok(Math.abs(before.x - after.x) < 1e-9);
      assert.ok(Math.abs(before.y - after.y) < 1e-9);
    }
  }
});

test("zoomTo も上下の限界で止まる", () => {
  assert.equal(zoomTo(V, 0, 0, 99).k, MAX_ZOOM);
  assert.equal(zoomTo(V, 0, 0, 0.001).k, MIN_ZOOM);
});

test("2 本指を離すと拡大、近づけると縮小", () => {
  const from = span(100, 100, 200, 100);
  assert.ok(pinch(V, from, span(50, 100, 250, 100)).k > V.k);
  assert.ok(pinch(V, from, span(140, 100, 160, 100)).k < V.k);
});

test("pinch は、2 点の中点の下の world を中点へ運ぶ", () => {
  // 拡大しながら指をずらしても、掴んでいた場所が指の下に留まる
  const from = span(100, 200, 300, 200); // 中点 (200, 200)
  const to = span(140, 260, 460, 260); // 中点 (300, 260)、距離は 1.6 倍
  const w = toWorld(V, 200, 200);
  const after = pinch(V, from, to);
  assert.ok(Math.abs(w.x * after.k + after.tx - 300) < 1e-9);
  assert.ok(Math.abs(w.y * after.k + after.ty - 260) < 1e-9);
});

test("距離が変わらない 2 本指は、ただのパン", () => {
  const after = pinch(V, span(0, 0, 100, 0), span(30, -20, 130, -20));
  assert.deepEqual(after, { k: 1, tx: 90, ty: 40 });
});

test("2 本の指が重なっても倍率は壊れない", () => {
  // 距離 0 で割ると Infinity/NaN が k に流れ込み、以降すべての描画が消える
  const after = pinch(V, span(50, 50, 50, 50), span(60, 60, 80, 80));
  assert.equal(after.k, V.k);
});

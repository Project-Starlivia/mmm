// 座標と線の形。マップの見た目はここから組み上がるので、
// ドロップ判定（drop.test.ts）が立つ土台として固定しておく。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  centerOf,
  distToSeg,
  leftOf,
  midOfPolyline,
  rightOf,
  round2,
  unionRect,
} from "../src/map/geometry.ts";
import { edgePath, edgeSegs, flattenSegs } from "../src/map/edge.ts";

const BOX = { x: 10, y: 20, w: 100, h: 40 };

test("箱の中心と、線が触れる左右の辺の中点", () => {
  assert.deepEqual(centerOf(BOX), { x: 60, y: 40 });
  assert.deepEqual(rightOf(BOX), { x: 110, y: 40 });
  assert.deepEqual(leftOf(BOX), { x: 10, y: 40 });
});

test("点から線分までの距離。端より外なら端までの距離になる", () => {
  const a = { x: 0, y: 0 };
  const b = { x: 10, y: 0 };
  assert.equal(distToSeg({ x: 5, y: 3 }, a, b), 3); // 真横
  assert.equal(distToSeg({ x: -4, y: 0 }, a, b), 4); // 手前の外
  assert.equal(distToSeg({ x: 14, y: 0 }, a, b), 4); // 先の外
  assert.equal(distToSeg({ x: 3, y: 0 }, a, a), 3); // 長さ 0 の線分
});

test("折れ線の真ん中は、長さで測った中央", () => {
  const pts = [
    { x: 0, y: 0 },
    { x: 10, y: 0 },
    { x: 10, y: 10 },
  ];
  assert.deepEqual(midOfPolyline(pts), { x: 10, y: 0 });
});

test("真横に並ぶ親子は直線で結ぶ", () => {
  const segs = edgeSegs(100, 0);
  assert.equal(segs.length, 1);
  assert.equal(segs[0].c, "L");
});

test("段差があれば三次ベジェ 1 本", () => {
  const segs = edgeSegs(100, 40);
  assert.equal(segs.length, 1);
  assert.equal(segs[0].c, "C");
  assert.equal(segs[0].p.length, 6); // 制御点 2 つ + 終点
});

test("折れ線に落としても、始点と終点は動かない", () => {
  const pts = flattenSegs(edgeSegs(100, 40), 8);
  assert.deepEqual(pts[0], [0, 0]);
  assert.deepEqual(pts[pts.length - 1], [100, 40]);
});

test("d 属性は始点から始まり、終点で終わる", () => {
  const d = edgePath({ x: 10, y: 20 }, { x: 110, y: 60 });
  assert.ok(d.startsWith("M 10 20"), d);
  assert.ok(d.endsWith("110 60"), d);
});

test("座標は小数 2 桁に丸める（d 属性を短く保つため）", () => {
  assert.equal(round2(1.23456), 1.23);
  assert.equal(round2(-1.005), -1);
});

test("複数の箱を包む最小の箱", () => {
  const r = unionRect([
    { x: 0, y: 10, w: 20, h: 5 },
    { x: 100, y: 0, w: 10, h: 40 },
  ]);
  assert.deepEqual(r, { x: 0, y: 0, w: 110, h: 40 });
});

test("箱が1つなら、その箱そのもの", () => {
  const box = { x: 5, y: 5, w: 20, h: 20 };
  assert.deepEqual(unionRect([box]), box);
});

test("箱が無ければ null", () => {
  assert.equal(unionRect([]), null);
});

// 分割線の居場所。狭いときに「両方」を残すと、CSS が片方を隠して
// **状態が 2 つになり食い違う**（矢印は行けない場所を指す）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type Vis, project, spotsFor } from "../src/app/panes.ts";

const MD_ONLY: Vis = { md: true, map: false };
const BOTH: Vis = { md: true, map: true };
const MAP_ONLY: Vis = { md: false, map: true };

test("広いときは 3 つ、狭いときは 2 つ", () => {
  assert.deepEqual(spotsFor(false), [MAP_ONLY, BOTH, MD_ONLY]);
  assert.deepEqual(spotsFor(true), [MAP_ONLY, MD_ONLY]);
});

test("左から右へ並ぶ順は、狭くても変わらない", () => {
  // `‹` はいつでも「分割線を左へ 1 つ」。行き先が減るだけ
  for (const narrow of [false, true]) {
    const list = spotsFor(narrow);
    assert.deepEqual(list[0], MAP_ONLY);
    assert.deepEqual(list[list.length - 1], MD_ONLY);
  }
});

test("居場所にある形は、そのまま", () => {
  assert.deepEqual(project(BOTH, spotsFor(false)), BOTH);
  assert.deepEqual(project(MD_ONLY, spotsFor(true)), MD_ONLY);
});

test("狭いところへ「両方」が来たら、マップを残す", () => {
  assert.deepEqual(project(BOTH, spotsFor(true)), MAP_ONLY);
});

test("「両方消えた」は作らない", () => {
  const none: Vis = { md: false, map: false };
  // 広いときは両方に戻す（今までと同じ）。狭いときはマップだけ
  assert.deepEqual(project(none, spotsFor(false)), BOTH);
  assert.deepEqual(project(none, spotsFor(true)), MAP_ONLY);
});

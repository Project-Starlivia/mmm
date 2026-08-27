// 指の台帳。「いま何本か」を取り違えると、2 本目を置いた瞬間に地図が
// 跳ねたり、1 本離しても掴んだままになったりする。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { Fingers } from "../src/map/gesture.ts";

test("1 本だけでは何も言わない", () => {
  const f = new Fingers();
  f.down(1, 10, 10);
  assert.equal(f.pinching, false);
  assert.equal(f.move(1, 20, 20), null);
});

test("2 本目が乗ると pinch が始まる", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  assert.equal(f.pinching, true);
});

test("2 本目が動くと、前後の位置が出る", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  const g = f.move(2, 140, 0);
  assert.deepEqual(g, {
    from: { a: { x: 0, y: 0 }, b: { x: 100, y: 0 } },
    to: { a: { x: 0, y: 0 }, b: { x: 140, y: 0 } },
  });
});

test("動いた分だけを次の起点にする", () => {
  // 覚え直さないと、2 回目以降が「最初の位置からの差」になって加速する
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.move(2, 140, 0);
  const g = f.move(2, 160, 0);
  assert.deepEqual(g?.from.b, { x: 140, y: 0 });
});

test("動いていない指は何も言わない", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  assert.equal(f.move(2, 100, 0), null);
});

test("1 本離すと pinch は終わる", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.up(2);
  assert.equal(f.pinching, false);
  assert.equal(f.move(1, 50, 50), null);
});

test("3 本目は組に入れない — 最初の 2 本を使い続ける", () => {
  // 途中で組が入れ替わると、指を足した瞬間に地図が跳ぶ
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.down(3, 200, 0);
  assert.equal(f.move(3, 260, 0), null);
  assert.deepEqual(f.move(2, 140, 0)?.to.b, { x: 140, y: 0 });
});

test("clear ですべて忘れる", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.clear();
  assert.equal(f.pinching, false);
});

test("only: 0 本なら null", () => {
  const f = new Fingers();
  assert.equal(f.only(), null);
});

test("only: 1 本ならその位置", () => {
  const f = new Fingers();
  f.down(1, 10, 20);
  assert.deepEqual(f.only(), { x: 10, y: 20 });
});

test("only: 2 本なら null", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  assert.equal(f.only(), null);
});

test("only: 2 本目を離すと、残った指の動いた後の位置が出る", () => {
  // 着地した場所ではなく、離すまでに動いた「いま」の位置でないと、
  // パンを立て直したときに指の下から地図がずれる
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.move(1, 30, 40);
  f.up(2);
  assert.deepEqual(f.only(), { x: 30, y: 40 });
});

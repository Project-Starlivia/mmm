// その場で直す入力欄の置き場所。
//
// 「重なって見えるか」は目でしか確かめられないが、**重なる条件は関係として
// 書ける**: 入力欄の中で文字が始まる位置は、SVG のラベルが始まる位置と
// 画面座標で一致しなければならない。枠と余白はズームに追従しない CSS ピクセル
// なので、倍率 1 では合っているのに 2 倍でずれる、が起きやすい。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CARD_BORDER,
  LABEL_BORDER,
  LABEL_MIN_PAD,
  cardPlacement,
  labelPlacement,
} from "../src/map/overlay.ts";
import type { Box } from "../src/map/layout.ts";
import type { NodeInfo } from "../src/coreApi.ts";
import { rowOf } from "../src/map/metrics.ts";

const NODE: NodeInfo = {
  id: 1,
  depth: 2,
  parent: -1,
  from: 0,
  headEnd: 0,
  to: 0,
  hasContent: false,
  hidden: false,
  group: 0,
  left: false,
  label: "ラベル",
};
const BOX: Box = { n: NODE, x: 40, y: 25, w: 120, h: 30, rows: [] };

/** SVG のラベルの文字が始まる画面座標 */
const labelInkAt = (b: Box, k: number, tx: number): number =>
  (b.x + rowOf(b.n).padX) * k + tx;

/** 入力欄の文字が始まる画面座標（box-sizing: border-box） */
const editorInkAt = (p: { left: number; padding: number }): number =>
  p.left + LABEL_BORDER + p.padding;

for (const view of [
  { k: 1, tx: 0, ty: 0 },
  { k: 2.5, tx: 37, ty: -14 },
  { k: 0.4, tx: 5, ty: 5 },
]) {
  test(`ラベルの入力欄は、倍率 ${view.k} でも文字の始まりが SVG と一致する`, () => {
    const p = labelPlacement(BOX, view, 50);
    const want = labelInkAt(BOX, view.k, view.tx);
    // 余白は潰れないよう 2px を下限にしてあるので、縮めたときだけ右へずれる
    const slack = rowOf(NODE).padX * view.k < LABEL_MIN_PAD ? LABEL_MIN_PAD : 0;
    assert.ok(
      Math.abs(editorInkAt(p) - want) <= slack + 1e-9,
      `k=${view.k}: 入力欄 ${editorInkAt(p)} / SVG ${want}`,
    );
  });
}

test("ラベルの入力欄は、上端も箱と揃う（枠のぶんだけ外へ出る）", () => {
  const view = { k: 2, tx: 10, ty: 20 };
  const p = labelPlacement(BOX, view, 50);
  assert.equal(p.top + LABEL_BORDER, BOX.y * view.k + view.ty);
  assert.equal(p.height, rowOf(NODE).rowH * view.k + LABEL_BORDER * 2);
});

test("短いラベルなら箱にぴったり、長ければ右へ伸びる", () => {
  const view = { k: 1, tx: 0, ty: 0 };
  const short = labelPlacement(BOX, view, 0);
  assert.equal(short.width, BOX.w + LABEL_BORDER * 2);
  const long = labelPlacement(BOX, view, 400);
  assert.ok(long.width > short.width);
});

test("字の大きさも倍率に乗る（ズームしても箱と字がずれない）", () => {
  const one = labelPlacement(BOX, { k: 1, tx: 0, ty: 0 }, 10);
  const two = labelPlacement(BOX, { k: 2, tx: 0, ty: 0 }, 10);
  assert.equal(two.fontSize, one.fontSize * 2);
});

const CARD = { x: 40, y: 60, w: 100, h: 40 };

test("カードの入力欄は、カードより小さくならない", () => {
  const view = { k: 1, tx: 0, ty: 0 };
  const p = cardPlacement(CARD, view, { lines: 1, widest: 8 });
  assert.equal(p.left, CARD.x);
  assert.equal(p.top, CARD.y);
  assert.ok(p.width >= CARD.w && p.height >= CARD.h);
  // 枠のぶんを足しておかないと最終行が削れる
  assert.equal(p.width, CARD.w + CARD_BORDER);
});

test("カードの入力欄は、中身が増えたら下と右へ伸びる", () => {
  const view = { k: 1, tx: 0, ty: 0 };
  const one = cardPlacement(CARD, view, { lines: 1, widest: 8 });
  const many = cardPlacement(CARD, view, { lines: 20, widest: 8 });
  assert.ok(many.height > one.height, "行が増えても伸びていない");
  const wide = cardPlacement(CARD, view, { lines: 1, widest: 300 });
  assert.ok(wide.width > one.width, "長い行で伸びていない");
});

test("カードの入力欄も倍率にそのまま乗る", () => {
  const one = cardPlacement(CARD, { k: 1, tx: 0, ty: 0 }, { lines: 1, widest: 8 });
  const two = cardPlacement(CARD, { k: 2, tx: 0, ty: 0 }, { lines: 1, widest: 8 });
  assert.equal(two.fontSize, one.fontSize * 2);
  assert.equal(two.padding, one.padding * 2);
  assert.equal(two.width - CARD_BORDER, (one.width - CARD_BORDER) * 2);
});

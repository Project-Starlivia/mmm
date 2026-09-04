// カードの入力欄を SVG の上のどこに置くか。枠はカードの矩形に載せ、余白は内側。
// 枠はズームに追従しない CSS ピクセルなので、world 単位で組んでから倍率を掛ける。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { CARD_BORDER, CARD_PAD, cardPlacement } from "../src/map/card.ts";

const RECT = { x: 40, y: 60, w: 100, h: 40 };

test("倍率 1 — 枠はカードの矩形に載り、余白は内側", () => {
  const p = cardPlacement(RECT, { k: 1, tx: 0, ty: 0 }, { lines: 1, widest: 8 });
  assert.equal(p.left, RECT.x);
  assert.equal(p.top, RECT.y);
  assert.equal(p.width, RECT.w + CARD_BORDER * 2);
  assert.equal(p.height, RECT.h + CARD_BORDER * 2);
  assert.equal(p.padding, CARD_PAD);
});

test("倍率 2 — 位置と余白は倍率に乗り、枠は乗らない", () => {
  const p = cardPlacement(RECT, { k: 2, tx: 37, ty: -14 }, { lines: 1, widest: 8 });
  assert.equal(p.left, RECT.x * 2 + 37);
  assert.equal(p.top, RECT.y * 2 - 14);
  assert.equal(p.width, RECT.w * 2 + CARD_BORDER * 2);
  assert.equal(p.padding, CARD_PAD * 2);
  assert.equal(p.fontSize, cardPlacement(RECT, { k: 1, tx: 0, ty: 0 }, { lines: 1, widest: 8 }).fontSize * 2);
});

test("中身がカードに収まればぴったり、はみ出せば右・下へ伸びる", () => {
  const view = { k: 1, tx: 0, ty: 0 };
  const small = cardPlacement(RECT, view, { lines: 1, widest: 8 });
  const wide = cardPlacement(RECT, view, { lines: 1, widest: 400 });
  assert.equal(wide.width, 400 + CARD_PAD * 2 + CARD_BORDER * 2);
  assert.equal(wide.height, small.height);
  const tall = cardPlacement(RECT, view, { lines: 20, widest: 8 });
  assert.ok(tall.height > small.height);
  assert.equal(tall.width, small.width);
});

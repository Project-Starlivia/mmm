// カードの入力欄を SVG の上のどこに置くか。ラベルと同じ理由でズームに追従しない
// 枠・余白を world 単位で組んでから倍率を掛ける。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { CARD_BORDER, cardPlacement } from "../src/map/card.ts";

const RECT = { x: 40, y: 60, w: 100, h: 40 };

test("倍率 1 — 入力欄の文字の始まりはカードの原点と一致する", () => {
  const p = cardPlacement(RECT, { k: 1, tx: 0, ty: 0 }, { lines: 1, widest: 8 });
  assert.equal(p.left + CARD_BORDER + p.padding, RECT.x);
  assert.equal(p.top + CARD_BORDER + p.padding, RECT.y);
});

test("倍率 2 — ズームしても文字の始まりはカードの原点と一致する", () => {
  const p = cardPlacement(RECT, { k: 2, tx: 37, ty: -14 }, { lines: 1, widest: 8 });
  assert.equal(p.left + CARD_BORDER + p.padding, RECT.x * 2 + 37);
  assert.equal(p.top + CARD_BORDER + p.padding, RECT.y * 2 - 14);
});

test("中身がカードより小さければぴったり、大きければ右・下へ伸びる", () => {
  const view = { k: 1, tx: 0, ty: 0 };
  const small = cardPlacement(RECT, view, { lines: 1, widest: 8 });
  assert.equal(small.width, RECT.w + CARD_BORDER * 2 + small.padding * 2);
  assert.equal(small.height, RECT.h + CARD_BORDER * 2 + small.padding * 2);
  const wide = cardPlacement(RECT, view, { lines: 1, widest: 400 });
  assert.ok(wide.width > small.width);
  const tall = cardPlacement(RECT, view, { lines: 20, widest: 8 });
  assert.ok(tall.height > small.height);
});

test("字の大きさも倍率に乗る（ズームしても箱と字がずれない）", () => {
  const one = cardPlacement(RECT, { k: 1, tx: 0, ty: 0 }, { lines: 1, widest: 8 });
  const two = cardPlacement(RECT, { k: 2, tx: 0, ty: 0 }, { lines: 1, widest: 8 });
  assert.equal(two.fontSize, one.fontSize * 2);
});

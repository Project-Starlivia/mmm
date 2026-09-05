// ラベルの入力欄を SVG の上のどこに置くか。枠と余白は CSS ピクセルでズームに
// 追従しないので、world の単位で組んでから倍率を掛け、追従しないぶんを別に足す。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import type { Box } from "../src/map/layout.ts";
import { LABEL_BORDER, LABEL_MIN_PAD, labelPlacement } from "../src/map/label.ts";
import { ROW_NORMAL } from "../src/map/metrics.ts";

const node: core.Node = { id: 2, label: "a", fold: null, blocks: [], children: [] };
const box: Box = { node, parent: null, buried: 0, fan: 0, x: 10, y: 20, w: 100, h: 30, rows: [] };

test("倍率 1 — 箱の左上から枠のぶん外へ。字は箱の padX から始まる", () => {
  const p = labelPlacement(box, { k: 1, tx: 0, ty: 0 }, 30);
  assert.equal(p.left, 10 - LABEL_BORDER);
  assert.equal(p.top, 20 - LABEL_BORDER);
  assert.equal(p.width, 100 + LABEL_BORDER * 2);
  assert.equal(p.height, ROW_NORMAL.rowH + LABEL_BORDER * 2);
  assert.equal(p.fontSize, ROW_NORMAL.fontPx);
  assert.equal(p.padding, ROW_NORMAL.padX);
});

test("倍率 2 — 位置と字と余白は倍になり、枠は倍にならない", () => {
  const p = labelPlacement(box, { k: 2, tx: 5, ty: 7 }, 30);
  assert.equal(p.left, 10 * 2 + 5 - LABEL_BORDER);
  assert.equal(p.top, 20 * 2 + 7 - LABEL_BORDER);
  assert.equal(p.width, 100 * 2 + LABEL_BORDER * 2);
  assert.equal(p.fontSize, ROW_NORMAL.fontPx * 2);
  assert.equal(p.padding, ROW_NORMAL.padX * 2);
});

test("字が箱より長ければ右へ伸びる。倍率が小さくても余白は最低ぶん残す", () => {
  const p = labelPlacement(box, { k: 1, tx: 0, ty: 0 }, 200);
  assert.equal(p.width, 200 + ROW_NORMAL.padX * 2 + LABEL_BORDER * 2);
  const q = labelPlacement(box, { k: 0.1, tx: 0, ty: 0 }, 30);
  assert.equal(q.padding, LABEL_MIN_PAD);
});

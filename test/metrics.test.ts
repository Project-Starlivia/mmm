// 寸法のうち、DOM を触らない規則だけ（文字の実測は canvas に聞くしかない）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { foldName, labelOf } from "../src/map/metrics.ts";

const node = (label: string | null, fold: core.Fold | null = null): core.Node => ({
  id: 1,
  label,
  fold,
  blocks: [],
  children: [],
});

test("畳んだノードの字は summary > ラベル", () => {
  assert.equal(foldName(node("a", { open: false, summary: "s" })), "s");
  assert.equal(foldName(node("a", { open: false, summary: null })), "a");
  assert.equal(foldName(node("", { open: false, summary: null })), "");
});

test("Implicit の字は空", () => {
  assert.equal(labelOf(node(null)), "");
  assert.equal(labelOf(node("")), "");
});

// 記法構造は原文を 1 バイトも落とさない。**大きさの見本 5 本で言う** —
// core の中の見本 188 通りは短くて作られたものなので、実文書に近い大きさで
// もう一度言う。
//
// **記法の変化はここに無い。** それは core の見本が言う（corpus_wbtest.mbt）。
// ここが持つのは大きさだけなので、**大きさそのものを主張する**（#88）— 深さ・幅・
// ノード数が縮んでいたら、法則が通っても意味が無い。時間は測らない（CI で揺れる）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { isNode, notationBack, serialize, spot, survey } from "../src/app.ts";

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures");
const names = fs.readdirSync(dir).filter((f) => f.endsWith(".md"));

test("見本が在る", () => {
  assert.ok(names.length > 0, "test/fixtures に .md が 1 つも無い");
});

for (const name of names) {
  const md = fs.readFileSync(path.join(dir, name), "utf8");

  test(`${name}: 触っていない記法構造を書けば、原文がそのまま返る`, () => {
    assert.equal(notationBack(md), md);
  });

  // **書きは別の道。** 木から綴る正規形は入力と違いうる（見出しの末尾空白や
  // タブが正規化される）ので、冪等であることだけを言う。
  test(`${name}: 木から綴った正規形は冪等`, () => {
    const once = serialize(md);
    assert.equal(serialize(once), once);
  });
}

// 大きさの見本が、名乗っている大きさを持っているか。**生成器の名前ではなく、
// core が読んだ木で数える** — deep.md は  を 200 本まで増やして「深さ 200」を
// 名乗っていたが、見出しは 6 段までなので実際は 6 ノードしか作っていなかった（#88）。
const SIZES: Array<{ name: string; nodes: number }> = [
  { name: "deep.md", nodes: 200 },
  { name: "wide.md", nodes: 2001 },
  { name: "mixed.md", nodes: 5000 },
  { name: "fat.md", nodes: 3 },
  { name: "rich.md", nodes: 301 },
];

/** 木のノードの数。地番の在る id を頭から辿って数える */
function nodeCount(md: string): number {
  const s = survey(md);
  let n = 0;
  for (let id = 2; spot(s, id) !== null; id++) if (isNode(s, id)) n++;
  return n;
}

test("大きさの見本は 5 本で、それぞれが名乗る大きさを持つ", () => {
  assert.deepEqual(names.sort(), SIZES.map((s) => s.name).sort());
  for (const { name, nodes } of SIZES) {
    const md = fs.readFileSync(path.join(dir, name), "utf8");
    assert.equal(nodeCount(md), nodes, name);
  }
});

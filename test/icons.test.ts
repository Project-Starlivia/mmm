// 絵の表（app/parts/icons.mbt）を**表の側から**照らす。
//
// 表は「使う絵の全部」を名乗るので、誰も使わない絵を抱えてはいけない。読む人は
// その絵が出る場面を探しに行って、見つけられない（#325。しらせの言葉は #303）。
// 呼ぶ側 → 表 は見ない — 知らない名前は `icon` が abort し、メニューの絵は `is_icon` が落とす
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import * as mbt from "../_build/js/release/build/mmm/app/js/js.js";

const TABLE = path.normalize("app/parts/icons.mbt");

// 呼ぶ側を待っている絵。呼ばれたら外す
const waiting = [
  "circle-plus", // #48 ノードの脇の +
];

function* sources(dir: string): Generator<string> {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) yield* sources(p);
    else if (name.endsWith(".mbt") && !name.endsWith("_wbtest.mbt")) yield p;
  }
}

// 絵は綴りのまま渡る（`"clock"`）。表の中身は呼びではないので除く — 同じファイルの
// `nod` は `check` と `loader-circle` を使う
const text = [...sources("app"), ...sources("core")]
  .map((p) => {
    const s = fs.readFileSync(p, "utf8");
    return p === TABLE ? s.replace(/^let marks\b[\s\S]*?^\]\r?$/m, "") : s;
  })
  .join("\n");

const table: string[] = [...mbt.mmmIconNames()];
const used = (name: string) => text.includes(`"${name}"`);

test("表の絵は全部、呼ぶ側が使う", () => {
  const mute = table.filter((n) => !used(n) && !waiting.includes(n));
  assert.deepEqual(mute, [], `誰も使わない。${TABLE} から消すか、使う側を足す`);
});

test("待っている絵は表に在り、まだ誰も使わない", () => {
  const done = waiting.filter((n) => !table.includes(n) || used(n));
  assert.deepEqual(done, [], "待ちが済んだ。waiting から外す");
});

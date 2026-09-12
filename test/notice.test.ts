// しらせの言葉と表（app/parts/notice.mbt）を**両向きで**照らす。
//
// 呼ぶ側 → 表  … 表に無い綴りを渡すと実行時に abort するが、それは押して初めて分かる
// 表 → 呼ぶ側  … 表は「言える言葉の全部」を名乗るので、誰も言わない言葉を抱えてはいけない。
//                読む人はその言葉が出る場面を探しに行って、見つけられない（#303）
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import * as mbt from "../_build/js/release/build/mmm/app/js/js.js";

const TABLE = "app/parts/notice.mbt";

// 言葉の形で向きが決まる（docs/spec.md「しらせ」）。`Couldn't …` は failed、
// 「次の一手はそちら」は blocked
const shape = { failed: /"(Couldn't [^"]*)"/g, blocked: /"((?:Select a node|Nothing to export)[^"]*)"/g };

function* sources(dir: string): Generator<string> {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) yield* sources(p);
    else if (name.endsWith(".mbt") && !name.endsWith("_wbtest.mbt") && name !== path.basename(TABLE)) yield p;
  }
}

const text = new Map([...sources("app")].map((p) => [p, fs.readFileSync(p, "utf8")] as const));

// しらせの呼び 1 つぶんの字。`failed(` / `blocked(` から、引数が収まるだけ先まで。
// **渡している場所だけを見る** — 同じ綴りや名前がコメントや別の用途で出てくるので
const calls = [...text.values()].flatMap((s) =>
  [...s.matchAll(/\b(?:failed|blocked)\s*\(/g)].map((m) => s.slice(m.index!, m.index! + 160)),
);

// 表の言葉のうち、名前に束ねてあるもの（`pub let no_file_access = "…"`）。
// 呼ぶ側はその名前で渡すので、綴りのほうは呼ぶ側に出てこない
const named = new Map<string, string>();
for (const [, name, word] of fs.readFileSync(TABLE, "utf8").matchAll(/pub let (\w+) = "([^"]*)"/g)) {
  named.set(word, name);
}

for (const [kind, re] of Object.entries(shape)) {
  const table: string[] = [...(kind === "failed" ? mbt.mmmFailedWords() : mbt.mmmBlockedWords())];
  const spoken = new Set<string>();
  const unknown: string[] = [];
  for (const [file, source] of text) {
    for (const m of source.matchAll(re)) {
      spoken.add(m[1]);
      if (!table.includes(m[1])) unknown.push(`${file}: ${m[1]}`);
    }
  }

  test(`${kind}: 呼ぶ側の綴りは全部、表に在る`, () => {
    assert.deepEqual(unknown, [], `表に無い綴りを渡している。${TABLE} に足すか、綴りを揃える`);
  });

  // 名前に束ねた言葉は、**その名前がしらせとして渡されていれば**言っている。
  // 名前が在るだけでは足りない — 同じ名前は「押せない理由」としても使われる
  // （app/bar/files.mbt の Rename の行）ので、しらせの呼びの中に在ることを見る
  const says = (word: string) => {
    const by = named.get(word);
    return spoken.has(word) || (by !== undefined && calls.some((c) => c.includes(by)));
  };

  test(`${kind}: 表の言葉は全部、呼ぶ側が言う`, () => {
    const mute = table.filter((w) => !says(w));
    assert.deepEqual(mute, [], `誰も言わない。${TABLE} から消すか、言う側を足す`);
  });
}

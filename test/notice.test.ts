// しらせの言葉は表（app/parts/notice.mbt）に在るものだけを渡す — 外れていれば実行時に
// abort するが、それは押して初めて分かる。呼ぶ側の綴りを静的に表と突き合わせる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import * as mbt from "../_build/js/release/build/mmm/app/js/js.js";

// 言葉の形で向きが決まる（docs/spec.md「しらせ」）。`Couldn't …` は failed、
// 「次の一手はそちら」は blocked
const spoken = { failed: /"(Couldn't [^"]*)"/g, blocked: /"((?:Select a node|Nothing to export)[^"]*)"/g };

function* sources(dir: string): Generator<string> {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) yield* sources(p);
    else if (name.endsWith(".mbt") && !name.endsWith("_wbtest.mbt") && name !== "notice.mbt") yield p;
  }
}

for (const [kind, re] of Object.entries(spoken)) {
  const table = new Set<string>(kind === "failed" ? mbt.mmmFailedWords() : mbt.mmmBlockedWords());
  test(`${kind}: 呼ぶ側の綴りは全部、表に在る`, () => {
    const unknown: string[] = [];
    for (const file of sources("app")) {
      for (const m of fs.readFileSync(file, "utf8").matchAll(re)) {
        if (!table.has(m[1])) unknown.push(`${file}: ${m[1]}`);
      }
    }
    assert.deepEqual(unknown, []);
  });
}

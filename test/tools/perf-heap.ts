// フェーズ4 追加計測: 編集を続けたときのヒープと DOM ノード数。
// 注意: playwright は devDependencies に入れていない（計測時だけ使う）。
// 実行前に `pnpm dlx playwright install chromium` 相当の環境を用意すること。
// この 3 つの perf ツールは test/tsconfig.json の型チェック対象外。
// performance.memory は Chromium が量子化していて漏れ検出に使えないので、
// CDP の HeapProfiler.collectGarbage + Runtime.getHeapUsage で実測する。
// detached DOM は Memory.getDOMCounters で数える。
//
// 使い方: node test/tools/perf-heap.ts [fixture] [編集回数]

import { createRequire } from "node:module";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const PW_ROOT =
  process.env.PW_ROOT ??
  "C:/Users/taker/AppData/Local/Temp/claude/D--1-atrium-mmm/be9391a3-ddd1-4429-8419-aaa2b6756793/scratchpad";
const require = createRequire(join(PW_ROOT, "noop.js"));
const { chromium } = require("playwright");

const URL_BASE = process.env.MMM_URL ?? "http://localhost:13131";
const fixture = process.argv[2] ?? "baseline";
const ROUNDS = Number(process.argv[3] ?? 400);

const md =
  fixture === "baseline"
    ? readFileSync(join(process.cwd(), "mmm.md"), "utf8")
    : readFileSync(join(process.cwd(), "test", "fixtures", `${fixture}.md`), "utf8");

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
await ctx.addInitScript(`(() => {
  try {
    localStorage.setItem("mmm.text", ${JSON.stringify(md)});
    localStorage.setItem("mmm.savedText", ${JSON.stringify(md)});
    localStorage.setItem("mmm.fileName", ${JSON.stringify(fixture + ".md")});
  } catch (e) {}
  const o = Storage.prototype.setItem;
  Storage.prototype.setItem = function (k) {
    if (k === "mmm.text" || k === "mmm.savedText" || k === "mmm.fileName") return;
    return o.apply(this, arguments);
  };
})();`);
const page = await ctx.newPage();
const cdp = await ctx.newCDPSession(page);
await cdp.send("HeapProfiler.enable");
await cdp.send("Runtime.enable");

await page.goto(URL_BASE, { waitUntil: "load" });
await page.waitForSelector("#map-svg g.node");

async function sample(label) {
  await cdp.send("HeapProfiler.collectGarbage");
  await page.waitForTimeout(300);
  const usage = await cdp.send("Runtime.getHeapUsage");
  const counters = await cdp.send("Memory.getDOMCounters");
  const dom = await page.evaluate(() => ({
    all: document.getElementsByTagName("*").length,
    svg: document.getElementById("map-svg").getElementsByTagName("*").length,
    nodes: document.querySelectorAll("#map-svg g.node").length,
  }));
  return {
    label,
    heapUsedMB: +(usage.usedSize / 1048576).toFixed(2),
    heapTotalMB: +(usage.totalSize / 1048576).toFixed(2),
    // Memory.getDOMCounters はフラットな { documents, nodes, jsEventListeners }
    domCounters: counters,
    dom,
  };
}

const before = await sample("編集前");

// テキストペインで編集を繰り返す（1文字ごとに全再描画が走る経路）
const cm = page.locator("#md-pane .cm-content");
await cm.click();
await page.keyboard.press("Control+End");
const t0 = Date.now();
for (let i = 0; i < ROUNDS; i++) {
  await page.keyboard.type("x");
  if (i % 25 === 24) await page.keyboard.press("Control+z");
}
const editWallMs = Date.now() - t0;

const after = await sample(`${ROUNDS}回編集後`);

// さらにマップ側の操作（選択・パン・ズーム）を混ぜてもう一度
const map = page.locator("#map-pane");
const box = await map.boundingBox();
for (let i = 0; i < 60; i++) {
  await page.mouse.move(box.x + 100 + (i % 20) * 10, box.y + 100 + (i % 15) * 10);
  await page.mouse.wheel(0, i % 2 ? 120 : -120);
}
const after2 = await sample("マップ操作も追加後");

await browser.close();

const out = {
  fixture,
  rounds: ROUNDS,
  editWallMs,
  msPerEdit: +(editWallMs / ROUNDS).toFixed(1),
  samples: [before, after, after2],
  delta: {
    heapMB: +(after2.heapUsedMB - before.heapUsedMB).toFixed(2),
    domNodes: after2.domCounters.nodes - before.domCounters.nodes,
    listeners: after2.domCounters.js_event_listeners - before.domCounters.js_event_listeners,
  },
};
const path = join(process.cwd(), "docs", "audit", `perf-heap-${fixture}.json`);
writeFileSync(path, JSON.stringify(out, null, 2), "utf8");
console.log(JSON.stringify(out, null, 2));
console.log("\n書き出し:", path);

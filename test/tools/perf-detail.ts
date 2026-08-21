// フェーズ4 追加計測: 上位の遅い経路の内訳を取る。
// 注意: playwright は devDependencies に入れていない（計測時だけ使う）。
// 実行前に `pnpm dlx playwright install chromium` 相当の環境を用意すること。
// この 3 つの perf ツールは test/tsconfig.json の型チェック対象外。
//  (a) パン/ズームが本当に発火しているかの検証（発火していなければ
//      「フレーム落ちゼロ」という結論は無効なので、先にこれを確かめる）
//  (b) render() 単体のコスト（DOM 構築 vs レイアウト計算 vs コア呼び出し）
//  (c) rich.md が baseline より遅い理由（ノードあたり SVG 要素数）
//
// 使い方: node test/tools/perf-detail.ts [fixture...]

import { createRequire } from "node:module";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const PW_ROOT =
  process.env.PW_ROOT ??
  "C:/Users/taker/AppData/Local/Temp/claude/D--1-atrium-mmm/be9391a3-ddd1-4429-8419-aaa2b6756793/scratchpad";
const require = createRequire(join(PW_ROOT, "noop.js"));
const { chromium } = require("playwright");

const URL_BASE = process.env.MMM_URL ?? "http://localhost:13131";
const want = process.argv.slice(2).length ? process.argv.slice(2) : ["baseline", "rich", "wide", "mixed"];

const text = (n) =>
  n === "baseline"
    ? readFileSync(join(process.cwd(), "mmm.md"), "utf8")
    : readFileSync(join(process.cwd(), "test", "fixtures", `${n}.md`), "utf8");

const init = (md, name) => `(() => {
  try {
    localStorage.setItem("mmm.text", ${JSON.stringify(md)});
    localStorage.setItem("mmm.savedText", ${JSON.stringify(md)});
    localStorage.setItem("mmm.fileName", ${JSON.stringify(name)});
    localStorage.setItem("mmm.panes", "md,map");
  } catch (e) {}
  const o = Storage.prototype.setItem;
  Storage.prototype.setItem = function (k) {
    if (k === "mmm.text" || k === "mmm.savedText" || k === "mmm.fileName") return;
    return o.apply(this, arguments);
  };
})();`;

const pct = (a, p) => {
  if (!a.length) return null;
  const s = a.slice().sort((x, y) => x - y);
  return +s[Math.min(s.length - 1, Math.floor((s.length * p) / 100))].toFixed(2);
};

const browser = await chromium.launch();
const out = [];

for (const name of want) {
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
  await ctx.addInitScript(init(text(name), name + ".md"));
  const page = await ctx.newPage();
  await page.goto(URL_BASE, { waitUntil: "load" });
  await page.waitForSelector("#map-svg g.node");

  const map = page.locator("#map-pane");
  const box = await map.boundingBox();
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;

  // ---- (a) パン/ズームが実際に viewport を動かしているかを検証 ----
  const vpBefore = await page.evaluate(() => document.querySelector("#map-svg > g").getAttribute("transform"));
  await page.mouse.move(cx, cy);
  await page.mouse.down({ button: "middle" });
  await page.mouse.move(cx + 180, cy + 90);
  await page.mouse.move(cx + 260, cy + 140);
  await page.mouse.up({ button: "middle" });
  const vpAfterPan = await page.evaluate(() => document.querySelector("#map-svg > g").getAttribute("transform"));
  await page.mouse.move(cx, cy);
  await page.mouse.wheel(0, -240);
  await page.mouse.wheel(0, -240);
  const vpAfterZoom = await page.evaluate(() => document.querySelector("#map-svg > g").getAttribute("transform"));

  // ---- (b) 経路ごとの同期コスト内訳 ----
  // マップ側の構造コマンドは同期一直線なので、区間ごとに performance.now で挟める。
  const breakdown = await page.evaluate(() => {
    const pane = document.getElementById("map-pane");
    pane.focus();
    const nodes = () => document.querySelectorAll("#map-svg g.node").length;
    const svgEls = () => document.getElementById("map-svg").getElementsByTagName("*").length;

    // 何も変化しない undo（= 純粋な applySnap + render のコスト）
    const emptyUndo = [];
    for (let i = 0; i < 15; i++) {
      const t = performance.now();
      pane.dispatchEvent(new KeyboardEvent("keydown", { key: "u", bubbles: true, cancelable: true }));
      emptyUndo.push(performance.now() - t);
    }

    // 選択移動のみ（render を通らない経路: refreshSelection だけ）
    const firstNode = document.querySelectorAll("#map-svg g.node")[1];
    if (firstNode) {
      const r = firstNode.getBoundingClientRect();
      const o = { bubbles: true, cancelable: true, clientX: r.left + 5, clientY: r.top + 5, pointerId: 1, button: 0, isPrimary: true };
      firstNode.dispatchEvent(new PointerEvent("pointerdown", o));
      firstNode.dispatchEvent(new PointerEvent("pointerup", o));
    }
    const selMove = [];
    for (let i = 0; i < 15; i++) {
      const t = performance.now();
      pane.dispatchEvent(new KeyboardEvent("keydown", { key: "j", bubbles: true, cancelable: true }));
      selMove.push(performance.now() - t);
    }

    // 強制レイアウト込みのコスト（getBBox を1回呼んでレイアウトを流す）
    const t0 = performance.now();
    document.getElementById("map-svg").getBoundingClientRect();
    const forcedLayout = performance.now() - t0;

    return {
      nodes: nodes(),
      svgEls: svgEls(),
      svgElsPerNode: +(svgEls() / Math.max(1, nodes())).toFixed(2),
      emptyUndoMs: emptyUndo.map((v) => +v.toFixed(2)),
      selMoveMs: selMove.map((v) => +v.toFixed(2)),
      forcedLayoutMs: +forcedLayout.toFixed(2),
      textLen: (localStorage.getItem("mmm.text") || "").length,
    };
  });

  // ---- (c) 1文字入力の内訳を CDP のプロファイラで取る ----
  const cdp = await ctx.newCDPSession(page);
  await cdp.send("Profiler.enable");
  await cdp.send("Profiler.setSamplingInterval", { interval: 100 });
  await page.locator("#md-pane .cm-content").click();
  await page.keyboard.press("Control+End");
  await cdp.send("Profiler.start");
  for (let i = 0; i < 15; i++) {
    await page.keyboard.type("z");
    await page.waitForTimeout(20);
  }
  const { profile } = await cdp.send("Profiler.stop");

  // self-time を関数名ごとに集計
  const byId = new Map(profile.nodes.map((n) => [n.id, n]));
  const self = new Map();
  const total = profile.samples?.length ?? 0;
  const dt = profile.timeDeltas ?? [];
  for (let i = 0; i < (profile.samples?.length ?? 0); i++) {
    const n = byId.get(profile.samples[i]);
    if (!n) continue;
    const cf = n.callFrame;
    const key = `${cf.functionName || "(anonymous)"} @ ${(cf.url || "").split("/").pop()}:${cf.lineNumber + 1}`;
    self.set(key, (self.get(key) ?? 0) + (dt[i] ?? 0));
  }
  const topSelf = [...self.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 18)
    .map(([k, us]) => ({ fn: k, ms: +(us / 1000).toFixed(1) }));

  await ctx.close();

  out.push({
    fixture: name,
    panActuallyMoved: vpBefore !== vpAfterPan,
    zoomActuallyChanged: vpAfterPan !== vpAfterZoom,
    transforms: { before: vpBefore, afterPan: vpAfterPan, afterZoom: vpAfterZoom },
    ...breakdown,
    emptyUndo: { p50: pct(breakdown.emptyUndoMs, 50), p95: pct(breakdown.emptyUndoMs, 95) },
    selMove: { p50: pct(breakdown.selMoveMs, 50), p95: pct(breakdown.selMoveMs, 95) },
    profileTotalSamples: total,
    topSelfTimeMs: topSelf,
  });
  console.log(
    name,
    "| panMoved:", vpBefore !== vpAfterPan,
    "| zoomChanged:", vpAfterPan !== vpAfterZoom,
    "| emptyUndo p50:", pct(breakdown.emptyUndoMs, 50) + "ms",
    "| selMove p50:", pct(breakdown.selMoveMs, 50) + "ms",
    "| svgEls/node:", breakdown.svgElsPerNode,
  );
}

await browser.close();
writeFileSync(join(process.cwd(), "docs", "audit", "perf-detail.json"), JSON.stringify(out, null, 2), "utf8");
console.log("\n書き出し: docs/audit/perf-detail.json");

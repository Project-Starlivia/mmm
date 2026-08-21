// フェーズ4 計測ハーネス。既存ファイルには一切触れない。
// 注意: playwright は devDependencies に入れていない（計測時だけ使う）。
// 実行前に `pnpm dlx playwright install chromium` 相当の環境を用意すること。
// この 3 つの perf ツールは test/tsconfig.json の型チェック対象外。
//
// 前提: vite dev サーバが http://localhost:13131 で動いていること。
//       playwright はリポジトリ外(スクラッチ)に入れてあるので、
//       リポジトリの package.json / lockfile は汚さない。
//
// 使い方:
//   node test/tools/perf.ts                      # 全 fixture
//   node test/tools/perf.ts wide mixed           # 指定のみ
//   PW_ROOT=<playwrightのnode_modulesの親> node test/tools/perf.ts
//
// 出力: docs/audit/perf-raw.json （PERF.md はこの生データから書く）

import { createRequire } from "node:module";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const PW_ROOT =
  process.env.PW_ROOT ??
  "C:/Users/taker/AppData/Local/Temp/claude/D--1-atrium-mmm/be9391a3-ddd1-4429-8419-aaa2b6756793/scratchpad";
const require = createRequire(join(PW_ROOT, "noop.js"));
const { chromium } = require("playwright");

const URL_BASE = process.env.MMM_URL ?? "http://localhost:13131";
const FIXTURE_DIR = join(process.cwd(), "test", "fixtures");

const ALL = ["baseline", "rich", "deep", "wide", "mixed", "fat"];
const want = process.argv.slice(2).length ? process.argv.slice(2) : ALL;

/** baseline = リポジトリ同梱の mmm.md（実使用サイズの基準点） */
function fixtureText(name) {
  if (name === "baseline") return readFileSync(join(process.cwd(), "mmm.md"), "utf8");
  const p = join(FIXTURE_DIR, `${name}.md`);
  if (!existsSync(p)) throw new Error(`fixture がない: ${p}`);
  return readFileSync(p, "utf8");
}

const pct = (arr, p) => {
  if (!arr.length) return null;
  const s = arr.slice().sort((a, b) => a - b);
  return +s[Math.min(s.length - 1, Math.floor((s.length * p) / 100))].toFixed(2);
};
const stats = (arr) => ({
  n: arr.length,
  p50: pct(arr, 50),
  p95: pct(arr, 95),
  max: arr.length ? +Math.max(...arr).toFixed(2) : null,
});

/**
 * ページが起動する前に走らせる仕込み。
 *  - localStorage に fixture を入れる（アプリはここから復元する）
 *  - アプリ自身の persistNow が注入を上書きしないよう setItem を封じる
 *  - 起動前から計測フックを入れる（コールドブートを正しく測るため）
 */
function initScript(md, name) {
  return `(() => {
    try {
      localStorage.setItem("mmm.text", ${JSON.stringify(md)});
      localStorage.setItem("mmm.savedText", ${JSON.stringify(md)});
      localStorage.setItem("mmm.fileName", ${JSON.stringify(name + ".md")});
      localStorage.setItem("mmm.panes", "md,map");
      localStorage.removeItem("mmm.theme");
    } catch (e) {}
    const orig = Storage.prototype.setItem;
    Storage.prototype.setItem = function (k) {
      if (k === "mmm.text" || k === "mmm.savedText" || k === "mmm.fileName") return;
      return orig.apply(this, arguments);
    };
    window.__perf = {
      firstMapPaint: null, keyT0: null, latencies: [], mapMutationCount: 0,
    };
    // 地図の DOM が最初に埋まった時刻 + 打鍵で地図が実際に変化した回数。
    // 「地図の変化を待つ」方式で遅延を測ってはいけない: 差分レンダリング後は
    // 本文への 1 文字では地図が変化せず、サンプルが取れなくなる。
    // 遅延は keydown → 次フレームで測る（必ず発火し、体感と一致する）。
    const mo = new MutationObserver(() => {
      const svg = document.getElementById("map-svg");
      if (!svg) return;
      if (window.__perf.firstMapPaint === null && svg.querySelector("g.node")) {
        window.__perf.firstMapPaint = performance.now();
      }
      window.__perf.mapMutationCount++;
    });
    // module script は DOMContentLoaded より前に走り切るので、そこから
    // 観測を始めると初回描画を取りこぼす。document ごと最初から観測する。
    const startObserving = () => {
      try { mo.observe(document, { childList: true, subtree: true }); return true; }
      catch (e) { return false; }
    };
    if (!startObserving()) {
      document.addEventListener("readystatechange", startObserving, { once: true });
    }
    // 長タスク
    window.__perf.longtasks = [];
    try {
      new PerformanceObserver((l) => {
        for (const e of l.getEntries()) window.__perf.longtasks.push([Math.round(e.startTime), Math.round(e.duration)]);
      }).observe({ type: "longtask", buffered: true });
    } catch (e) {}
  })();`;
}

/** rAF のフレーム間隔を計測しながら fn を実行する */
const FRAME_PROBE = `(dur) => new Promise((res) => {
  const ts = [];
  let stop = false;
  const tick = (t) => { ts.push(t); if (!stop) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
  setTimeout(() => {
    stop = true;
    const d = [];
    for (let i = 1; i < ts.length; i++) d.push(+(ts[i] - ts[i - 1]).toFixed(2));
    res(d);
  }, dur);
})`;

async function measure(browser, name) {
  const md = fixtureText(name);
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
  await ctx.addInitScript(initScript(md, name));
  const page = await ctx.newPage();

  const consoleErrors = [];
  page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
  page.on("pageerror", (e) => consoleErrors.push("pageerror: " + String(e)));

  const t0 = Date.now();
  await page.goto(URL_BASE, { waitUntil: "load" });
  await page.waitForSelector("#map-svg g.node", { timeout: 120000 });
  const wallClockMs = Date.now() - t0;

  // ---- 初回表示 ----
  const boot = await page.evaluate(() => {
    const n = performance.getEntriesByType("navigation")[0];
    const paints = {};
    for (const p of performance.getEntriesByType("paint")) paints[p.name] = Math.round(p.startTime);
    return {
      firstMapPaint: window.__perf.firstMapPaint === null ? null : Math.round(window.__perf.firstMapPaint),
      paints,
      domInteractive: n ? Math.round(n.domInteractive) : null,
      domContentLoaded: n ? Math.round(n.domContentLoadedEventEnd) : null,
      loadEventEnd: n ? Math.round(n.loadEventEnd) : null,
      longtasks: window.__perf.longtasks.slice(0, 20),
      mapNodes: document.querySelectorAll("#map-svg g.node").length,
      svgElements: document.getElementById("map-svg").getElementsByTagName("*").length,
      domNodes: document.getElementsByTagName("*").length,
      heapMB: performance.memory ? +(performance.memory.usedJSHeapSize / 1048576).toFixed(1) : null,
    };
  });

  // ---- 1文字入力の 入力→反映 遅延 ----
  // CodeMirror ペインの末尾にカーソルを置き、実キー入力を送る。
  // t0 は keydown(capture)、t1 は #map-svg の MutationObserver 発火。
  await page.evaluate(() => {
    window.addEventListener(
      "keydown",
      () => {
        if (window.__perf.keyT0 !== null) return; // 前の測定が未了
        window.__perf.keyT0 = performance.now();
        window.__perf.mapMutated = false;
        requestAnimationFrame(() => {
          if (window.__perf.keyT0 === null) return;
          window.__perf.latencies.push(performance.now() - window.__perf.keyT0);
          window.__perf.keyT0 = null;
        });
      },
      true,
    );
    window.__perf.latencies.length = 0;
    window.__perf.mapMutationCount = 0;
  });
  const cm = page.locator("#md-pane .cm-content");
  await cm.click();
  await page.keyboard.press("Control+End");
  const typeCount = 40;
  for (let i = 0; i < typeCount; i++) {
    await page.keyboard.type("a");
    await page.waitForTimeout(30); // 連続入力がマージされないよう間隔を空ける
  }
  const latencies = await page.evaluate(() => window.__perf.latencies.map((v) => +v.toFixed(2)));
  const mapMutations = await page.evaluate(() => window.__perf.mapMutationCount);

  // ---- パン / ズームのフレーム時間 ----
  const map = page.locator("#map-pane");
  const box = await map.boundingBox();
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;

  const probe = (ms) => page.evaluate(`(${FRAME_PROBE})(${ms})`);

  const panFrames = await (async () => {
    const p = probe(1200);
    await page.mouse.move(cx, cy);
    await page.mouse.down({ button: "middle" });
    for (let i = 0; i < 40; i++) {
      await page.mouse.move(cx + Math.sin(i / 4) * 220, cy + Math.cos(i / 4) * 140);
      await page.waitForTimeout(16);
    }
    await page.mouse.up({ button: "middle" });
    return p;
  })();

  const zoomFrames = await (async () => {
    const p = probe(1200);
    await page.mouse.move(cx, cy);
    for (let i = 0; i < 30; i++) {
      await page.mouse.wheel(0, i % 2 === 0 ? -120 : 120);
      await page.waitForTimeout(16);
    }
    return p;
  })();

  // ---- Hide/Show（折りたたみ相当）のフレーム時間 ----
  // このアプリに折り畳みは無い。相当機能は H の Hide/Show なのでそれを測る。
  const hideFrames = await (async () => {
    await map.click({ position: { x: 30, y: 30 } });
    await page.evaluate(() => {
      const n = document.querySelectorAll("#map-svg g.node")[1];
      if (!n) return;
      const r = n.getBoundingClientRect();
      const o = { bubbles: true, cancelable: true, clientX: r.left + 5, clientY: r.top + 5, pointerId: 1, button: 0, isPrimary: true };
      n.dispatchEvent(new PointerEvent("pointerdown", o));
      n.dispatchEvent(new PointerEvent("pointerup", o));
    });
    const p = probe(900);
    for (let i = 0; i < 6; i++) {
      await page.keyboard.press("Shift+H");
      await page.waitForTimeout(120);
    }
    return p;
  })();

  // ---- 5分編集相当の負荷後のヒープと DOM ----
  // 実時間5分は待たず、編集回数で近似する（回数と手順を記録する）。
  const EDIT_ROUNDS = 150;
  await cm.click();
  await page.keyboard.press("Control+End");
  for (let i = 0; i < EDIT_ROUNDS; i++) {
    await page.keyboard.type("x");
    if (i % 10 === 9) await page.keyboard.press("Control+z");
  }
  const after = await page.evaluate(async () => {
    if (window.gc) window.gc();
    await new Promise((r) => setTimeout(r, 400));
    return {
      heapMB: performance.memory ? +(performance.memory.usedJSHeapSize / 1048576).toFixed(1) : null,
      domNodes: document.getElementsByTagName("*").length,
      svgElements: document.getElementById("map-svg").getElementsByTagName("*").length,
      mapNodes: document.querySelectorAll("#map-svg g.node").length,
      detachedHint: "detached ノード数は heap snapshot が要るのでここでは測れない",
    };
  });

  await ctx.close();

  const frameStats = (d) => ({ ...stats(d), over16ms: d.filter((x) => x > 16.7).length, over50ms: d.filter((x) => x > 50).length });

  return {
    fixture: name,
    inputChars: md.length,
    wallClockToFirstNodeMs: wallClockMs,
    boot,
    inputLatencyMs: { ...stats(latencies), samples: latencies.length, typed: typeCount },
    mapMutationsWhileTyping: mapMutations,
    panFrameMs: frameStats(panFrames),
    zoomFrameMs: frameStats(zoomFrames),
    hideShowFrameMs: frameStats(hideFrames),
    afterEditing: { rounds: EDIT_ROUNDS, ...after },
    consoleErrors: consoleErrors.slice(0, 20),
  };
}

const browser = await chromium.launch();
const results = [];
for (const name of want) {
  process.stdout.write(`計測中: ${name} ... `);
  try {
    const r = await measure(browser, name);
    results.push(r);
    console.log(
      `初回表示 ${r.boot.firstMapPaint}ms / 入力遅延 p50 ${r.inputLatencyMs.p50}ms p95 ${r.inputLatencyMs.p95}ms / ノード ${r.boot.mapNodes}`,
    );
  } catch (e) {
    console.log("失敗:", String(e).slice(0, 300));
    if (process.env.PERF_DEBUG) console.error(e);
    results.push({ fixture: name, error: String(e).slice(0, 500), stack: String(e.stack ?? "").slice(0, 1200) });
  }
}
await browser.close();

const out = {
  measuredAt: new Date().toISOString(),
  url: URL_BASE,
  note: "vite dev サーバ上での計測。production build ではない。",
  results,
};
writeFileSync(join(process.cwd(), "docs", "audit", "perf-raw.json"), JSON.stringify(out, null, 2), "utf8");
console.log("\n書き出し: docs/audit/perf-raw.json");

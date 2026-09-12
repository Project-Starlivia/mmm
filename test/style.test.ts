// 幅で変わる見た目。style.css と index.html を本物のまま読ませ、狭いときに
// 何が退いて何が残るかを固定する。**カスケードは happy-dom に解かせる** —
// 綴りを照合しても、後から書いた規則に負けたことは見えない。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { Window } from "happy-dom";

const css = fs.readFileSync("src/style.css", "utf8");
const bar = fs.readFileSync("index.html", "utf8").match(/<header id="bar">[\s\S]*?<\/header>/)![0];

/** 帯だけを立てて style.css を当てる。幅は viewport が持ち、メディアクエリがそれを見る */
function display(width: number): (id: string) => string {
  const win = new Window({ width, height: 812 });
  win.document.body.innerHTML = `<style>${css}</style>${bar}`;
  return (id) => win.getComputedStyle(win.document.getElementById(id)!).display;
}

// 未保存を言うものは `#dirty` と favicon の 2 つきり。タブの題は名前しか言わない
// ので、帯から印が退くと画面に 1 つも残らない（#310、docs/browsers.md）
test("狭いとき退くのは名前だけ — 未保存の印は残る", () => {
  const narrow = display(375);
  assert.equal(narrow("filename"), "none");
  assert.notEqual(narrow("dirty"), "none");

  const wide = display(1200);
  assert.notEqual(wide("filename"), "none");
  assert.notEqual(wide("dirty"), "none");
});

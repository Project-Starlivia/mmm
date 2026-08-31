// 性能の物差し。**追加の依存なしで、いつでも同じ数字が出る**ことを優先する。
//
//   node test/tools/perf.ts            # 合成した文書で規模ごとに測る
//   node test/tools/perf.ts fixtures   # test/fixtures/*.md でも測る
//
// 測るのはコアと、その上のカード抽出まで。ブラウザ側のフレーム時間は
// DOM が要るのでここでは測れない。
//
// ここに数字を書き込まない — 出すのは実行した結果だけ。

import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { core } from "../../src/coreApi.ts";
import { cardRows } from "../../src/map/cards.ts";

const REPO = dirname(dirname(dirname(fileURLToPath(import.meta.url))));

/** 何度か回して中央値を取る（1 回だけだと JIT の当たり外れで倍は動く） */
function median(runs: number, fn: () => void): number {
  const times: number[] = [];
  for (let i = 0; i < runs; i++) {
    const t = performance.now();
    fn();
    times.push(performance.now() - t);
  }
  times.sort((a, b) => a - b);
  return times[times.length >> 1];
}

const ms = (v: number): string => v.toFixed(2).padStart(8);

/** 兄弟だけを並べた文書。覆うノードが無いので、選択の正規化には最悪 */
const flat = (n: number): string =>
  Array.from({ length: n }, (_, i) => `## n${i}\n`).join("\n");

/** ルート 1 つに子がぶら下がる、ふつうの形 */
const tree = (n: number): string =>
  `# root\n\n${Array.from({ length: n }, (_, i) => `## n${i}\n`).join("\n")}`;

function measure(name: string, md: string): void {
  const initMs = median(5, () => core.initDoc(md));
  const snap = core.initDoc(md);
  const ids = snap.nodes.map((n) => n.id);
  const doc = { text: core.getText(), nodes: snap.nodes, fences: snap.fences };

  const typeMs = median(20, () => core.replaceText(0, 0, "x", "t"));
  core.initDoc(md);
  const cardsMs = median(5, () => cardRows(doc, new Set<number>()));
  const copyMs = median(5, () => core.selectionText(ids));
  const indentMs = median(3, () => {
    core.initDoc(md);
    core.indentNodes(ids);
  });

  console.log(
    `${name.padEnd(18)}${String(snap.nodes.length).padStart(6)}` +
      `${ms(initMs)}${ms(typeMs)}${ms(cardsMs)}${ms(copyMs)}${ms(indentMs)}`,
  );
}

console.log(
  "文書".padEnd(18) +
    "ノード".padStart(6) +
    "  init(ms)  1打鍵  カード  全コピー  全段下げ",
);

for (const n of [500, 1000, 2000, 4000, 8000]) {
  measure(`flat ${n}`, flat(n));
}
for (const n of [500, 2000, 8000]) {
  measure(`tree ${n}`, tree(n));
}

if (process.argv.includes("fixtures")) {
  const dir = join(REPO, "test", "fixtures");
  for (const name of readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    measure(name, readFileSync(join(dir, name), "utf8"));
  }
}

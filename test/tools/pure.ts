// core は DOM を知らない。純粋な module（core/）の package が browser の道具
// （mizchi/js・js_browser）や async を import していないことを確かめる。mizchi/markdown は md の読みで、純粋。
// check:core から呼ぶ。破れば止まる — 線は言葉でなく機械が見る。
//
// 実行: node test/tools/pure.ts

import { readdirSync, readFileSync, existsSync } from "node:fs";

const forbidden = /"(mizchi\/js|moonbitlang\/async)/;
const broken: string[] = [];
for (const name of readdirSync("core")) {
  const pkg = `core/${name}/moon.pkg`;
  if (existsSync(pkg) && forbidden.test(readFileSync(pkg, "utf8"))) broken.push(pkg);
}
if (broken.length > 0) {
  console.error(`core は DOM を知らない。browser の道具を import している:\n  ${broken.join("\n  ")}`);
  process.exit(1);
}

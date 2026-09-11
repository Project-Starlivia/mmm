// 大きさの見本の生成器。test/fixtures/*.md を作り直す（5 本とも上書きする）。
// 使い方: node test/tools/gen-load.ts [出力ディレクトリ]
// 既定の出力先は test/fixtures/ 。
//
// **記法の変化はここには無い。** それは core の見本（corpus_wbtest.mbt）が言う。
// ここが持つのは大きさだけ — 深さ・幅・ノード数・1 ノードの中身の大きさ（#88）。
//
// 生成するもの:
//   wide.md    直下 2000 ノード（幅広型）
//   deep.md    深さ 200（深型。6 段目から下は項目の入れ子）
//   mixed.md   5000 ノード（混合型）
//   fat.md     1 ノードに 10000 文字の添付コンテンツ
//   rich.md    コードブロックと表が多い文書

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const outDir = process.argv[2] ?? join(process.cwd(), "test", "fixtures");
mkdirSync(outDir, { recursive: true });

/** 決定論的な擬似乱数（毎回同じサンプルが出ないと計測が比較できない）。 */
function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const WORDS = [
  "設計", "実装", "検証", "リファクタ", "パーサ", "レイアウト", "ノード",
  "テキスト", "同期", "undo", "選択", "描画", "永続化", "フォーカス",
  "measure", "render", "layout", "commit", "snapshot", "offset",
];

function words(rand: () => number, n: number): string {
  const out: string[] = [];
  for (let i = 0; i < n; i++) out.push(WORDS[Math.floor(rand() * WORDS.length)]);
  return out.join(" ");
}

// ---- wide: root の直下に 2000 個 ----
{
  const rand = rng(1);
  const L = ["# wide", ""];
  for (let i = 0; i < 2000; i++) {
    L.push(`## ノード ${i} ${words(rand, 3)}`, "");
  }
  writeFileSync(join(outDir, "wide.md"), L.join("\n"), "utf8");
}

// ---- deep: 深さ 200 の一本鎖 ----
//
// **見出しでは深くならない。** 見出しは 6 段までで、7 本目以降の `#` は見出しでは
// なくただの段落（#91 / #19「見出しは 6 段、階層そのものは無限」）。`#` を増やして
// いた頃のこの見本は 200 段のつもりで **6 ノード**しか作っていなかった（#88）。
// 階層が無限なのは項目の側なので、6 段目から下は項目の入れ子で伸ばす。
{
  const rand = rng(2);
  const L = [];
  const heads = 6;
  for (let d = 1; d <= heads; d++) {
    L.push(`${"#".repeat(d)} 深さ ${d} ${words(rand, 2)}`, "");
  }
  for (let d = heads + 1; d <= 200; d++) {
    L.push(`${"  ".repeat(d - heads - 1)}- 深さ ${d} ${words(rand, 2)}`);
  }
  L.push("");
  writeFileSync(join(outDir, "deep.md"), L.join("\n"), "utf8");
}

// ---- mixed: 5000 ノード、分岐する木 + --- 区切り + 添付コンテンツ ----
{
  const rand = rng(3);
  const L = ["# mixed", ""];
  let made = 1;
  // 深さ 2..6 を行ったり来たりしながら 5000 に達するまで積む
  let depth = 2;
  while (made < 5000) {
    if (rand() < 0.18 && depth < 6) depth++;
    else if (rand() < 0.3 && depth > 2) depth--;
    if (depth === 2 && rand() < 0.02) L.push("---", "");
    L.push(`${"#".repeat(depth)} n${made} ${words(rand, 2)}`, "");
    if (rand() < 0.25) L.push(words(rand, 12), "");
    if (rand() < 0.05) L.push(`https://example.com/${made}`, "");
    made++;
  }
  writeFileSync(join(outDir, "mixed.md"), L.join("\n"), "utf8");
}

// ---- fat: 1 ノードの添付コンテンツが 10000 文字 ----
{
  const rand = rng(4);
  let body = "";
  while (body.length < 10000) body += words(rand, 20) + "\n";
  const L = [
    "# fat",
    "",
    "## 巨大な添付コンテンツを持つノード",
    "",
    body.slice(0, 10000),
    "",
    "## 隣のノード",
    "",
  ];
  writeFileSync(join(outDir, "fat.md"), L.join("\n"), "utf8");
}

// ---- rich: コードブロックと表が多い ----
{
  const rand = rng(5);
  const L = ["# rich", ""];
  for (let i = 0; i < 300; i++) {
    L.push(`## セクション ${i}`, "");
    L.push("```ts", `const v${i} = ${i};`, `function f${i}() {`,
      `  return v${i} * 2;`, "}", "```", "");
    L.push("| 列A | 列B | 列C |", "|---|---|---|");
    for (let r = 0; r < 6; r++) {
      L.push(`| ${words(rand, 1)} | ${r} | ${words(rand, 2)} |`);
    }
    L.push("");
    if (i % 10 === 9) L.push("---", "");
  }
  writeFileSync(join(outDir, "rich.md"), L.join("\n"), "utf8");
}


console.log("生成先:", outDir);
for (const f of ["wide.md", "deep.md", "mixed.md", "fat.md", "rich.md"]) {
  console.log(" -", f);
}

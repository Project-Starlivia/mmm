// 負荷サンプル生成器（フェーズ4の計測入力）。
// 使い方: node test/tools/gen-load.ts [出力ディレクトリ]
// 既定の出力先は test/fixtures/ 。既存ファイルには一切触れない。
//
// 生成するもの（監査指示のとおり）:
//   wide.md    直下 2000 ノード（幅広型）
//   deep.md    深さ 200（深型）
//   mixed.md   5000 ノード（混合型）
//   fat.md     1 ノードに 10000 文字の添付コンテンツ
//   rich.md    コードブロックと表が多い文書
// 加えて、パーサの境界を踏むための小さな種も出す:
//   gnarly.md  フェンス・区切り・コメント・CRLF などの境界が混ざったもの

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
{
  const rand = rng(2);
  const L = [];
  for (let d = 1; d <= 200; d++) {
    L.push(`${"#".repeat(d)} 深さ ${d} ${words(rand, 2)}`, "");
  }
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

// ---- gnarly: パーサ境界の詰め合わせ（計測ではなく往復テスト用の種） ----
{
  const parts = [
    "# gnarly",
    "",
    "## フェンスの中に見出しと区切り",
    "",
    "```md",
    "# これは見出しではない",
    "---",
    "<!--",
    "```",
    "",
    "## チルダのフェンス",
    "",
    "~~~",
    "## これも見出しではない",
    "~~~",
    "",
    "## 本文中の水平線",
    "",
    "text",
    "",
    "---",
    "",
    "more text",
    "",
    "## 深さが飛ぶ",
    "",
    "##### 3段飛ばし",
    "",
    "## 空ラベル",
    "",
    "##",
    "",
    "## 末尾空白付き   ",
    "",
    "## タブ区切り",
    "",
    "##\tタブのあと",
    "",
    "## setext 風",
    "",
    "見出しのようなもの",
    "===",
    "",
    "## HTML コメント",
    "",
    "<!--",
    "### 隠されたノード",
    "-->",
    "",
    "## 2 つ目のルート",
    "",
    "# もうひとつの #",
    "",
    "## 最後",
    "",
  ];
  writeFileSync(join(outDir, "gnarly.md"), parts.join("\n"), "utf8");
  // CRLF 版
  writeFileSync(join(outDir, "gnarly-crlf.md"), parts.join("\r\n"), "utf8");
}

console.log("生成先:", outDir);
for (const f of ["wide.md", "deep.md", "mixed.md", "fat.md", "rich.md", "gnarly.md", "gnarly-crlf.md"]) {
  console.log(" -", f);
}

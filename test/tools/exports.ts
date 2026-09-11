// `src/app.ts` は core の出口で、**面が 2 つある** — 本番（`src/` が呼ぶ）と、
// 試験と見本（`test/` と `lab/` だけが呼ぶ）。その線は節の見出しが引いていて、
// 「本番は 1 つも読まない」と書いてある（#252）。見出しは言葉なので、機械が見る。
//
// もう 1 つ見るのは `export` の印。**印は「外から呼ばれる」ことを意味する** —
// 呼ばれない印は余っていて、公開と内輪の線が印から見分けられなくなる（#78）。
//
// **見るのは import。** 呼んでいるかを字の全文検索で測ると、`Holder` の値 `"map"` が
// `map` を呼んでいることになり、`.map(` も当たる。名前が面を跨ぐ道は import 1 つ
// しかないので、そこだけを読む。
//
// check:core から呼ぶ。破れば止まる（pure.ts と同じ形）。
//
// 実行: node test/tools/exports.ts

import { existsSync, readFileSync, readdirSync } from "node:fs";

/** そのディレクトリの .ts。無いディレクトリは飛ばす */
function ts(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith(".ts"))
    .map((e) => `${dir}/${e.name}`);
}

/** その名前で終わる import 元か（`../src/app.ts` も `./app.ts` も同じ出口） */
const isFrom = (spec: string, file: string): boolean => spec.endsWith(`/${file}`) || spec === `./${file}`;

/**
 * そのファイルが `file` から名前で取り込んでいるもの、と名前空間の別名。
 * `import { a, b as c }` は a と b、`import * as ns` は ns
 */
function imported(source: string, file: string): { names: Set<string>; spaces: string[] } {
  const names = new Set<string>();
  const spaces: string[] = [];
  const named = /import\s+(?:type\s+)?\{([^}]*)\}\s*from\s*["']([^"']+)["']/g;
  for (const [, list, spec] of source.matchAll(named)) {
    if (!isFrom(spec, file)) continue;
    for (const part of list.split(",")) {
      const name = part.trim().replace(/^type\s+/, "").split(/\s+as\s+/)[0].trim();
      if (name !== "") names.add(name);
    }
  }
  const space = /import\s+(?:type\s+)?\*\s*as\s+(\w+)\s*from\s*["']([^"']+)["']/g;
  for (const [, alias, spec] of source.matchAll(space)) {
    if (isFrom(spec, file)) spaces.push(alias);
  }
  return { names, spaces };
}

const DECLARED = /^export (?:declare )?(?:const|let|function|class|interface|type|enum) (\w+)/gm;

const callers = [
  ...ts("src"),
  ...ts("test"),
  ...ts("test/tools"),
  ...ts("lab"),
  ...ts("lab/parts"),
  ...(existsSync("vite.config.ts") ? ["vite.config.ts"] : []),
];
const text = new Map(callers.map((p) => [p, readFileSync(p, "utf8")]));

/** `p` が `file` の `name` を呼んでいるか（名前で取り込む / 名前空間から辿る） */
function reaches(p: string, file: string, name: string): boolean {
  const source = text.get(p) ?? "";
  const { names, spaces } = imported(source, file);
  if (names.has(name)) return true;
  return spaces.some((ns) => new RegExp(`(?<![\\w$])${ns}\\.${name}(?![\\w$])`).test(source));
}

const broken: string[] = [];

// ---- 印は「外から呼ばれる」だけ（#78） ----
for (const path of ts("src")) {
  const file = path.slice(path.lastIndexOf("/") + 1);
  for (const [, name] of (text.get(path) ?? "").matchAll(DECLARED)) {
    const outside = callers.some((p) => p !== path && reaches(p, file, name));
    if (!outside) broken.push(`外から呼ばれない export: ${path}  ${name}（印を外すか、呼ぶ側を足す。#78）`);
  }
}

// ---- 試験と見本の面を、本番は 1 つも読まない（#252） ----
const FACE = "試験と見本の面";
const APP = "src/app.ts";
const lines = (text.get(APP) ?? "").split("\n");
// 節の見出しは `// ====` の罫線に挟まれた最後のもの（ファイルの頭でも同じ語が出る）
const heads = lines.map((l, i) => [l, i] as const).filter(([l]) => l.trim().startsWith("//") && l.includes(FACE));
if (heads.length === 0) {
  broken.push(`${APP} に「${FACE}」の節の見出しが無い。面の線はその見出しが引いている（#252）`);
} else {
  const face = lines.slice(heads[heads.length - 1][1]).join("\n");
  for (const [, name] of face.matchAll(DECLARED)) {
    for (const p of ts("src").filter((q) => q !== APP)) {
      if (reaches(p, "app.ts", name)) {
        broken.push(`本番が試験と見本の面を読んでいる: ${p} が ${name}（本番の面へ移すか、呼ぶのをやめる。#252）`);
      }
    }
  }
}

if (broken.length > 0) {
  console.error(`core の出口の線が破れている:\n  ${broken.join("\n  ")}`);
  process.exit(1);
}

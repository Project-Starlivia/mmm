// `export` の印は「外から呼ばれる」ことを意味する。定義したファイルの外から
// 一度も名前を呼ばれない `export` は、印だけが余っている状態で、**公開と内輪の線が
// 印から見分けられなくなる**（#78）。
//
// check:core から呼ぶ。破れば止まる — 線は言葉でなく機械が見る（pure.ts と同じ形）。
//
// 見るのは `src/*.ts` の宣言だけ。呼び手は `src` / `test` / `lab` / vite.config.ts の
// `.ts` 全部（試験と見本は「外」— そこだけが呼ぶ面をどう割るかは #252）。
//
// 実行: node test/tools/exports.ts

import { existsSync, readFileSync, readdirSync } from "node:fs";

/** その拡張子の .ts を集める。無いディレクトリは飛ばす */
function ts(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith(".ts"))
    .map((e) => `${dir}/${e.name}`);
}

const callers = [
  ...ts("src"),
  ...ts("test"),
  ...ts("test/tools"),
  ...ts("lab"),
  ...ts("lab/parts"),
  ...(existsSync("vite.config.ts") ? ["vite.config.ts"] : []),
];
const text = new Map(callers.map((p) => [p, readFileSync(p, "utf8")]));

const declared = /^export (?:declare )?(?:const|let|function|class|interface|type|enum) (\w+)/gm;
const spare: string[] = [];
for (const path of ts("src")) {
  const source = text.get(path) ?? "";
  for (const [, name] of source.matchAll(declared)) {
    const outside = callers.some((p) => p !== path && new RegExp(`\\b${name}\\b`).test(text.get(p) ?? ""));
    if (!outside) spare.push(`${path}  ${name}`);
  }
}

if (spare.length > 0) {
  console.error(
    `外から呼ばれない export がある。印を外すか、呼ぶ側を足す（#78）:\n  ${spare.join("\n  ")}`,
  );
  process.exit(1);
}

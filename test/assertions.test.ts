// **型アサーション**（`as T` と `!`）を置かない、という決めごとを守る仕掛け。
// テストの assert とは別の話。
//
// なぜ: `as` も `!` も「確かめずに名乗る」だけで、外れていても誰も気づけない。
// 実際、`<svg id="logo">` を `HTMLElement` と名乗り続けていた（SVG は HTML では
// ないので、これは型として嘘）。代わりに `instanceof` / 絞り込み / 既定値で
// **確かめる**。確かめれば、外れたときにその場で分かる。
//
// 例外を置きたくなったら ALLOWED に理由つきで足す。**この表そのものが、
// 「どこで型を信じているか」の一覧**になる（いまは空）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { REPO } from "./_helpers.ts";

/** 許した場所と、その理由。`"<パス>:<行の中身の一部>"` で書く */
const ALLOWED: { where: string; why: string }[] = [];

/** コメントと文字列を落とす。中に出てくる ` as ` を数えないため */
function code(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1")
    .replace(/`(?:[^`\\]|\\.)*`/g, "``")
    .replace(/"(?:[^"\\]|\\.)*"/g, '""')
    .replace(/'(?:[^'\\]|\\.)*'/g, "''");
}

/** `as T`（`as const` と `import * as x` は除く） */
const TYPE_ASSERTION = /(?<![.\w])\bas\s+(?!const\b)[A-Z_$]/;

/** `x!` の形（`!==` や先頭の `!` は除く） */
const NON_NULL = /[\w)\]"']!(?=[.,;)\]\s]|$)/;

function tsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...tsFiles(p));
    else if (e.name.endsWith(".ts")) out.push(p);
  }
  return out;
}

function offenders(pattern: RegExp): string[] {
  const found: string[] = [];
  for (const dir of ["src", "test"]) {
    for (const file of tsFiles(join(REPO, dir))) {
      const rel = file.replace(REPO, "").replace(/\\/g, "/").replace(/^\//, "");
      // この仕掛け自体は、禁じている形の見本を持っている
      if (rel === "test/assertions.test.ts") continue;
      code(readFileSync(file, "utf8"))
        .split("\n")
        .forEach((line, i) => {
          if (!pattern.test(line)) return;
          const trimmed = line.trim();
          if (ALLOWED.some((a) => a.where.startsWith(rel) && trimmed.includes(a.where.split(":").slice(1).join(":")))) {
            return;
          }
          found.push(`${rel}:${i + 1}  ${trimmed.slice(0, 90)}`);
        });
    }
  }
  return found;
}

test("型アサーション `as T` を置かない（instanceof や絞り込みで確かめる）", () => {
  assert.deepEqual(
    offenders(TYPE_ASSERTION),
    [],
    "確かめずに名乗っている。instanceof / 型ガード / 既定値のどれかに直すか、" +
      "どうしても要るなら test/assertions.test.ts の ALLOWED に理由を添えて足す",
  );
});

test("非 null 表明 `!` を置かない（無いときにどうするかを書く）", () => {
  assert.deepEqual(
    offenders(NON_NULL),
    [],
    "`!` は「無いはずがない」の言い張り。外れると遠くで undefined として落ちる。" +
      "早期 return / 既定値 / 覚えて返す形のどれかに直す",
  );
});

test("この仕掛け自体が効いている（嘘を混ぜたら気づく）", () => {
  // 検出そのものが壊れていれば上の 2 つは黙って通ってしまう
  assert.ok(TYPE_ASSERTION.test("const x = y as HTMLElement;"));
  assert.ok(TYPE_ASSERTION.test("return el as T;"));
  assert.ok(NON_NULL.test("const b = boxes.get(id)!;"));
  assert.ok(NON_NULL.test("place(root, 0, -subH.get(root.id)! / 2);"));
  // 通してよいもの
  assert.ok(!TYPE_ASSERTION.test('import * as mbt from "./x.ts";'));
  assert.ok(!TYPE_ASSERTION.test("const a = [1] as const;"));
  assert.ok(!TYPE_ASSERTION.test("] satisfies [string, number][]"));
  assert.ok(!NON_NULL.test("if (a !== b) return;"));
  assert.ok(!NON_NULL.test("if (!parent) continue;"));
  // コメントと文字列の中は数えない
  assert.ok(!TYPE_ASSERTION.test(code("// treats it as Element")));
  assert.ok(!TYPE_ASSERTION.test(code('const s = "as Element";')));
});

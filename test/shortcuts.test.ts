// キーの一覧（docs/shortcuts.md）と実装（src/app/shortcuts.ts）が
// 黙って食い違わないようにする仕掛け。
//
// なぜ: キーが README の節ごとに散っていた頃、`Mod+E` を足した変更
// （書き出しのショートカット）はどこにも書かれないまま入った。足した人にも
// 「どこに書き足すか」が決まらなかったため。一覧を 1 か所に集めても、
// **集めただけでは次の追加でまた同じことが起きる**ので、機械に見張らせる。
//
// 見張れるのは**全体キーだけ**（src/app/shortcuts.ts が持つもの）。マップ側の
// キーは src/mindmap.ts に散っていて、ここからは届かない。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { REPO } from "./_helpers.ts";

/** 一覧の中で、全体キーを並べている節の名前。ここを変えたらこの定数も変える */
const SECTION = "全体";

/** `key === "s"` / `e.key === "1"` のどちらも拾う */
const BOUND_KEY = /\bkey === "([^"]+)"/g;

/** `Mod+Shift+S` のような、修飾キーから始まる組み合わせ */
const COMBO = /^(?:Mod|Ctrl|Cmd|Alt|Shift)\+/;

/**
 * 実装が押さえているキー。`Mod+Shift+S` の `s` のように、**修飾を落とした
 * 素のキー**の集合にする — 実装は修飾を別々の枝で見る（`e.shiftKey`）ので、
 * 組み合わせの数と分岐の数は最初から一致しない。
 */
function boundKeys(src: string): Set<string> {
  return new Set([...src.matchAll(BOUND_KEY)].map((m) => m[1].toLowerCase()));
}

/** その節の中身だけを切り出す（次の `## ` まで） */
function section(md: string, name: string): string {
  const lines = md.split("\n");
  const start = lines.findIndex((l) => l.trim() === `## ${name}`);
  assert.ok(start !== -1, `docs/shortcuts.md に「## ${name}」の節が無い`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((l) => l.startsWith("## "));
  return (end === -1 ? rest : rest.slice(0, end)).join("\n");
}

/**
 * 一覧が載せているキー。`` `Mod+Shift+S` `` から `s` を取る。
 * 修飾を持たない `` `Mod` `` のような注記は、組み合わせではないので数えない。
 */
function listedKeys(md: string): Set<string> {
  const out = new Set<string>();
  for (const m of md.matchAll(/`([^`]+)`/g)) {
    const span = m[1].trim();
    if (!COMBO.test(span)) continue;
    const bare = span.slice(span.lastIndexOf("+") + 1).toLowerCase();
    if (bare !== "") out.add(bare);
  }
  return out;
}

const sorted = (s: Set<string>): string[] => [...s].sort();

test("全体キーの一覧と実装が食い違わない", () => {
  const src = readFileSync(join(REPO, "src/app/shortcuts.ts"), "utf8");
  const doc = readFileSync(join(REPO, "docs/shortcuts.md"), "utf8");
  assert.deepEqual(
    sorted(listedKeys(section(doc, SECTION))),
    sorted(boundKeys(src)),
    `docs/shortcuts.md の「${SECTION}」と src/app/shortcuts.ts がずれている。` +
      "キーを足したなら一覧にも足す。やめたなら一覧からも消す",
  );
});

test("この仕掛け自体が効いている（ずれを混ぜたら気づく）", () => {
  // 検出が壊れていれば上のテストは黙って通ってしまう
  assert.deepEqual(sorted(boundKeys('if (key === "s") {')), ["s"]);
  assert.deepEqual(sorted(boundKeys('if (e.key === "1") {')), ["1"]);
  assert.deepEqual(sorted(boundKeys('key === "Z"')), ["z"]); // 大小は揃える
  assert.deepEqual(sorted(boundKeys("const key = e.key;")), []);

  assert.deepEqual(sorted(listedKeys("| `Mod+Shift+S` | 別名で保存 |")), ["s"]);
  assert.deepEqual(sorted(listedKeys("`Mod+Alt+N` と `Alt+1`")), ["1", "n"]);
  assert.deepEqual(sorted(listedKeys("`Mod+/` … ペイン切り替え")), ["/"]);
  // 修飾から始まらないものは組み合わせではない（`Mod` そのものの注記など）
  assert.deepEqual(sorted(listedKeys("`Mod` は `Ctrl` / `Cmd` のこと")), []);
  assert.deepEqual(sorted(listedKeys("`Enter` で確定")), []);

  // 節の切り出しが、隣の節まで拾っていない
  const md = ["## 全体", "`Mod+S`", "", "## マップ", "`Mod+Q`"].join("\n");
  assert.deepEqual(sorted(listedKeys(section(md, "全体"))), ["s"]);
});

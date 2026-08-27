// テストの共通部品。既存ファイルは読むだけ。
//
// コアは src/coreApi.ts 経由で叩く。型と snap（JSON→オブジェクト）を
// アプリ本体と共有するので、テストだけが古い形を写経し続けることがない。
//
// 重要: MoonBit コアはモジュールグローバルな状態 (`st`) を1つ持つ。
// どのテストも必ず initDoc() から始めること。テストは同期で書く。

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

export const REPO = dirname(dirname(fileURLToPath(import.meta.url)));

const CORE_JS = join(REPO, "core/_build/js/release/build/js/js.js");
if (!existsSync(CORE_JS)) {
  throw new Error(
    `コアの JS 出力が無い: ${CORE_JS}\n先に \`pnpm run core\` を実行すること。`,
  );
}

export { core, type Snapshot, type NodeInfo } from "../src/coreApi.ts";
import { core, type DocView, type NodeInfo } from "../src/coreApi.ts";

export const initDoc = (md: string) => core.initDoc(md);
export const getText = () => core.getText();

/** initDoc して、いまの文書をテキスト・ノード・フェンスの組で返す。 */
export function loadDoc(md: string): DocView {
  const snap = core.initDoc(md);
  return {
    text: core.getText(),
    nodes: snap.nodes,
    fences: snap.fences,
    head: snap.head,
  };
}

/** ラベルからノードを引く。無ければ分かりやすく失敗させる。
 *  `find(...)!` で押し切ると、無かったときに関係ない場所で
 *  「undefined の何かを読めない」と落ちて原因が見えない。 */
export function nodeOf(nodes: NodeInfo[], label: string): NodeInfo {
  const n = nodes.find((x) => x.label === label);
  assert.ok(n, `ノード ${label} が無い`);
  return n;
}

/** ラベルから id を引く（テストの初期化直後に使う）。 */
export const idOf = (nodes: NodeInfo[], label: string): number =>
  nodeOf(nodes, label).id;

/** ランダム系テストのケース数。環境変数 MMM_FUZZ で上書き可能（デフォルトは各所で指定）。 */
export function fuzzCases(defaultCases: number): number {
  return Number(process.env.MMM_FUZZ ?? defaultCases);
}

/**
 * ノード配列の比較用正規化。
 * `withIds=false` のとき id を落とす（別セッションで振り直される想定の比較用）。
 */
export function normTree(nodes: NodeInfo[], withIds = true) {
  return nodes.map((n) => ({
    ...(withIds ? { id: n.id } : {}),
    depth: n.depth,
    parent: n.parent,
    from: n.from,
    headEnd: n.headEnd,
    to: n.to,
    hasContent: n.hasContent,
    hidden: n.hidden,
    label: n.label,
  }));
}

/** 親子関係を id ではなく「文書順の添字」で表した形（id 非依存の構造比較用） */
export function shape(nodes: NodeInfo[]) {
  const idx = new Map(nodes.map((n, i) => [n.id, i]));
  return nodes.map((n) => ({
    depth: n.depth,
    parentIdx: n.parent === -1 ? -1 : (idx.get(n.parent) ?? "??"),
    hidden: n.hidden,
    hasContent: n.hasContent,
    label: n.label,
  }));
}

/** 決定論的な擬似乱数 */
export function rng(seed: number): () => number {
  let s = (seed >>> 0) || 1;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

const LABELS = [
  "a", "b", "見出し", "with space", "  leading", "trailing  ",
  "記号 #!$%", "https://example.com/x", "[md](https://e.com)", "###",
  "very ".repeat(12) + "long", "タブ\tあり", "", "-", "--",
];

const CONTENT = [
  "本文テキスト",
  "https://example.com/link",
  "[タイトル](https://example.com/t)",
  "![](./img.webp)",
  "![alt](./sub/deep.png)",
  "| a | b |\n|---|---|\n| 1 | 2 |",
  "```ts\nconst x = 1;\n```",
  "```\n# fenced heading\n---\n```",
  "~~~\n## tilde fenced\n~~~",
  "<svg xmlns=\"http://www.w3.org/2000/svg\"><circle r=\"5\"/></svg>",
  "> 引用",
  "- リスト1\n- リスト2",
  "    インデントされた行",
  "<div>生 HTML</div>",
  "テキスト\n\n---\n\n続きのテキスト",
];

/**
 * ランダムな markdown 文書を生成する。パーサの境界を踏むことを狙う:
 * フェンス / 区切り / HTML コメント / 深さ飛び / 空ラベル / CRLF /
 * 末尾改行の有無 / ルート前ノード / 複数ルート。
 */
export function randomDoc(seed: number): string {
  const rand = rng(seed);
  const pick = <T,>(a: T[]): T => a[Math.floor(rand() * a.length)];
  const lines: string[] = [];
  const nl = rand() < 0.2 ? "\r\n" : "\n";

  // ルートより前のノード（別ツリー扱いになる経路）
  if (rand() < 0.15) {
    lines.push(`## ${pick(LABELS)}`, "");
  }
  if (rand() < 0.9) {
    lines.push(`# ${pick(LABELS)}`, "");
  }
  const n = 1 + Math.floor(rand() * 14);
  let depth = 2;
  for (let i = 0; i < n; i++) {
    if (rand() < 0.25 && depth < 7) depth++;
    else if (rand() < 0.3 && depth > 2) depth--;
    if (rand() < 0.12) lines.push("---", "");
    if (rand() < 0.06) lines.push("<!--", "");
    lines.push(`${"#".repeat(depth)} ${pick(LABELS)}`.trimEnd(), "");
    if (rand() < 0.45) lines.push(pick(CONTENT), "");
    if (rand() < 0.05) lines.push("-->", "");
    if (rand() < 0.04) lines.push(`# ${pick(LABELS)}`, ""); // 2つ目のルート
  }
  let out = lines.join(nl);
  if (rand() < 0.25) out = out.replace(/[\r\n]+$/, ""); // 末尾改行なし
  return out;
}

/** リポジトリ内の実物の .md を全部集める（fixtures と audit 配下も含む） */
export function corpus(): { path: string; md: string }[] {
  const files: string[] = [];
  const walk = (dir: string, depth = 0): void => {
    if (depth > 3) return;
    let ents;
    try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (
        e.name === "node_modules" ||
        e.name === "_build" ||
        e.name === ".git" ||
        e.name === "target" || // Rust のビルド出力 (src-tauri/target)
        e.name === ".worktrees" // CLAUDE.md の並行作業用ワークツリー置き場
      ) {
        continue;
      }
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p, depth + 1);
      else if (e.name.endsWith(".md")) files.push(p);
    }
  };
  walk(REPO);
  return files.map((p) => ({
    path: p.replace(REPO, "").replace(/\\/g, "/"),
    md: readFileSync(p, "utf8"),
  }));
}

/** catch した何かを、読める理由にする（`catch (e)` は unknown）。 */
export const reason = (e: unknown): string =>
  e instanceof Error ? e.message : String(e);

/** 入力の要点を短く出す（失敗時に何が原因か分かるように） */
export function brief(md: string, max = 220): string {
  const s = JSON.stringify(md);
  return s.length <= max ? s : s.slice(0, max) + `..." (全${md.length}文字)`;
}

/**
 * `layoutMap` を DOM 無しで動かすための最小の身代わり。
 *
 * 寸法は `map/metrics.ts` が canvas の `measureText` で実測するので、
 * ブラウザの外ではそこだけが動かない。**1 文字 = 7px の等幅**にしてしまえば
 * 配置の関係（左右・積み順・余白）はそのまま確かめられる。
 * 呼ぶのはテストの先頭で 1 度だけ。
 */
export function stubCanvas(): void {
  // `globalThis` は型上 DOM を持たないので、`as` で名乗らず Reflect 経由で
  // 出し入れする（無ければ素通しの `undefined`、あれば確かめずに信じない）。
  if (Reflect.has(globalThis, "document")) return;
  const ctx = {
    font: "",
    measureText: (s: string) => ({ width: s.length * 7 }),
  };
  Reflect.set(globalThis, "document", {
    createElement: () => ({ getContext: () => ctx }),
    documentElement: {},
  });
  Reflect.set(globalThis, "getComputedStyle", () => ({
    getPropertyValue: () => "",
  }));
}

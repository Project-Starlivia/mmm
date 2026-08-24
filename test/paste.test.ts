// 貼り付けたものを何として扱うか。純粋な判断だけを取り出してあるのに
// 試験が無かったので、5 つの分岐すべてを固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { initDoc } from "./_helpers.ts";
import { decidePaste } from "../src/app/paste.ts";

// コアはモジュールに 1 つの状態を持つ。どのテストも initDoc から始める
initDoc("");

const AT = { depth: 2 }; // 選んでいるノード（深さ 2）

test("空 / 空白だけなら何もしない", () => {
  assert.deepEqual(decidePaste("", AT, true), { kind: "noop" });
  assert.deepEqual(decidePaste("  \n\t\n", AT, true), { kind: "noop" });
});

test("URL 単体は、そのノードの内容（リンクカード）になる", () => {
  assert.deepEqual(decidePaste("https://example.com/x", AT, true), {
    kind: "link",
    url: "https://example.com/x",
  });
  // 前後の空白は落とす
  assert.deepEqual(decidePaste("\n https://e.com \n", AT, true), {
    kind: "link",
    url: "https://e.com",
  });
});

test("URL でも、選んでいるノードが無ければリンクにしない", () => {
  // 付ける先が無いため。空の文書ならルートとして立つ
  const action = decidePaste("https://example.com", null, false);
  assert.equal(action.kind, "rootTree");
});

test("見出しの無いテキストは、行ごとに子ノードになる", () => {
  const action = decidePaste("一行目\n\n二行目\n三行目", AT, true);
  assert.equal(action.kind, "children");
  assert.equal(
    action.kind === "children" ? action.body : "",
    "### 一行目\n\n### 二行目\n\n### 三行目",
  );
});

test("空の文書へ見出し無しを貼ると、先頭行がルートになる", () => {
  const action = decidePaste("題\n中身1\n中身2", null, false);
  assert.equal(action.kind, "rootTree");
  assert.equal(
    action.kind === "rootTree" ? action.body : "",
    "# 題\n\n## 中身1\n\n## 中身2",
  );
});

test("見出しつきは深さを読み替えて、そのまま子ツリーになる", () => {
  const action = decidePaste("## a\n\n### b\n", AT, true);
  assert.equal(action.kind, "block");
  assert.equal(action.kind === "block" ? action.body : "", "### a\n\n#### b");
});

test("見出しつきでも、選んでいるノードが無い文書へは貼らない", () => {
  // どこに付いたか分からない貼り方はしない
  assert.deepEqual(decidePaste("## a\n", null, true), { kind: "noop" });
  // ただし空の文書なら、そのまま入れる
  const action = decidePaste("## a\n", null, false);
  assert.equal(action.kind, "block");
  assert.equal(action.kind === "block" ? action.body : "", "## a");
});

test("フェンスの中の # は見出しとして数えない", () => {
  // 数えていたら「見出しつき」として深さを読み替えてしまう
  const action = decidePaste("```\n# にせ\n```", AT, true);
  assert.equal(action.kind, "children");
});

test("改行は CRLF も単独 CR も LF に揃える", () => {
  const action = decidePaste("a\r\nb\rc", AT, true);
  assert.equal(
    action.kind === "children" ? action.body : "",
    "### a\n\n### b\n\n### c",
  );
});

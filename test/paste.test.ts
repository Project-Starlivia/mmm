// decidePaste の分岐。骨格の判定（hasSkeleton）は core の持ち物なので、
// ここでは手で書いた小さな判定を渡す（`main.ts` では core.survey を通す）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { decidePaste } from "../src/app/paste.ts";

/** 試験用の骨格判定。見出しか項目の行があれば骨格ありとする */
const hasSkeleton = (md: string): boolean => /^(#|- )/m.test(md);

test("decidePaste: 空 → noop", () => {
  assert.deepEqual(decidePaste("", hasSkeleton), { kind: "noop" });
  assert.deepEqual(decidePaste("   \n  \n", hasSkeleton), { kind: "noop" });
});

test("decidePaste: 1 行で URL のみ → link", () => {
  assert.deepEqual(decidePaste("https://example.com/a", hasSkeleton), {
    kind: "link",
    url: "https://example.com/a",
  });
  // 前後の空白は落とす
  assert.deepEqual(decidePaste("  http://a.example  ", hasSkeleton), {
    kind: "link",
    url: "http://a.example",
  });
});

test("decidePaste: URL でも複数行なら link にしない", () => {
  const out = decidePaste("https://example.com/a\nhttps://example.com/b", hasSkeleton);
  assert.equal(out.kind, "labels");
});

test("decidePaste: 骨格の無い字は、空でない行ごとに labels", () => {
  assert.deepEqual(decidePaste("a\n\nb\n  c  \n", hasSkeleton), {
    kind: "labels",
    labels: ["a", "b", "c"],
  });
});

test("decidePaste: 骨格のある md はそのまま", () => {
  assert.deepEqual(decidePaste("# a\n\n- b\n", hasSkeleton), { kind: "md", md: "# a\n\n- b" });
});

test("decidePaste: CRLF は LF に正規化してから判定する", () => {
  assert.deepEqual(decidePaste("a\r\nb\r\n", hasSkeleton), { kind: "labels", labels: ["a", "b"] });
  assert.deepEqual(decidePaste("# a\r\n\r\n- b\r\n", hasSkeleton), { kind: "md", md: "# a\n\n- b" });
});

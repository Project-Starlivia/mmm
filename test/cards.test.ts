// Block → カード行の分類。何をカードにし、何を落とすか。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import type * as core from "../src/coreApi.ts";
import { bare, cardRows } from "../src/map/cards.ts";

/** id は分類に関係ないので、ここでは 1 で揃える */
const block = (content: core.Content): core.Block => ({ id: 1, content });

test("Block の種類がカードの種類になる。並びは Block のまま", () => {
  const rows = cardRows([
    block({ kind: "image", alt: "", src: "./p.png", title: "" }),
    block({ kind: "thematicBreak" }),
    block({ kind: "link", text: "t", href: "https://x.example/a", title: "" }),
    block({ kind: "code", info: "js", text: "1\n" }),
    block({ kind: "details", text: "<details>x</details>", open: false, summary: null, body: "x" }),
    block({ kind: "svg", markup: "<svg/>" }),
  ]);
  assert.deepEqual(rows, [
    { kind: "image", path: "p.png", name: "p.png" },
    { kind: "break" },
    { kind: "link", title: "t", url: "https://x.example/a" },
    { kind: "code", lang: "js", lines: ["1"] },
    { kind: "details", open: false, summary: null, lines: ["x"] },
    { kind: "svg", markup: "<svg/>" },
  ]);
});

test("details は open と summary をそのまま持ち、中身はコードと同じ割り方", () => {
  const d = (open: boolean, summary: string | null, body: string) =>
    cardRows([block({ kind: "details", text: "", open, summary, body })]);
  assert.deepEqual(d(true, "s", "a\n\nb\n"), [
    { kind: "details", open: true, summary: "s", lines: ["a", "", "b"] },
  ]);
  assert.deepEqual(d(false, null, ""), [{ kind: "details", open: false, summary: null, lines: [""] }]);
  assert.deepEqual(d(false, null, "1\n2\n3\n4\n5\n6\n7"), [
    { kind: "details", open: false, summary: null, lines: ["1", "2", "3", "4", "5", "…"] },
  ]);
});

test("リンクは http(s) だけ。題が無ければホスト名", () => {
  assert.deepEqual(
    cardRows([block({ kind: "link", text: "", href: "https://x.example/a", title: "" })]),
    [{ kind: "link", title: "x.example", url: "https://x.example/a" }],
  );
  assert.deepEqual(cardRows([block({ kind: "link", text: "m", href: "mailto:a@b", title: "" })]), []);
});

test("画像は相対パスだけ。./ は剥がし、名前は最後の要素", () => {
  assert.deepEqual(cardRows([block({ kind: "image", alt: "", src: "../pics/y.png", title: "" })]), [
    { kind: "image", path: "../pics/y.png", name: "y.png" },
  ]);
  assert.deepEqual(cardRows([block({ kind: "image", alt: "", src: "C:\\pics\\z.png", title: "" })]), [
    { kind: "image", path: "C:\\pics\\z.png", name: "z.png" },
  ]);
  assert.deepEqual(cardRows([block({ kind: "image", alt: "", src: "https://x/a.png", title: "" })]), []);
  assert.deepEqual(
    cardRows([block({ kind: "image", alt: "", src: "data:image/png;base64,AA", title: "" })]),
    [],
  );
});

test("コードは 6 行まで。末尾の改行は行にならず、空なら 1 行", () => {
  const seven = cardRows([block({ kind: "code", info: "", text: "1\n2\n3\n4\n5\n6\n7\n" })]);
  assert.deepEqual(seven, [{ kind: "code", lang: "", lines: ["1", "2", "3", "4", "5", "…"] }]);
  assert.deepEqual(cardRows([block({ kind: "code", info: "", text: "" })]), [
    { kind: "code", lang: "", lines: [""] },
  ]);
  assert.deepEqual(cardRows([block({ kind: "code", info: "", text: "\ta\n" })]), [
    { kind: "code", lang: "", lines: ["  a"] },
  ]);
});

test("bare は先頭の ./ だけを落とす", () => {
  assert.equal(bare("./x/y"), "x/y");
  assert.equal(bare("../x"), "../x");
});

// Block → カード行の分類。何をカードにし、何を落とすか。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { bare, cardRows } from "../src/map/cards.ts";

test("Block の種類がカードの種類になり、水平線と Details は落ちる", () => {
  const rows = cardRows([
    { kind: "image", alt: "", src: "./p.png", title: "" },
    { kind: "thematicBreak" },
    { kind: "link", text: "t", href: "https://x.example/a", title: "" },
    { kind: "code", info: "js", text: "1\n" },
    { kind: "details", id: 3, text: "<details>x</details>" },
    { kind: "svg", markup: "<svg/>" },
  ]);
  assert.deepEqual(rows, [
    { kind: "img", path: "p.png", name: "p.png" },
    { kind: "link", title: "t", url: "https://x.example/a" },
    { kind: "code", lang: "js", lines: ["1"] },
    { kind: "svg", markup: "<svg/>" },
  ]);
});

test("リンクは http(s) だけ。題が無ければホスト名", () => {
  assert.deepEqual(
    cardRows([{ kind: "link", text: "", href: "https://x.example/a", title: "" }]),
    [{ kind: "link", title: "x.example", url: "https://x.example/a" }],
  );
  assert.deepEqual(cardRows([{ kind: "link", text: "m", href: "mailto:a@b", title: "" }]), []);
});

test("画像は相対パスだけ。./ は剥がし、名前は最後の要素", () => {
  assert.deepEqual(cardRows([{ kind: "image", alt: "", src: "../pics/y.png", title: "" }]), [
    { kind: "img", path: "../pics/y.png", name: "y.png" },
  ]);
  assert.deepEqual(cardRows([{ kind: "image", alt: "", src: "C:\\pics\\z.png", title: "" }]), [
    { kind: "img", path: "C:\\pics\\z.png", name: "z.png" },
  ]);
  assert.deepEqual(cardRows([{ kind: "image", alt: "", src: "https://x/a.png", title: "" }]), []);
  assert.deepEqual(
    cardRows([{ kind: "image", alt: "", src: "data:image/png;base64,AA", title: "" }]),
    [],
  );
});

test("コードは 6 行まで。末尾の改行は行にならず、空なら 1 行", () => {
  const seven = cardRows([{ kind: "code", info: "", text: "1\n2\n3\n4\n5\n6\n7\n" }]);
  assert.deepEqual(seven, [{ kind: "code", lang: "", lines: ["1", "2", "3", "4", "5", "…"] }]);
  assert.deepEqual(cardRows([{ kind: "code", info: "", text: "" }]), [
    { kind: "code", lang: "", lines: [""] },
  ]);
  assert.deepEqual(cardRows([{ kind: "code", info: "", text: "\ta\n" }]), [
    { kind: "code", lang: "", lines: ["  a"] },
  ]);
});

test("bare は先頭の ./ だけを落とす", () => {
  assert.equal(bare("./x/y"), "x/y");
  assert.equal(bare("../x"), "../x");
});

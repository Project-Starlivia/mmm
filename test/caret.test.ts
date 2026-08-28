// md のカーソル・選択が、どのノードに掛かっているか。
//
// 規則は 1 つ「区間が重なっていれば挙げる、端は両側とも閉じて見る」。
// ノードの区間は子孫を含むので、点 1 つでもその枝の道筋が揃って挙がる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type NodeInfo, loadDoc, randomDoc, brief } from "./_helpers.ts";
import { type Span, caretNodes } from "../src/caret.ts";

/** 総当たりの答え（同じ規則を、素直に書き下したもの）。 */
function naive(nodes: NodeInfo[], spans: Span[]): number[] {
  return nodes
    .filter((n) => spans.some((s) => n.from <= s.to && n.to >= s.from))
    .map((n) => n.id);
}

/** 点 1 つ。 */
const at = (pos: number): Span[] => [{ from: pos, to: pos }];

const labelsAt = (md: string, spans: (text: string) => Span[]): string[] => {
  const { text, nodes } = loadDoc(md);
  const ids = new Set(caretNodes(nodes, spans(text)));
  return nodes.filter((n) => ids.has(n.id)).map((n) => n.label);
};

const MD = `# 根

## 枝 A

本文の行

### A の子

## 枝 B
`;

test("点 1 つでも、その枝の道筋がまとめて挙がる", () => {
  assert.deepEqual(
    labelsAt(MD, (t) => at(t.indexOf("A の子"))),
    ["根", "枝 A", "A の子"],
  );
});

test("本文の行は、その本文を持つノードまで（子は含まない）", () => {
  assert.deepEqual(
    labelsAt(MD, (t) => at(t.indexOf("本文の行"))),
    ["根", "枝 A"],
  );
});

test("兄弟をまたぐ範囲は、両方とその中身まで挙がる", () => {
  assert.deepEqual(
    labelsAt(MD, (t) => [{ from: t.indexOf("## 枝 A"), to: t.indexOf("## 枝 B") }]),
    ["根", "枝 A", "A の子", "枝 B"],
  );
});

test("離れた複数カーソルは、それぞれの分を合わせたものになる", () => {
  assert.deepEqual(
    labelsAt(MD, (t) => [...at(t.indexOf("A の子")), ...at(t.indexOf("## 枝 B"))]),
    ["根", "枝 A", "A の子", "枝 B"],
  );
});

test("文書の末尾でも、掛かっているものが挙がり続ける", () => {
  // ここが半開のままだと、全部の区間が閉じきっていて何も挙がらない。
  // 追記しているあいだじゅう印が出ない、といういちばん困る形になる
  assert.deepEqual(
    labelsAt(MD, (t) => at(t.length)),
    ["根", "枝 B"],
  );
  // 末尾に改行が無い文書でも同じ
  assert.deepEqual(
    labelsAt("# 根\n\n## 枝", (t) => at(t.length)),
    ["根", "枝"],
  );
});

test("どのノードにも掛からない位置では空", () => {
  // 文書の頭（frontmatter）は走査されない = そこにノードは無い
  assert.deepEqual(
    labelsAt("---\ntitle: x\n---\n\n# 根\n", (t) => at(t.indexOf("title"))),
    [],
  );
  // 最初の見出しより前の散文も、どのノードでもない
  assert.deepEqual(labelsAt("ただの文\n\n# 根\n", (t) => at(0)), []);
});

test("範囲が 1 つも無ければ（md にカーソルが無い）空", () => {
  const { nodes } = loadDoc(MD);
  assert.deepEqual(caretNodes(nodes, []), []);
});

test("返す並びは常に文書順（範囲をどの順で渡しても）", () => {
  const { text, nodes } = loadDoc(MD);
  const forward = caretNodes(nodes, [...at(text.indexOf("# 根")), ...at(text.indexOf("## 枝 B"))]);
  const backward = caretNodes(nodes, [...at(text.indexOf("## 枝 B")), ...at(text.indexOf("# 根"))]);
  assert.deepEqual(forward, backward);
  assert.deepEqual(
    forward,
    nodes.filter((n) => forward.includes(n.id)).map((n) => n.id),
  );
});

test("どんな文書のどの位置・どの範囲でも、総当たりと同じ答えになる", () => {
  for (let seed = 1; seed <= 30; seed++) {
    const md = randomDoc(seed);
    const { text, nodes } = loadDoc(md);
    for (let a = 0; a <= text.length; a += 3) {
      for (const b of [a, Math.min(a + 40, text.length), text.length]) {
        const spans = [{ from: a, to: b }];
        assert.deepEqual(
          caretNodes(nodes, spans),
          naive(nodes, spans),
          `seed ${seed} の [${a}, ${b}]: ${brief(md)}`,
        );
      }
    }
  }
});

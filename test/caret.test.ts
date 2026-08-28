// md のカーソルが居るノード。
//
// ノードは [from, to) の区間で、入れ子はそのまま区間の入れ子になる。だから
// 「その位置を含む、いちばん内側のノード」はいつも 1 つに決まる — それを
// 二分探索 + 遡りで当てているのが caretNode。ここではその答えが、素朴な
// 総当たり（含むもののうち from がいちばん大きいもの）と常に一致することを
// 固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type NodeInfo, idOf, loadDoc, randomDoc, brief } from "./_helpers.ts";
import { caretNode } from "../src/caret.ts";

/** 総当たりの答え。含むノードのうち、いちばん後ろから始まるものが最も内側。
 *  閉じ際（`offset === to`）も中と見なす — 文書の末尾で何も指せなくなるため */
function naive(nodes: NodeInfo[], offset: number): number {
  let id = -1;
  let from = -1;
  for (const n of nodes) {
    if (n.from <= offset && offset <= n.to && n.from > from) {
      id = n.id;
      from = n.from;
    }
  }
  return id;
}

const MD = `# 根

## 枝 A

本文の行

### A の子

## 枝 B
`;

test("見出し行に居れば、そのノード", () => {
  const { text, nodes } = loadDoc(MD);
  assert.equal(caretNode(nodes, text.indexOf("## 枝 A")), idOf(nodes, "枝 A"));
  assert.equal(caretNode(nodes, text.indexOf("枝 A")), idOf(nodes, "枝 A"));
});

test("本文に居れば、その本文を持つノード（親ではない）", () => {
  const { text, nodes } = loadDoc(MD);
  assert.equal(caretNode(nodes, text.indexOf("本文の行")), idOf(nodes, "枝 A"));
});

test("子の中に居れば、いちばん内側のノードを返す", () => {
  const { text, nodes } = loadDoc(MD);
  assert.equal(caretNode(nodes, text.indexOf("A の子")), idOf(nodes, "A の子"));
});

test("区間の端 — from ちょうどは自分、兄弟の継ぎ目は後から始まったほう", () => {
  const { nodes } = loadDoc(MD);
  const a = nodes.find((n) => n.label === "枝 A");
  assert.ok(a);
  assert.equal(caretNode(nodes, a.from), a.id);
  // A の閉じ際は B の始まりでもある。並んだら後から始まったほうが勝つ
  assert.equal(caretNode(nodes, a.to), idOf(nodes, "枝 B"));
});

test("文書の末尾でも、最後の枝を指し続ける", () => {
  // ここが半開のままだと、全部の区間が閉じきっていて何も指せない。
  // 追記しているあいだじゅう印が出ない、といういちばん困る形になる
  const { text, nodes } = loadDoc(MD);
  assert.equal(caretNode(nodes, text.length), idOf(nodes, "枝 B"));

  // 末尾に改行が無い文書でも同じ
  const bare = loadDoc("# 根\n\n## 枝");
  assert.equal(caretNode(bare.nodes, bare.text.length), idOf(bare.nodes, "枝"));
});

test("どのノードにも属さない位置では -1", () => {
  // 文書の頭（frontmatter）は走査されない = そこにノードは無い
  const head = loadDoc("---\ntitle: x\n---\n\n# 根\n");
  assert.equal(caretNode(head.nodes, head.text.indexOf("title")), -1);

  // 最初の見出しより前の散文も、どのノードでもない
  const pre = loadDoc("ただの文\n\n# 根\n");
  assert.equal(caretNode(pre.nodes, pre.text.indexOf("ただの文")), -1);
});

test("区切り行では、直前に閉じた枝を指す", () => {
  const { text, nodes } = loadDoc("# 根\n\n## A\n\n---\n\n## B\n");
  // `---` はどの枝の範囲にも入らない（コピーや移動に付いてこない）。
  // それでもそこは A の閉じ際なので、文書の末尾と同じ読み方で A になる
  assert.equal(caretNode(nodes, text.indexOf("---")), idOf(nodes, "A"));
});

test("ノードの無い文書では、どこでも -1", () => {
  const { text, nodes } = loadDoc("ただの文\n");
  assert.equal(nodes.length, 0);
  assert.equal(caretNode(nodes, 0), -1);
  assert.equal(caretNode(nodes, text.length), -1);
});

test("どんな文書のどの位置でも、総当たりと同じ答えになる", () => {
  for (let seed = 1; seed <= 40; seed++) {
    const md = randomDoc(seed);
    const { text, nodes } = loadDoc(md);
    for (let at = 0; at <= text.length; at++) {
      assert.equal(
        caretNode(nodes, at),
        naive(nodes, at),
        `seed ${seed} の ${at} 文字目: ${brief(md)}`,
      );
    }
  }
});

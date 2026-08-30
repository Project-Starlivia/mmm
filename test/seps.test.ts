// 区切りを書いた文書が、**外の Markdown パーサでも同じ木に読める**こと。
//
// リストの形では、区切りを列 0 に書くと外の CommonMark パーサはそこで
// 外側のリストを閉じ、続く項目が別の木になる。字下げの規則（core が持つ）が
// 効いていることを、実物のパーサに読ませて確かめる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { parser } from "@lezer/markdown";
import { core, initDoc, getText, idOf } from "./_helpers.ts";

/** その md を CommonMark として読み、リスト項目のラベルを入れ子の深さつきで返す */
function itemsOf(md: string): { depth: number; text: string }[] {
  const tree = parser.parse(md);
  const out: { depth: number; text: string }[] = [];
  let depth = 0;
  tree.iterate({
    enter: (n) => {
      if (n.name === "BulletList") depth++;
      if (n.name === "ListItem") {
        const line = md.slice(n.from, n.to).split("\n")[0];
        out.push({ depth, text: line.replace(/^\s*[-*+]\s*/, "").trim() });
      }
    },
    leave: (n) => {
      if (n.name === "BulletList") depth--;
    },
  });
  return out;
}

test("リストの形へ切り替えても、境界のある文書の木は変わらない", () => {
  // 区切り行は**どのノードの中身でもない**。owner（直前のノード）の中身と
  // して字下げしていたころは、深い枝の下の `---` がその枝の中身の列まで
  // 押し込まれ、1 つの境界の 2 行のあいだに空行まで入っていた。
  const md =
    "# r\n\n## b\n\n### a\n\n#### e\n\n#### f\n\n##### d\n\n---\n---\n\n## c\n";
  initDoc(md);
  core.setListFrom(1);
  core.reformat("");
  const list = getText();
  // 区切りは根の中身の列（2 桁）に揃い、1 つの境界の中に空行は入らない
  assert.ok(
    list.includes("\n  ---\n  ---\n"),
    `区切りの列か詰め方が違う:\n${list}`,
  );
  // 外のパーサから見て、リストは区切りで閉じない（項目が全部 1 つの木）
  const items = itemsOf(list);
  assert.deepEqual(
    items.map((i) => i.text),
    ["r", "b", "a", "e", "f", "d", "c"],
    `外のパーサで木が割れている:\n${list}`,
  );
  // 見出しの形へ戻すと、バイト単位で元へ戻る
  initDoc(list);
  core.setListFrom(0);
  core.reformat("");
  assert.equal(getText(), md);
});

test("リストの形で境界を書いても、外のパーサの木は変わらない", () => {
  const snap = initDoc("- root\n\n  - a\n\n  - b\n");
  const before = itemsOf(getText());
  // b を左へ（切り替えの境界が書かれる）
  core.moveSideEnd([idOf(snap.nodes, "b")], idOf(snap.nodes, "root"), true);
  const after = itemsOf(getText());
  // depth だけでなくラベルも比べる。深さの並びが偶然一致しても、
  // どの項目がどのラベルかが入れ替わっていては壊れているのと同じ
  assert.deepEqual(after, before, `字下げまたはラベルが崩れている:\n${getText()}`);
});

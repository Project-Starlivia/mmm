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

test("リストの形で境界を書いても、外のパーサの木は変わらない", () => {
  const snap = initDoc("- root\n\n  - a\n\n  - b\n");
  const before = itemsOf(getText());
  // b を左へ（切り替えの境界が書かれる）
  core.moveSideEnd([idOf(snap.nodes, "b")], idOf(snap.nodes, "root"), true);
  const after = itemsOf(getText());
  assert.deepEqual(
    after.map((i) => i.depth),
    before.map((i) => i.depth),
    `字下げが崩れている:\n${getText()}`,
  );
});

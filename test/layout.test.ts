// 木 → 箱の配置。**左右の振り分けはここでしか見えない**（core が出すのは
// 「どっち側か」だけで、実際にどこへ置くかはこの層が決める）。
//
// 寸法の実測だけは canvas が要るので身代わりを立てる（stubCanvas）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { loadDoc, nodeOf, stubCanvas } from "./_helpers.ts";
import { GAP, layoutMap } from "../src/map/layout.ts";

stubCanvas();

/** ラベルから箱を引く */
function boxOf(md: string, label: string) {
  const doc = loadDoc(md);
  const L = layoutMap(doc);
  const b = L.boxes.get(nodeOf(doc.nodes, label).id);
  assert.ok(b, `箱 ${label} が無い`);
  return b;
}

test("区切りが無ければ、今までどおり全部右へ伸びる", () => {
  const md = "# r\n\n## a\n\n## b\n";
  const root = boxOf(md, "r");
  const a = boxOf(md, "a");
  assert.equal(root.x, 0);
  assert.equal(a.x, root.x + root.w + GAP.x);
});

// 区切りが無ければ従来と 1px も変わらない、が spec の約束。関係式だけでは
// 縦の式（groupsH / treeH / placeTree）の退行を捕まえられないので、
// 実際に走らせた値をそのまま golden にして数値ごと止める。孫・幅の違う兄弟・
// 2 つ目の木（2 個目の `#`）を全部通す。
test("区切りの無い本格的な文書は、全ノードの箱が golden の数値と一致する", () => {
  const md = "# root\n\n## a\n\n### a1\n\n### a22\n\n## bb\n\n# root2\n\n## c\n";
  const doc = loadDoc(md);
  const L = layoutMap(doc);
  const box = (label: string) => {
    const b = L.boxes.get(nodeOf(doc.nodes, label).id);
    assert.ok(b, `箱 ${label} が無い`);
    return { x: b.x, y: b.y, w: b.w, h: b.h };
  };
  assert.deepEqual(box("root"), { x: 0, y: -5, w: 52, h: 30 });
  assert.deepEqual(box("a"), { x: 97, y: -35, w: 31, h: 30 });
  assert.deepEqual(box("a1"), { x: 173, y: -55, w: 38, h: 30 });
  assert.deepEqual(box("a22"), { x: 173, y: -15, w: 45, h: 30 });
  assert.deepEqual(box("bb"), { x: 97, y: 25, w: 38, h: 30 });
  assert.deepEqual(box("root2"), { x: 0, y: 123, w: 59, h: 30 });
  assert.deepEqual(box("c"), { x: 104, y: 123, w: 31, h: 30 });
});

test("切り替えの後ろの枝は、ルートの左へミラーで伸びる", () => {
  const md = "# r\n\n## a\n\n---\n---\n\n## b\n\n### b1\n";
  const root = boxOf(md, "r");
  const b = boxOf(md, "b");
  const b1 = boxOf(md, "b1");
  // 右の枝は右辺から、左の枝は左辺から同じだけ離れる
  assert.equal(b.x + b.w, root.x - GAP.x);
  // 左の枝の子は、さらに左へ
  assert.equal(b1.x + b1.w, b.x - GAP.x);
});

test("同じ側のグループは、間を GAP.group だけ空けて縦に積む", () => {
  const md = "# r\n\n## a\n\n---\n\n## b\n";
  const a = boxOf(md, "a");
  const b = boxOf(md, "b");
  assert.equal(a.x, b.x); // 同じ側 = 同じ列
  assert.ok(
    b.y - (a.y + a.h) >= GAP.group,
    `グループの間が空いていない: ${b.y - (a.y + a.h)}`,
  );
});

test("継ぎ目の線は、同じ側の列の中のグループの境目に出る", () => {
  const doc = loadDoc("# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n");
  const L = layoutMap(doc);
  // 右の列は [a][b] の 2 グループ = 継ぎ目 1 本、左の列は [c] だけ = 0 本
  assert.equal(L.seams.length, 1);
  const a = L.boxes.get(nodeOf(doc.nodes, "a").id);
  const b = L.boxes.get(nodeOf(doc.nodes, "b").id);
  assert.ok(a && b);
  assert.ok(L.seams[0].y > a.y + a.h && L.seams[0].y < b.y);
  assert.equal(L.seams[0].x, a.x);
});

test("継ぎ目の線は、左の列でも境目に出る（列の右端 - 幅の位置）", () => {
  const doc = loadDoc("# r\n\n## a\n\n---\n---\n\n## b\n\n---\n\n## c\n");
  const L = layoutMap(doc);
  // 右の列は [a] だけ = 0 本、左の列は [b][c] の 2 グループ = 継ぎ目 1 本
  assert.equal(L.seams.length, 1);
  const b = L.boxes.get(nodeOf(doc.nodes, "b").id);
  const c = L.boxes.get(nodeOf(doc.nodes, "c").id);
  assert.ok(b && c);
  assert.ok(L.seams[0].y > b.y + b.h && L.seams[0].y < c.y);
  // 左向きの箱は右辺 (x+w) が列の共通の辺（root と向かい合う辺）になる。
  // 継ぎ目もその辺に右端を揃える
  assert.equal(L.seams[0].x + L.seams[0].w, b.x + b.w);
});

test("左だけの文書でも、ルートは枝の中心に立つ", () => {
  const md = "# r\n\n---\n---\n\n## a\n\n## b\n";
  const root = boxOf(md, "r");
  const a = boxOf(md, "a");
  const b = boxOf(md, "b");
  assert.equal(
    root.y + root.h / 2,
    (a.y + a.h / 2 + (b.y + b.h / 2)) / 2,
  );
});

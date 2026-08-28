// 木 → 箱の配置。**左右の振り分けはここでしか見えない**（core が出すのは
// 「どっち側か」だけで、実際にどこへ置くかはこの層が決める）。
// あわせて rootId（視点を寄せる/指す先の既定）。
//
// 寸法の実測だけは canvas が要るので身代わりを立てる（stubCanvas）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type NodeInfo, idOf, loadDoc, nodeOf, stubCanvas } from "./_helpers.ts";
import {
  type Box,
  type Layout,
  GAP,
  edgeEnds,
  layoutMap,
  rootId,
} from "../src/map/layout.ts";
import { leftOf, rightOf } from "../src/map/geometry.ts";

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

test("左の枝の edgeEnds は、親の左辺から出て子の右辺へ入る", () => {
  // 右の枝（edgeEnds の通常経路）は golden 群で間接に踏まれているが、
  // ミラーした側は edgeEnds を直接見て確かめないと片方だけ直したときに気づけない
  const doc = loadDoc("# r\n\n---\n---\n\n## a\n");
  const L = layoutMap(doc);
  const r = nodeOf(doc.nodes, "r");
  const a = nodeOf(doc.nodes, "a");
  const rb = L.boxes.get(r.id);
  const ab = L.boxes.get(a.id);
  assert.ok(rb && ab);
  const ends = edgeEnds(L, a.id);
  assert.ok(ends);
  assert.deepEqual(ends.from, leftOf(rb));
  assert.deepEqual(ends.to, rightOf(ab));
});

test("ルートの左右に 1 本ずつなら、線は真っすぐ出る", () => {
  // 扇（fanOf）は「同じ出口で重なる線をほどく」ためのもの。左右は**別の辺**
  // から出るので元から重ならない。親 id だけでまとめていたころは、各側 1 本
  // ずつしか無いのに互いに散らされ、両方の線が曲がっていた
  const doc = loadDoc("# r\n\n## a\n\n---\n---\n\n## b\n");
  const L = layoutMap(doc);
  for (const label of ["a", "b"]) {
    const ends = edgeEnds(L, nodeOf(doc.nodes, label).id);
    assert.ok(ends, `${label} のエッジが無い`);
    assert.equal(ends.from.y, ends.to.y, `${label} の線が曲がっている`);
  }
});

test("反対側の重さが偏っていても、1 本だけの側の線は真っすぐ", () => {
  // 根の中心は「採用した側の最初と最後の子の中心の中間」であって、幾何学的な
  // 中心ではない。採用した側（右）の子どうしで部分木の重さが偏っていると
  // （最初の子だけ子孫が深い）、この中間点は空間の真ん中からずれる。左に
  // 1 本だけの枝は箱の中で独立して中央寄せされるので、ずれた根とは噛み合わず
  // 曲がっていた
  const md =
    "# r\n\n## heavy\n\n### x\n\n#### y\n\n##### z\n\n## light1\n\n## light2\n\n---\n---\n\n## lone\n";
  const doc = loadDoc(md);
  const L = layoutMap(doc);
  const ends = edgeEnds(L, nodeOf(doc.nodes, "lone").id);
  assert.ok(ends, "lone のエッジが無い");
  assert.equal(ends.from.y, ends.to.y, "lone の線が曲がっている");
});

// 枝分かれのある重い部分木。1 子の連なりでは heightOf が増えないので、
// 「重さが偏る」を作るには枝分かれが要る
const HEAVY =
  "## h\n\n### x1\n\n#### y1\n\n#### y2\n\n### x2\n\n#### y3\n\n#### y4\n\n";

test("どの側も、第 1 子と最終子の中心の中点が根の中心に乗る", () => {
  // 根は自分の中心をこの尺度で決める。だから**両側ともこの尺度で揃っていな
  // ければ扇の中心が根からずれる** = 線が曲がる。側の縦位置を「合計の高さの
  // 幾何学的な中央寄せ」で決めていたころは中心の尺度が 2 つあり、根が尺度を
  // コピーする採用側しか噛み合っていなかった（本数に関わらず起きる）。
  for (const md of [
    `# r\n\n${HEAVY}## l\n\n---\n---\n\n## lone\n`,
    `# r\n\n${HEAVY}## l\n\n---\n---\n\n## c1\n\n## c2\n`,
    `# r\n\n## l\n\n${HEAVY}---\n---\n\n## c1\n\n## c2\n`,
    `# r\n\n## a\n\n---\n---\n\n${HEAVY}## l\n`,
  ]) {
    const doc = loadDoc(md);
    const L = layoutMap(doc);
    const root = doc.nodes.find((n) => n.depth === 1 && n.parent === -1);
    assert.ok(root, "根が無い");
    const rb = L.boxes.get(root.id);
    assert.ok(rb, "根の箱が無い");
    const rc = rb.y + rb.h / 2;
    for (const left of [false, true]) {
      const cy: number[] = [];
      for (const n of doc.nodes) {
        if (n.parent !== root.id || n.left !== left) continue;
        const b = L.boxes.get(n.id);
        if (b) cy.push(b.y + b.h / 2);
      }
      if (cy.length === 0) continue;
      const mid = (cy[0] + cy[cy.length - 1]) / 2;
      assert.equal(mid, rc, `${left ? "左" : "右"}(${cy.length}本)の中点がずれた`);
    }
  }
});

test("背の高い箱でも、箱は自分の帯からはみ出して兄弟を覆わない", () => {
  // 親の中心は「第 1 子と最終子の中心の中点」なのに、帯は「max(自分の高さ,
  // 子を積んだ高さ)」で見積もっていた。子の重さが偏るとこの 2 つがずれ、
  // 箱が帯の外へ出て隣の兄弟を丸ごと覆っていた（ずれは兄弟の隙間より大きい）
  const img = (n: number) =>
    Array.from({ length: n }, (_, i) => `![](./${i}.png)`).join("\n\n");
  const md = `# root\n\n## A\n\n## B\n\n${img(6)}\n\n### light\n\n### heavy\n\n${img(4)}\n`;
  const L = layoutMap(loadDoc(md));
  const bs = [...L.boxes.values()];
  for (let i = 0; i < bs.length; i++) {
    for (let k = i + 1; k < bs.length; k++) {
      const a = bs[i];
      const b = bs[k];
      const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
      const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
      assert.ok(
        ox <= 0.5 || oy <= 0.5,
        `${a.n.label} と ${b.n.label} の箱が ${ox}x${oy} 重なる`,
      );
    }
  }
});

test("グループの継ぎ目は、箱の上を横切らない", () => {
  const md =
    "# r\n\n## a\n\n![](./x.png)\n\n![](./x.png)\n\n### h\n\n```\n0\n1\n2\n3\n4\n5\n```\n\n### l\n\n---\n\n## b\n";
  const L = layoutMap(loadDoc(md));
  for (const s of L.seams) {
    for (const b of L.boxes.values()) {
      const inside =
        s.y > b.y && s.y < b.y + b.h && s.x < b.x + b.w && s.x + s.w > b.x;
      assert.ok(!inside, `継ぎ目 y=${s.y} が ${b.n.label} の箱を横切る`);
    }
  }
});

test("別々の `#` ルートの木は、上下に食い込まない", () => {
  // 側を根の中心へ揃えると、木は渡された top より**上**へも伸びうる。
  // placeTree は上端も返すのに積む側が下端しか読んでおらず、前の木へ
  // 食い込んでいた（区切りのある文書でだけ起きる）
  const md =
    "# R1\n---\n---\n## z0\n### z6\n# R2\n## a\n---\n---\n## b0\n" +
    "### b9\n### b10\n### b11\n### b12\n### b13\n### b14\n### b15\n### b16\n## c\n";
  const L = layoutMap(loadDoc(md));
  const bs = [...L.boxes.values()];
  for (let i = 0; i < bs.length; i++) {
    for (let k = i + 1; k < bs.length; k++) {
      const a = bs[i];
      const b = bs[k];
      const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
      const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
      assert.ok(
        ox <= 0.5 || oy <= 0.5,
        `${a.n.label} と ${b.n.label} の箱が ${ox}x${oy} 重なる`,
      );
    }
  }
});

test("同じ側に 2 本あれば、これまでどおり付け根を散らす", () => {
  const doc = loadDoc("# r\n\n## a\n\n## b\n");
  const L = layoutMap(doc);
  const a = L.fanOf.get(nodeOf(doc.nodes, "a").id);
  const b = L.fanOf.get(nodeOf(doc.nodes, "b").id);
  assert.ok(a !== undefined && b !== undefined, "扇が働いていない");
  assert.notEqual(a, b);
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

// ---- rootId ----

/** rootId が読むのは boxes の n だけ。寸法は要らない。 */
function layoutOf(nodes: NodeInfo[]): Layout {
  const boxes = new Map<number, Box>();
  for (const n of nodes) boxes.set(n.id, { n, x: 0, y: 0, w: 0, h: 0, rows: [] });
  return {
    visible: nodes,
    boxes,
    parentOf: new Map(),
    buriedCount: new Map(),
    fanOf: new Map(),
    seams: [],
  };
}

test("ルートは深さ1で親を持たないノード", () => {
  const { nodes } = loadDoc("# 根\n\n## 枝\n");
  assert.equal(rootId(layoutOf(nodes)), idOf(nodes, "根"));
});

test("複数の # があっても、最初の深さ1が主ルート", () => {
  const { nodes } = loadDoc("# 根\n\n# 別の根\n");
  assert.equal(rootId(layoutOf(nodes)), idOf(nodes, "根"));
});

test("箱が無ければ null（空文書）", () => {
  assert.equal(rootId(layoutOf([])), null);
});

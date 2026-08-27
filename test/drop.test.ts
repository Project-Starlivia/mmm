// ドラッグの落とし先。マップでいちばん込み入った判断で、しかも「惜しい」が
// いちばん嫌われる場所（右に置いたのに兄弟になる／線に落としたのに子になる）。
// クラスの中に埋まっていた頃は 1 本も試験できていなかった。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveDrop, type DropScene } from "../src/map/drop.ts";
import type { Box } from "../src/map/layout.ts";
import type { NodeInfo } from "../src/coreApi.ts";
import { leftOf, rightOf } from "../src/map/geometry.ts";
import { edgeSegs, flattenSegs } from "../src/map/edge.ts";

/** 箱を 1 つ。中身（NodeInfo）は depth しか見ないので最小限で足りる */
function box(id: number, depth: number, x: number, y: number, w = 100, h = 30): Box {
  const n: NodeInfo = {
    id,
    depth,
    parent: -1,
    from: 0,
    headEnd: 0,
    to: 0,
    hasContent: false,
    hidden: false,
    group: 0,
    left: false,
    label: `n${id}`,
  };
  return { n, x, y, w, h, rows: [] };
}

/**
 * 場面を組み立てる。`parent` は「子 → 親」で、エッジの折れ線は実物と同じ式
 * （map/edge.ts）から作る — 判定だけ別の形の線を見ていては意味が無い。
 */
function scene(
  boxes: Box[],
  parent: [number, number][],
  at: { x: number; y: number },
  opts: Partial<DropScene> = {},
): DropScene {
  const boxMap = new Map(boxes.map((b) => [b.n.id, b]));
  const parentOf = new Map(parent);
  return {
    at,
    order: boxes.map((b) => b.n.id),
    boxes: boxMap,
    parentOf,
    dragging: new Set<number>(),
    single: true,
    preferEdge: false,
    polyline: (id) => {
      const b = boxMap.get(id);
      const pid = parentOf.get(id);
      const p = pid === undefined ? undefined : boxMap.get(pid);
      if (!b || !p) return null;
      const a = rightOf(p);
      const z = leftOf(b);
      return flattenSegs(edgeSegs(z.x - a.x, z.y - a.y), 8).map((q) => ({
        x: a.x + q[0],
        y: a.y + q[1],
      }));
    },
    ...opts,
  };
}

// 親(1) ── 子(2) / 子(3) の縦並び。落とすのは別ツリーの 9
const ROOT = box(1, 1, 0, 100);
const KID_A = box(2, 2, 145, 60);
const KID_B = box(3, 2, 145, 140);
const TREE = [ROOT, KID_A, KID_B];
const LINKS: [number, number][] = [
  [2, 1],
  [3, 1],
];

test("箱のまんなかに落とせば、その子になる", () => {
  const d = resolveDrop(scene(TREE, LINKS, { x: 195, y: 75 }));
  assert.deepEqual(d.target, { id: 2, pos: 0 });
});

test("箱の上寄りは手前へ、下寄りは後ろへの挿入になる", () => {
  const up = resolveDrop(scene(TREE, LINKS, { x: 195, y: 62 }));
  assert.deepEqual(up.target, { id: 2, pos: 1 });
  const down = resolveDrop(scene(TREE, LINKS, { x: 195, y: 88 }));
  assert.deepEqual(down.target, { id: 2, pos: 2 });
});

test("ルートには兄弟が無いので、どこに落としても子になる", () => {
  const up = resolveDrop(scene(TREE, LINKS, { x: 50, y: 102 }));
  assert.deepEqual(up.target, { id: 1, pos: 0 });
  const down = resolveDrop(scene(TREE, LINKS, { x: 50, y: 128 }));
  assert.deepEqual(down.target, { id: 1, pos: 0 });
});

test("箱のすぐ右（子の伸びる方向）も子にする", () => {
  // 外側ゾーンの近い側。ここを兄弟に振ると「右に置いたのに兄弟になる」
  const d = resolveDrop(scene(TREE, LINKS, { x: 265, y: 75 }));
  assert.deepEqual(d.target, { id: 2, pos: 0 });
});

test("どこからも遠ければ、落とし先を出さない", () => {
  const d = resolveDrop(scene(TREE, LINKS, { x: 900, y: 900 }));
  assert.equal(d.target, null);
});

test("掴んでいる部分木は落とし先にならない", () => {
  const d = resolveDrop(
    scene(TREE, LINKS, { x: 195, y: 75 }, { dragging: new Set([2]) }),
  );
  assert.notEqual(d.target?.id, 2);
});

test("Shift なら線への割り込みが最優先", () => {
  // 親(1) → 子(2) の線の中ほど。素の状態では「子にする」が勝つ場所
  const at = { x: 122, y: 90 };
  const plain = resolveDrop(scene(TREE, LINKS, at));
  assert.notEqual(plain.target?.pos, 3);
  const shifted = resolveDrop(scene(TREE, LINKS, at, { preferEdge: true }));
  assert.deepEqual(shifted.target, { id: 2, pos: 3 });
});

test("複数まとめて掴んでいるときは、線への割り込みを出さない", () => {
  // 誰が親になるのかが決まらないため
  const d = resolveDrop(
    scene(TREE, LINKS, { x: 122, y: 90 }, { preferEdge: true, single: false }),
  );
  assert.notEqual(d.target?.pos, 3);
});

test("親が違う候補が競っているときだけ、どの親につくかを予告する", () => {
  // 2 と 3 のあいだ（どちらの親も 1 なので迷いようがない）
  const same = resolveDrop(scene(TREE, LINKS, { x: 195, y: 110 }));
  assert.equal(same.ambiguous, false);

  // 別の親を持つ子どうしの境目。「上の親の末尾」と「下の親の先頭」が
  // 同じ場所に出るので、どちらにつくのかを言わないと選べない
  const otherRoot = box(5, 1, 0, 260);
  const otherKid = box(4, 2, 145, 200);
  const d = resolveDrop(
    scene([...TREE, otherRoot, otherKid], [...LINKS, [4, 5]], {
      x: 195,
      y: 190,
    }),
  );
  assert.equal(d.ambiguous, true);
});

test("左の枝では、外側ゾーンも左へ伸びる", () => {
  // ルート(1) の左に子(2)。子の左 30px は「2 の子にする」ゾーン
  const root = box(1, 1, 0, 100);
  const kid = { ...box(2, 2, -145, 100) };
  kid.n = { ...kid.n, left: true };
  const s = scene([root, kid], [[2, 1]], { x: -175, y: 115 });
  assert.deepEqual(resolveDrop(s).target, { id: 2, pos: 0 });
});

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
    contentStart: 0,
    contentEnd: 0,
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
    newGroup: false,
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
  assert.deepEqual(d.drop, { kind: "node", id: 2, pos: 0 });
});

test("箱の上寄りは手前へ、下寄りは後ろへの挿入になる", () => {
  const up = resolveDrop(scene(TREE, LINKS, { x: 195, y: 62 }));
  assert.deepEqual(up.drop, { kind: "node", id: 2, pos: 1 });
  const down = resolveDrop(scene(TREE, LINKS, { x: 195, y: 88 }));
  assert.deepEqual(down.drop, { kind: "node", id: 2, pos: 2 });
});

test("ルートには兄弟が無いので、どこに落としてもその側の末尾へ", () => {
  // 根の「子にする」(pos 0) は、どちら側かが決まって初めて意味を持つ
  const up = resolveDrop(scene(TREE, LINKS, { x: 50, y: 102 }));
  assert.deepEqual(up.drop, { kind: "side", root: 1, left: false });
  const down = resolveDrop(scene(TREE, LINKS, { x: 50, y: 128 }));
  assert.deepEqual(down.drop, { kind: "side", root: 1, left: false });
});

test("箱のすぐ右（子の伸びる方向）も子にする", () => {
  // 外側ゾーンの近い側。ここを兄弟に振ると「右に置いたのに兄弟になる」
  const d = resolveDrop(scene(TREE, LINKS, { x: 265, y: 75 }));
  assert.deepEqual(d.drop, { kind: "node", id: 2, pos: 0 });
});

test("どこからも遠ければ、落とし先を出さない", () => {
  const d = resolveDrop(scene(TREE, LINKS, { x: 900, y: 900 }));
  assert.equal(d.drop, null);
});

test("掴んでいる部分木は落とし先にならない", () => {
  // 2 を外すと、この場所には代わりに拾えるほど近い相手が無い
  const d = resolveDrop(
    scene(TREE, LINKS, { x: 195, y: 75 }, { dragging: new Set([2]) }),
  );
  assert.equal(d.drop, null);
});

test("列の上端より上・下端より下は、遠くても前後への挿入で受ける", () => {
  // 兄弟は縦に積まれるので、上端の上と下端の下には競う相手が居ない。
  // 帯の 40px で切ると、そこは誰も取らない広い死に地になっていた
  const up = resolveDrop(scene(TREE, LINKS, { x: 195, y: -40 }));
  assert.deepEqual(up.drop, { kind: "node", id: 2, pos: 1 });
  const down = resolveDrop(scene(TREE, LINKS, { x: 195, y: 280 }));
  assert.deepEqual(down.drop, { kind: "node", id: 3, pos: 2 });
});

test("開いている側でも、OPEN を超えて離せばキャンセルできる", () => {
  // 無制限にすると、列の x に収まったまま上下へいくら離しても必ずどこかへ
  // 落ちてしまい、ドラッグを諦める手が「横に外す」だけになる
  const d = resolveDrop(scene(TREE, LINKS, { x: 195, y: -160 }));
  assert.equal(d.drop, null);
});

test("同じ列に積まれた 2 つの stack の谷間は、近いほうの端が取る", () => {
  // 端は (親, 側) ごとに数える。列でいちばん上/下のノードだけを端に
  // すると、谷間の両側がどちらも端にならず死に地のまま残る
  const root = box(1, 1, 0, 100);
  const p1 = box(2, 2, 145, 40);
  const p2 = box(3, 2, 145, 200);
  const c1 = box(4, 3, 290, 20);
  const c2 = box(5, 3, 290, 240);
  const boxes = [root, p1, p2, c1, c2];
  const links: [number, number][] = [
    [2, 1],
    [3, 1],
    [4, 2],
    [5, 3],
  ];
  // 上の stack 寄り → その下へ / 下の stack 寄り → その上へ
  const near1 = resolveDrop(scene(boxes, links, { x: 335, y: 120 }));
  assert.deepEqual(near1.drop, { kind: "node", id: 4, pos: 2 });
  const near2 = resolveDrop(scene(boxes, links, { x: 335, y: 180 }));
  assert.deepEqual(near2.drop, { kind: "node", id: 5, pos: 1 });
});

test("線の中ほどは、Shift 無しでも割り込みになる", () => {
  // 線は箱の帯には勝てないが、外側ゾーンより先。親の帯が線を丸ごと覆って
  // いたころは、親が子を持つほど f3/g3 のような割り込みが一切狙えなかった
  const d = resolveDrop(scene(TREE, LINKS, { x: 122, y: 90 }));
  assert.deepEqual(d.drop, { kind: "node", id: 2, pos: 3 });
});

test("Shift は線の狙い所を広げる", () => {
  // 端から 30% を外す既定では届かない、線の端寄り。Shift だと 10% まで縮む
  const at = { x: 138, y: 76 };
  const plain = resolveDrop(scene(TREE, LINKS, at));
  assert.notDeepEqual(plain.drop, { kind: "node", id: 2, pos: 3 });
  const shifted = resolveDrop(scene(TREE, LINKS, at, { preferEdge: true }));
  assert.deepEqual(shifted.drop, { kind: "node", id: 2, pos: 3 });
});

test("複数まとめて掴んでいるときは、線への割り込みを出さない", () => {
  // 誰が親になるのかが決まらないため。Shift の狙い所と同じ場所は根の脇に落ちる
  const d = resolveDrop(
    scene(TREE, LINKS, { x: 122, y: 90 }, { preferEdge: true, single: false }),
  );
  assert.deepEqual(d.drop, { kind: "side", root: 1, left: false });
});

test("別の親を持つ子どうしの境目は、近いほうにつく", () => {
  // 「上の親の末尾」と「下の親の先頭」は同じ場所に出るので、距離で決める
  const otherRoot = box(5, 1, 0, 260);
  const otherKid = box(4, 2, 145, 200);
  const boxes = [...TREE, otherRoot, otherKid];
  const links: [number, number][] = [...LINKS, [4, 5]];
  const up = resolveDrop(scene(boxes, links, { x: 195, y: 178 }));
  assert.deepEqual(up.drop, { kind: "node", id: 3, pos: 2 });
  const down = resolveDrop(scene(boxes, links, { x: 195, y: 196 }));
  assert.deepEqual(down.drop, { kind: "node", id: 4, pos: 1 });
});

// 列 1 の枝の「子にする」ゾーンが、列 2 の兄弟挿入を横取りしていた。
// 実寸に近い幅（31）と間隔で組む — 幅を広く取ると通路の比率が変わって
// 再現しない
const COL_ROOT = box(1, 1, 0, 100, 31);
const COL_A = box(2, 2, 76, 60, 31);
const COL_B = box(3, 2, 76, 120, 31);
const COL_F = box(4, 3, 152, 60, 31);
const COLS = [COL_ROOT, COL_A, COL_B, COL_F];
const COL_LINKS: [number, number][] = [
  [2, 1],
  [3, 1],
  [4, 2],
];

test("隣の列の枝は、その先の列の兄弟挿入を横取りしない", () => {
  // f のすぐ下（f の箱の外）で、ちょうど b と同じ高さ。ここは f の弟の場所で
  // あって、b の子の場所ではない
  const d = resolveDrop(scene(COLS, COL_LINKS, { x: 167, y: 105 }));
  assert.deepEqual(d.drop, { kind: "node", id: 4, pos: 2 });
});

test("子の無い枝の通路は、その最初の子にするゾーン", () => {
  // b の右辺(107) と f の列(152) のあいだ。隣に並ぶ子がいないので、通路は
  // 丸ごと「最初の子にする」。ここを取り上げると子を足す手が無くなる
  const d = resolveDrop(scene(COLS, COL_LINKS, { x: 130, y: 135 }));
  assert.deepEqual(d.drop, { kind: "node", id: 3, pos: 0 });
});

test("子がいる枝の通路は、指した高さがそのまま行き先", () => {
  // 通路のどの高さも「末尾に足す」に潰していたころは、e の隣を指しても
  // f の隣を指しても印が最後の子の下に 1 点で出て、指した場所と着地点が
  // 対応しなかった（「引っ張られる」の正体）
  const root = box(1, 1, 0, 100, 31);
  const a = box(2, 2, 76, -55, 31); // 子 3 つ (-95..15) の中心に立つ
  const e = box(3, 3, 152, -95, 31);
  const f = box(4, 3, 152, -55, 31);
  const g = box(5, 3, 152, -15, 31);
  const boxes = [root, a, e, f, g];
  const links: [number, number][] = [
    [2, 1],
    [3, 2],
    [4, 2],
    [5, 2],
  ];
  // 帯の**子側**（真ん中は線への割り込みが持つ）。付け根から 3 分の 2 あたり
  const at = (y: number) => resolveDrop(scene(boxes, links, { x: 145, y })).drop;
  // e の下寄り → e の後ろ / f の上寄り → f の手前 / f と g の間 → g の手前
  assert.deepEqual(at(-71), { kind: "node", id: 3, pos: 2 });
  assert.deepEqual(at(-56), { kind: "node", id: 4, pos: 1 });
  assert.deepEqual(at(-31), { kind: "node", id: 4, pos: 2 });
  assert.deepEqual(at(-16), { kind: "node", id: 5, pos: 1 });
});

test("帯の真ん中は線への割り込み、子側は前後への挿入", () => {
  // 線は端から 30% を狙い所から外すので、帯は自然と三層になる
  // （付け根側 = 親のゾーン / 真ん中 = 線 / 子側 = 前後への挿入）
  const root = box(1, 1, 0, 100, 31);
  const a = box(2, 2, 76, -55, 31);
  const e = box(3, 3, 152, -95, 31);
  const f = box(4, 3, 152, -55, 31);
  const g = box(5, 3, 152, -15, 31);
  const boxes = [root, a, e, f, g];
  const links: [number, number][] = [
    [2, 1],
    [3, 2],
    [4, 2],
    [5, 2],
  ];
  const mid = resolveDrop(scene(boxes, links, { x: 130, y: -40 }));
  assert.deepEqual(mid.drop, { kind: "node", id: 4, pos: 3 });
});

test("左の枝では、外側ゾーンも左へ伸びる", () => {
  // ルート(1) の左に子(2)。子の左 30px は「2 の子にする」ゾーン
  const root = box(1, 1, 0, 100);
  const kid = { ...box(2, 2, -145, 100) };
  kid.n = { ...kid.n, left: true };
  const s = scene([root, kid], [[2, 1]], { x: -175, y: 115 });
  assert.deepEqual(resolveDrop(s).drop, { kind: "node", id: 2, pos: 0 });
});

test("ルートの右脇へ落とすと、その側の末尾へ", () => {
  const root = box(1, 1, 0, 100);
  const kid = box(2, 2, 145, 100);
  const s = scene([root, kid], [[2, 1]], { x: 60, y: 115 });
  assert.deepEqual(resolveDrop(s).drop, { kind: "side", root: 1, left: false });
});

test("ルートの左脇へ落とすと、左の側の末尾へ", () => {
  const root = box(1, 1, 0, 100);
  const kid = box(2, 2, 145, 100);
  const s = scene([root, kid], [[2, 1]], { x: -60, y: 115 });
  assert.deepEqual(resolveDrop(s).drop, { kind: "side", root: 1, left: true });
});

test("Mod を押していれば、枝の隣が新しいグループのスロットになる", () => {
  const root = box(1, 1, 0, 100);
  const a = box(2, 2, 145, 60);
  const b = box(3, 2, 145, 140);
  // a（実在する枝）を掴んで b の近くへ落とす。掴んでいるものはスロット探しから除く
  const s = scene([root, a, b], [[2, 1], [3, 1]], { x: 195, y: 130 }, {
    newGroup: true,
    dragging: new Set([2]),
  });
  // b の上半分 = b の手前へ新しいグループ
  assert.deepEqual(resolveDrop(s).drop, {
    kind: "group",
    target: 3,
    before: true,
    left: false,
  });
});

test("Mod で根そのものを掴んでいれば、その根は nearestRoot の候補から外れる", () => {
  // 木が縦に 2 つ。掴んでいるのは根(1)自身で、ポインタもその真上。
  // 除外していなければ最短距離で根(1)が拾われてしまうが、
  // 正しくは掴んでいない側の根(5)まで見に行く
  const rootA = box(1, 1, 0, 100);
  const kidA = box(2, 2, 145, 100);
  const rootB = box(5, 1, 0, 300);
  const kidB = box(4, 2, 145, 300);
  const s = scene(
    [rootA, kidA, rootB, kidB],
    [[2, 1], [4, 5]],
    { x: 50, y: 115 },
    { newGroup: true, dragging: new Set([1, 2]) },
  );
  assert.deepEqual(resolveDrop(s).drop, {
    kind: "group",
    target: 4,
    before: true,
    left: false,
  });
});

test("Mod でも、枝が 1 つも無い側は「その側の末尾」に落ちる", () => {
  const root = box(1, 1, 0, 100);
  const a = box(2, 2, 145, 100);
  // 根の届く範囲（REACH/SLACK 相当）の内側で、まだ何も無い左側
  const s = scene([root, a], [[2, 1]], { x: -150, y: 100 }, { newGroup: true });
  assert.deepEqual(resolveDrop(s).drop, { kind: "side", root: 1, left: true });
});

test("Mod を押していても、どの木からも遠い空所ではキャンセルできる", () => {
  // nearestRoot に上限が無いと、Mod を押したまま空振りしても必ずどこかの
  // 根への移動が成立してしまい、ドラッグを諦める手段が無くなる
  const root = box(1, 1, 0, 100);
  const s = scene([root], [], { x: 900, y: 900 }, { newGroup: true });
  assert.equal(resolveDrop(s).drop, null);
});

test("Mod: 根から縦に離れた枝の近くへ落としても、新しいグループとして拾う", () => {
  // 複数グループが縦に積まれた実際の文書では、根自身の箱は小さく、
  // グループはそこから遠く離れた位置にも並ぶ。「木から遠いか」を根の
  // 小さい箱だけで測ると、根の近くにしか Mod+ドロップが効かなくなる
  const root = box(1, 1, 0, 0, 80, 30);
  const kids = Array.from({ length: 8 }, (_, i) => box(10 + i, 2, 125, i * 60));
  const links: [number, number][] = kids.map((k) => [k.n.id, 1]);
  const s = scene([root, ...kids], links, { x: 175, y: 420 }, { newGroup: true });
  const d = resolveDrop(s).drop;
  assert.ok(d && d.kind !== "node", `根から遠い枝の近くで Mod+ドロップが効かない: ${JSON.stringify(d)}`);
});

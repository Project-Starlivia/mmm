// ノード木 → 箱の配置。DOM を知らない純粋なレイアウト層。
// すべての木は左から右へ伸びる。

import type { DocView, NodeInfo } from "../coreApi.ts";
import { type CardRow, cardBleed, cardInset, cardRows, rowH } from "./cards.ts";
import { type Pt, type Rect, entryEdgeOf, growthEdgeOf } from "./geometry.ts";
import { ROW_NORMAL, nodeSize, rowTop } from "./metrics.ts";

export const GAP = {
  x: 45,
  y: 10,
  /** 同じ側の、グループとグループの間 */
  group: 26,
  root: 34,
};

/** その枝が伸びる向き（右 = 1 / 左 = -1）。**側を読むのはここだけ** */
export const dirOf = (n: NodeInfo): 1 | -1 => (n.left ? -1 : 1);

/**
 * グループの継ぎ目に引く水平線。**同じ側の列の中の継ぎ目すべて**に出るので、
 * 意味の境界（`---` の位置）と 1 対 1 ではない — 右 A・左 B・右 C の並びでは、
 * 右の列の A と C の間に 1 本出る。線は見せ方であって意味ではない。
 */
export interface Seam {
  x: number;
  y: number;
  w: number;
}

/**
 * 親の辺のうち、何割を「付け根の帯」に使うか。子が複数あるとき、線の出口を
 * この帯の中に配って重なりを解く。
 */
const FAN_BAND = 0.6;

export interface Box {
  n: NodeInfo;
  x: number;
  y: number;
  w: number;
  h: number;
  rows: CardRow[];
}

/**
 * カード 1 行の中身を置く矩形（**箱の左上から見た座標**）。
 *
 * 描くのも、選んだ枠を出すのも、その場で直す入力欄を置くのも、必ずここを
 * 通る。以前は描画とマップが同じ積み方を別々に数えていて、実際に 2px ずれた。
 */
export function cardRect(b: Box, index: number): Rect | null {
  const r = b.rows[index];
  if (r === undefined) return null;
  const inset = cardInset(r);
  const bleed = cardBleed(r);
  return {
    x: ROW_NORMAL.padX - bleed,
    y: rowTop(b.rows, index) + inset,
    w: b.w - ROW_NORMAL.padX * 2 + bleed * 2,
    h: rowH(r) - inset * 2,
  };
}

export interface Layout {
  /** 描くノード、文書順（畳まれて埋もれたものは入らない） */
  visible: NodeInfo[];
  boxes: Map<number, Box>;
  parentOf: Map<number, number>;
  /** 畳んだノード → その下に埋もれている**子孫**の数（子だけではない） */
  buriedCount: Map<number, number>;
  /** 子 → 親の辺の上での、付け根のずらし量(px) */
  fanOf: Map<number, number>;
  /** 同じ側の列の中の、グループの継ぎ目 */
  seams: Seam[];
}

/**
 * `roots` とその子孫のうち、見えているものすべて。**`roots` が空なら全体**。
 *
 * 書き出しの範囲がこれ。mmm では「選ぶ」がどこでも枝ごとを意味する
 * （コピーもカットも削除も移動も）ので、書き出しだけ別の意味にはしない。
 * 畳んで埋もれているノードは `visible` に入らないため、畳んだまま書き出せば
 * 畳んだ姿がそのまま出る。
 */
export function branchIds(
  layout: Layout,
  roots: ReadonlySet<number>,
): Set<number> {
  const out = new Set<number>();
  for (const n of layout.visible) {
    if (roots.size === 0) {
      out.add(n.id);
      continue;
    }
    // 自分から親をたどって、途中に選ばれたものがあれば入る
    for (let id = n.id; ; ) {
      if (roots.has(id)) {
        out.add(n.id);
        break;
      }
      const up = layout.parentOf.get(id);
      if (up === undefined) break;
      id = up;
    }
  }
  return out;
}

/** ルート = 深さ 1 でどの親も持たないノード。無ければ null（空文書）。 */
export function rootId(layout: Layout): number | null {
  for (const [id, b] of layout.boxes) {
    if (b.n.depth === 1 && b.n.parent === -1) return id;
  }
  return null;
}

const gapBefore = (i: number): number => (i === 0 ? 0 : GAP.y);

function collapseHidden(nodes: NodeInfo[]): {
  visible: NodeInfo[];
  buried: Set<number>;
  buriedCount: Map<number, number>;
} {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const topOf = new Map<number, number>();
  const buried = new Set<number>();
  const buriedCount = new Map<number, number>();
  for (const n of nodes) {
    const parent = n.parent === -1 ? undefined : byId.get(n.parent);
    if (!parent) continue;
    const top = topOf.get(parent.id) ?? (parent.hidden ? parent.id : undefined);
    if (top !== undefined) {
      topOf.set(n.id, top);
      buried.add(n.id);
      buriedCount.set(top, (buriedCount.get(top) ?? 0) + 1);
    }
  }
  return { visible: nodes.filter((n) => !buried.has(n.id)), buried, buriedCount };
}

export function layoutMap(doc: DocView): Layout {
  const nodes = doc.nodes;
  const { visible, buried, buriedCount } = collapseHidden(nodes);
  const rowsOf = cardRows(doc, buried);

  const children = new Map<number, NodeInfo[]>();
  const tops: NodeInfo[] = [];
  for (const n of visible) {
    if (n.parent === -1) tops.push(n);
    else {
      const list = children.get(n.parent);
      if (list) list.push(n);
      else children.set(n.parent, [n]);
    }
  }
  const kidsOf = (n: NodeInfo): NodeInfo[] => children.get(n.id) ?? [];
  const root = tops.find((n) => n.depth === 1) ?? null;
  const boxes = new Map<number, Box>();
  const seams: Seam[] = [];

  // 寸法と部分木の高さは**要るときに測って覚える**。先に表を埋めてから
  // 引き直す形だと「必ず入っているはず」を `!` で言い張ることになり、
  // 順番を間違えたときに遠くで落ちる
  const sizes = new Map<number, { w: number; h: number }>();
  const sizeOf = (n: NodeInfo): { w: number; h: number } => {
    const hit = sizes.get(n.id);
    if (hit) return hit;
    const size = nodeSize(n, rowsOf.get(n.id) ?? [], buriedCount.get(n.id) ?? 0);
    sizes.set(n.id, size);
    return size;
  };

  const heights = new Map<number, number>();
  /** その部分木が縦にどれだけ要るか（自分の高さと、子を積んだ高さの大きい方） */
  const heightOf = (n: NodeInfo): number => {
    const hit = heights.get(n.id);
    if (hit !== undefined) return hit;
    const kids = kidsOf(n);
    const height = Math.max(
      sizeOf(n).h,
      kids.length === 0 ? 0 : stackH(kids),
    );
    heights.set(n.id, height);
    return height;
  };

  /** 子を縦に積んだときの高さ（あいだの隙間込み） */
  function stackH(kids: NodeInfo[]): number {
    let sum = 0;
    for (let i = 0; i < kids.length; i++) sum += heightOf(kids[i]) + gapBefore(i);
    return sum;
  }

  /**
   * 枝を `dir` 方向へ置く。`nearX` は**親と向かい合う辺**の x
   * （右向きなら箱の左辺、左向きなら右辺）。左右で式を分けないための座標。
   */
  const place = (
    n: NodeInfo,
    nearX: number,
    top: number,
    dir: 1 | -1,
  ): number => {
    const size = sizeOf(n);
    const x = dir === 1 ? nearX : nearX - size.w;
    const kids = kidsOf(n);
    let centerY: number;
    if (kids.length === 0) {
      centerY = top + size.h / 2;
    } else {
      let y = top + Math.max(0, (size.h - stackH(kids)) / 2);
      const childNear = dir === 1 ? x + size.w + GAP.x : x - GAP.x;
      const centers: number[] = [];
      for (let i = 0; i < kids.length; i++) {
        y += gapBefore(i);
        centers.push(place(kids[i], childNear, y, dir));
        y += heightOf(kids[i]);
      }
      centerY = (centers[0] + centers[centers.length - 1]) / 2;
    }
    boxes.set(n.id, {
      n,
      x,
      y: centerY - size.h / 2,
      w: size.w,
      h: size.h,
      rows: rowsOf.get(n.id) ?? [],
    });
    return centerY;
  };

  /** ルート直下の枝を、側ごとにグループへ切り分ける（文書順） */
  const sideGroups = (root: NodeInfo, left: boolean): NodeInfo[][] => {
    const out: NodeInfo[][] = [];
    for (const k of kidsOf(root)) {
      if (k.left !== left) continue;
      const last = out[out.length - 1];
      if (last && last[0].group === k.group) last.push(k);
      else out.push([k]);
    }
    return out;
  };

  /** グループ列を縦に積んだ高さ（グループの間は GAP.group） */
  const groupsH = (groups: NodeInfo[][]): number => {
    let sum = 0;
    for (let g = 0; g < groups.length; g++) {
      sum += (g === 0 ? 0 : GAP.group) + stackH(groups[g]);
    }
    return sum;
  };

  /** 木ぜんぶが縦にどれだけ要るか（左右のうち高いほう） */
  const treeH = (root: NodeInfo): number =>
    Math.max(
      sizeOf(root).h,
      groupsH(sideGroups(root, false)),
      groupsH(sideGroups(root, true)),
    );

  /**
   * 木の根を置く。**グループと左右はルート直下にしか無い**ので、根の子だけが
   * ここを通り、孫から下は `place` がそのまま面倒を見る。区切りの無い文書では
   * 右のグループが 1 つあるだけになり、置き方は従来（片側 1 列）と一致する。
   */
  const placeTree = (
    root: NodeInfo,
    top: number,
  ): { top: number; bottom: number } => {
    const size = sizeOf(root);
    const span = treeH(root);
    const sides = [
      { left: false, dir: 1 as const, groups: sideGroups(root, false) },
      { left: true, dir: -1 as const, groups: sideGroups(root, true) },
    ];
    let centerY = top + span / 2;
    // 置いた側を控える。**根の中心が決まるまで側の縦位置は確定しない**ので、
    // いったん置いてから、側ごとにまとめてずらす
    const placed: {
      kids: NodeInfo[];
      centers: number[];
      mySeams: Seam[];
      y0: number;
      h: number;
    }[] = [];
    for (const s of sides) {
      if (s.groups.length === 0) continue;
      const nearX = s.dir === 1 ? size.w + GAP.x : -GAP.x;
      const h = groupsH(s.groups);
      const y0 = top + Math.max(0, (span - h) / 2);
      let y = y0;
      const centers: number[] = [];
      const mine: NodeInfo[] = [];
      const mySeams: Seam[] = [];
      for (let g = 0; g < s.groups.length; g++) {
        if (g > 0) {
          // 継ぎ目の線は、隣り合うグループの間の真ん中に、
          // その 2 グループでいちばん広い枝の幅で引く
          const near = [...s.groups[g - 1], ...s.groups[g]];
          const w = Math.max(...near.map((k) => sizeOf(k).w));
          const seam = {
            x: s.dir === 1 ? nearX : nearX - w,
            y: y + GAP.group / 2,
            w,
          };
          seams.push(seam);
          mySeams.push(seam); // 側ごとずらすとき、継ぎ目も連れていく
          y += GAP.group;
        }
        const kids = s.groups[g];
        for (let i = 0; i < kids.length; i++) {
          y += gapBefore(i);
          centers.push(place(kids[i], nearX, y, s.dir));
          mine.push(kids[i]);
          y += heightOf(kids[i]);
        }
      }
      placed.push({ kids: mine, centers, mySeams, y0, h });
      // 根の中心は右の枝に合わせる（右が無ければ左）。区切りの無い文書で
      // 従来と 1px も変えないための取り決めで、両側にあるときも
      // 「どちらに合わせるか」を決めておかないと揺れる
      if (!s.left || sides[0].groups.length === 0) {
        centerY = (centers[0] + centers[centers.length - 1]) / 2;
      }
    }
    // **不変条件: どの側も、第 1 子と最終子の中心の中点が根の中心に乗る。**
    //
    // 根は自分の中心をこの尺度で決める（`place` が親を子の上に置くのと同じ）。
    // なのに側の縦位置は「側の合計の高さを帯の中で幾何学的に中央寄せ」で
    // 決めていて、**中心の尺度が 2 つあった**。部分木の重さが偏るとその 2 つは
    // 一致しないので、根が尺度をコピーする採用側だけが噛み合い、もう一方の側は
    // 根と一度も突き合わせないまま置かれていた（= 線が曲がる）。
    //
    // 根以外の親にこの穴が無いのは、**子の山を 1 つしか持たない**から。
    // 2 つ持つのは根だけで、そこだけ規則が抜けていた。採用した側はずれが 0 に
    // なるので、この一手で本数に関わらず両側が同じ規則で揃う。
    for (const p of placed) {
      const mid = (p.centers[0] + p.centers[p.centers.length - 1]) / 2;
      const dy = centerY - mid;
      if (dy === 0) continue;
      for (const k of p.kids) shiftSubtree(k, dy);
      for (const sm of p.mySeams) sm.y += dy;
      p.y0 += dy;
    }
    boxes.set(root.id, {
      n: root,
      x: 0,
      y: centerY - size.h / 2,
      w: size.w,
      h: size.h,
      rows: rowsOf.get(root.id) ?? [],
    });
    // 実際に占めた縦の範囲。**ずらしたぶん `treeH` の見積もりを超えうる**ので、
    // 木を縦に積む側はこれを見る（見積もりで積むと次の木と重なる）
    let lo = centerY - size.h / 2;
    let hi = centerY + size.h / 2;
    for (const p of placed) {
      lo = Math.min(lo, p.y0);
      hi = Math.max(hi, p.y0 + p.h);
    }
    return { top: lo, bottom: hi };
  };

  /** その枝と子孫すべての箱を縦にずらす。側を根の中心へ揃えるため */
  const shiftSubtree = (n: NodeInfo, dy: number): void => {
    const b = boxes.get(n.id);
    if (b) b.y += dy;
    for (const k of kidsOf(n)) shiftSubtree(k, dy);
  };

  let bottom = 0;
  if (root) bottom = placeTree(root, -treeH(root) / 2).bottom;
  let top = boxes.size > 0 ? bottom + GAP.root * 2 : 0;
  for (const tree of tops) {
    if (tree === root) continue;
    // 積む位置は**実測の下端**から。側を根へ揃えるとその側は `treeH` の
    // 見積もりからはみ出しうるので、見積もりで積むと次の木と重なる
    top = placeTree(tree, top).bottom + GAP.root;
  }

  const parentOf = new Map<number, number>();
  const fanOf = new Map<number, number>();
  // 付け根をずらすのは「**同じ辺から**出る線が 2 本以上」あるときだけ。
  // 扇は出口が重なるのをほどくためのものなので、**側でまとめる** — ルートは
  // 左右の両辺から線を出す唯一のノードで、反対の辺から出る線は元から重ならない。
  // 親 id だけでまとめていたころは、左右に 1 本ずつのルートでも 2 本と数えて
  // 互いに散らし、**どちらの線も真っすぐ出なかった**。
  // 箱そのものを持ち回るので、id で引き直して「必ず在るはず」を言わなくてよい
  const fans = new Map<string, { parent: Box; kids: Box[] }>();
  for (const [id, b] of boxes) {
    const pid = b.n.parent;
    const parent = pid === -1 ? undefined : boxes.get(pid);
    if (!parent) continue;
    parentOf.set(id, pid);
    const key = `${pid},${b.n.left}`;
    const fan = fans.get(key);
    if (fan) fan.kids.push(b);
    else fans.set(key, { parent, kids: [b] });
  }
  const centerY = (b: Box): number => b.y + b.h / 2;
  for (const { parent, kids } of fans.values()) {
    if (kids.length < 2) continue;
    const band = parent.h * FAN_BAND;
    const sorted = [...kids].sort((a, b) => centerY(a) - centerY(b));
    for (let i = 0; i < sorted.length; i++) {
      fanOf.set(sorted[i].n.id, ((i + 0.5) / sorted.length - 0.5) * band);
    }
  }

  return { visible, boxes, parentOf, buriedCount, fanOf, seams };
}

/**
 * 子 id から、その親へ引く線の両端（付け根のずらしも込み）。
 * **描画も当たり判定もここだけを見る** — 同じ式を 2 箇所に書いていた頃、
 * 片方だけ直すと線と当たり判定が静かにずれた。
 */
export function edgeEnds(L: Layout, id: number): { from: Pt; to: Pt } | null {
  const b = L.boxes.get(id);
  const pid = L.parentOf.get(id);
  const p = pid === undefined ? undefined : L.boxes.get(pid);
  if (!b || !p) return null;
  // 線は「親の、子が伸びる側の辺」から出て「子の、親を向いた辺」へ入る
  const dir = dirOf(b.n);
  const out = growthEdgeOf(p, dir);
  const into = entryEdgeOf(b, dir);
  return { from: { x: out.x, y: out.y + (L.fanOf.get(id) ?? 0) }, to: into };
}

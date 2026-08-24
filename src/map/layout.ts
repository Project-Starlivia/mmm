// ノード木 → 箱の配置。DOM を知らない純粋なレイアウト層。
// すべての木は左から右へ伸びる。

import type { DocView, NodeInfo } from "../coreApi.ts";
import { type CardRow, cardBleed, cardInset, cardRows, rowH } from "./cards.ts";
import { type Pt, type Rect, leftOf, rightOf } from "./geometry.ts";
import { ROW_NORMAL, nodeSize, rowTop } from "./metrics.ts";

export const GAP = {
  x: 45,
  y: 10,
  root: 34,
};

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
}

/**
 * `roots` とその子孫のうち、見えているものすべて。**`roots` が空なら全体**。
 *
 * 書き出しの範囲がこれ。mmm では「選ぶ」がどこでも枝ごとを意味する
 * （コピーもカットも削除も移動も）ので、書き出しだけ別の意味にはしない。
 * 畳んで埋もれているノードは `visible` に入らないため、畳んだまま書き出せば
 * 畳んだ姿がそのまま出る。
 */
export function branchIds(layout: Layout, roots: Set<number>): Set<number> {
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

  const place = (n: NodeInfo, left: number, top: number): number => {
    const size = sizeOf(n);
    const kids = kidsOf(n);
    let centerY: number;
    if (kids.length === 0) {
      centerY = top + size.h / 2;
    } else {
      let y = top + Math.max(0, (size.h - stackH(kids)) / 2);
      const centers: number[] = [];
      for (let i = 0; i < kids.length; i++) {
        y += gapBefore(i);
        centers.push(place(kids[i], left + size.w + GAP.x, y));
        y += heightOf(kids[i]);
      }
      centerY = (centers[0] + centers[centers.length - 1]) / 2;
    }
    boxes.set(n.id, {
      n,
      x: left,
      y: centerY - size.h / 2,
      w: size.w,
      h: size.h,
      rows: rowsOf.get(n.id) ?? [],
    });
    return centerY;
  };

  if (root) place(root, 0, -heightOf(root) / 2);

  let bottom = 0;
  for (const box of boxes.values()) bottom = Math.max(bottom, box.y + box.h);
  let top = boxes.size > 0 ? bottom + GAP.root * 2 : 0;
  for (const tree of tops) {
    if (tree === root) continue;
    place(tree, 0, top);
    top += heightOf(tree) + GAP.root;
  }

  const parentOf = new Map<number, number>();
  const fanOf = new Map<number, number>();
  // 付け根をずらすのは「同じ親から出る線が 2 本以上」あるときだけ。
  // 箱そのものを持ち回るので、id で引き直して「必ず在るはず」を言わなくてよい
  const fans = new Map<number, { parent: Box; kids: Box[] }>();
  for (const [id, b] of boxes) {
    const pid = b.n.parent;
    const parent = pid === -1 ? undefined : boxes.get(pid);
    if (!parent) continue;
    parentOf.set(id, pid);
    const fan = fans.get(pid);
    if (fan) fan.kids.push(b);
    else fans.set(pid, { parent, kids: [b] });
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

  return { visible, boxes, parentOf, buriedCount, fanOf };
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
  const e = rightOf(p);
  return { from: { x: e.x, y: e.y + (L.fanOf.get(id) ?? 0) }, to: leftOf(b) };
}

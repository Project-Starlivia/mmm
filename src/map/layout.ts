// ノード木 → 箱の配置。DOM を知らない純粋なレイアウト層。
// すべての木は左から右へ伸びる。

import type { DocView, NodeInfo } from "../coreApi.ts";
import { type CardRow, cardRows } from "./cards.ts";
import { nodeSize } from "./metrics.ts";

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

export interface Layout {
  visible: NodeInfo[];
  order: number[];
  boxes: Map<number, Box>;
  parentOf: Map<number, number>;
  hiddenKids: Map<number, number>;
  fanOf: Map<number, number>;
}

const gapBefore = (i: number): number => (i === 0 ? 0 : GAP.y);

function collapseHidden(nodes: NodeInfo[]): {
  visible: NodeInfo[];
  buried: Set<number>;
  hiddenKids: Map<number, number>;
} {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const topOf = new Map<number, number>();
  const buried = new Set<number>();
  const hiddenKids = new Map<number, number>();
  for (const n of nodes) {
    const parent = n.parent === -1 ? undefined : byId.get(n.parent);
    if (!parent) continue;
    const top = topOf.get(parent.id) ?? (parent.hidden ? parent.id : undefined);
    if (top !== undefined) {
      topOf.set(n.id, top);
      buried.add(n.id);
      hiddenKids.set(top, (hiddenKids.get(top) ?? 0) + 1);
    }
  }
  return { visible: nodes.filter((n) => !buried.has(n.id)), buried, hiddenKids };
}

export function layoutMap(doc: DocView): Layout {
  const nodes = doc.nodes;
  const { visible, buried, hiddenKids } = collapseHidden(nodes);
  const rowsOf = cardRows(doc, buried);
  const sizes = new Map<number, { w: number; h: number }>();
  for (const n of visible) {
    sizes.set(n.id, nodeSize(n, rowsOf.get(n.id)!, hiddenKids.get(n.id) ?? 0));
  }

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
  const root = tops.find((n) => n.depth === 1) ?? null;
  const boxes = new Map<number, Box>();
  const subH = new Map<number, number>();

  const stackH = (kids: NodeInfo[]): number => {
    let sum = 0;
    for (let i = 0; i < kids.length; i++) sum += (subH.get(kids[i].id) ?? 0) + gapBefore(i);
    return sum;
  };

  const measureTree = (n: NodeInfo): number => {
    const kids = children.get(n.id) ?? [];
    for (const child of kids) measureTree(child);
    const height = Math.max(sizes.get(n.id)!.h, kids.length === 0 ? 0 : stackH(kids));
    subH.set(n.id, height);
    return height;
  };

  const place = (n: NodeInfo, left: number, top: number): number => {
    const size = sizes.get(n.id)!;
    const kids = children.get(n.id) ?? [];
    let centerY: number;
    if (kids.length === 0) {
      centerY = top + size.h / 2;
    } else {
      let y = top + Math.max(0, (size.h - stackH(kids)) / 2);
      const centers: number[] = [];
      for (let i = 0; i < kids.length; i++) {
        y += gapBefore(i);
        centers.push(place(kids[i], left + size.w + GAP.x, y));
        y += subH.get(kids[i].id)!;
      }
      centerY = (centers[0] + centers[centers.length - 1]) / 2;
    }
    boxes.set(n.id, {
      n,
      x: left,
      y: centerY - size.h / 2,
      w: size.w,
      h: size.h,
      rows: rowsOf.get(n.id)!,
    });
    return centerY;
  };

  if (root) {
    measureTree(root);
    place(root, 0, -subH.get(root.id)! / 2);
  }

  let bottom = 0;
  for (const box of boxes.values()) bottom = Math.max(bottom, box.y + box.h);
  let top = boxes.size > 0 ? bottom + GAP.root * 2 : 0;
  for (const tree of tops) {
    if (tree === root) continue;
    measureTree(tree);
    place(tree, 0, top);
    top += subH.get(tree.id)! + GAP.root;
  }

  const parentOf = new Map<number, number>();
  const fanOf = new Map<number, number>();
  for (const n of visible) {
    if (n.parent !== -1 && boxes.has(n.parent) && boxes.has(n.id)) parentOf.set(n.id, n.parent);
  }
  const fans = new Map<number, NodeInfo[]>();
  for (const n of visible) {
    if (!parentOf.has(n.id)) continue;
    const list = fans.get(n.parent);
    if (list) list.push(n);
    else fans.set(n.parent, [n]);
  }
  const centerY = (id: number): number => {
    const b = boxes.get(id)!;
    return b.y + b.h / 2;
  };
  for (const list of fans.values()) {
    if (list.length < 2) continue;
    const band = boxes.get(list[0].parent)!.h * FAN_BAND;
    const sorted = [...list].sort((a, b) => centerY(a.id) - centerY(b.id));
    for (let i = 0; i < sorted.length; i++) {
      fanOf.set(sorted[i].id, ((i + 0.5) / sorted.length - 0.5) * band);
    }
  }

  return {
    visible,
    order: visible.map((n) => n.id),
    boxes,
    parentOf,
    hiddenKids,
    fanOf,
  };
}

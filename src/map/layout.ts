// ノード木 → 箱の配置。DOM を知らない純粋なレイアウト層。
//
// 古典的なツリーレイアウトをフレーム（u = 成長軸、v = 兄弟軸）の上で行う。
// フレームは右と左の 2 つしか無いので、投影は常に正確な箱の寸法になる。
//
// 入口は layoutMap(nodes, doc) の 1 つ。折り畳みの解決 → カード行の抽出 →
// 寸法 → 配置 → 付け根の帯、までを済ませ、描画層（mindmap.ts）は
// この結果を DOM に写すだけにする。

import type { NodeInfo } from "../coreApi.ts";
import { type Frame, F_RIGHT, F_LEFT, vOf, centerOf } from "./geometry.ts";
import { EDGE } from "./edge.ts";
import { type CardRow, cardRows } from "./cards.ts";
import { nodeSize } from "./metrics.ts";

/**
 * ノード同士の間隔。ドロップ判定や ＋ボタンの位置もここを見るので、
 * 数字を散らさず 1 か所に集めてある。
 */
export const GAP = {
  x: 45, // 親と子の横の間隔
  y: 10, // 兄弟どうしの縦の間隔
  root: 34, // 別ツリー（# より前のノード）どうしの間隔
};

export interface Box {
  n: NodeInfo;
  x: number;
  y: number; // top-left of box
  w: number;
  h: number;
  rows: CardRow[]; // card rows from the attached content
}

export interface Layout {
  /** 描かれるノード（折り畳まれた子孫を除いた文書順） */
  visible: NodeInfo[];
  order: number[]; // visible の id
  boxes: Map<number, Box>;
  sideOf: Map<number, -1 | 0 | 1>; // -1 left, 0 root, 1 right
  frameOf: Map<number, Frame>; // layout frame (not on root)
  parentOf: Map<number, number>; // エッジを持つノード → 親（線の判定用）
  rootId: number; // 主ルート（最初の深さ1）。-1 = 無い
  underRoot: Set<number>; // 主ルートの子孫（別ツリーを除く）
  hiddenKids: Map<number, number>; // 折り畳んだ子孫の数（バッジ用）
  fanOf: Map<number, number>; // 子 id → 付け根のずらし量(px)
}

/** 兄弟 i の手前に挟む間隔（唯一の定義）。`---` は左右を分けるだけで、
 * 同じ側に並んだノードは 1 つの列 — 区切りを跨いでも間隔は変わらない */
const gapBefore = (_kids: NodeInfo[], i: number): number => (i === 0 ? 0 : GAP.y);

/**
 * hidden = 折り畳み (mmm.md その３): hidden なノード自身は小さく描かれ、
 * その子孫は地図から丸ごと消える。領域の一番外側の hidden だけが描かれる。
 */
function collapseHidden(nodes: NodeInfo[]): {
  visible: NodeInfo[];
  buried: Set<number>;
  hiddenKids: Map<number, number>;
} {
  // nodes は文書順（親が子より先）なので、祖先チェインを毎ノードごとに
  // 根まで遡らずに済む。topOf[id] = そのノードより上にある「最も外側の
  // hidden 祖先」の id（無ければ未設定）— 親の topOf をそのまま受け継ぐ
  // だけで、深いツリーでも 1 ノードあたり O(1) になる。
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const topOf = new Map<number, number>();
  const buried = new Set<number>();
  const hiddenKids = new Map<number, number>(); // 折り畳んだ子孫の数
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

export function layoutMap(nodes: NodeInfo[], doc: string): Layout {
  const { visible, buried, hiddenKids } = collapseHidden(nodes);

  // カード行と寸法は最初に 1 回だけ決める。以前は widthOf/heightOf が
  // レイアウト中に 1 ノードあたり 4 回ずつ再計算していた
  const rowsOf = cardRows(doc, nodes, buried);
  const sizes = new Map<number, { w: number; h: number }>();
  for (const n of visible) {
    sizes.set(n.id, nodeSize(n, rowsOf.get(n.id)!, hiddenKids.get(n.id) ?? 0));
  }

  // children lists in document order (collapsed subtrees excluded)
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
  const sideOf = new Map<number, -1 | 0 | 1>();
  const frameOf = new Map<number, Frame>();

  // フレームへ投影した箱の辺の長さ（フレームは軸平行なので絶対値で足りる）
  const effU = (n: NodeInfo, f: Frame): number => {
    const s = sizes.get(n.id)!;
    return s.w * Math.abs(f.ux) + s.h * Math.abs(f.uy);
  };
  const effV = (n: NodeInfo, f: Frame): number => {
    const s = sizes.get(n.id)!;
    return s.w * Math.abs(f.vx) + s.h * Math.abs(f.vy);
  };

  const subV = new Map<number, number>(); // 部分木が兄弟軸に占める長さ
  const stackV = (kids: NodeInfo[]): number => {
    let sum = 0;
    for (let i = 0; i < kids.length; i++) {
      sum += (subV.get(kids[i].id) ?? 0) + gapBefore(kids, i);
    }
    return sum;
  };
  const calcV = (n: NodeInfo, f: Frame): number => {
    const kids = children.get(n.id) ?? [];
    let v = effV(n, f);
    if (kids.length > 0) {
      for (const c of kids) calcV(c, f);
      v = Math.max(v, stackV(kids));
    }
    subV.set(n.id, v);
    return v;
  };
  // place n with its near edge at `edge` (along u) and its subtree slot
  // starting at `top` (along v); returns the node's center on the v axis
  const placeF = (n: NodeInfo, f: Frame, edge: number, top: number): number => {
    const eu = effU(n, f);
    const ev = effV(n, f);
    const kids = children.get(n.id) ?? [];
    let clv: number;
    if (kids.length === 0) {
      clv = top + ev / 2;
    } else {
      // when the children stack is narrower than the node itself, center
      // the children inside the node's slot — otherwise centering the
      // node over its children would push it out of its reserved space
      // and into the previous sibling
      let t = top + Math.max(0, (ev - stackV(kids)) / 2);
      const childEdge = edge + eu + GAP.x;
      const centers: number[] = [];
      for (let i = 0; i < kids.length; i++) {
        t += gapBefore(kids, i);
        centers.push(placeF(kids[i], f, childEdge, t));
        t += subV.get(kids[i].id)!;
      }
      clv = (centers[0] + centers[centers.length - 1]) / 2;
    }
    const lu = edge + eu / 2;
    const cx = lu * f.ux + clv * f.vx;
    const cy = lu * f.uy + clv * f.vy;
    const { w, h } = sizes.get(n.id)!;
    boxes.set(n.id, {
      n,
      x: cx - w / 2,
      y: cy - h / 2,
      w,
      h,
      rows: rowsOf.get(n.id)!,
    });
    sideOf.set(n.id, f.ux < -1e-6 ? -1 : 1);
    frameOf.set(n.id, f);
    return clv;
  };

  if (root) {
    sideOf.set(root.id, 0);
    const { w: rw, h: rh } = sizes.get(root.id)!;
    boxes.set(root.id, {
      n: root,
      x: -rw / 2,
      y: -rh / 2,
      w: rw,
      h: rh,
      rows: rowsOf.get(root.id)!,
    });
    const kidsAll = children.get(root.id) ?? [];
    // `---` は「そこから下の左右が入れ替わる」印。group は「その位置より
    // 前にある有効な区切りの本数」なので、偶数なら右、奇数なら左。
    // マップの操作はこの並びを乱さない局所編集しかしない（core/seps.mbt）。
    const rightKids = kidsAll.filter((c) => c.group % 2 === 0);
    const leftKids = kidsAll.filter((c) => c.group % 2 !== 0);
    const placeSide = (list: NodeInfo[], f: Frame): void => {
      if (list.length === 0) return;
      for (const m of list) calcV(m, f);
      const edge0 = rw / 2 + GAP.x;
      let t = -stackV(list) / 2;
      const before = boxes.size;
      for (let i = 0; i < list.length; i++) {
        t += gapBefore(list, i);
        placeF(list[i], f, edge0, t);
        t += subV.get(list[i].id)!;
      }
      // align the side on its MEMBER boxes (the same "parent centered
      // over children" rule placeF uses), so first-level nodes hug the
      // root's height
      const ids = [...boxes.keys()].slice(before);
      const cF = centerOf(boxes.get(list[0].id)!);
      const cL = centerOf(boxes.get(list[list.length - 1].id)!);
      const mid = (cF.y + cL.y) / 2;
      if (mid !== 0) {
        for (const id of ids) boxes.get(id)!.y -= mid;
      }
    };
    placeSide(rightKids, F_RIGHT);
    placeSide(leftKids, F_LEFT);
  }
  // separate trees (e.g. nodes written before the root): stacked below
  let maxBottom = 0;
  for (const b of boxes.values()) {
    maxBottom = Math.max(maxBottom, b.y + b.h);
  }
  // 主ツリーの直後だけ隙間を GAP.root の 2 倍取り、「別ツリーの並び」だと
  // 一目で分かるようにする。別ツリー同士は GAP.root のまま詰める
  const FIRST_SEPARATE_TREE_GAP = GAP.root * 2;
  let top = boxes.size > 0 ? maxBottom + FIRST_SEPARATE_TREE_GAP : 0;
  for (const r of tops) {
    if (r === root) continue;
    calcV(r, F_RIGHT);
    placeF(r, F_RIGHT, 0, top);
    top += subV.get(r.id)! + GAP.root;
  }

  // 主ルートの子孫だけを集めておく。`#` より前に書かれたノードや
  // 2 つ目以降の `#` は別ツリーで、下部に積まれるだけなのに
  // sideOf には右(1)が入る。区間の範囲計算に混ぜると、区切り線の位置や
  // 長さが画面下の別ツリーに引っ張られる
  const underRoot = new Set<number>();
  if (root) {
    underRoot.add(root.id);
    for (const n of visible) {
      if (n.parent !== -1 && underRoot.has(n.parent)) underRoot.add(n.id);
    }
  }

  // ---- 付け根の帯 ----
  // 親から出る線の付け根を、1 点ではなく帯の中に振り分ける。同じ親でも
  // 右へ伸びる子と左へ伸びる子は別の扇なので、辺ごとに分ける。
  // 兄弟軸の位置で並べてから割り当てると、線同士が交差しない。
  const parentOf = new Map<number, number>();
  const fanOf = new Map<number, number>();
  for (const n of visible) {
    if (n.parent !== -1 && boxes.has(n.parent) && boxes.has(n.id)) {
      parentOf.set(n.id, n.parent);
    }
  }
  if (EDGE.spread > 0) {
    const fans = new Map<string, NodeInfo[]>();
    for (const n of visible) {
      if (!parentOf.has(n.id)) continue;
      const key = `${n.parent}|${sideOf.get(n.id) ?? 0}`;
      const list = fans.get(key);
      if (list) list.push(n);
      else fans.set(key, [n]);
    }
    for (const list of fans.values()) {
      if (list.length < 2) continue;
      const p = boxes.get(list[0].parent)!;
      const f = frameOf.get(list[0].id) ?? F_RIGHT;
      const sorted = [...list].sort(
        (a, b) => vOf(boxes.get(a.id)!, f) - vOf(boxes.get(b.id)!, f),
      );
      // 帯の幅は親の高さの spread 倍。辺からはみ出さないので付け根は必ず親の上
      const band = p.h * Math.min(1, EDGE.spread);
      for (let i = 0; i < sorted.length; i++) {
        fanOf.set(sorted[i].id, ((i + 0.5) / sorted.length - 0.5) * band);
      }
    }
  }

  return {
    visible,
    order: visible.map((n) => n.id),
    boxes,
    sideOf,
    frameOf,
    parentOf,
    rootId: root?.id ?? -1,
    underRoot,
    hiddenKids,
    fanOf,
  };
}

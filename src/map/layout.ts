// View → 箱の配置。DOM を知らない純粋なレイアウト層。
//
// core の木をそのまま歩き、幾何（x/y/w/h）と、畳みで埋もれた子孫の数と、
// 中身から組んだカード行だけを足す。構造は core の語（node / side）のまま読み、
// 言い換えない。寸法は `sizeOf` で外から受ける — 文字の実測は DOM の仕事で、
// ここは数だけを扱う（試験も数だけで書ける）。
//
// すべての木は根から左右へ伸びる。側を持つのは根の子だけ（`sides` と並走）で、
// 孫から下は親の側を継ぐ。グループという概念は無い — 側ごとに 1 列積むだけ。

import type * as core from "../coreApi.ts";
import { type CardRow, cardRows } from "./cards.ts";
import { type Pt, type Rect, dirOf, entryEdgeOf, growthEdgeOf } from "./geometry.ts";
import { ROW_NORMAL, cardBleed, cardInset, rowH, rowTop } from "./metrics.ts";

export const GAP = {
  x: 45,
  y: 10,
  /** 木と木の間 */
  root: 34,
};

/**
 * 親の辺のうち、何割を「付け根の帯」に使うか。子が複数あるとき、線の出口を
 * この帯の中に配って重なりを解く。
 */
const FAN_BAND = 0.6;

/** 親との繋がり。側は繋がりの性質なのでここに乗る（根は繋がりを持たない） */
export interface Edge {
  id: number;
  side: core.Side;
}

export interface Box {
  /** View のノードそのまま。label / fold / blocks はここから読む */
  node: core.Node;
  parent: Edge | null;
  /** 畳んで埋もれた子孫の数（全部の子孫。種類で除かない） */
  buried: number;
  /** 親の辺の上での、付け根のずらし量(px)。兄弟と出口が重ならないように */
  fan: number;
  x: number;
  y: number;
  w: number;
  h: number;
  /** node.blocks から組んだもの。寸法に要るので持つ */
  rows: CardRow[];
}

export interface Layout {
  /** 描くノードの id、文書順（= 重なり順）。畳まれて埋もれたものは入らない */
  order: number[];
  boxes: Map<number, Box>;
}

export interface Size {
  w: number;
  h: number;
}

/** ノードの箱の大きさを答えるもの。実体は metrics.nodeSize */
export type SizeOf = (node: core.Node, rows: CardRow[], buried: number) => Size;

/**
 * カード 1 行の中身を置く矩形（**箱の左上から見た座標**）。
 * 描くのも書き出すのも、必ずここを通る — 積み方を 2 か所で数えない。
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

/** その中身（ブロック id）を持つ箱と、その行の番号。畳まれて箱が無ければ null */
export function ownerOf(L: Layout, block: number): { box: Box; index: number } | null {
  for (const box of L.boxes.values()) {
    const index = box.node.blocks.findIndex((x) => x.id === block);
    if (index !== -1) return { box, index };
  }
  return null;
}

/** 最初の木の根。無ければ null（空文書） */
export function rootBox(L: Layout): Box | null {
  for (const id of L.order) {
    const b = L.boxes.get(id);
    if (b && b.parent === null) return b;
  }
  return null;
}

const gapBefore = (i: number): number => (i === 0 ? 0 : GAP.y);

/** 子孫の数 */
function descendants(n: core.Node): number {
  let c = 0;
  for (const k of n.children) c += 1 + descendants(k);
  return c;
}

const SIDES: readonly core.Side[] = ["Right", "Left"];

export function layoutMap(trees: core.Tree[], sizeOf: SizeOf): Layout {
  const boxes = new Map<number, Box>();
  const order: number[] = [];

  /** 見えている子。畳んだノードの下は無い — 畳みの裁定はここ 1 つ */
  const kidsOf = (n: core.Node): core.Node[] => (n.fold === null ? n.children : []);

  // ノードごとの、木から決まるもの。要るときに数えて覚える（鍵はノードの参照。
  // id を介さないので「必ず在るはず」を言わなくてよい）
  interface Twig {
    rows: CardRow[];
    buried: number;
    size: Size;
  }
  const twigs = new Map<core.Node, Twig>();
  const twigOf = (n: core.Node): Twig => {
    const hit = twigs.get(n);
    if (hit) return hit;
    const folded = n.fold !== null;
    const rows = folded ? [] : cardRows(n.blocks);
    const buried = folded ? descendants(n) : 0;
    const t = { rows, buried, size: sizeOf(n, rows, buried) };
    twigs.set(n, t);
    return t;
  };

  /**
   * その部分木が縦に占める帯の高さ `h` と、**その帯の上端から見た自分の箱の
   * 中心** `anchor`。
   *
   * 親の中心は「第 1 子と最終子の中心の中点」で決める。この中点は帯の幾何学的な
   * 中心とは限らないので、帯のほうを中心に合わせて広げる（箱が帯からはみ出して
   * 隣の兄弟を覆わないように）。
   */
  const metrics = new Map<core.Node, { h: number; anchor: number }>();
  const metricsOf = (n: core.Node): { h: number; anchor: number } => {
    const hit = metrics.get(n);
    if (hit) return hit;
    const { size } = twigOf(n);
    const kids = kidsOf(n);
    let m: { h: number; anchor: number };
    if (kids.length === 0) {
      m = { h: size.h, anchor: size.h / 2 };
    } else {
      const mid = stackCenter(kids);
      const slide = Math.max(0, size.h / 2 - mid);
      const anchor = slide + mid;
      m = { h: Math.max(slide + stackH(kids), anchor + size.h / 2), anchor };
    }
    metrics.set(n, m);
    return m;
  };

  const heightOf = (n: core.Node): number => metricsOf(n).h;

  /** 子を 0 から積んだときの「第 1 子と最終子の中心の中点」 */
  function stackCenter(kids: core.Node[]): number {
    let y = 0;
    const centers: number[] = [];
    for (let i = 0; i < kids.length; i++) {
      y += gapBefore(i);
      centers.push(y + metricsOf(kids[i]).anchor);
      y += metricsOf(kids[i]).h;
    }
    return (centers[0] + centers[centers.length - 1]) / 2;
  }

  /** 子の山を、その部分木の帯の上端から何 px 下に置くか */
  const slideOf = (n: core.Node): number => metricsOf(n).anchor - stackCenter(kidsOf(n));

  /** 子を縦に積んだときの高さ（あいだの隙間込み） */
  function stackH(kids: core.Node[]): number {
    let sum = 0;
    for (let i = 0; i < kids.length; i++) sum += heightOf(kids[i]) + gapBefore(i);
    return sum;
  }

  /**
   * 枝を置く。`nearX` は**親と向かい合う辺**の x（右向きなら箱の左辺、
   * 左向きなら右辺）。左右で式を分けないための座標。返すのは箱の中心の y。
   */
  const place = (n: core.Node, parent: Edge, nearX: number, top: number): number => {
    const dir = dirOf(parent.side);
    const { size, rows, buried } = twigOf(n);
    const x = dir === 1 ? nearX : nearX - size.w;
    const kids = kidsOf(n);
    let centerY: number;
    if (kids.length === 0) {
      centerY = top + size.h / 2;
    } else {
      // 子の山の置き所は `metricsOf` が決めた `slide` から取る（同じ式を 2 か所に持たない）
      let y = top + slideOf(n);
      const childNear = dir === 1 ? x + size.w + GAP.x : x - GAP.x;
      const centers: number[] = [];
      for (let i = 0; i < kids.length; i++) {
        y += gapBefore(i);
        centers.push(place(kids[i], { id: n.id, side: parent.side }, childNear, y));
        y += heightOf(kids[i]);
      }
      centerY = (centers[0] + centers[centers.length - 1]) / 2;
    }
    boxes.set(n.id, {
      node: n,
      parent,
      buried,
      fan: 0,
      x,
      y: centerY - size.h / 2,
      w: size.w,
      h: size.h,
      rows,
    });
    return centerY;
  };

  /** その枝と子孫すべての箱を縦にずらす。側を根の中心へ揃えるため */
  const shiftSubtree = (n: core.Node, dy: number): void => {
    const b = boxes.get(n.id);
    if (b) b.y += dy;
    for (const k of kidsOf(n)) shiftSubtree(k, dy);
  };

  /** 根の子を側ごとに分ける。**sides を読むのはここだけ。** 足りなければ右 */
  const splitSides = (t: core.Tree): Record<core.Side, core.Node[]> => {
    const out: Record<core.Side, core.Node[]> = { Right: [], Left: [] };
    kidsOf(t.node).forEach((k, i) => out[t.sides[i] ?? "Right"].push(k));
    return out;
  };

  /**
   * 木を 1 本置く。側は根の子にしか無いので、根の子だけがここを通り、孫から
   * 下は `place` が面倒を見る。
   *
   * **不変条件: どの側も、第 1 子と最終子の中心の中点が根の中心に乗る。**
   * 根の中心は右の枝に合わせ（右が無ければ左）、もう一方の側はその中心へ
   * まとめてずらす。
   */
  const placeTree = (
    t: core.Tree,
    top: number,
  ): { top: number; bottom: number; shift: (dy: number) => void } => {
    const root = t.node;
    const { size, rows, buried } = twigOf(root);
    const sides = splitSides(t);
    const span = Math.max(size.h, stackH(sides.Right), stackH(sides.Left));
    let centerY = top + span / 2;
    const placed: { kids: core.Node[]; centers: number[]; y0: number; h: number }[] = [];
    for (const side of SIDES) {
      const kids = sides[side];
      if (kids.length === 0) continue;
      const dir = dirOf(side);
      const nearX = dir === 1 ? size.w + GAP.x : -GAP.x;
      const h = stackH(kids);
      const y0 = top + Math.max(0, (span - h) / 2);
      let y = y0;
      const centers: number[] = [];
      for (let i = 0; i < kids.length; i++) {
        y += gapBefore(i);
        centers.push(place(kids[i], { id: root.id, side }, nearX, y));
        y += heightOf(kids[i]);
      }
      placed.push({ kids, centers, y0, h });
      if (side === "Right" || sides.Right.length === 0) {
        centerY = (centers[0] + centers[centers.length - 1]) / 2;
      }
    }
    for (const p of placed) {
      const mid = (p.centers[0] + p.centers[p.centers.length - 1]) / 2;
      const dy = centerY - mid;
      if (dy === 0) continue;
      for (const k of p.kids) shiftSubtree(k, dy);
      p.y0 += dy;
    }
    boxes.set(root.id, {
      node: root,
      parent: null,
      buried,
      fan: 0,
      x: 0,
      y: centerY - size.h / 2,
      w: size.w,
      h: size.h,
      rows,
    });
    // 実際に占めた縦の範囲。ずらしたぶん見積もり（span）を超えうるので、
    // 木を積む側はこれを見る。上へもはみ出しうるので上端も返す
    let lo = centerY - size.h / 2;
    let hi = centerY + size.h / 2;
    for (const p of placed) {
      lo = Math.min(lo, p.y0);
      hi = Math.max(hi, p.y0 + p.h);
    }
    return {
      top: lo,
      bottom: hi,
      shift: (dy) => {
        if (dy !== 0) shiftSubtree(root, dy);
      },
    };
  };

  /** 文書順に並べる（親が先） */
  const walk = (n: core.Node): void => {
    order.push(n.id);
    for (const k of kidsOf(n)) walk(k);
  };

  let top = 0;
  for (const t of trees) {
    const put = placeTree(t, top);
    // 上へはみ出したぶんは押し下げて、頼んだ位置から始まるようにする
    const up = Math.max(0, top - put.top);
    put.shift(up);
    top = put.bottom + up + GAP.root;
    walk(t.node);
  }

  // 付け根をずらすのは「**同じ辺から**出る線が 2 本以上」あるときだけ。
  // 根は左右の両辺から線を出す唯一のノードなので、親 id だけでなく側でまとめる
  const fans = new Map<string, { parent: Box; kids: Box[] }>();
  for (const b of boxes.values()) {
    if (b.parent === null) continue;
    const parent = boxes.get(b.parent.id);
    if (!parent) continue;
    const key = `${b.parent.id},${b.parent.side}`;
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
      sorted[i].fan = ((i + 0.5) / sorted.length - 0.5) * band;
    }
  }

  return { order, boxes };
}

/**
 * 子 id から、その親へ引く線の両端（付け根のずらしも込み）。
 * **描画も書き出しもここだけを見る。**
 */
export function edgeEnds(L: Layout, id: number): { from: Pt; to: Pt } | null {
  const b = L.boxes.get(id);
  if (!b || b.parent === null) return null;
  const p = L.boxes.get(b.parent.id);
  if (!p) return null;
  // 線は「親の、子が伸びる側の辺」から出て「子の、親を向いた辺」へ入る
  const dir = dirOf(b.parent.side);
  const out = growthEdgeOf(p, dir);
  const into = entryEdgeOf(b, dir);
  return { from: { x: out.x, y: out.y + b.fan }, to: into };
}

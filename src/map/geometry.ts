// マップの座標系。DOM を知らない数学だけの層。

export interface Pt {
  x: number;
  y: number;
}

/** 位置と大きさだけの箱（レイアウトの結果もドロップ判定もこれで話す） */
export interface Rect {
  x: number;
  y: number; // top-left
  w: number;
  h: number;
}

/** d 属性を短く保つための丸め（見た目は変わらない） */
export const round2 = (v: number): number => Math.round(v * 100) / 100;

/** 箱の中心 */
export const centerOf = (b: Rect): Pt => ({ x: b.x + b.w / 2, y: b.y + b.h / 2 });

// 箱の左右の辺の中点。線が箱に触れるのはここだけで、任意方向へ出る一般形は
// 要らない。**どちらの辺が「子へ出る」役でどちらが「親から入る」役かは、
// その枝の向き（dirOf）で決まる** — 右の枝ならこの並びのまま、左の枝なら逆になる。

/** 右辺の中点 */
export const rightOf = (b: Rect): Pt => ({ x: b.x + b.w, y: b.y + b.h / 2 });

/** 左辺の中点 */
export const leftOf = (b: Rect): Pt => ({ x: b.x, y: b.y + b.h / 2 });

// dir（右 = 1 / 左 = -1）を受けて左右どちらの辺を使うか決める箇所は、
// 育つ辺と入る辺のこの 2 つだけにする。**鏡映（左右の入れ替え）を書いていいのはここだけ**
// — 呼び出し側は「育つ辺」「入る辺」としか言わない。

/** 箱から、その枝が dir 方向へ**育っていく**辺の中点 */
export const growthEdgeOf = (b: Rect, dir: 1 | -1): Pt =>
  dir === 1 ? rightOf(b) : leftOf(b);

/** 箱へ、dir 方向の枝が**入ってくる**辺の中点（`growthEdgeOf` の反対側） */
export const entryEdgeOf = (b: Rect, dir: 1 | -1): Pt =>
  dir === 1 ? leftOf(b) : rightOf(b);

/** 点 p から線分 ab までの距離 */
export function distToSeg(p: Pt, a: Pt, b: Pt): number {
  const vx = b.x - a.x;
  const vy = b.y - a.y;
  const len2 = vx * vx + vy * vy;
  const t =
    len2 === 0
      ? 0
      : Math.max(0, Math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2));
  return Math.hypot(p.x - (a.x + vx * t), p.y - (a.y + vy * t));
}

/** 折れ線の、長さで測った真ん中の点。見た目の中央と一致する */
export function midOfPolyline(pts: Pt[]): Pt {
  let total = 0;
  for (let i = 1; i < pts.length; i++) {
    total += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
  }
  let acc = 0;
  for (let i = 1; i < pts.length; i++) {
    const seg = Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
    if (acc + seg >= total / 2) {
      const t = seg === 0 ? 0 : (total / 2 - acc) / seg;
      return {
        x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
        y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t,
      };
    }
    acc += seg;
  }
  return pts[pts.length - 1];
}

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

// 木は左から右へ伸びる。線が箱に触れるのは左右の辺の中点だけで、
// 任意方向へ出る一般形は左右振り分けを持っていた頃の名残だった。

/** 右辺の中点。子への線・`+` ボタンはここから出る */
export const rightOf = (b: Rect): Pt => ({ x: b.x + b.w, y: b.y + b.h / 2 });

/** 左辺の中点。親からの線はここへ入る */
export const leftOf = (b: Rect): Pt => ({ x: b.x, y: b.y + b.h / 2 });

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

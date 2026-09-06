// マップの座標系のうち、入力側（選択・落とし先・視点）が使う算術。DOM を知らない。
// 配置と線の形は core/map（geometry.mbt / layout.mbt / edge.mbt）。

import type * as core from "../coreApi.ts";

/** 側 → 伸びる向き（右 = 1 / 左 = -1）。**側を符号にするのは ts ではここだけ** */
export const dirOf = (side: core.Side): 1 | -1 => (side === "Left" ? -1 : 1);

export interface Pt {
  x: number;
  y: number;
}

/** 位置と大きさだけの箱。core の語（Layout の箱とカードの矩形がこの形） */
export type Rect = core.Rect;

/** 箱の中心 */
export const centerOf = (b: Rect): Pt => ({ x: b.x + b.w / 2, y: b.y + b.h / 2 });

/** 複数の箱を包む最小の箱。1 つも無ければ null。 */
export function unionRect(boxes: Iterable<Rect>): Rect | null {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  let any = false;
  for (const b of boxes) {
    any = true;
    x0 = Math.min(x0, b.x);
    y0 = Math.min(y0, b.y);
    x1 = Math.max(x1, b.x + b.w);
    y1 = Math.max(y1, b.y + b.h);
  }
  return any ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : null;
}

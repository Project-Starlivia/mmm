// 画面外にある対象を、控えめな針で指す。DOM を知らない計算だけの層。
//
// 何を指すか（選択の外接箱 / 無ければルート）と、表示するかどうか（対象が
// 画面内かではなく「選択のどれかが見えているか」「文書のどれかが見えて
// いるか」）は呼び出し側が決める — ここは「指すとしたら画面のどこか」だけを持つ。

import type { Rect } from "./geometry.ts";
import type { Pane, View } from "./view.ts";

export interface Indicator {
  x: number; // 画面 px
  y: number;
  angle: number; // 度。ペイン中心から対象へ向く向き
}

/** 縁からの余白(px)。角ぎりぎりに張り付かせない */
const MARGIN = 20;

const toScreen = (box: Rect, view: View): Rect => ({
  x: box.x * view.k + view.tx,
  y: box.y * view.k + view.ty,
  w: box.w * view.k,
  h: box.h * view.k,
});

/** その箱がペインに少しでも重なっているか */
export function isVisible(box: Rect, view: View, pane: Pane): boolean {
  const s = toScreen(box, view);
  return s.x < pane.width && s.x + s.w > 0 && s.y < pane.height && s.y + s.h > 0;
}

/**
 * 対象を指す針の画面位置と向き。ペイン中心から対象への直線が、
 * 縁の内側(`MARGIN`)と交わる点に置く。
 */
export function indicatorFor(target: Rect, view: View, pane: Pane): Indicator {
  const s = toScreen(target, view);
  const cx = pane.width / 2;
  const cy = pane.height / 2;
  const dx = s.x + s.w / 2 - cx;
  const dy = s.y + s.h / 2 - cy;
  const hw = Math.max(1, cx - MARGIN);
  const hh = Math.max(1, cy - MARGIN);
  const scale =
    dx === 0 && dy === 0
      ? 0
      : Math.min(
          dx === 0 ? Infinity : Math.abs(hw / dx),
          dy === 0 ? Infinity : Math.abs(hh / dy),
        );
  return {
    x: cx + dx * scale,
    y: cy + dy * scale,
    angle: (Math.atan2(dy, dx) * 180) / Math.PI,
  };
}

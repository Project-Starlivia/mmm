// 画面外にある対象を、控えめな針で指す。DOM を知らない計算だけの層。
//
// 何を指すか（`indicatorTarget`）と、指すとしたら画面のどこか
// （`indicatorFor`）の 2 つを持つ。呼び出し側は箱を渡して置くだけ。

import { type Rect, unionRect } from "./geometry.ts";
import type { Pane, Camera } from "./camera.ts";

export interface Indicator {
  x: number; // 画面 px
  y: number;
  angle: number; // 度。ペイン中心から対象へ向く向き
}

/** 縁からの余白(px)。角ぎりぎりに張り付かせない */
const MARGIN = 20;

const toScreen = (box: Rect, cam: Camera): Rect => ({
  x: box.x * cam.k + cam.tx,
  y: box.y * cam.k + cam.ty,
  w: box.w * cam.k,
  h: box.h * cam.k,
});

/** その箱がペインに少しでも重なっているか */
export function isVisible(box: Rect, cam: Camera, pane: Pane): boolean {
  const s = toScreen(box, cam);
  return s.x < pane.width && s.x + s.w > 0 && s.y < pane.height && s.y + s.h > 0;
}

/**
 * 針が指す箱。見失っていなければ null（＝出さない）。
 *
 * 指すのは選択の外接箱、選択が無ければ根。見失ったかの判定は対象そのものが
 * 画面内かではない — 選択があるときは選択のどれか、無いときは文書のどれかが
 * 見えていれば、その人は迷っていない。
 */
export function indicatorTarget(
  boxes: { selection: Rect[]; all: Iterable<Rect>; root: Rect | null },
  cam: Camera,
  pane: Pane,
): Rect | null {
  const chosen = boxes.selection.length > 0;
  const target = chosen ? unionRect(boxes.selection) : boxes.root;
  if (!target) return null;
  for (const b of chosen ? boxes.selection : boxes.all) {
    if (isVisible(b, cam, pane)) return null;
  }
  return target;
}

/**
 * 対象を指す針の画面位置と向き。ペイン中心から対象への直線が、
 * 縁の内側(`MARGIN`)と交わる点に置く。
 */
export function indicatorFor(target: Rect, cam: Camera, pane: Pane): Indicator {
  const s = toScreen(target, cam);
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

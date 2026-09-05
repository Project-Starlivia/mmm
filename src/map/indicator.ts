// 見失った対象を、控えめな針で指す。DOM を知らない計算だけの層。
//
// 見失っているか（`isLost`）・指す先（`nearest`）・置く場所（`indicatorFor`）
// の 3 つを別々に持つ。理由が違うものを 1 つの決めに畳まない。

import type { Rect } from "./geometry.ts";
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

/** その箱たちを見失っているか。1 つでも見えていれば迷っていない */
export function isLost(boxes: Iterable<Rect>, cam: Camera, pane: Pane): boolean {
  for (const b of boxes) if (isVisible(b, cam, pane)) return false;
  return true;
}

/**
 * 画面の中心にいちばん近い箱。1 つも無ければ null。
 *
 * 近さは箱の中心で測る — 針の向きも中心で決めるので、物差しは 1 つで足りる。
 */
export function nearest(boxes: Iterable<Rect>, cam: Camera, pane: Pane): Rect | null {
  const cx = pane.width / 2;
  const cy = pane.height / 2;
  let best: Rect | null = null;
  let least = Infinity;
  for (const b of boxes) {
    const s = toScreen(b, cam);
    const d = (s.x + s.w / 2 - cx) ** 2 + (s.y + s.h / 2 - cy) ** 2;
    if (d < least) {
      least = d;
      best = b;
    }
  }
  return best;
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

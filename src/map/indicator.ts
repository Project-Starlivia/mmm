// 見失った対象を、控えめな針で指す。DOM を知らない計算だけの層。
//
// 指す先（`indicatorTarget`）・出すか（`isLost`）・置く場所（`indicatorFor`）
// の 3 つを別々に持つ。理由が違うものを 1 つの決めに畳まない。

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

/** 針が指す先。選択の外接箱、選択が無ければ根。空の文書なら null */
export function indicatorTarget(selection: Iterable<Rect>, root: Rect | null): Rect | null {
  return unionRect(selection) ?? root;
}

/**
 * その先を見失っているか。針を出すのはこのときだけ。
 *
 * 指す先が画面に被っていれば、指す方角が無い — 只中に居るのだから迷っていない。
 * 目印（選択があれば選択そのもの、無ければ文書のどれか）が見えているときも同じ。
 */
export function isLost(target: Rect, landmarks: Iterable<Rect>, cam: Camera, pane: Pane): boolean {
  if (isVisible(target, cam, pane)) return false;
  for (const b of landmarks) if (isVisible(b, cam, pane)) return false;
  return true;
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

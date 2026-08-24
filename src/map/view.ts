// マップの見え方（world ⇄ 画面）と、その動かし方。DOM を触らない算術だけの層。
//
// パン・ズーム・「見えるところまで寄せる」は、どれも `View` を受け取って
// **新しい `View` を返す**だけにしてある。画面に反映するのは呼び出し側。
// カーソル基点のズームや端寄せは符号を 1 つ間違えても動いてしまい、目でしか
// 気づけないので、値として試験できる形が要る。

import type { Rect } from "./geometry.ts";

/** world → 画面: `screen = world * k + t` */
export interface View {
  k: number;
  tx: number;
  ty: number;
}

/** ペインの大きさ（画面 px） */
export interface Pane {
  width: number;
  height: number;
}

/** 縮小・拡大の限界。これ以上は字も線も意味を失う */
export const MIN_ZOOM = 0.15;
export const MAX_ZOOM = 3;

/** ホイール 1 目盛りあたりの倍率の効き */
const ZOOM_RATE = 0.0022;

/** 画面の点を world に戻す（座標はペインの左上から測ったもの） */
export const toWorld = (view: View, x: number, y: number): { x: number; y: number } => ({
  x: (x - view.tx) / view.k,
  y: (y - view.ty) / view.k,
});

/**
 * カーソルを基点にズームする。**その点の下にある world の位置が動かない**
 * ように平行移動を合わせる — 合わせないと、拡大するたびに見ていた場所が
 * 画面の外へ逃げる。
 */
export function zoomAt(view: View, x: number, y: number, deltaY: number): View {
  const k = Math.min(
    MAX_ZOOM,
    Math.max(MIN_ZOOM, view.k * Math.exp(-deltaY * ZOOM_RATE)),
  );
  const ratio = k / view.k;
  return {
    k,
    tx: x - (x - view.tx) * ratio,
    ty: y - (y - view.ty) * ratio,
  };
}

/** 平行移動だけ（倍率は変えない） */
export const panBy = (view: View, dx: number, dy: number): View => ({
  k: view.k,
  tx: view.tx + dx,
  ty: view.ty + dy,
});

/**
 * その箱が縁から `margin` の内側に入るまで寄せる。**既に見えていれば動かない**
 * — 動く必要が無いのに動くと、キーボードで辿っているとき画面が跳ねる。
 */
export function panToShow(
  view: View,
  box: Rect,
  pane: Pane,
  margin: number,
): View {
  const x = box.x * view.k + view.tx;
  const y = box.y * view.k + view.ty;
  const w = box.w * view.k;
  const h = box.h * view.k;
  let { tx, ty } = view;
  if (x < margin) tx += margin - x;
  else if (x + w > pane.width - margin) tx -= x + w - (pane.width - margin);
  if (y < margin) ty += margin - y;
  else if (y + h > pane.height - margin) ty -= y + h - (pane.height - margin);
  return { k: view.k, tx, ty };
}

/**
 * 全部が入る見え方。**拡大はしない**（1 倍を超えて寄ると、小さい文書ほど
 * 間延びして見える）。箱が無ければ null。
 */
export function fitToPane(
  boxes: Iterable<Rect>,
  pane: Pane,
  margin: number,
): View | null {
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
  if (!any) return null;
  const kx = (pane.width - margin * 2) / Math.max(1, x1 - x0);
  const ky = (pane.height - margin * 2) / Math.max(1, y1 - y0);
  const k = Math.max(MIN_ZOOM, Math.min(1, kx, ky));
  return {
    k,
    tx: pane.width / 2 - ((x0 + x1) / 2) * k,
    ty: pane.height / 2 - ((y0 + y1) / 2) * k,
  };
}

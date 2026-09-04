// マップの見え方（world ⇄ 画面）と、その動かし方。DOM を触らない算術だけの層。
//
// パン・ズーム・「見えるところまで寄せる」は、どれも `Camera` を受け取って
// **新しい `Camera` を返す**だけにしてある。画面に反映するのは呼び出し側。
// カーソル基点のズームや端寄せは符号を 1 つ間違えても動いてしまい、目でしか
// 気づけないので、値として試験できる形が要る。

import { type Pt, type Rect, unionRect } from "./geometry.ts";

/** world → 画面: `screen = world * k + t` */
export interface Camera {
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
export const toWorld = (cam: Camera, x: number, y: number): { x: number; y: number } => ({
  x: (x - cam.tx) / cam.k,
  y: (y - cam.ty) / cam.k,
});

/** 倍率だけを限界に収める */
const clampZoom = (k: number): number =>
  Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, k));

/**
 * その点を基点に、倍率を `k` にする。**その点の下にある world の位置が
 * 動かない**ように平行移動を合わせる — 合わせないと、拡大するたびに
 * 見ていた場所が画面の外へ逃げる。
 */
export function zoomTo(cam: Camera, x: number, y: number, k: number): Camera {
  const next = clampZoom(k);
  const ratio = next / cam.k;
  return {
    k: next,
    tx: x - (x - cam.tx) * ratio,
    ty: y - (y - cam.ty) * ratio,
  };
}

/** ホイールの目盛りを倍率に読み替えて `zoomTo` に渡すだけ */
export const zoomAt = (cam: Camera, x: number, y: number, deltaY: number): Camera =>
  zoomTo(cam, x, y, cam.k * Math.exp(-deltaY * ZOOM_RATE));

/** 平行移動だけ（倍率は変えない） */
export const panBy = (cam: Camera, dx: number, dy: number): Camera => ({
  k: cam.k,
  tx: cam.tx + dx,
  ty: cam.ty + dy,
});

/**
 * その箱が縁から `margin` の内側に入るまで寄せる。**既に見えていれば動かない**
 * — 動く必要が無いのに動くと、キーボードで辿っているとき画面が跳ねる。
 */
export function panToShow(
  cam: Camera,
  box: Rect,
  pane: Pane,
  margin: number,
): Camera {
  const x = box.x * cam.k + cam.tx;
  const y = box.y * cam.k + cam.ty;
  const w = box.w * cam.k;
  const h = box.h * cam.k;
  let { tx, ty } = cam;
  if (x < margin) tx += margin - x;
  else if (x + w > pane.width - margin) tx -= x + w - (pane.width - margin);
  if (y < margin) ty += margin - y;
  else if (y + h > pane.height - margin) ty -= y + h - (pane.height - margin);
  return { k: cam.k, tx, ty };
}

/**
 * 全部が入る見え方。**拡大はしない**（1 倍を超えて寄ると、小さい文書ほど
 * 間延びして見える）。箱が無ければ null。
 */
export function fitToPane(
  boxes: Iterable<Rect>,
  pane: Pane,
  margin: number,
): Camera | null {
  const r = unionRect(boxes);
  if (!r) return null;
  const kx = (pane.width - margin * 2) / Math.max(1, r.w);
  const ky = (pane.height - margin * 2) / Math.max(1, r.h);
  const k = Math.max(MIN_ZOOM, Math.min(1, kx, ky));
  return centerOn({ k, tx: 0, ty: 0 }, r, pane);
}

/** その箱を画面の中心に置く（拡大率は変えない）。 */
export function centerOn(cam: Camera, box: Rect, pane: Pane): Camera {
  const cx = box.x + box.w / 2;
  const cy = box.y + box.h / 2;
  return {
    k: cam.k,
    tx: pane.width / 2 - cx * cam.k,
    ty: pane.height / 2 - cy * cam.k,
  };
}

/** 2 本指の位置（ペインの左上から測った画面 px） */
export interface Span {
  a: Pt;
  b: Pt;
}

const dist = (p: Pt, q: Pt): number => Math.hypot(q.x - p.x, q.y - p.y);
const mid = (p: Pt, q: Pt): Pt => ({ x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 });

/**
 * 2 本指の前後の位置から、見え方を 1 つ出す。
 *
 * **拡大とパンを別々の話にしない** — 指は同時に離れながら動くので、
 * 「中点を基点に倍率を変える」→「中点のずれだけ平行移動する」の 2 つを
 * 順に当てれば、掴んでいた場所は指の下に留まる。
 *
 * 2 本が重なると距離が 0 になる。割ると `Infinity` が倍率へ流れ込み、以降
 * すべての描画が消えるので、そのときは倍率を据え置く。
 */
export function pinch(cam: Camera, from: Span, to: Span): Camera {
  const d0 = dist(from.a, from.b);
  const m0 = mid(from.a, from.b);
  const m1 = mid(to.a, to.b);
  const k = d0 > 0 ? cam.k * (dist(to.a, to.b) / d0) : cam.k;
  return panBy(zoomTo(cam, m0.x, m0.y, k), m1.x - m0.x, m1.y - m0.y);
}

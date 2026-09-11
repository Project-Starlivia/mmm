// マップの視点（world ⇄ 画面）と、その動かし方。DOM を触らない算術だけの層。
//
// `Camera` は world を画面へ写す変換 `screen = world * k + t` の 3 つの数。
// 見えている矩形は `Pane` のほうで、こちらは位置と倍率 — どこをどれだけ拡大して見ているか。
//
// パン・ズーム・「見えるところまで寄せる」は、どれも `Camera` を受け取って
// **新しい `Camera` を返す**だけ。画面に反映するのは呼び出し側。
// カーソル基点のズームや端寄せは符号を 1 つ間違えても動いてしまい、目でしか
// 気づけないので、値として試験できる形が要る。

///|
/// world → 画面: `screen = world * k + t`
pub(all) struct Camera {
  k : Double
  tx : Double
  ty : Double
} derive(Eq, Debug)

///|
/// ペインの大きさ（画面 px）
pub(all) struct Pane {
  width : Double
  height : Double
} derive(Eq, Debug)

///|
/// 縮小・拡大の限界。これ以上は字も線も意味を失う
let min_zoom = 0.15

///|
let max_zoom = 3.0

///|
/// ホイール 1 目盛りあたりの倍率の効き
let zoom_rate = 0.0022

///|
/// 画面の点を world に戻す（座標はペインの左上から測ったもの）
pub fn to_world(cam : Camera, x : Double, y : Double) -> Pt {
  { x: (x - cam.tx) / cam.k, y: (y - cam.ty) / cam.k, }
}

///|
/// world の箱を画面（ペインの左上から測った px）に写す。`to_world` の逆
fn Camera::to_screen(self : Camera, r : Rect) -> Rect {
  {
    x: r.x * self.k + self.tx,
    y: r.y * self.k + self.ty,
    w: r.w * self.k,
    h: r.h * self.k,
  }
}

///|
/// 倍率だけを限界に収める
fn clamp_zoom(k : Double) -> Double {
  @cmp.minimum(max_zoom, @cmp.maximum(min_zoom, k))
}

///|
/// その点を基点に、倍率を `k` にする。**その点の下にある world の位置が
/// 動かない**ように平行移動を合わせる — 合わせないと、拡大するたびに
/// 見ていた場所が画面の外へ逃げる
fn zoom_to(cam : Camera, x : Double, y : Double, k : Double) -> Camera {
  let next = clamp_zoom(k)
  let ratio = next / cam.k
  { k: next, tx: x - (x - cam.tx) * ratio, ty: y - (y - cam.ty) * ratio, }
}

///|
/// ホイールの目盛りを倍率に読み替えて `zoom_to` に渡すだけ
pub fn zoom_at(
  cam : Camera,
  x : Double,
  y : Double,
  delta_y : Double,
) -> Camera {
  zoom_to(cam, x, y, cam.k * @math.exp(-delta_y * zoom_rate))
}

///|
/// 平行移動だけ（倍率は変えない）
pub fn pan_by(cam : Camera, dx : Double, dy : Double) -> Camera {
  { k: cam.k, tx: cam.tx + dx, ty: cam.ty + dy, }
}

///|
/// その箱が縁から `margin` の内側に入るまで寄せる。**既に見えていれば動かない**
/// — 動く必要が無いのに動くと、キーボードで辿っているとき画面が跳ねる
pub fn pan_to_show(
  cam : Camera,
  b : Rect,
  pane : Pane,
  margin : Double,
) -> Camera {
  let s = cam.to_screen(b)
  let mut tx = cam.tx
  let mut ty = cam.ty
  if s.x < margin {
    tx += margin - s.x
  } else if s.x + s.w > pane.width - margin {
    tx -= s.x + s.w - (pane.width - margin)
  }
  if s.y < margin {
    ty += margin - s.y
  } else if s.y + s.h > pane.height - margin {
    ty -= s.y + s.h - (pane.height - margin)
  }
  { k: cam.k, tx, ty, }
}

///|
/// 全部が入る見え方。**拡大はしない**（1 倍を超えて寄ると、小さい文書ほど
/// 間延びして見える）。箱が無ければ None
pub fn fit(boxes : Array[Rect], pane : Pane, margin : Double) -> Camera? {
  guard union(boxes) is Some(r) else { return None }
  let kx = (pane.width - margin * 2.0) / @cmp.maximum(1.0, r.w)
  let ky = (pane.height - margin * 2.0) / @cmp.maximum(1.0, r.h)
  let k = @cmp.maximum(min_zoom, @cmp.minimum(1.0, @cmp.minimum(kx, ky)))
  Some(center_on({ k, tx: 0, ty: 0, }, r, pane))
}

///|
/// その箱を画面の中心に置く（拡大率は変えない）
pub fn center_on(cam : Camera, b : Rect, pane : Pane) -> Camera {
  let c = b.center()
  {
    k: cam.k,
    tx: pane.width / 2.0 - c.x * cam.k,
    ty: pane.height / 2.0 - c.y * cam.k,
  }
}

///|
/// 2 本指の位置（ペインの左上から測った画面 px）
pub(all) struct Span {
  a : Pt
  b : Pt
} derive(Eq, Debug)

///|
fn dist(p : Pt, q : Pt) -> Double {
  @math.hypot(q.x - p.x, q.y - p.y)
}

///|
fn mid(p : Pt, q : Pt) -> Pt {
  { x: (p.x + q.x) / 2.0, y: (p.y + q.y) / 2.0, }
}

///|
/// 2 本指の前後の位置から、見え方を 1 つ出す。
///
/// **拡大とパンを別々の話にしない** — 指は同時に離れながら動くので、
/// 「中点を基点に倍率を変える」→「中点のずれだけ平行移動する」の 2 つを
/// 順に当てれば、掴んでいた場所は指の下に留まる。
///
/// 2 本が重なると距離が 0 になる。割ると無限大が倍率へ流れ込み、以降
/// すべての描画が消えるので、そのときは倍率を据え置く
pub fn pinch(cam : Camera, from : Span, to : Span) -> Camera {
  let d0 = dist(from.a, from.b)
  let m0 = mid(from.a, from.b)
  let m1 = mid(to.a, to.b)
  let k = if d0 > 0.0 { cam.k * (dist(to.a, to.b) / d0) } else { cam.k }
  pan_by(zoom_to(cam, m0.x, m0.y, k), m1.x - m0.x, m1.y - m0.y)
}

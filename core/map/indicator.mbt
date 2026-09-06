// 見失った対象を、控えめな針で指す。DOM を知らない計算だけの層。
//
// 見失っているか（`is_lost`）・指す先（`nearest`）・置く場所（`indicator_for`）
// の 3 つを別々に持つ。理由が違うものを 1 つの決めに畳まない。

///|
/// 針の画面位置（px）と向き（度。ペイン中心から対象へ向く向き）
pub(all) struct Indicator {
  x : Double
  y : Double
  angle : Double
} derive(Eq, Debug)

///|
/// 縁からの余白(px)。角ぎりぎりに張り付かせない
let indicator_margin = 20.0

///|
fn to_screen(b : Rect, cam : Camera) -> Rect {
  {
    x: b.x * cam.k + cam.tx,
    y: b.y * cam.k + cam.ty,
    w: b.w * cam.k,
    h: b.h * cam.k,
  }
}

///|
/// その箱がペインに少しでも重なっているか
pub fn is_visible(b : Rect, cam : Camera, pane : Pane) -> Bool {
  let s = to_screen(b, cam)
  s.x < pane.width && s.x + s.w > 0.0 && s.y < pane.height && s.y + s.h > 0.0
}

///|
/// その箱たちを見失っているか。1 つでも見えていれば迷っていない
pub fn is_lost(boxes : Array[Rect], cam : Camera, pane : Pane) -> Bool {
  for b in boxes {
    if is_visible(b, cam, pane) {
      return false
    }
  }
  true
}

///|
/// 画面の中心にいちばん近い箱。1 つも無ければ None。
/// 近さは箱の中心で測る — 針の向きも中心で決めるので、物差しは 1 つで足りる
pub fn nearest(boxes : Array[Rect], cam : Camera, pane : Pane) -> Rect? {
  let cx = pane.width / 2.0
  let cy = pane.height / 2.0
  let mut best : Rect? = None
  let mut least = @double.infinity
  for b in boxes {
    let s = to_screen(b, cam)
    let dx = s.x + s.w / 2.0 - cx
    let dy = s.y + s.h / 2.0 - cy
    let d = dx * dx + dy * dy
    if d < least {
      least = d
      best = Some(b)
    }
  }
  best
}

///|
/// 対象を指す針の画面位置と向き。ペイン中心から対象への直線が、
/// 縁の内側（`indicator_margin`）と交わる点に置く
pub fn indicator_for(target : Rect, cam : Camera, pane : Pane) -> Indicator {
  let s = to_screen(target, cam)
  let cx = pane.width / 2.0
  let cy = pane.height / 2.0
  let dx = s.x + s.w / 2.0 - cx
  let dy = s.y + s.h / 2.0 - cy
  let hw = @cmp.maximum(1.0, cx - indicator_margin)
  let hh = @cmp.maximum(1.0, cy - indicator_margin)
  let scale = if dx == 0.0 && dy == 0.0 {
    0.0
  } else {
    @cmp.minimum(
      if dx == 0.0 {
        @double.infinity
      } else {
        (hw / dx).abs()
      },
      if dy == 0.0 {
        @double.infinity
      } else {
        (hh / dy).abs()
      },
    )
  }
  {
    x: cx + dx * scale,
    y: cy + dy * scale,
    angle: @math.atan2(dy, dx) * 180.0 / @math.PI,
  }
}

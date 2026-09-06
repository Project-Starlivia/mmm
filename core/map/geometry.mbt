// マップの座標系。DOM を知らない数学だけの層。

///|
/// 側 → 伸びる向き（右 = 1 / 左 = -1）。**側を符号にするのはここだけ**
pub fn dir(side : @tree.Side) -> Int {
  match side {
    Right => 1
    Left => -1
  }
}

///|
pub(all) struct Pt {
  x : Double
  y : Double
} derive(Eq, Debug, ToJson)

///|
/// 位置と大きさだけの箱（レイアウトの結果もドロップ判定もこれで話す）。x, y は左上
pub(all) struct Rect {
  x : Double
  y : Double
  w : Double
  h : Double
} derive(Eq, Debug, ToJson)

///|
/// d 属性を短く保つための丸め（見た目は変わらない）
pub fn round2(v : Double) -> Double {
  (v * 100.0).round() / 100.0
}

///|
/// 箱の中心
pub fn Rect::center(self : Rect) -> Pt {
  { x: self.x + self.w / 2.0, y: self.y + self.h / 2.0, }
}

///|
/// 複数の箱を包む最小の箱。1 つも無ければ None
pub fn union(boxes : Array[Rect]) -> Rect? {
  guard boxes.length() > 0 else { return None }
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  for b in boxes {
    x0 = @cmp.minimum(x0, b.x)
    y0 = @cmp.minimum(y0, b.y)
    x1 = @cmp.maximum(x1, b.x + b.w)
    y1 = @cmp.maximum(y1, b.y + b.h)
  }
  Some({ x: x0, y: y0, w: x1 - x0, h: y1 - y0, })
}

// 箱の左右の辺の中点。線が箱に触れるのはここだけで、任意方向へ出る一般形は
// 要らない。**どちらの辺が「子へ出る」役でどちらが「親から入る」役かは、
// その枝の向き（dir）で決まる** — 右の枝ならこの並びのまま、左の枝なら逆になる。

///|
/// 右辺の中点
pub fn Rect::right(self : Rect) -> Pt {
  { x: self.x + self.w, y: self.y + self.h / 2.0, }
}

///|
/// 左辺の中点
pub fn Rect::left(self : Rect) -> Pt {
  { x: self.x, y: self.y + self.h / 2.0, }
}

// dir（右 = 1 / 左 = -1）を受けて左右どちらの辺を使うか決める箇所は、
// 育つ辺と入る辺のこの 2 つだけにする。**鏡映（左右の入れ替え）を書いていいのはここだけ**
// — 呼び出し側は「育つ辺」「入る辺」としか言わない。

///|
/// 箱から、その枝が dir 方向へ**育っていく**辺の中点
pub fn Rect::growth_edge(self : Rect, dir : Int) -> Pt {
  if dir == 1 {
    self.right()
  } else {
    self.left()
  }
}

///|
/// 箱へ、dir 方向の枝が**入ってくる**辺の中点（`growth_edge` の反対側）
pub fn Rect::entry_edge(self : Rect, dir : Int) -> Pt {
  if dir == 1 {
    self.left()
  } else {
    self.right()
  }
}

///|
/// 点 p から線分 ab までの距離
pub fn dist_to_seg(p : Pt, a : Pt, b : Pt) -> Double {
  let vx = b.x - a.x
  let vy = b.y - a.y
  let len2 = vx * vx + vy * vy
  let t = if len2 == 0.0 {
    0.0
  } else {
    @cmp.maximum(
      0.0,
      @cmp.minimum(1.0, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2),
    )
  }
  @math.hypot(p.x - (a.x + vx * t), p.y - (a.y + vy * t))
}

///|
/// 折れ線の、長さで測った真ん中の点。見た目の中央と一致する
pub fn mid_of_polyline(pts : Array[Pt]) -> Pt {
  let mut total = 0.0
  for i in 1..<pts.length() {
    total += @math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
  }
  let mut acc = 0.0
  for i in 1..<pts.length() {
    let seg = @math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
    if acc + seg >= total / 2.0 {
      let t = if seg == 0.0 { 0.0 } else { (total / 2.0 - acc) / seg }
      return {
        x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
        y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t,
      }
    }
    acc += seg
  }
  pts[pts.length() - 1]
}

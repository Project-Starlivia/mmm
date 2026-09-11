// マップの座標系。DOM を知らない数学だけの層。

///|
/// 側 → 伸びる向き（右 = 1 / 左 = -1）。**側を符号にするのはここだけ**
fn dir(side : @tree.Side) -> Int {
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
fn round2(v : Double) -> Double {
  (v * 100.0).round() / 100.0
}

///|
/// 箱の中心
fn Rect::center(self : Rect) -> Pt {
  { x: self.x + self.w / 2.0, y: self.y + self.h / 2.0, }
}

///|
/// 少しでも重なるか（辺が触れるだけでは重ならない）
fn Rect::overlaps(self : Rect, o : Rect) -> Bool {
  self.x < o.x + o.w &&
  o.x < self.x + self.w &&
  self.y < o.y + o.h &&
  o.y < self.y + self.h
}

///|
/// 点から箱までの、軸ごとの距離。中なら 0
fn Rect::gap_to(self : Rect, p : Pt) -> (Double, Double) {
  (
    @cmp.maximum(@cmp.maximum(self.x - p.x, 0.0), p.x - (self.x + self.w)),
    @cmp.maximum(@cmp.maximum(self.y - p.y, 0.0), p.y - (self.y + self.h)),
  )
}

///|
/// 点が箱の中か（辺の上も中）
fn Rect::contains(self : Rect, p : Pt) -> Bool {
  self.gap_to(p) == (0.0, 0.0)
}

///|
/// 四方へ pad だけ広げた箱
fn Rect::grown(self : Rect, pad : Double) -> Rect {
  {
    x: self.x - pad,
    y: self.y - pad,
    w: self.w + pad * 2.0,
    h: self.h + pad * 2.0,
  }
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

///|
/// 右辺の中点
fn Rect::right(self : Rect) -> Pt {
  { x: self.x + self.w, y: self.y + self.h / 2.0, }
}

///|
/// 左辺の中点
pub fn Rect::left(self : Rect) -> Pt {
  { x: self.x, y: self.y + self.h / 2.0, }
}

///|
/// 箱から、その枝が dir 方向へ**育っていく**辺の中点。線が箱に触れるのは左右の辺の
/// 中点だけで、どちらが「子へ出る」役かは枝の向きで決まる — **鏡映（左右の入れ替え）を
/// 書いていいのはここと `entry_edge` だけ**。呼び出し側は「育つ辺」「入る辺」としか言わない
fn Rect::growth_edge(self : Rect, dir : Int) -> Pt {
  if dir == 1 {
    self.right()
  } else {
    self.left()
  }
}

///|
/// 箱へ、dir 方向の枝が**入ってくる**辺の中点（`growth_edge` の反対側）
fn Rect::entry_edge(self : Rect, dir : Int) -> Pt {
  if dir == 1 {
    self.left()
  } else {
    self.right()
  }
}

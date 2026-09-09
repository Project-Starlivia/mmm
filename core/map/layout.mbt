// View → 箱の配置。DOM を知らない純粋なレイアウト層。
//
// view の木をそのまま歩き、幾何（x/y/w/h）と、畳みで埋もれた子孫の数と、
// 中身から組んだカードだけを足す。構造は view の語（Node / Root / Side）のまま読み、
// 言い換えない。寸法は `SizeOf` で外から受ける — 文字の実測は DOM の仕事で、
// ここは数だけを扱う（試験も数だけで書ける）。
//
// すべての木は根から左右へ伸びる。側を持つのは根の子だけ（`sides` と並走）で、
// 孫から下は親の側を継ぐ。グループという概念は無い — 側ごとに 1 列積むだけ。

///|
/// 親の辺のうち、何割を「付け根の帯」に使うか。子が複数あるとき、線の出口を
/// この帯の中に配って重なりを解く
let fan_band = 0.6

///|
/// 親との繋がり。側は繋がりの性質なのでここに乗る（根は繋がりを持たない）
pub(all) struct Edge {
  id : Int
  side : @tree.Side
} derive(Eq, Debug, ToJson)

///|
pub(all) struct Box {
  /// View のノードそのまま。label / fold / blocks はここから読む
  node : @view.Node
  parent : Edge?
  /// 畳んで埋もれた子孫の数（全部の子孫。種類で除かない）
  buried : Int
  /// 親の辺の上での、付け根のずらし量(px)。兄弟と出口が重ならないように
  mut fan : Double
  x : Double
  mut y : Double
  w : Double
  h : Double
  /// node.blocks から組んだもの。カードにならない中身は入らないので、
  /// **blocks と並びが揃わない**。1 枚ずつが出どころの id を持つ
  cards : Array[Card]
} derive(Debug)

///|
pub(all) struct Layout {
  /// 描くノードの id、文書順（= 重なり順）。畳まれて埋もれたものは入らない
  order : Array[Int]
  boxes : Map[Int, Box]
} derive(Debug)

///|
pub fn Box::rect(self : Box) -> Rect {
  { x: self.x, y: self.y, w: self.w, h: self.h, }
}

///|
/// カード 1 枚の中身を置く矩形（**箱の左上から見た座標**）。
/// 描くのも書き出すのも、必ずここを通る — 積み方を 2 か所で数えない
pub fn card_rect(b : Box, i : Int) -> Rect? {
  guard i >= 0 && i < b.cards.length() else { return None }
  let c = b.cards[i]
  let inset = card_inset(c.kind)
  let bleed = card_bleed(c.kind)
  Some({
    x: normal.pad - bleed,
    y: row_top(b.cards, i) + inset,
    w: b.w - normal.pad * 2.0 + bleed * 2.0,
    h: row_h(c.kind) - inset * 2.0,
  })
}

///|
/// その中身から起きたカードを持つ箱と、そのカードの枚目。**探すのはカードの列**
/// — 中身の列ではない。カードにならなかった中身と、畳まれて箱を失った中身は None
pub fn owner_of(l : Layout, block : Int) -> (Box, Int)? {
  for b in l.boxes.values() {
    for i, c in b.cards {
      if c.id == block {
        return Some((b, i))
      }
    }
  }
  None
}

///|
/// 最初の木の根。無ければ None（空文書）
pub fn root_box(l : Layout) -> Box? {
  for id in l.order {
    match l.boxes.get(id) {
      Some(b) => if b.parent is None { return Some(b) }
      None => ()
    }
  }
  None
}

///|
fn gap_before(i : Int) -> Double {
  if i == 0 {
    0.0
  } else {
    gap.y
  }
}

///|
/// 子孫の数
fn descendants(n : @view.Node) -> Int {
  let mut c = 0
  for k in n.children {
    c += 1 + descendants(k)
  }
  c
}

///|
/// 見えている子。閉じた畳みの下は無い — 畳みの裁定はここ 1 つ。
/// 開いた畳み（`<details open>`）の子は普通に出る
fn kids_of(n : @view.Node) -> Array[@view.Node] {
  if closed(n) {
    []
  } else {
    n.children
  }
}

///|
/// ノードごとの、木から決まるもの。要るときに数えて覚える
priv struct Twig {
  cards : Array[Card]
  buried : Int
  size : Size
}

///|
/// その部分木が縦に占める帯の高さ `h` と、**その帯の上端から見た自分の箱の中心** `anchor`。
///
/// 親の中心は「第 1 子と最終子の中心の中点」で決める。この中点は帯の幾何学的な
/// 中心とは限らないので、帯のほうを中心に合わせて広げる（箱が帯からはみ出して
/// 隣の兄弟を覆わないように）
priv struct Band {
  h : Double
  anchor : Double
}

///|
/// 1 回の配置。覚え書き（twigs / bands）は id で引く — id は文書順で一意
priv struct Pass {
  size : SizeOf
  boxes : Map[Int, Box]
  order : Array[Int]
  twigs : Map[Int, Twig]
  bands : Map[Int, Band]
}

///|
fn Pass::twig_of(self : Pass, n : @view.Node) -> Twig {
  match self.twigs.get(n.id) {
    Some(t) => t
    None => {
      let folded = closed(n)
      let cs = if folded { [] } else { cards(n.blocks) }
      let buried = if folded { descendants(n) } else { 0 }
      let t = { cards: cs, buried, size: (self.size)(n, cs, buried), }
      self.twigs[n.id] = t
      t
    }
  }
}

///|
fn Pass::band_of(self : Pass, n : @view.Node) -> Band {
  match self.bands.get(n.id) {
    Some(b) => return b
    None => ()
  }
  let size = self.twig_of(n).size
  let kids = kids_of(n)
  let b = if kids.length() == 0 {
    { h: size.h, anchor: size.h / 2.0, }
  } else {
    let mid = self.stack_center(kids)
    let slide = @cmp.maximum(0.0, size.h / 2.0 - mid)
    let anchor = slide + mid
    {
      h: @cmp.maximum(slide + self.stack_h(kids), anchor + size.h / 2.0),
      anchor,
    }
  }
  self.bands[n.id] = b
  b
}

///|
fn Pass::height_of(self : Pass, n : @view.Node) -> Double {
  self.band_of(n).h
}

///|
/// 子を 0 から積んだときの「第 1 子と最終子の中心の中点」
fn Pass::stack_center(self : Pass, kids : Array[@view.Node]) -> Double {
  let mut y = 0.0
  let centers = []
  for i, k in kids {
    y += gap_before(i)
    centers.push(y + self.band_of(k).anchor)
    y += self.band_of(k).h
  }
  (centers[0] + centers[centers.length() - 1]) / 2.0
}

///|
/// 子の山を、その部分木の帯の上端から何 px 下に置くか
fn Pass::slide_of(self : Pass, n : @view.Node) -> Double {
  self.band_of(n).anchor - self.stack_center(kids_of(n))
}

///|
/// 子を縦に積んだときの高さ（あいだの隙間込み）
fn Pass::stack_h(self : Pass, kids : Array[@view.Node]) -> Double {
  let mut sum = 0.0
  for i, k in kids {
    sum += self.height_of(k) + gap_before(i)
  }
  sum
}

///|
/// 枝を置く。`near_x` は**親と向かい合う辺**の x（右向きなら箱の左辺、
/// 左向きなら右辺）。左右で式を分けないための座標。返すのは箱の中心の y
fn Pass::place(
  self : Pass,
  n : @view.Node,
  parent : Edge,
  near_x : Double,
  top : Double,
) -> Double {
  let d = dir(parent.side)
  let { size, cards, buried, } = self.twig_of(n)
  let x = if d == 1 { near_x } else { near_x - size.w }
  let kids = kids_of(n)
  let center_y = if kids.length() == 0 {
    top + size.h / 2.0
  } else {
    // 子の山の置き所は `band_of` が決めた `slide` から取る（同じ式を 2 か所に持たない）
    let mut y = top + self.slide_of(n)
    let child_near = if d == 1 { x + size.w + gap.x } else { x - gap.x }
    let centers = []
    for i, k in kids {
      y += gap_before(i)
      centers.push(
        self.place(k, { id: n.id, side: parent.side, }, child_near, y),
      )
      y += self.height_of(k)
    }
    (centers[0] + centers[centers.length() - 1]) / 2.0
  }
  self.boxes[n.id] = {
    node: n,
    parent: Some(parent),
    buried,
    fan: 0,
    x,
    y: center_y - size.h / 2.0,
    w: size.w,
    h: size.h,
    cards,
  }
  center_y
}

///|
/// その枝と子孫すべての箱を縦にずらす。側を根の中心へ揃えるため
fn Pass::shift_subtree(self : Pass, n : @view.Node, dy : Double) -> Unit {
  match self.boxes.get(n.id) {
    Some(b) => b.y += dy
    None => ()
  }
  for k in kids_of(n) {
    self.shift_subtree(k, dy)
  }
}

///|
/// 根の子を側ごとに分ける（右, 左）。**sides を読むのはここだけ。** 足りなければ右
fn split_sides(t : @view.Root) -> (Array[@view.Node], Array[@view.Node]) {
  let right = []
  let left = []
  for i, k in kids_of(t.node) {
    match t.sides.get(i) {
      Some(Left) => left.push(k)
      _ => right.push(k)
    }
  }
  (right, left)
}

///|
/// 置いた側 1 つぶん。y0 は子の山の上端、h はその高さ
priv struct Placed {
  kids : Array[@view.Node]
  centers : Array[Double]
  mut y0 : Double
  h : Double
}

///|
/// 木を 1 本置く。側は根の子にしか無いので、根の子だけがここを通り、孫から
/// 下は `place` が面倒を見る。返すのは実際に占めた縦の範囲（上端, 下端） —
/// ずらしたぶん見積もり（span）を超えうるので、木を積む側はこれを見る。
///
/// **不変条件: どの側も、第 1 子と最終子の中心の中点が根の中心に乗る。**
/// 根の中心は右の枝に合わせ（右が無ければ左）、もう一方の側はその中心へ
/// まとめてずらす
fn Pass::place_tree(
  self : Pass,
  t : @view.Root,
  top : Double,
) -> (Double, Double) {
  let root = t.node
  let { size, cards, buried, } = self.twig_of(root)
  let (right, left) = split_sides(t)
  let span = @cmp.maximum(
    size.h,
    @cmp.maximum(self.stack_h(right), self.stack_h(left)),
  )
  let placed : Array[Placed] = []
  let mut center_y = top + span / 2.0
  for side in ([Right, Left] : Array[@tree.Side]) {
    let kids = if side == Right { right } else { left }
    guard kids.length() > 0 else { continue }
    let p = self.stack_side(root, kids, side, size, top, span)
    placed.push(p)
    // 右が居れば右が根の中心を決める。片側だけなら、その側が決める
    if side == Right || right.length() == 0 {
      center_y = mid_of(p)
    }
  }
  for p in placed {
    self.center_side(p, center_y)
  }
  self.boxes[root.id] = {
    node: root,
    parent: None,
    buried,
    fan: 0,
    x: 0,
    y: center_y - size.h / 2.0,
    w: size.w,
    h: size.h,
    cards,
  }
  reach_of_tree(placed, center_y, size.h)
}

///|
/// 側 1 つに子を積む。**縦は側の見積もり（span）の中で真ん中**に寄せる。
fn Pass::stack_side(
  self : Pass,
  root : @view.Node,
  kids : Array[@view.Node],
  side : @tree.Side,
  size : Size,
  top : Double,
  span : Double,
) -> Placed {
  let near_x = if dir(side) == 1 { size.w + gap.x } else { -gap.x }
  let h = self.stack_h(kids)
  let y0 = top + @cmp.maximum(0.0, (span - h) / 2.0)
  let mut y = y0
  let centers = []
  for i, k in kids {
    y += gap_before(i)
    centers.push(self.place(k, { id: root.id, side, }, near_x, y))
    y += self.height_of(k)
  }
  { kids, centers, y0, h, }
}

///|
/// 積んだ側を、根の中心に合わせて動かす。
/// **不変条件: どの側も、第 1 子と最終子の中心の中点が根の中心に乗る。**
fn Pass::center_side(self : Pass, p : Placed, center_y : Double) -> Unit {
  let dy = center_y - mid_of(p)
  guard dy != 0.0 else { return }
  for k in p.kids {
    self.shift_subtree(k, dy)
  }
  p.y0 += dy
}

///|
/// その側の第 1 子と最終子の中心の中点。
fn mid_of(p : Placed) -> Double {
  (p.centers[0] + p.centers[p.centers.length() - 1]) / 2.0
}

///|
/// 木が実際に占めた縦の範囲。**ずらしたぶん見積もり（span）を超えうる**ので、
/// 木を積む側はこれを見る。
fn reach_of_tree(
  placed : Array[Placed],
  center_y : Double,
  h : Double,
) -> (Double, Double) {
  let mut lo = center_y - h / 2.0
  let mut hi = center_y + h / 2.0
  for p in placed {
    lo = @cmp.minimum(lo, p.y0)
    hi = @cmp.maximum(hi, p.y0 + p.h)
  }
  (lo, hi)
}

///|
/// 文書順に並べる（親が先）
fn walk(n : @view.Node, order : Array[Int]) -> Unit {
  order.push(n.id)
  for k in kids_of(n) {
    walk(k, order)
  }
}

///|
/// 付け根をずらすのは「**同じ辺から**出る線が 2 本以上」あるときだけ。
/// 根は左右の両辺から線を出す唯一のノードなので、親 id だけでなく側でまとめる
fn fan_out(boxes : Map[Int, Box]) -> Unit {
  let groups : Map[(Int, Int), (Box, Array[Box])] = Map([])
  for b in boxes.values() {
    guard b.parent is Some(e) else { continue }
    guard boxes.get(e.id) is Some(parent) else { continue }
    let key = (e.id, dir(e.side))
    match groups.get(key) {
      Some((_, kids)) => kids.push(b)
      None => groups[key] = (parent, [b])
    }
  }
  for _, group in groups {
    let (parent, kids) = group
    if kids.length() < 2 {
      continue
    }
    let band = parent.h * fan_band
    let sorted = kids.copy()
    sorted.sort_by((a, b) => a.rect().center().y.compare(b.rect().center().y))
    for i, b in sorted {
      b.fan = ((i.to_double() + 0.5) / sorted.length().to_double() - 0.5) * band
    }
  }
}

///|
pub fn layout(roots : Array[@view.Root], size : SizeOf) -> Layout {
  let p : Pass = { size, boxes: {}, order: [], twigs: {}, bands: {}, }
  let mut top = 0.0
  for t in roots {
    let (lo, hi) = p.place_tree(t, top)
    // 上へはみ出したぶんは押し下げて、頼んだ位置から始まるようにする
    let up = @cmp.maximum(0.0, top - lo)
    if up != 0.0 {
      p.shift_subtree(t.node, up)
    }
    top = hi + up + gap.root
    walk(t.node, p.order)
  }
  fan_out(p.boxes)
  { order: p.order, boxes: p.boxes, }
}

///|
/// 子 id から、その親へ引く線の両端（付け根のずらしも込み）。
/// **描画も書き出しもここだけを見る**
pub fn edge_ends(l : Layout, id : Int) -> (Pt, Pt)? {
  guard l.boxes.get(id) is Some(b) else { return None }
  guard b.parent is Some(parent) else { return None }
  guard l.boxes.get(parent.id) is Some(p) else { return None }
  // 線は「親の、子が伸びる側の辺」から出て「子の、親を向いた辺」へ入る
  let d = dir(parent.side)
  let out = p.rect().growth_edge(d)
  let into = b.rect().entry_edge(d)
  Some(({ x: out.x, y: out.y + b.fan, }, into))
}

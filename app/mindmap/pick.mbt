// 選んでいるカードに被せる枠と、その角の × ボタン。
//
// **選ばれているカードは常に高々 1 枚**なので、置き場所も 1 つでよい。
// ノードの子要素として作ると、選ぶ / 外すたびにそのノードの中身が丸ごと作り直され、
// **コードカードを選ぶだけでコードが再トークナイズされる**。落とし先の線（drop-line）と
// 同じく、world 座標に浮かぶ 1 個の印にすれば、描画はカードの選択を知らなくてよい。

///|
/// × の中心からの腕の長さと、その当たり判定の半径
let arm = 2.5

///|
let hit_r = 7.0

///|
/// × を押されたときに誰を消すか。input.mbt が読む契約
let data_delete = "data-delete"

///|
pub struct CardPick {
  /// world の層に入れる。ノード層より上に置くこと
  el : @dom.Element
  frame : @dom.Element
  /// 角の ×。押せば Delete（操作と同じ名）
  delete : @dom.Element
  circle : @dom.Element
  strokes : Array[@dom.Element]
  /// 直前に被せたカード。同じなら書かない — 視点を動かすたびに来るが、
  /// 印は world に浮かぶので視点では動かない（#249）
  mut shown : (Int, @map.Rect)?
}

///|
fn CardPick::new(doc : @dom.Document) -> CardPick {
  let el_ = @web.el(doc, "g", [("class", "card-pick")])
  @web.svg_show(el_, false)
  let frame = @web.el(doc, "rect", [("class", "frame")])
  let delete = @web.el(doc, "g", [("class", "delete")])
  let circle = @web.el(doc, "circle", [("r", @web.num(hit_r))])
  let strokes = [@web.el(doc, "line", []), @web.el(doc, "line", [])]
  delete.append(circle.as_node())
  for s in strokes {
    delete.append(s.as_node())
  }
  el_.append(frame.as_node())
  el_.append(delete.as_node())
  { el: el_, frame, delete, circle, strokes, shown: None, }
}

///|
/// `rect` にぴったり被せる。`id` は × を押されたときに誰を消すかで、`data-delete` として
/// 出す（当たり判定は座標から辿るため）
fn CardPick::show(self : CardPick, id : Int, rect : @map.Rect) -> Unit {
  guard self.shown != Some((id, rect)) else { return }
  self.shown = Some((id, rect))
  @web.svg_show(self.el, true)
  cover(self.frame, rect)
  // × は角そのものに載せる。枠線がボタンの中心を通る位置
  let cx = rect.x + rect.w
  let cy = rect.y
  self.delete.setAttribute(data_delete, id.to_string())
  self.circle.setAttribute("cx", @web.num(cx))
  self.circle.setAttribute("cy", @web.num(cy))
  // × は文字ではなく線で引く。字だと書体で中心も太さも揺れる
  for i, d in [(1.0, 1.0), (1.0, -1.0)] {
    let (dx, dy) = d
    @web.set_line(
      self.strokes[i],
      cx - arm * dx,
      cy - arm * dy,
      cx + arm * dx,
      cy + arm * dy,
    )
  }
}

///|
fn CardPick::hide(self : CardPick) -> Unit {
  guard self.shown is Some(_) else { return }
  self.shown = None
  @web.svg_show(self.el, false)
  // 隠れていても当たり判定の印は残るので、消しておく
  self.delete.removeAttribute(data_delete)
}

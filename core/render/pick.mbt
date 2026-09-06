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
pub struct CardPick {
  /// world の層に入れる。ノード層より上に置くこと
  el : @dom.Element
  frame : @dom.Element
  /// 角の ×。押せば Delete（操作と同じ名）
  delete : @dom.Element
  circle : @dom.Element
  strokes : Array[@dom.Element]
}

///|
pub fn CardPick::new(doc : @dom.Document) -> CardPick {
  let el_ = el(doc, "g", [("class", "card-pick"), ("visibility", "hidden")])
  let frame = el(doc, "rect", [("class", "frame")])
  let delete = el(doc, "g", [("class", "delete")])
  let circle = el(doc, "circle", [("r", num(hit_r))])
  let strokes = [el(doc, "line", []), el(doc, "line", [])]
  delete.append(circle.as_node())
  for s in strokes {
    delete.append(s.as_node())
  }
  el_.append(frame.as_node())
  el_.append(delete.as_node())
  { el: el_, frame, delete, circle, strokes, }
}

///|
/// `rect` にぴったり被せる。`id` は × を押されたときに誰を消すかで、`data-delete` として
/// 出す（当たり判定は座標から辿るため）
pub fn CardPick::show(self : CardPick, id : Int, rect : @map.Rect) -> Unit {
  self.el.setAttribute("visibility", "visible")
  self.frame.setAttribute("x", num(rect.x))
  self.frame.setAttribute("y", num(rect.y))
  self.frame.setAttribute("width", num(rect.w))
  self.frame.setAttribute("height", num(rect.h))
  // × は角そのものに載せる。枠線がボタンの中心を通る位置
  let cx = rect.x + rect.w
  let cy = rect.y
  self.delete.setAttribute("data-delete", id.to_string())
  self.circle.setAttribute("cx", num(cx))
  self.circle.setAttribute("cy", num(cy))
  // × は文字ではなく線で引く。字だと書体で中心も太さも揺れる
  for i, d in [(1.0, 1.0), (1.0, -1.0)] {
    let (dx, dy) = d
    let line = self.strokes[i]
    line.setAttribute("x1", num(cx - arm * dx))
    line.setAttribute("y1", num(cy - arm * dy))
    line.setAttribute("x2", num(cx + arm * dx))
    line.setAttribute("y2", num(cy + arm * dy))
  }
}

///|
pub fn CardPick::hide(self : CardPick) -> Unit {
  self.el.setAttribute("visibility", "hidden")
  // 隠れていても当たり判定の印は残るので、消しておく
  self.delete.removeAttribute("data-delete")
}

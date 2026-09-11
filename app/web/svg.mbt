// SVG の要素を作る最小の道具。描画も部品もここを通り、書き出しは
// 出来た要素を写す（`serialize`）だけなので、要素の形はここ 1 つ。

///|
pub let svg_ns = "http://www.w3.org/2000/svg"

///|
/// 属性を付けた要素。**SVG の属性はほとんどが数**なので、数は `num` で綴って渡す
pub fn el(
  doc : @dom.Document,
  tag : String,
  attrs : Array[(String, String)],
) -> @dom.Element {
  let e = doc.createElementNs(svg_ns, tag)
  for kv in attrs {
    let (k, v) = kv
    e.setAttribute(k, v)
  }
  e
}

///|
/// 矩形の 4 つの属性（rect / image）
pub fn set_rect(
  e : @dom.Element,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  e.setAttribute("x", num(x))
  e.setAttribute("y", num(y))
  e.setAttribute("width", num(w))
  e.setAttribute("height", num(h))
}

///|
/// 線の両端
pub fn set_line(
  e : @dom.Element,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Unit {
  e.setAttribute("x1", num(x1))
  e.setAttribute("y1", num(y1))
  e.setAttribute("x2", num(x2))
  e.setAttribute("y2", num(y2))
}

///|
/// SVG の要素を見せる / 隠す。`visibility` で — display だと CSS との入り乱れが増える
pub fn svg_show(e : @dom.Element, on : Bool) -> Unit {
  e.setAttribute("visibility", if on { "visible" } else { "hidden" })
}

///|
/// 要素をそのまま字にする（SVG の書き出し）
pub extern "js" fn serialize(e : @dom.Element) -> String =
  #| (e) => new XMLSerializer().serializeToString(e)

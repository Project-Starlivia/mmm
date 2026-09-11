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
/// 要素をそのまま字にする（SVG の書き出し）
pub extern "js" fn serialize(e : @dom.Element) -> String =
  #| (e) => new XMLSerializer().serializeToString(e)

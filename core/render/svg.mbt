// SVG の要素を作る最小の道具。描画がここを通り、書き出し（ts の toSvg）は
// 出来た要素を写すだけなので、要素の形はここ 1 つ。

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
/// 数の属性の綴り。JS の `String(n)` と同じ（`@map.num`）
pub fn num(v : Double) -> String {
  @map.num(v)
}

///|
/// class の付け外し。`classList.toggle(name, on)` — 同じ値なら DOM は変わらない
pub fn toggle_class(e : @dom.Element, name : String, on : Bool) -> Unit {
  e.as_any()._get("classList")._call("toggle", [@core.any(name), @core.any(on)])
  |> ignore
}

///|
pub fn has_class(e : @dom.Element, name : String) -> Bool {
  e.as_any()._get("classList")._call("contains", [@core.any(name)]).cast()
}

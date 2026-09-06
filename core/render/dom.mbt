// DOM の小さな道具。js_browser に型の無い呼び出し（style・画面の矩形・ポインタの
// 捕捉・欄の値・出来事の的）を、ここで 1 行ずつ包む。**他のファイルは `_get` /
// `_call` を書かない** — 綴りの間違いはこの 1 か所でしか起きない。

///|
/// HTML の要素を class 付きで作る
pub fn html(
  doc : @dom.Document,
  tag : String,
  class : String,
) -> @dom.HTMLElement {
  let e = doc.createElement(tag)
  e.setAttribute("class", class)
  @dom.HTMLElement::cast_from_element(e)
}

///|
/// style に 1 つ入れる
pub fn set_style(e : @dom.Element, name : String, value : String) -> Unit {
  @dom.css_style_from_val(e.as_any()._get("style")).set_property(name, value)
}

///|
/// style の px の綴り
pub fn px(v : Double) -> String {
  num(v) + "px"
}

///|
/// 見せる / 隠す
pub fn show(e : @dom.Element, display : String, on : Bool) -> Unit {
  set_style(e, "display", if on { display } else { "none" })
}

///|
/// 画面上の矩形
pub fn client_rect(e : @dom.Element) -> @dom.DOMRect {
  e.as_any()._call("getBoundingClientRect", []).cast()
}

///|
/// ポインタを捕まえる（離すまで出来事がこの要素に来る）
pub fn capture(e : @dom.Element, pointer : Int) -> Unit {
  e.as_any()._call("setPointerCapture", [@core.any(pointer)]) |> ignore
}

///|
/// 出来事を聞く。`passive` は偽 — preventDefault を言える
pub fn listen(
  e : @dom.Element,
  name : String,
  f : (@core.Any) -> Unit,
  capture? : Bool = false,
) -> Unit {
  e.as_event_target().addEventListener(name, f, capture~, passive=false)
}

///|
/// マウスの出来事として読む（PointerEvent も同じ欄を持つ）
pub fn mouse(e : @core.Any) -> @dom.MouseEvent {
  e.cast()
}

///|
pub fn keyboard(e : @core.Any) -> @dom.KeyboardEvent {
  e.cast()
}

///|
pub fn pointer_id(e : @core.Any) -> Int {
  e._get("pointerId").cast()
}

///|
/// 指か（マウス・ペンでない）
pub fn is_touch(e : @core.Any) -> Bool {
  let t : String = e._get("pointerType").cast()
  t == "touch"
}

///|
pub fn event_type(e : @core.Any) -> String {
  e._get("type").cast()
}

///|
/// ホイールの目盛り
pub fn delta(e : @core.Any) -> (Double, Double) {
  (e._get("deltaX").cast(), e._get("deltaY").cast())
}

///|
/// IME の変換中か（input の出来事。無ければ偽）
pub fn is_composing(e : @core.Any) -> Bool {
  @core.identity_option(e._get("isComposing")).unwrap_or(false)
}

///|
pub fn prevent(e : @core.Any) -> Unit {
  e._call("preventDefault", []) |> ignore
}

///|
pub fn stop(e : @core.Any) -> Unit {
  e._call("stopPropagation", []) |> ignore
}

///|
/// 出来事の的が `selector` に当てはまる要素（かその中）なら、それ
pub fn target_in(e : @core.Any, selector : String) -> @dom.Element? {
  let t = e._get("target")
  guard !@core.is_nullish(t) && !@core.is_undefined(t._get("closest")) else {
    return None
  }
  let el : @dom.Element = t.cast()
  el.closest(selector)
}

///|
/// 的の属性。的が `selector` の中でなければ None
pub fn attr_in(e : @core.Any, selector : String, name : String) -> String? {
  target_in(e, selector).bind(el => el.getAttribute(name))
}

///|
/// 欄（input / textarea）の値
pub fn value(e : @dom.Element) -> String {
  e.as_any()._get("value").cast()
}

///|
pub fn set_value(e : @dom.Element, v : String) -> Unit {
  e.as_any()._set("value", @core.any(v))
}

///|
/// 欄の選択範囲
pub fn select_range(e : @dom.Element, from : Int, to : Int) -> Unit {
  e.as_any()._call("setSelectionRange", [@core.any(from), @core.any(to)])
  |> ignore
}

///|
pub fn focus(e : @dom.Element) -> Unit {
  e.as_any()._call("focus", []) |> ignore
}

///|
/// 大きさが変わったら呼ぶ。観察者はその要素の窓のもの（happy-dom は global に持たない）
pub fn observe_resize(e : @dom.Element, f : () -> Unit) -> Unit {
  let win = e.as_any()._get("ownerDocument")._get("defaultView")
  let ctor = win._get("ResizeObserver")
  @core.new(ctor, [@core.from_fn0(f)])._call("observe", [@core.any(e)])
  |> ignore
}

///|
/// 別のタブで開く
pub fn open_url(url : String) -> Unit {
  @dom.window()
  .as_any()
  ._call("open", [
    @core.any(url),
    @core.any("_blank"),
    @core.any("noopener,noreferrer"),
  ])
  |> ignore
}

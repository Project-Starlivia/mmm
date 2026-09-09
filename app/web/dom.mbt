// DOM の小さな道具。js_browser に型の無い呼び出し（style・画面の矩形・ポインタの
// 捕捉・欄の値・出来事の的・約束）を、ここで 1 行ずつ包む。**他の package は `_get` /
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
/// 焦点を移す。**ブラウザに寄せさせない**（`preventScroll`）— 器はどれも
/// `overflow: hidden` で、見えている場所は地図なら camera、md なら
/// CodeMirror が決める。ブラウザが器ごとスクロールすると、その決めと食い違って
/// 中身が画面の外へ出る（#134 — 画面外のノードを編集し始めると地図が全部消えた）
pub fn focus(e : @dom.Element) -> Unit {
  let opts = @core.new_object()
  opts._set("preventScroll", @core.any(true))
  e.as_any()._call("focus", [opts]) |> ignore
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

///|
/// 出来事の細部（click なら押した回数。キーで押した click は 0）
pub fn detail(e : @core.Any) -> Int {
  e._get("detail").cast()
}

///|
/// 要素の描かれた大きさ（offsetWidth / offsetHeight）
pub fn offset_size(e : @dom.Element) -> (Double, Double) {
  (
    e.as_any()._get("offsetWidth").cast(),
    e.as_any()._get("offsetHeight").cast(),
  )
}

///|
/// 同じ要素か
pub fn same(a : @dom.Element, b : @dom.Element) -> Bool {
  @core.equal(a.as_any(), b.as_any())
}

///|
/// その文書の窓（happy-dom は global に window を持たないので、文書から辿る）
pub fn window_of(doc : @dom.Document) -> @core.Any {
  doc.as_any()._get("defaultView")
}

///|
/// 窓の大きさ（innerWidth / innerHeight）
pub fn inner_size(doc : @dom.Document) -> (Double, Double) {
  let w = window_of(doc)
  (w._get("innerWidth").cast(), w._get("innerHeight").cast())
}

///|
/// 窓の出来事を聞く
pub fn on_window(
  doc : @dom.Document,
  name : String,
  f : (@core.Any) -> Unit,
  capture? : Bool = false,
) -> Unit {
  let t : @event.EventTarget = window_of(doc).cast()
  t.addEventListener(name, f, capture~)
}

///|
/// 押せる / 押せない（`disabled` は属性ではなく性質）
pub fn set_disabled(e : @dom.Element, off : Bool) -> Unit {
  e.as_any()._set("disabled", @core.any(off))
}

///|
/// 文書の根に効いている CSS 変数の値（空白は落とす）
pub fn css_var(doc : @dom.Document, name : String) -> String {
  computed(doc.documentElement(), name)
}

///|
/// その要素に効いている計算済みの値（空白は落とす）。CSS 変数も読める
pub extern "js" fn computed(e : @dom.Element, name : String) -> String =
  #| (e, name) => e.ownerDocument.defaultView.getComputedStyle(e).getPropertyValue(name).trim()

///|
/// 閉じて、答えを添える（`returnValue`）
pub extern "js" fn close_with(dialog : @dom.Element, value : String) -> Unit =
  #| (d, v) => d.close(v)

///|
pub fn head(doc : @dom.Document) -> @dom.Element {
  doc.as_any()._get("head").cast()
}

///|
/// メディアクエリ。`matches` で今の答え
pub fn match_media(doc : @dom.Document, query : String) -> @dom.MediaQueryList {
  window_of(doc)._call("matchMedia", [@core.any(query)]).cast()
}

///|
pub fn matches(m : @dom.MediaQueryList) -> Bool {
  m.as_any()._get("matches").cast()
}

///|
/// `<dialog>` を塞いで開く
pub fn show_modal(dialog : @dom.Element) -> Unit {
  dialog.as_any()._call("showModal", []) |> ignore
}

///|
pub fn close_dialog(dialog : @dom.Element) -> Unit {
  dialog.as_any()._call("close", []) |> ignore
}

///|
/// `<dialog>` が閉じたときの答え（送信したボタンの value。断りは ""）
pub fn return_value(dialog : @dom.Element) -> String {
  dialog.as_any()._get("returnValue").cast()
}

///|
/// 欄の字を全部選ぶ
pub fn select_all(e : @dom.Element) -> Unit {
  e.as_any()._call("select", []) |> ignore
}

// 地図の器を happy-dom で立てて、入力 → 判断 → host への答えを固定する。
// 置き方・当たり・キーの表そのものは map/ の試験が持つ。ここは配線 — 出来事が
// 正しい判断に届き、印（selected / 輪 / 落とし先 / 欄）が DOM に出ることを見る。

///|
/// 見本。r(2) → a(3) / b(4)。b はコード 1 枚（5）
let sample_md = "# r\n\n## a\n\n## b\n\n```ts\nx\n```\n"

///|
/// 1 文字 7px。実測の代わり
fn seven_wide(_font : @map.Font, text : String) -> Double {
  text.char_length().to_double() * 7.0
}

///|
/// host の代役。文書は固定、選択と picked と、受け取った答えを覚える
struct Stub {
  survey : @read.Survey
  mut holder : @read.Holder
  mut selection : @map.Selection
  mut picked : Int?
  applied : Array[@op.Op]
  reveals : Array[Bool]
  failed : Array[String]
  mut pasted : Int
  mut drawn : Int?
  mut clipboard : String
  /// 帯へ抜けた回数
  mut left : Int
}

///|
fn Stub::new(md : String) -> Stub {
  {
    survey: @read.survey(md),
    holder: Map,
    selection: @map.none,
    picked: None,
    applied: [],
    reveals: [],
    failed: [],
    pasted: 0,
    drawn: None,
    clipboard: "",
    left: 0,
  }
}

///|
fn Stub::host(self : Stub) -> Host {
  {
    survey: () => self.survey,
    measure: seven_wide,
    image_url: _ => None,
    image_hint: () => None,
    connect_assets: () => (),
    holder: () => self.holder,
    selection: () => self.selection,
    set_selection: (sel, reveal) => {
      self.selection = sel
      self.reveals.push(reveal)
    },
    picked: () => self.picked,
    set_picked: id => self.picked = id,
    block_text: id => {
      let s = self.survey
      match s.spots.get(id) {
        Some(sp) => String::unsafe_substring(s.md, start=sp.from, end=sp.to)
        None => ""
      }
    },
    apply: (op, _edit) => {
      self.applied.push(op)
      Some(9)
    },
    paste: () => self.pasted += 1,
    copy: k => k(true),
    draw: id => self.drawn = Some(id),
    read_clipboard: k => k(self.clipboard),
    tokens: (lines, _lang) => lines.map(l => [{ text: l, cls: "", }]),
    tokens_block: text => {
      text.split("\n").map(l => [{ text: l.to_owned(), cls: "", }]).collect()
    },
    epoch: () => 0,
    failed: msg => self.failed.push(msg),
    leave: () => self.left = self.left + 1,
  }
}

///|
/// 器を立てる。窓・ペイン・地図・代役
struct Stand {
  win : @dom.Window
  pane : @dom.HTMLElement
  map : Mindmap
  stub : Stub
}

///|
fn stand(md? : String = sample_md) -> Stand {
  let win = @test_utils.create_happy_window()
  let doc = win.document()
  let pane = @web.html(doc, "div", "")
  doc.body().unwrap().append(pane.as_node())
  let stub = Stub::new(md)
  let map = Mindmap::new(pane, stub.host())
  map.render()
  { win, pane, map, stub, }
}

///|
/// 出来事を作って流す。happy-dom はレイアウトを持たないので、ペインの左上は (0, 0)
fn fire(
  s : Stand,
  kind : String,
  name : String,
  x : Double,
  y : Double,
  button? : Int = 0,
  pointer? : Int = 1,
  touch? : Bool = false,
  shift? : Bool = false,
  ctrl? : Bool = false,
  key? : String = "",
  target? : @dom.Element? = None,
) -> Unit {
  let init = @core.new_object()
  init._set("bubbles", @core.any(true))
  init._set("cancelable", @core.any(true))
  init._set("clientX", @core.any(x))
  init._set("clientY", @core.any(y))
  init._set("button", @core.any(button))
  init._set("pointerId", @core.any(pointer))
  init._set("pointerType", @core.any(if touch { "touch" } else { "mouse" }))
  init._set("shiftKey", @core.any(shift))
  init._set("ctrlKey", @core.any(ctrl))
  init._set("key", @core.any(key))
  let ctor = s.win.as_any()._get(kind)
  let ev = @core.new(ctor, [@core.any(name), init])
  let at = match target {
    Some(t) => t
    None => s.pane.as_element()
  }
  at.as_event_target().dispatchEvent(ev.cast()) |> ignore
}

///|
fn click_at(s : Stand, x : Double, y : Double, shift? : Bool = false) -> Unit {
  fire(s, "PointerEvent", "pointerdown", x, y, shift~)
  fire(s, "PointerEvent", "pointerup", x, y, shift~)
}

///|
/// その id の箱の真ん中（画面 px。視点は起動時の k=1, 60, 60）
fn mid(s : Stand, id : Int) -> (Double, Double) {
  let b = s.map.layout.boxes.get(id).unwrap()
  let c = s.map.camera
  (b.x * c.k + c.tx + b.w / 2.0, b.y * c.k + c.ty + b.h / 2.0)
}

///|
fn press_key(s : Stand, key : String, shift? : Bool = false) -> Unit {
  fire(s, "KeyboardEvent", "keydown", 0, 0, key~, shift~)
}

///|
test "立てると器が揃い、描いたノードは文書順。白紙なら言い出しが出る" {
  let s = stand()
  defer s.win.close()
  let pane = s.pane.as_element()
  assert_true(@web.has_class(pane, "map-pane"))
  assert_eq(pane.querySelectorAll(".node").length(), 3)
  assert_eq(pane.querySelector(".map-svg") is Some(_), true)
  assert_eq(pane.querySelector(".rubber") is Some(_), true)
  assert_eq(pane.querySelector(".label-editor") is Some(_), true)
  assert_eq(pane.querySelector(".card-editor") is Some(_), true)
  assert_eq(pane.querySelector(".card-pick") is Some(_), true)
  assert_eq(pane.querySelector(".drop-line") is Some(_), true)
  let blank = stand(md="")
  defer blank.win.close()
  let hint = blank.pane.querySelector(".pane-hint").unwrap()
  assert_eq(
    @dom.css_style_from_val(hint.as_any()._get("style")).get_property_value(
      "display",
    ),
    "flex",
  )
}

///|
test "箱を押して離すと選ぶ（reveal 付き）。Shift で範囲。背景を押して離すと解く" {
  let s = stand()
  defer s.win.close()
  let (ax, ay) = mid(s, 3)
  click_at(s, ax, ay)
  assert_eq(s.stub.selection, { ids: [3], anchor: Some(3), })
  assert_eq(s.stub.reveals, [true])
  let (bx, by) = mid(s, 4)
  click_at(s, bx, by, shift=true)
  assert_eq(s.stub.selection.ids, [3, 4])
  // 地図が持つ間は selected の枠
  s.map.refresh_selection()
  assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "selected"))
  assert_true(@web.has_class(s.map.renderer.node_el(4).unwrap(), "selected"))
  click_at(s, 5, 5)
  assert_eq(s.stub.selection, @map.none)
}

///|
test "md が持つ間は輪。輪は箱の 3px 内側で、本数は選択の数" {
  let s = stand()
  defer s.win.close()
  s.stub.holder = Md
  s.stub.selection = { ids: [2, 3], anchor: Some(3), }
  s.map.refresh_selection()
  let rings = s.pane.as_element().querySelectorAll(".caret-ring")
  assert_eq(rings.length(), 2)
  let b = s.map.layout.boxes.get(2).unwrap()
  assert_eq(rings[0].getAttribute("x"), Some(@web.num(b.x + 3.0)))
  assert_eq(rings[0].getAttribute("width"), Some(@web.num(b.w - 6.0)))
  assert_false(@web.has_class(s.map.renderer.node_el(3).unwrap(), "selected"))
  s.stub.selection = @map.none
  s.map.refresh_selection()
  assert_eq(s.pane.as_element().querySelectorAll(".caret-ring").length(), 0)
}

///|
test "背景をなぞると矩形選択（触れた箱を全部）" {
  let s = stand()
  defer s.win.close()
  fire(s, "PointerEvent", "pointerdown", 2, 2)
  fire(s, "PointerEvent", "pointermove", 800, 400)
  assert_eq(s.stub.selection.ids, [2, 3, 4])
  fire(s, "PointerEvent", "pointerup", 800, 400)
  // なぞったので解かない
  assert_eq(s.stub.selection.ids, [2, 3, 4])
}

///|
test "キーは表へ。Enter は兄弟を足す Op、矢印は選び直し、Space は掴む手" {
  let s = stand()
  defer s.win.close()
  s.stub.selection = { ids: [3], anchor: Some(3), }
  press_key(s, "Enter")
  assert_eq(s.stub.applied.length(), 1)
  assert_true(s.stub.applied[0] is AddNode(..))
  press_key(s, "ArrowDown")
  assert_eq(s.stub.selection.ids, [4])
  press_key(s, " ")
  assert_true(s.map.space_held)
  fire(s, "KeyboardEvent", "keyup", 0, 0, key=" ")
  assert_false(s.map.space_held)
}

///|
test "掴んで動かすと落とし先を予告し、離すと MoveNode。Escape は取り消し" {
  let s = stand()
  defer s.win.close()
  let (ax, ay) = mid(s, 3)
  let (bx, by) = mid(s, 4)
  fire(s, "PointerEvent", "pointerdown", ax, ay)
  fire(s, "PointerEvent", "pointermove", bx, by + 20.0)
  assert_true(s.map.dragging is Some(_))
  assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "dragging"))
  assert_true(s.map.drop is Some(_))
  let line = s.pane.as_element().querySelector(".drop-line").unwrap()
  let parent = s.pane.as_element().querySelector(".drop-parent")
  // 兄弟の隙間なら線、箱の上なら drop-parent — どちらか一方の印が出る
  assert_true(
    line.getAttribute("visibility") == Some("visible") || parent is Some(_),
  )
  fire(s, "PointerEvent", "pointerup", bx, by + 20.0)
  assert_true(s.map.dragging is None)
  assert_true(s.stub.applied.last() is Some(MoveNode(..)))
  assert_false(@web.has_class(s.map.renderer.node_el(3).unwrap(), "dragging"))
  // 取り消し
  fire(s, "PointerEvent", "pointerdown", ax, ay)
  fire(s, "PointerEvent", "pointermove", bx, by + 20.0)
  let n = s.stub.applied.length()
  press_key(s, "Escape")
  assert_true(s.map.dragging is None)
  assert_eq(s.stub.applied.length(), n)
  assert_eq(line.getAttribute("visibility"), Some("hidden"))
}

///|
test "右クリックは触った箱を選び直してから行を開く。箱の外なら空の行（閉じる）" {
  let s = stand()
  defer s.win.close()
  let (ax, ay) = mid(s, 3)
  fire(s, "MouseEvent", "contextmenu", ax, ay)
  assert_eq(s.stub.selection.ids, [3])
  assert_true(s.map.menu.is_open())
  let rows = s.map.menu.el.querySelectorAll(".item")
  assert_true(rows.length() > 0)
  // 行を押せば Intent が走る（Rename の行 → 欄が開く）
  let rename = rows.filter(r => r.textContent().has_prefix("Rename"))
  assert_eq(rename.length(), 1)
  @dom.HTMLElement::cast_from_element(rename[0]).click()
  assert_false(s.map.menu.is_open())
  assert_eq(s.map.label.editing(), Some(3))
  fire(s, "MouseEvent", "contextmenu", 5, 5)
  assert_false(s.map.menu.is_open())
}

///|
test "ダブルクリックでラベルの欄が開き、打てば Rename。Escape で閉じる" {
  let s = stand()
  defer s.win.close()
  let (ax, ay) = mid(s, 3)
  fire(s, "MouseEvent", "dblclick", ax, ay)
  assert_eq(s.map.label.editing(), Some(3))
  let input = s.pane.as_element().querySelector(".label-editor").unwrap()
  assert_eq(@web.value(input), "a")
  @web.set_value(input, "ab")
  fire(s, "Event", "input", 0, 0, target=Some(input))
  assert_true(s.stub.applied.last() is Some(Rename(id=3, label="ab")))
  fire(s, "KeyboardEvent", "keydown", 0, 0, key="Escape", target=Some(input))
  assert_eq(s.map.label.editing(), None)
  // 箱が無いノードは開けない
  assert_false(s.map.begin_edit(99, None))
}

///|
test "カードは選ぶと枠が出て、開けば欄、閉じるときに変わっていれば 1 回だけ書く" {
  let s = stand()
  defer s.win.close()
  s.stub.picked = Some(5)
  s.map.refresh_selection()
  let pick = s.pane.as_element().querySelector(".card-pick").unwrap()
  assert_eq(pick.getAttribute("visibility"), Some("visible"))
  assert_eq(
    s.pane
    .as_element()
    .querySelector(".delete")
    .unwrap()
    .getAttribute("data-delete"),
    Some("5"),
  )
  s.map.edit_card(5)
  assert_eq(s.map.card.editing(), Some(5))
  let ta = s.pane.as_element().querySelector("textarea").unwrap()
  assert_eq(@web.value(ta), "```ts\nx\n```")
  // 変えずに閉じれば書かない
  let n = s.stub.applied.length()
  s.map.card.close()
  assert_eq(s.stub.applied.length(), n)
  s.map.edit_card(5)
  @web.set_value(ta, "```ts\ny\n```")
  s.map.card.close()
  assert_true(
    s.stub.applied.last() is Some(SetBlock(id=5, content=Raw("```ts\ny\n```"))),
  )
  // 無いカードは断る
  s.map.edit_card(99)
  assert_eq(s.stub.failed, ["Couldn't open that card"])
}

///|
test "act: 選び直しは reveal で寄せ、Copy は写せたときだけ cut、AddLink は URL でなければ断る" {
  let s = stand()
  defer s.win.close()
  s.map.act(Select(sel={ ids: [4], anchor: Some(4), }, reveal=true))
  assert_eq(s.stub.selection.ids, [4])
  s.map.act(Copy(cut=Some(Op(op=Delete(ids=[4]), edit=false))))
  assert_true(s.stub.applied.last() is Some(Delete(ids=[4])))
  s.stub.clipboard = "not a url"
  s.map.act(AddLink(id=3))
  assert_eq(s.stub.failed, ["Couldn't read that as a link"])
  s.stub.clipboard = " https://example.com/x \n"
  s.map.act(AddLink(id=3))
  assert_true(
    s.stub.applied.last()
    is Some(AddBlock(content=Link(href="https://example.com/x", ..), ..)),
  )
  s.map.act(Paste)
  assert_eq(s.stub.pasted, 1)
  s.map.act(Draw(id=2))
  assert_eq(s.stub.drawn, Some(2))
}

///|
test "ファイルの落とし先: 箱の上なら drop-parent、外なら無し、消せば消える" {
  let s = stand()
  defer s.win.close()
  let (ax, ay) = mid(s, 3)
  assert_eq(s.map.mark_file_drop(Some({ x: ax, y: ay, })), Some(3))
  assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "drop-parent"))
  assert_eq(s.map.mark_file_drop(Some({ x: 1, y: 1, })), None)
  assert_false(
    @web.has_class(s.map.renderer.node_el(3).unwrap(), "drop-parent"),
  )
  assert_eq(s.map.mark_file_drop(None), None)
}

///|
test "ホイールは動かし、Ctrl+ホイールは拡大。視点は world の transform に" {
  let s = stand()
  defer s.win.close()
  fire(s, "WheelEvent", "wheel", 100, 100)
  let world = s.pane.as_element().querySelector(".map-svg > g").unwrap()
  assert_eq(world.getAttribute("transform"), Some("translate(60 60) scale(1)"))
  let wheel = (dy : Double, ctrl : Bool) => {
    let init = @core.new_object()
    init._set("deltaY", @core.any(dy))
    init._set("cancelable", @core.any(true))
    let ev = @core.new(s.win.as_any()._get("WheelEvent"), [
      @core.any("wheel"),
      init,
    ])
    // happy-dom の WheelEvent は init の修飾キーを落とすので、出来事に直に置く
    ev._set("ctrlKey", @core.any(ctrl))
    s.pane.as_element().as_event_target().dispatchEvent(ev.cast()) |> ignore
  }
  wheel(30, false)
  assert_eq(world.getAttribute("transform"), Some("translate(60 30) scale(1)"))
  wheel(-100, true)
  assert_true(s.map.camera.k > 1.0)
}

///|
async test "to_svg: 全体を 1 枚に。選択の印は写さず画面には残す。透かしが付き、空なら None" {
  let s = stand()
  defer s.win.close()
  s.stub.selection = { ids: [3], anchor: Some(3), }
  s.map.refresh_selection()
  assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "selected"))
  let svg = s.map.to_svg().unwrap()
  assert_eq(svg.tagName(), "svg")
  assert_eq(svg.getAttribute("xmlns"), Some(@web.svg_ns))
  assert_eq(svg.getAttribute("viewBox").unwrap().split(" ").count(), 4)
  // 写しに class は残らず、選択の印も無い。画面の側には戻っている
  assert_eq(svg.querySelectorAll(".selected").length(), 0)
  assert_eq(svg.querySelectorAll("[class]").length(), 0)
  assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "selected"))
  // 線・ノード・透かしの 3 つの層
  let layers = svg.children()
  assert_eq(layers.length(), 3)
  assert_eq(layers[1].children().length(), s.map.layout.order.length())
  assert_eq(layers[2].tagName(), "a")
  assert_eq(layers[2].textContent(), "made with mmm")
  let empty = stand(md="")
  defer empty.win.close()
  assert_true(empty.map.to_svg() is None)
}

///|
/// **Escape は 1 段ずつ外へ。** 選んでいれば解き、解くものが無ければ帯へ抜ける。
/// 抜けた先の焦点は app が持つ（ここは呼ばれたかだけを見る）
test "Escape は選択を解き、解くものが無ければ帯へ抜ける" {
  let s = stand()
  defer s.win.close()
  s.stub.selection = { ids: [3], anchor: Some(3), }
  press_key(s, "Escape")
  assert_eq(s.stub.selection, @map.none)
  assert_eq(s.stub.left, 0)
  press_key(s, "Escape")
  assert_eq(s.stub.left, 1)
}

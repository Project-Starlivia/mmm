// 地図の器を happy-dom で立てて、入力 → 判断 → host への答えを固定する。
// 置き方・当たり・キーの表そのものは map/ の試験が持つ。ここは配線 — 出来事が
// 正しい判断に届き、印（selected / 輪 / 落とし先 / 欄）が DOM に出ることを見る。
// 窓の用意と出来事の起こし方はここ 1 つ — render の試験もこれを借りる

///|
/// happy-dom の文書を 1 つ用意して渡し、済んだら閉じる
fn with_doc(f : (@dom.Document) -> Unit raise) -> Unit raise {
  let w = @test_utils.create_happy_window()
  defer w.close()
  f(w.document())
}

///|
/// 出来事を起こす。`kind` は窓の構築子の名（`PointerEvent` / `KeyboardEvent` …）、
/// `init` はその欄。bubbles と cancelable は常に真
fn fire(
  doc : @dom.Document,
  target : @dom.Element,
  kind : String,
  name : String,
  init : Array[(String, @core.Any)],
) -> Unit {
  let obj = @core.new_object()
  obj._set("bubbles", @core.any(true))
  obj._set("cancelable", @core.any(true))
  for kv in init {
    obj._set(kv.0, kv.1)
  }
  let ev = @core.new(doc.as_any()._get("defaultView")._get(kind), [
    @core.any(name),
    obj,
  ])
  target.as_event_target().dispatchEvent(ev.cast()) |> ignore
}

///|
/// 見本。r(2) → a(3) / b(4)。b はコード 1 枚（5）
let sample_md = "# r\n\n## a\n\n## b\n\n```ts\nx\n```\n"

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
    measure: seven,
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
/// 器。文書・ペイン・地図・代役
struct Stand {
  doc : @dom.Document
  pane : @dom.HTMLElement
  map : Mindmap
  stub : Stub
}

///|
fn stand(doc : @dom.Document, md? : String = sample_md) -> Stand {
  let pane = @dom.HTMLElement::cast_from_element(@web.html(doc, "div", ""))
  doc.body().unwrap().append(pane.as_node())
  let stub = Stub::new(md)
  let map = Mindmap::new(pane, stub.host())
  map.render()
  { doc, pane, map, stub, }
}

///|
/// ペインへ出来事を流す。happy-dom はレイアウトを持たないので、ペインの左上は (0, 0)
fn Stand::fire(
  self : Stand,
  kind : String,
  name : String,
  x : Double,
  y : Double,
  shift? : Bool = false,
  key? : String = "",
  target? : @dom.Element? = None,
) -> Unit {
  fire(self.doc, target.unwrap_or(self.pane.as_element()), kind, name, [
    ("clientX", @core.any(x)),
    ("clientY", @core.any(y)),
    ("button", @core.any(0)),
    ("pointerId", @core.any(1)),
    ("pointerType", @core.any("mouse")),
    ("shiftKey", @core.any(shift)),
    ("ctrlKey", @core.any(false)),
    ("key", @core.any(key)),
  ])
}

///|
fn Stand::click_at(
  self : Stand,
  x : Double,
  y : Double,
  shift? : Bool = false,
) -> Unit {
  self.fire("PointerEvent", "pointerdown", x, y, shift~)
  self.fire("PointerEvent", "pointerup", x, y, shift~)
}

///|
/// その id の箱の真ん中（画面 px。視点は起動時の k=1, 60, 60）
fn Stand::mid(self : Stand, id : Int) -> (Double, Double) {
  let b = self.map.layout.boxes.get(id).unwrap()
  let c = self.map.camera
  (
    b.rect.x * c.k + c.tx + b.rect.w / 2.0,
    b.rect.y * c.k + c.ty + b.rect.h / 2.0,
  )
}

///|
fn Stand::press_key(self : Stand, key : String) -> Unit {
  self.fire("KeyboardEvent", "keydown", 0, 0, key~)
}

///|
test "立てると器が揃い、描いたノードは文書順。白紙なら言い出しが出る" {
  with_doc(d => {
    let s = stand(d)
    let pane = s.pane.as_element()
    assert_true(@web.has_class(pane, "map-pane"))
    assert_eq(pane.querySelectorAll(".node").length(), 3)
    assert_eq(pane.querySelector(".map-svg") is Some(_), true)
    assert_eq(pane.querySelector(".rubber") is Some(_), true)
    assert_eq(pane.querySelector(".label-editor") is Some(_), true)
    assert_eq(pane.querySelector(".card-editor") is Some(_), true)
    assert_eq(pane.querySelector(".card-pick") is Some(_), true)
    assert_eq(pane.querySelector(".drop-line") is Some(_), true)
  })
  with_doc(d => {
    let blank = stand(d, md="")
    let hint = blank.pane.querySelector(".pane-hint").unwrap()
    assert_true(@web.is_shown(hint))
  })
}

///|
test "箱を押して離すと選ぶ（reveal 付き）。Shift で範囲。背景を押して離すと解く" {
  with_doc(d => {
    let s = stand(d)
    let (ax, ay) = s.mid(3)
    s.click_at(ax, ay)
    assert_eq(s.stub.selection, @map.Selection::only(3))
    assert_eq(s.stub.reveals, [true])
    let (bx, by) = s.mid(4)
    s.click_at(bx, by, shift=true)
    assert_eq(s.stub.selection.ids, [3, 4])
    // 地図が持つ間は selected の枠
    s.map.refresh_selection()
    assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "selected"))
    assert_true(@web.has_class(s.map.renderer.node_el(4).unwrap(), "selected"))
    s.click_at(5, 5)
    assert_eq(s.stub.selection, @map.none)
  })
}

///|
test "md が持つ間は輪。輪は箱の 3px 内側で、本数は選択の数" {
  with_doc(d => {
    let s = stand(d)
    s.stub.holder = Md
    s.stub.selection = { ids: [2, 3], anchor: Some(3), }
    s.map.refresh_selection()
    let rings = s.pane.as_element().querySelectorAll(".caret-ring")
    assert_eq(rings.length(), 2)
    let b = s.map.layout.boxes.get(2).unwrap()
    assert_eq(rings[0].getAttribute("x"), Some(@web.num(b.rect.x + 3.0)))
    assert_eq(rings[0].getAttribute("width"), Some(@web.num(b.rect.w - 6.0)))
    assert_false(@web.has_class(s.map.renderer.node_el(3).unwrap(), "selected"))
    s.stub.selection = @map.none
    s.map.refresh_selection()
    assert_eq(s.pane.as_element().querySelectorAll(".caret-ring").length(), 0)
  })
}

///|
/// **動きは 1 フレームに 1 回進む**（#55）。だから pointermove の効果を見る前に
/// 1 フレーム待つ。離すときは待たずに流すので、pointerup の後は同期で読める
async test "背景をなぞると矩形選択（触れた箱を全部）" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let s = stand(w.document())
  s.fire("PointerEvent", "pointerdown", 2, 2)
  s.fire("PointerEvent", "pointermove", 800, 400)
  @dom.wait_animation_frame()
  assert_eq(s.stub.selection.ids, [2, 3, 4])
  s.fire("PointerEvent", "pointerup", 800, 400)
  // なぞったので解かない
  assert_eq(s.stub.selection.ids, [2, 3, 4])
}

///|
test "キーは表へ。Enter は兄弟を足す Op、矢印は選び直し、Space は掴む手" {
  with_doc(d => {
    let s = stand(d)
    s.stub.selection = @map.Selection::only(3)
    s.press_key("Enter")
    assert_eq(s.stub.applied.length(), 1)
    assert_true(s.stub.applied[0] is AddNode(..))
    s.press_key("ArrowDown")
    assert_eq(s.stub.selection.ids, [4])
    s.press_key(" ")
    assert_true(s.map.space_held)
    s.fire("KeyboardEvent", "keyup", 0, 0, key=" ")
    assert_false(s.map.space_held)
  })
}

///|
async test "掴んで動かすと落とし先を予告し、離すと MoveNode。Escape は取り消し" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let s = stand(w.document())
  let (ax, ay) = s.mid(3)
  let (bx, by) = s.mid(4)
  s.fire("PointerEvent", "pointerdown", ax, ay)
  s.fire("PointerEvent", "pointermove", bx, by + 20.0)
  // 動きは 1 フレームに 1 回進む（#55）
  @dom.wait_animation_frame()
  assert_true(s.map.mode is Dragging({ drop: Some(_), .. }))
  assert_true(@web.has_class(s.map.renderer.node_el(3).unwrap(), "dragging"))
  let line = s.pane.as_element().querySelector(".drop-line").unwrap()
  let parent = s.pane.as_element().querySelector(".drop-parent")
  // 兄弟の隙間なら線、箱の上なら drop-parent — どちらか一方の印が出る
  assert_true(
    line.getAttribute("visibility") == Some("visible") || parent is Some(_),
  )
  s.fire("PointerEvent", "pointerup", bx, by + 20.0)
  assert_true(s.map.mode is Idle)
  assert_true(s.stub.applied.last() is Some(MoveNode(..)))
  assert_false(@web.has_class(s.map.renderer.node_el(3).unwrap(), "dragging"))
  // 取り消し
  s.fire("PointerEvent", "pointerdown", ax, ay)
  s.fire("PointerEvent", "pointermove", bx, by + 20.0)
  @dom.wait_animation_frame()
  let n = s.stub.applied.length()
  s.press_key("Escape")
  assert_true(s.map.mode is Idle)
  assert_eq(s.stub.applied.length(), n)
  assert_eq(line.getAttribute("visibility"), Some("hidden"))
}

///|
test "右クリックは触った箱を選び直してから行を開く。箱の外なら空の行（閉じる）" {
  with_doc(d => {
    let s = stand(d)
    let (ax, ay) = s.mid(3)
    s.fire("MouseEvent", "contextmenu", ax, ay)
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
    s.fire("MouseEvent", "contextmenu", 5, 5)
    assert_false(s.map.menu.is_open())
  })
}

///|
test "ダブルクリックでラベルの欄が開き、打てば Rename。Escape で閉じる" {
  with_doc(d => {
    let s = stand(d)
    let (ax, ay) = s.mid(3)
    s.fire("MouseEvent", "dblclick", ax, ay)
    assert_eq(s.map.label.editing(), Some(3))
    let input = s.pane.as_element().querySelector(".label-editor").unwrap()
    assert_eq(@web.value(input), "a")
    @web.set_value(input, "ab")
    s.fire("Event", "input", 0, 0, target=Some(input))
    assert_true(s.stub.applied.last() is Some(Rename(id=3, label="ab")))
    s.fire("KeyboardEvent", "keydown", 0, 0, key="Escape", target=Some(input))
    assert_eq(s.map.label.editing(), None)
    // 箱が無いノードは開けない
    assert_false(s.map.begin_edit(99, None))
  })
}

///|
/// `data-card` が中身の id であることは render の試験が見る。ここは押せば選ばれること
test "カードを押すと、そのカードの中身を選ぶ。もう一度押せば外れる" {
  with_doc(d => {
    let s = stand(d)
    let code = s.pane.as_element().querySelector(".code-bg").unwrap()
    s.fire("MouseEvent", "click", 0, 0, target=Some(code))
    assert_eq(s.stub.picked, Some(5))
    s.fire("MouseEvent", "click", 0, 0, target=Some(code))
    assert_eq(s.stub.picked, None)
  })
}

///|
test "カードは選ぶと枠が出て、開けば欄、閉じるときに変わっていれば 1 回だけ書く" {
  with_doc(d => {
    let s = stand(d)
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
      s.stub.applied.last()
      is Some(SetBlock(id=5, content=None, source=Some("```ts\ny\n```"))),
    )
    // 無いカードは断る
    s.map.edit_card(99)
    assert_eq(s.stub.failed, ["Couldn't open that card"])
    // 外せば印も × の宛先も消える
    s.stub.picked = None
    s.map.refresh_selection()
    assert_eq(pick.getAttribute("visibility"), Some("hidden"))
    assert_eq(
      s.pane
      .as_element()
      .querySelector(".delete")
      .unwrap()
      .getAttribute("data-delete"),
      None,
    )
  })
}

///|
test "act: 選び直しは reveal で寄せ、Copy は写せたときだけ cut、AddLink は URL でなければ断る" {
  with_doc(d => {
    let s = stand(d)
    s.map.act(Select(sel=@map.Selection::only(4), reveal=true))
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
      is Some(
        AddBlock(content=Some(Link(href="https://example.com/x", ..)), ..)
      ),
    )
    s.map.act(Paste)
    assert_eq(s.stub.pasted, 1)
    s.map.act(Draw(id=2))
    assert_eq(s.stub.drawn, Some(2))
  })
}

///|
test "ファイルの落とし先: 箱の上なら drop-parent、外なら無し、消せば消える" {
  with_doc(d => {
    let s = stand(d)
    let (ax, ay) = s.mid(3)
    assert_eq(s.map.mark_file_drop(Some({ x: ax, y: ay, })), Some(3))
    assert_true(
      @web.has_class(s.map.renderer.node_el(3).unwrap(), "drop-parent"),
    )
    assert_eq(s.map.mark_file_drop(Some({ x: 1, y: 1, })), None)
    assert_false(
      @web.has_class(s.map.renderer.node_el(3).unwrap(), "drop-parent"),
    )
    assert_eq(s.map.mark_file_drop(None), None)
  })
}

///|
test "ホイールは動かし、Ctrl+ホイールは拡大。視点は world の transform に" {
  with_doc(d => {
    let s = stand(d)
    s.fire("WheelEvent", "wheel", 100, 100)
    let world = s.pane.as_element().querySelector(".map-svg > g").unwrap()
    assert_eq(
      world.getAttribute("transform"),
      Some("translate(60 60) scale(1)"),
    )
    let wheel = (dy : Double, ctrl : Bool) => {
      let init = @core.new_object()
      init._set("deltaY", @core.any(dy))
      init._set("cancelable", @core.any(true))
      let ev = @core.new(d.as_any()._get("defaultView")._get("WheelEvent"), [
        @core.any("wheel"),
        init,
      ])
      // happy-dom の WheelEvent は init の修飾キーを落とすので、出来事に直に置く
      ev._set("ctrlKey", @core.any(ctrl))
      s.pane.as_element().as_event_target().dispatchEvent(ev.cast()) |> ignore
    }
    wheel(30, false)
    assert_eq(
      world.getAttribute("transform"),
      Some("translate(60 30) scale(1)"),
    )
    wheel(-100, true)
    assert_true(s.map.camera.k > 1.0)
  })
}

///|
/// 針は視点・選択・ペインが前と同じなら当て直さない。動けば当て直す（#249）
test "針は視点か選択が変わったときだけ当て直す" {
  with_doc(d => {
    let s = stand(d)
    let aimed = s.map.aimed
    assert_true(aimed is Some(_))
    s.map.refresh_selection()
    assert_true(physical_equal(s.map.aimed, aimed))
    s.stub.selection = @map.Selection::only(3)
    s.map.refresh_selection()
    assert_false(physical_equal(s.map.aimed, aimed))
  })
}

///|
async test "to_svg: 全体を 1 枚に。選択の印は写さず画面には残す。透かしが付き、空なら None" {
  // 窓は自分で閉じる — with_doc の閉包は同期で、中で wait できない
  let w = @test_utils.create_happy_window()
  defer w.close()
  let s = stand(w.document())
  s.stub.selection = @map.Selection::only(3)
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
  let empty = stand(w.document(), md="")
  assert_true(empty.map.to_svg() is None)
}

///|
/// **Escape は 1 段ずつ外へ。** 選んでいれば解き、解くものが無ければ帯へ抜ける。
/// 抜けた先の焦点は app が持つ（ここは呼ばれたかだけを見る）
test "Escape は選択を解き、解くものが無ければ帯へ抜ける" {
  with_doc(d => {
    let s = stand(d)
    s.stub.selection = @map.Selection::only(3)
    s.press_key("Escape")
    assert_eq(s.stub.selection, @map.none)
    assert_eq(s.stub.left, 0)
    s.press_key("Escape")
    assert_eq(s.stub.left, 1)
  })
}

///|
/// 端の ↓ は拾うが動かない — ページにも渡さない（#244）
test "カードの端で ↓ を押しても、出来事はブラウザに渡さない" {
  with_doc(d => {
    let s = stand(d)
    s.stub.picked = Some(5)
    let init = @core.new_object()
    init._set("bubbles", @core.any(true))
    init._set("cancelable", @core.any(true))
    init._set("key", @core.any("ArrowDown"))
    let ev = @core.new(d.as_any()._get("defaultView")._get("KeyboardEvent"), [
      @core.any("keydown"),
      init,
    ])
    s.pane.as_element().as_event_target().dispatchEvent(ev.cast()) |> ignore
    assert_eq(s.stub.picked, Some(5))
    let prevented : Bool = ev._get("defaultPrevented").cast()
    assert_true(prevented)
    // 拾わないキー（F5）は渡す
    let other = @core.new(
      d.as_any()._get("defaultView")._get("KeyboardEvent"),
      [@core.any("keydown"), init],
    )
    other._set("key", @core.any("F5"))
    s.pane.as_element().as_event_target().dispatchEvent(other.cast()) |> ignore
    let passed : Bool = other._get("defaultPrevented").cast()
    assert_false(passed)
  })
}

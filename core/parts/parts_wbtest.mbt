// 部品を happy-dom で組んで、形（class / role / 字）と振る舞い（開く・閉じる・押す・辿る）を固定する。

///|
fn doc_of(w : @dom.Window) -> @dom.Document {
  w.document()
}

///|
fn attr(e : @dom.Element, name : String) -> String {
  e.getAttribute(name).unwrap()
}

///|
test "icon: 線の絵は stroke、ロゴは塗り、動きのある絵は class が付く。知らない名は無い" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let folder = icon(d, "folder")
  assert_eq(attr(folder, "class"), "icon")
  assert_eq(attr(folder, "viewBox"), "0 0 24 24")
  assert_eq(attr(folder, "stroke"), "currentColor")
  assert_eq(attr(folder, "fill"), "none")
  assert_eq(folder.querySelectorAll("path").length(), 1)
  assert_eq(attr(icon(d, "mark-github"), "fill"), "currentColor")
  assert_eq(attr(icon(d, "check"), "class"), "icon drawn")
  assert_eq(attr(icon(d, "loader-circle"), "class"), "icon spun")
  assert_true(is_icon("pencil"))
  assert_false(is_icon("nope"))
  assert_eq(names().length(), 35)
  assert_eq(names()[0], "folder")
}

///|
test "label: 字と絵を並べる。後ろにも置ける" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let a = label(d, "SVG", "download", false)
  assert_eq(a.length(), 2)
  assert_eq(@dom.Element::cast_from_node(a[0]).tagName().to_lower(), "svg")
  let b = label(d, "SVG", "download", true)
  assert_eq(@dom.Element::cast_from_node(b[0]).textContent(), "SVG")
}

///|
test "nod: 済めば check を置く。しくじれば何も置かない" {
  let put : Array[String] = []
  let done : Array[Bool] = []
  nod(k => k(true), m => put.push(m), ok => done.push(ok))
  assert_eq(put, ["check"])
  assert_eq(done, [true])
  nod(k => k(false), m => put.push(m), ok => done.push(ok))
  assert_eq(put, ["check"])
  assert_eq(done, [true, false])
}

///|
test "notice: 印・詫び・文言。blocked は詫びない" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let n = notice(d, "circle-alert", "Couldn't save", true)
  assert_eq(attr(n, "class"), "notice")
  assert_eq(attr(n, "role"), "alert")
  assert_eq(n.querySelector(".lead").unwrap().textContent(), "Sorry...")
  assert_eq(n.querySelector(".msg").unwrap().textContent(), "Couldn't save")
  let b = notice(d, "triangle-alert", "Nothing to export yet", false)
  assert_true(b.querySelector(".lead") is None)
  assert_eq(failed_words.length(), 19)
  assert_eq(blocked_words, ["Nothing to export yet"])
}

///|
test "pane_hint: 真ん中の一手だけが .act" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let h = pane_hint(d, "map")
  assert_eq(attr(h, "class"), "pane-hint")
  assert_eq(attr(h, "aria-hidden"), "true")
  assert_eq(h.textContent(), "Press Enter to start")
  assert_eq(h.querySelector(".act").unwrap().textContent(), "Enter")
  assert_eq(pane_hint(d, "md").textContent(), "Write a # Title to start")
}

///|
test "pane_tool: class に名が付く" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  assert_eq(
    attr(pane_tool(doc_of(w), "map-center"), "class"),
    "pane-tool map-center",
  )
}

///|
/// 見本の並び。押した行を覚える
fn sample(pressed : Array[String]) -> Array[Entry] {
  [
    Caption("notes.md", Some("file")),
    Run(row("New", key=Some("Mod+N"), mark=Some("file-plus")), () => {
      pressed.push("new")
    }),
    Run(row("Open", disabled=Why("No access")), () => pressed.push("open")),
    Sub(
      row("Recent", mark=Some("clock")),
      [
        Run(row("a.md"), () => pressed.push("a")),
        Run(row("b.md"), () => pressed.push("b")),
      ],
      None,
    ),
    Sep,
    Done(
      row("Copy link", mark=Some("link"), note=Some(k => k(["Long link"]))),
      k => {
        pressed.push("copy")
        k(true)
      },
    ),
    Run(row("Plain"), () => pressed.push("plain")),
  ]
}

///|
test "rows: 行の形 — 見出し・区切り・絵の空欄・キー・入れ子の印・沈む理由・但し書き" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let el = rows(d, sample([]))
  assert_eq(attr(el, "role"), "menu")
  assert_eq(el.querySelectorAll(".item").length(), 5)
  assert_eq(el.querySelectorAll("hr").length(), 1)
  let cap = el.querySelector(".caption").unwrap()
  assert_eq(cap.textContent(), "notes.md")
  assert_eq(cap.querySelectorAll(".icon").length(), 1)
  let items = el.querySelectorAll(".item")
  assert_eq(items[0].querySelector(".key").unwrap().textContent(), "Mod+N")
  assert_eq(attr(items[1], "aria-disabled"), "true")
  assert_eq(attr(items[1], "title"), "No access")
  assert_eq(attr(items[1], "aria-label"), "Open, No access")
  assert_eq(attr(items[2], "aria-haspopup"), "menu")
  assert_eq(items[2].querySelector(".key").unwrap().textContent(), "▸")
  assert_eq(
    items[3].querySelector(".note-box .tip").unwrap().textContent(),
    "Long link",
  )
  // 絵の無い行にも空欄（この並びには絵を持つ行がある）
  assert_eq(items[4].querySelectorAll(".icon").length(), 1)
  assert_eq(
    items[4].querySelector(".icon").unwrap().tagName().to_lower(),
    "span",
  )
  // 絵を持つ行が 1 つも無ければ空欄も無い
  let bare = rows(d, [Run(row("x"), () => ())])
  assert_eq(bare.querySelectorAll(".icon").length(), 0)
}

///|
test "Menu: 開く・押して閉じる・沈む行は押せない・外を押せば閉じる・Escape" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let pressed : Array[String] = []
  let m = Menu::new(d)
  assert_false(m.is_open())
  m.show(10, 20, sample(pressed))
  assert_true(m.is_open())
  let items = m.el.querySelectorAll(".item")
  @dom.HTMLElement::cast_from_element(items[1]).click()
  assert_eq(pressed, [])
  assert_true(m.is_open())
  @dom.HTMLElement::cast_from_element(items[0]).click()
  assert_eq(pressed, ["new"])
  assert_false(m.is_open())
  // Done は閉じずに走り、絵がチェックになる
  m.show(10, 20, sample(pressed))
  let copy = m.el.querySelectorAll(".item")[3]
  @dom.HTMLElement::cast_from_element(copy).click()
  assert_eq(pressed, ["new", "copy"])
  assert_true(m.is_open())
  assert_eq(
    attr(copy.querySelector(":scope > .icon").unwrap(), "class"),
    "icon drawn",
  )
  // Escape で閉じる
  let esc = @core.new_object()
  esc._set("key", @core.any("Escape"))
  esc._set("bubbles", @core.any(true))
  let ev = @core.new(w.as_any()._get("KeyboardEvent"), [
    @core.any("keydown"),
    esc,
  ])
  d.documentElement().as_event_target().dispatchEvent(ev.cast()) |> ignore
  assert_false(m.is_open())
}

///|
test "Menu: 入れ子は行の隣に開き、子から選べば親ごと閉じる" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let pressed : Array[String] = []
  let m = Menu::new(d)
  m.show(0, 0, sample(pressed))
  let recent = m.el.querySelectorAll(".item")[2]
  @dom.HTMLElement::cast_from_element(recent).click()
  assert_eq(attr(recent, "aria-expanded"), "true")
  let sub = m.sub.unwrap()
  assert_true(sub.is_open())
  assert_eq(sub.el.querySelectorAll(".item").length(), 2)
  @dom.HTMLElement::cast_from_element(sub.el.querySelectorAll(".item")[1]).click()
  assert_eq(pressed, ["b"])
  assert_false(sub.is_open())
  assert_false(m.is_open())
  m.show(0, 0, sample(pressed))
  m.close_sub()
  assert_eq(attr(m.el.querySelectorAll(".item")[2], "aria-expanded"), "false")
}

///|
/// 欄に打つ（値を入れて、打ったと言う）
fn type_in(w : @dom.Window, input : @dom.Element, text : String) -> Unit {
  @web.set_value(input, text)
  let init = @core.new_object()
  init._set("bubbles", @core.any(true))
  let ev = @core.new(w.as_any()._get("Event"), [@core.any("input"), init])
  input.as_event_target().dispatchEvent(ev.cast()) |> ignore
}

///|
test "ask_form: 題・補足・絵・字と欄の並び・ボタンの綴り。欄の値は並び順で読める" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let (form, values) = ask_form(
    d,
    {
      title: "Name this image",
      note: Some("Images here point to ./pics/."),
      ok: "Save",
      cancel: None,
      parts: [
        Word("![]("),
        Blank({ value: "shot", check: None, }),
        Word(".webp)"),
      ],
      preview: Some("data:,"),
    },
    () => (),
  )
  assert_eq(attr(form, "method"), "dialog")
  assert_eq(
    form.querySelector(".title").unwrap().textContent(),
    "Name this image",
  )
  assert_eq(
    form.querySelector(".note").unwrap().textContent(),
    "Images here point to ./pics/.",
  )
  assert_eq(attr(form.querySelector(".shot").unwrap(), "src"), "data:,")
  // 欄は並びの中に居る
  assert_eq(form.querySelector(".parts").unwrap().textContent(), "![](.webp)")
  let input = form.querySelector(".parts input").unwrap()
  assert_eq(attr(input, "size"), "6")
  let buttons = form.querySelectorAll(".row button")
  assert_eq(buttons[0].textContent(), "Cancel")
  assert_eq(attr(buttons[0], "type"), "button")
  assert_eq(buttons[1].textContent(), "Save")
  assert_eq(attr(buttons[1], "value"), "ok")
  // 見直す相手が居なければ、理由の置き場も出さない
  assert_eq(form.querySelectorAll(".bad").length(), 0)
  assert_eq(values(), ["shot"])
  @web.set_value(input, "later")
  assert_eq(values(), ["later"])
}

///|
test "ask_form: 打つそばから見直す — だめな間は進む道が閉じ、理由が並びのすぐ下に出る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let (form, _) = ask_form(
    d,
    {
      title: "New file name",
      note: None,
      ok: "Rename",
      cancel: Some("Keep as is"),
      parts: [
        Blank({
          value: "",
          check: Some(v => if v == "" { Some("Give it a name") } else { None }),
        }),
      ],
      preview: None,
    },
    () => (),
  )
  let go = form.querySelector(".go").unwrap()
  let bad = form.querySelector(".bad").unwrap()
  assert_eq(attr(bad, "aria-live"), "polite")
  // 開いた時点で見直してある
  assert_true(go.hasAttribute("disabled"))
  assert_false(bad.hasAttribute("hidden"))
  assert_eq(bad.textContent(), "Give it a name")
  type_in(w, form.querySelector("input").unwrap(), "notes.md")
  assert_false(go.hasAttribute("disabled"))
  assert_true(bad.hasAttribute("hidden"))
  assert_eq(bad.textContent(), "")
  assert_eq(form.querySelectorAll(".row button")[0].textContent(), "Keep as is")
}

///|
test "ask: 器に載せて開く。進めば値、断れば何も返らない。どちらでも器は残らない" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = doc_of(w)
  let a : Ask = {
    title: "New file name",
    note: None,
    ok: "Rename",
    cancel: None,
    parts: [Blank({ value: "notes.md", check: None, })],
    preview: None,
  }
  let out : Array[Array[String]?] = []
  ask(d, a, v => out.push(v))
  let dlg = d.querySelector("dialog.ask").unwrap()
  assert_true(dlg.hasAttribute("open"))
  // 進む側は送信そのもの。押したボタンの value が returnValue になる
  @web.set_value(d.querySelector("dialog.ask input").unwrap(), "renamed.md")
  @dom.HTMLElement::cast_from_element(
    d.querySelector("dialog.ask .go").unwrap(),
  ).click()
  assert_eq(out, [Some(["renamed.md"])])
  assert_eq(d.querySelectorAll("dialog.ask").length(), 0)
  // 断る側は閉じるだけ（returnValue は空のまま）
  ask(d, a, v => out.push(v))
  @dom.HTMLElement::cast_from_element(
    d.querySelectorAll("dialog.ask .row button")[0],
  ).click()
  assert_eq(out, [Some(["renamed.md"]), None])
  assert_eq(d.querySelectorAll("dialog.ask").length(), 0)
}

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

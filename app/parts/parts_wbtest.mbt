// 部品を happy-dom で組んで、形（class / role / 字）と振る舞い（開く・閉じる・押す・辿る）を固定する。
// 窓の用意と出来事の起こし方はここ 1 つ — 各ファイルの試験はこれを借りる

///|
/// happy-dom の文書を 1 つ用意して渡し、済んだら閉じる
fn with_doc(f : (@dom.Document) -> Unit raise) -> Unit raise {
  let w = @test_utils.create_happy_window()
  defer w.close()
  f(w.document())
}

///|
/// 出来事を起こす。`kind` は窓の構築子の名（`Event` / `KeyboardEvent`）、`key` はキーの名
fn fire(
  doc : @dom.Document,
  target : @dom.Element,
  kind : String,
  name : String,
  key? : String,
) -> Unit {
  let init = @core.new_object()
  init._set("bubbles", @core.any(true))
  match key {
    Some(k) => init._set("key", @core.any(k))
    None => ()
  }
  let ev = @core.new(doc.as_any()._get("defaultView")._get(kind), [
    @core.any(name),
    init,
  ])
  target.as_event_target().dispatchEvent(ev.cast()) |> ignore
}

///|
fn attr(e : @dom.Element, name : String) -> String {
  e.getAttribute(name).unwrap()
}

///|
test "icon: 線の絵は stroke、ロゴは塗り、動きのある絵は class が付く。名は重ならない" {
  with_doc(d => {
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
    // 表の順で並び、同じ名は 2 度出ない
    assert_eq(names()[0], "folder")
    assert_eq(Set::from_array(names()).length(), names().length())
  })
}

///|
test "label: 字と絵を並べる。後ろにも置ける" {
  with_doc(d => {
    let a = label(d, "SVG", "download", false)
    assert_eq(a.length(), 2)
    assert_eq(@dom.Element::cast_from_node(a[0]).tagName().to_lower(), "svg")
    let b = label(d, "SVG", "download", true)
    assert_eq(@dom.Element::cast_from_node(b[0]).textContent(), "SVG")
  })
}

///|
test "icon_button: 送らないボタンに絵 1 つ。名乗りは title と aria-label（label が無ければ title）" {
  with_doc(d => {
    let b = icon_button(d, "crosshair", title="Center — Home", label="Center")
    assert_eq(attr(b, "type"), "button")
    assert_eq(attr(b, "title"), "Center — Home")
    assert_eq(attr(b, "aria-label"), "Center")
    assert_eq(b.querySelectorAll("svg").length(), 1)
    let same = icon_button(d, "eraser", title="Eraser")
    assert_eq(attr(same, "aria-label"), "Eraser")
    let bare = icon_button(d, "chevron-down")
    assert_eq(bare.getAttribute("title"), None)
    assert_eq(bare.getAttribute("aria-label"), None)
  })
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
  with_doc(d => {
    let n = notice(d, "circle-alert", "Couldn't save", true)
    assert_eq(attr(n, "class"), "notice")
    assert_eq(attr(n, "role"), "alert")
    assert_eq(n.querySelector(".lead").unwrap().textContent(), "Sorry...")
    assert_eq(n.querySelector(".msg").unwrap().textContent(), "Couldn't save")
    let b = notice(d, "triangle-alert", "Nothing to export yet", false)
    assert_true(b.querySelector(".lead") is None)
  })
}

///|
/// 言葉の表の性質。数は数えない — 足すたびに壊れて、何も言わない
test "words: failed は Couldn't か環境の理由、blocked は次の一手。2 つの表は交わらず、同じ言葉は 2 度無い" {
  for w in failed_words {
    assert_true(w.has_prefix("Couldn't ") || w == no_file_access)
    assert_false(blocked_words.contains(w))
  }
  for w in blocked_words {
    assert_true(w.has_prefix("Select ") || w.has_prefix("Nothing "))
  }
  let all = failed_words + blocked_words
  assert_eq(Set::from_array(all).length(), all.length())
}

///|
test "pane_hint: 真ん中の一手だけが .act" {
  with_doc(d => {
    let h = pane_hint(d, Map)
    assert_eq(attr(h, "class"), "pane-hint")
    assert_eq(attr(h, "aria-hidden"), "true")
    assert_eq(h.textContent(), "Press Enter to start")
    assert_eq(h.querySelector(".act").unwrap().textContent(), "Enter")
    assert_eq(pane_hint(d, Md).textContent(), "Write a # Title to start")
  })
}

///|
test "pane_tool: class に名が付く" {
  with_doc(d => {
    assert_eq(attr(pane_tool(d, "map-center"), "class"), "pane-tool map-center")
  })
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
      row("Copy link", mark=Some("link"), caveat=Some(k => k(["Long link"]))),
      k => {
        pressed.push("copy")
        k(true)
      },
    ),
    Run(row("Plain"), () => pressed.push("plain")),
  ]
}

///|
test "unless: 押せるなら No、理由があれば Why、無ければ Yes" {
  assert_eq(unless(true, why="x"), No)
  assert_eq(unless(false, why="x"), Why("x"))
  assert_eq(unless(false), Yes)
  assert_eq(unless(false, why?=None), Yes)
}

///|
test "rows: 行の形 — 見出し・区切り・絵の空欄・キー・入れ子の印・沈む理由・但し書き" {
  with_doc(d => {
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
    // 字の span に空の class は付かない
    assert_eq(
      items[4].querySelector("span:not(.icon)").unwrap().getAttribute("class"),
      None,
    )
    // 絵を持つ行が 1 つも無ければ空欄も無い
    let bare = rows(d, [Run(row("x"), () => ())])
    assert_eq(bare.querySelectorAll(".icon").length(), 0)
  })
}

///|
test "Menu: 開く・押して閉じる・沈む行は押せない・外を押せば閉じる・Escape" {
  with_doc(d => {
    let pressed : Array[String] = []
    let m = Menu::new(d)
    assert_false(m.is_open())
    m.show(10, 20, () => sample(pressed))
    assert_true(m.is_open())
    let items = m.el.querySelectorAll(".item")
    @web.click(items[1])
    assert_eq(pressed, [])
    assert_true(m.is_open())
    @web.click(items[0])
    assert_eq(pressed, ["new"])
    assert_false(m.is_open())
    // Done は閉じずに走り、絵がチェックになる
    m.show(10, 20, () => sample(pressed))
    let copy = m.el.querySelectorAll(".item")[3]
    @web.click(copy)
    assert_eq(pressed, ["new", "copy"])
    assert_true(m.is_open())
    assert_eq(
      attr(copy.querySelector(":scope > .icon").unwrap(), "class"),
      "icon drawn",
    )
    // Escape で閉じる
    fire(d, d.documentElement(), "KeyboardEvent", "keydown", key="Escape")
    assert_false(m.is_open())
  })
}

///|
test "Menu: 入れ子は行の隣に開き、子から選べば親ごと閉じる" {
  with_doc(d => {
    let pressed : Array[String] = []
    let m = Menu::new(d)
    m.show(0, 0, () => sample(pressed))
    let recent = m.el.querySelectorAll(".item")[2]
    @web.click(recent)
    assert_eq(attr(recent, "aria-expanded"), "true")
    let sub = m.sub.unwrap()
    assert_true(sub.is_open())
    assert_eq(sub.el.querySelectorAll(".item").length(), 2)
    @web.click(sub.el.querySelectorAll(".item")[1])
    assert_eq(pressed, ["b"])
    assert_false(sub.is_open())
    assert_false(m.is_open())
    m.show(0, 0, () => sample(pressed))
    m.close_sub()
    assert_eq(attr(m.el.querySelectorAll(".item")[2], "aria-expanded"), "false")
  })
}

///|
test "Menu: Flip は閉じずに走り、並びが次の状態を名乗る。焦点は同じ位置に残る" {
  with_doc(d => {
    let light : Ref[Bool] = { val: false, }
    let m = Menu::new(d)
    // 並びは状態から引く。綴りを持つのは表 1 つで、行は持たない
    m.show(0, 0, () => {
      [
        Run(row("Undo"), () => ()),
        Flip(
          row(
            if light.val {
              "Dark theme"
            } else {
              "Light theme"
            },
            mark=Some(if light.val { "moon" } else { "sun" }),
          ),
          () => light.val = !light.val,
        ),
      ]
    })
    let before = m.el.querySelectorAll(".item")[1]
    assert_eq(before.textContent(), "Light theme")
    @web.focus(before)
    @web.click(before)
    assert_true(light.val)
    assert_true(m.is_open())
    let after = m.el.querySelectorAll(".item")
    assert_eq(after[1].textContent(), "Dark theme")
    // 行は作り直されるが、手の置き場は動かない
    let active : @dom.Element? = @core.identity_option(
      d.activeElement().as_any(),
    )
    match active {
      Some(a) => assert_true(@web.same(a, after[1]))
      None => fail("焦点が行に戻っていない")
    }
  })
}

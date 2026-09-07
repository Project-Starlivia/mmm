// 束ねる場所を happy-dom で立てる。CodeMirror の代役は md を 1 本持つだけの写しで、
// 編集を当てたらサイクルを回す（本物は EditorState のトランザクションがそうする）。
// ディスクは手元の置き場。窓（たずね）は happy-dom の <dialog> で本当に開いて閉じる

///|
/// CodeMirror の代役。文書と選択を持ち、受けた指図を覚える
struct Fake {
  mut md : String
  mut cached : (String, @read.Survey)?
  mut holder : @read.Holder
  mut selection : @map.Selection
  picked : Int?
  mut app : App?
  log : Array[String]
  mut hint : Bool
}

///|
fn Fake::survey(self : Fake) -> @read.Survey {
  match self.cached {
    Some((md, s)) if md == self.md => s
    _ => {
      let s = @read.survey(self.md)
      self.cached = Some((self.md, s))
      s
    }
  }
}

///|
/// 編集を当てて、サイクルを 1 回回す（本物のトランザクションと同じ順）
fn Fake::change(self : Fake, next : String) -> Unit {
  let prev = self.survey()
  self.md = next
  self.app.unwrap().cycle(Some(prev), true)
}

///|
fn Fake::editor(self : Fake) -> Editor {
  {
    text: () => self.md,
    survey: () => self.survey(),
    holder: () => self.holder,
    selection: () => self.selection,
    picked: () => self.picked,
    set_text: t => {
      self.md = t
      self.log.push("set_text")
      self.app.unwrap().cycle(None, true)
    },
    apply: (sets, held, focus) => {
      let mut md = self.md
      for set in sets {
        md = @tree.patched(md, set)
      }
      self.log.push(
        "apply " +
        sets.length().to_string() +
        (if held {
          " focus=" + focus.map(f => f.to_string()).unwrap_or("-")
        } else {
          ""
        }),
      )
      self.change(md)
    },
    select: a => {
      self.log.push(
        "select " + a.map(x => x.to_json().stringify()).unwrap_or("-"),
      )
    },
    hold: (h, a) => {
      self.holder = h
      self.log.push(
        "hold " +
        (if h == Md { "md" } else { "map" }) +
        " " +
        a.map(x => x.to_json().stringify()).unwrap_or("-"),
      )
    },
    reveal: pos => self.log.push("reveal " + pos.to_string()),
    undo: () => self.log.push("undo"),
    redo: () => self.log.push("redo"),
    focus: () => self.log.push("focus"),
    set_theme: dark => self.log.push("theme " + dark.to_string()),
    show_hint: on => self.hint = on,
    tokens: (lines, _) => lines.map(l => [{ text: l, cls: "", }]),
    tokens_block: text => {
      text
      .split("\n")
      .map(l => ([{ text: l.to_owned(), cls: "", }] : Array[@mindmap.Token]))
      .collect()
    },
    epoch: () => 0,
    on_language_ready: _ => (),
  }
}

///|
/// 手元の置き場（ディスクの代わり）。何も覚えていない
fn memo_io() -> @disk.Io {
  let table : Map[String, @core.Any] = Map([])
  @disk.Io::new(
    @disk.Handles::new({
      read: fn(key) { table.get(key).unwrap_or(@core.null()) },
      write: fn(key, value) { table[key] = value },
      remove: fn(key) { table.remove(key) },
      same: fn(_, _) { false },
      is_file: _ => false,
      is_dir: _ => false,
    }),
  )
}

///|
struct Stand {
  win : @dom.Window
  doc : @dom.Document
  fake : Fake
  app : App
}

///|
/// index.html と同じ id の器を立てる
fn stand() -> Stand {
  let win = @test_utils.create_happy_window()
  let doc = win.document()
  let body = doc.body().unwrap()
  @web.set_style(doc.documentElement(), "--accent", "#5932ff")
  let mk = (tag : String, id : String, into : @dom.Element) => {
    let e = doc.createElement(tag)
    e.setAttribute("id", id)
    into.append(e.as_node())
    e
  }
  let bar = doc.createElement("header")
  body.append(bar.as_node())
  mk("svg", "logo", bar) |> ignore
  mk("span", "filename", bar) |> ignore
  mk("span", "dirty", bar) |> ignore
  mk("button", "files", bar) |> ignore
  mk("button", "export", bar) |> ignore
  mk("button", "export-way", bar) |> ignore
  mk("button", "more", bar) |> ignore
  let panes = mk("main", "panes", body.as_element())
  mk("section", "md-pane", panes) |> ignore
  mk("div", "splitter", panes) |> ignore
  mk("section", "map-pane", panes) |> ignore
  let fake : Fake = {
    md: "",
    cached: None,
    holder: Md,
    selection: @map.none,
    picked: None,
    app: None,
    log: [],
    hint: false,
  }
  let app = App::new(doc, fake.editor(), memo_io(), measure=(_, text) => {
    text.char_length().to_double() * 7.0
  })
  fake.app = Some(app)
  app.boot()
  { win, doc, fake, app, }
}

///|
fn Stand::text_of(self : Stand, id : String) -> String {
  self.doc.getElementById(id).unwrap().textContent()
}

///|
fn Stand::nodes(self : Stand) -> Int {
  self.doc.querySelectorAll(".map-svg .node").length()
}

///|
test "立ち上がりは空。名乗りは mmm / empty.md、言い出しが出て、書き出しは沈む。焦点は md へ" {
  let s = stand()
  defer s.win.close()
  assert_eq(s.doc.title(), "mmm")
  assert_eq(s.text_of("filename"), "empty.md")
  assert_true(s.fake.hint)
  assert_eq(s.nodes(), 0)
  assert_eq(
    s.doc.getElementById("dirty").unwrap().getAttribute("hidden"),
    Some(""),
  )
  assert_eq(
    s.doc.getElementById("export").unwrap().getAttribute("title"),
    Some("Nothing to export yet"),
  )
  // Node には改名の口が無いので、名乗りはその理由で沈む
  assert_eq(
    s.doc.getElementById("filename").unwrap().getAttribute("title"),
    Some(@bar.no_rename_here),
  )
  assert_eq(s.fake.log[1:], ["set_text", "focus"])
}

///|
test "打てば木が生まれ、地図が描かれ、名乗りが変わり、未保存の印が立ち、書き出しが開く" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n## a\n")
  assert_eq(s.nodes(), 2)
  assert_eq(s.doc.title(), "r.md - mmm")
  assert_eq(s.text_of("filename"), "r.md")
  assert_false(s.fake.hint)
  assert_eq(s.doc.getElementById("dirty").unwrap().getAttribute("hidden"), None)
  assert_eq(
    s.doc.getElementById("export").unwrap().getAttribute("title"),
    Some("Export the whole Mindmap — Download SVG"),
  )
  // 木が変わらないサイクルは塗り直しだけ（描き直さない）
  let before = s.doc.querySelectorAll(".map-svg .node")[0]
  s.app.cycle(Some(s.fake.survey()), false)
  assert_true(@web.same(before, s.doc.querySelectorAll(".map-svg .node")[0]))
}

///|
test "apply: 操作を md に映し、focus を effect で乗せ、別のノードなら寄せる。できない操作はしらせ" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n## a\n")
  let a = s.fake.survey().find("a").unwrap()
  assert_eq(s.app.apply(Rename(id=a, label="b"), false), Some(a))
  assert_eq(s.fake.md, "# r\n\n## b\n")
  assert_eq(s.fake.log[s.fake.log.length() - 2:], [
    "apply 1 focus=" + a.to_string(),
    "reveal 5",
  ])
  // 同じ名前への Rename は編集が無くても focus が在り、しらせは出ない
  assert_eq(s.app.apply(Rename(id=a, label="b"), false), Some(a))
  // 無い id はできない
  assert_eq(s.app.apply(Rename(id=99, label="x"), false), None)
  assert_eq(s.doc.querySelectorAll(".notice").length(), 1)
}

///|
test "持ち主: 地図に焦点が入れば、そのときの選択を位置にして引き継ぐ。選び直しは位置で CodeMirror へ" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n## a\n")
  let a = s.fake.survey().find("a").unwrap()
  s.fake.selection = { ids: [a], anchor: Some(a), }
  let map_pane = s.doc.getElementById("map-pane").unwrap()
  let ev = @core.new(s.win.as_any()._get("FocusEvent"), [@core.any("focusin")])
  map_pane.as_event_target().dispatchEvent(ev.cast()) |> ignore
  assert_eq(
    s.fake.log[s.fake.log.length() - 1],
    "hold map [\"NodeAt\",{\"at\":[8],\"anchor\":8}]",
  )
  // 地図で選び直した（host 経由）。位置に写り、寄せる
  (s.app.map.host.set_selection)({ ids: [a], anchor: Some(a), }, true)
  assert_eq(s.fake.log[s.fake.log.length() - 2:], [
    "select [\"NodeAt\",{\"at\":[8],\"anchor\":8}]", "reveal 5",
  ])
}

///|
test "宣言: 頭に書き、引っ越しなら本文の画像も同じ 1 手で追従する。フォルダの一言は宣言と許可で言う" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n![](pics/a.png)\n")
  assert_eq(s.app.folder_caption(), "no folder")
  s.app.set_declared("pics")
  assert_true(s.fake.md.has_prefix("---\n"))
  assert_eq(s.app.declared_folder(), Some("pics/"))
  assert_eq(s.app.folder_caption(), "pics/, no access")
  assert_eq(s.fake.log[s.fake.log.length() - 1], "apply 1")
  s.app.set_declared("img")
  assert_eq(s.app.declared_folder(), Some("img/"))
  assert_true(s.fake.md.contains("![](img/a.png)"))
  assert_eq(s.fake.log[s.fake.log.length() - 1], "apply 2")
}

///|
async test "リンクの但し書き: 画像が居れば言う。新規は捨てるか聞き、断れば何も起きない" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n![](pics/a.png)\n")
  assert_eq(s.app.link_note(), ["Images won't travel"])
  // 未保存のまま New → たずねが開く。Cancel を押せば文書はそのまま
  let asked = @js_async.Promise::from_async(async fn() { s.app.new_file() })
  let dlg = s.doc.querySelector("dialog.ask").unwrap()
  @web.click(dlg.querySelectorAll(".row button")[0])
  asked.wait()
  assert_eq(s.fake.md, "# r\n\n![](pics/a.png)\n")
  assert_true(s.doc.querySelector("dialog.ask") is None)
}

///|
test "帯: Files は状態を写す（保存していない・覚えているものが無い）。⋯ は掴みやすさを持ち物に" {
  let s = stand()
  defer s.win.close()
  @web.click(s.doc.getElementById("files").unwrap())
  let rows = s.doc
    .querySelectorAll(".menu [role=menuitem]")
    .map(r => r.textContent())
  assert_true(rows.length() > 0)
  assert_eq(
    s.doc.querySelector(".menu .caption").unwrap().textContent(),
    "not saved yet",
  )
  assert_eq(s.app.grab, false)
}

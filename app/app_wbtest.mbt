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
/// 手元の置き場（ディスクの代わり）。既定は何も覚えていない。`known` を渡せば
/// その名前の文書を覚えている台帳として立つ（立ち上がりの一覧。#277）。
/// 並びは最後に触れた順なので、先に渡したものが新しい
fn memo_disk(known : Array[String]) -> @disk.Disk {
  let table : Map[String, @core.Any] = Map([])
  if known.length() > 0 {
    table["docs"] = @core.any(
      known.mapi((i, name) => {
        @web.record([
          ("doc", paper(name, "", _ => ()).as_any()),
          ("directory", @core.null()),
          // i 分前に触れたことにする（先に渡したものが新しい）。
          // 行の字は「名前 · 古さ」なので、時刻が並びと綴りの両方を決める
          ("seen", @core.any(@web.now() - i.to_double() * 60_000.0)),
        ])
      }),
    )
  }
  @disk.Disk::new(
    @disk.Recent::new(memo_shelf(table)),
    @disk.Drafts::new(memo_shelf(Map([]))),
  )
}

///|
/// 手元の棚 1 つ。実物は IndexedDB の objectStore で、札も控えも同じ形で並ぶ
fn memo_shelf(table : Map[String, @core.Any]) -> @disk.Store {
  {
    read: fn(key) { table.get(key).unwrap_or(@core.null()) },
    write: fn(key, value) { table[key] = value },
    remove: fn(key) { table.remove(key) },
    all: fn() { table.values().collect() },
    same: fn(_, _) { false },
    is_file: looks_like_file,
    is_dir: _ => false,
  }
}

///|
struct Stand {
  win : @dom.Window
  doc : @dom.Document
  fake : Fake
  app : App
}

///|
/// index.html と同じ id の器（`(tag, id)` の並び）を `into` に立てる
fn mount(
  doc : @dom.Document,
  into : @dom.Element,
  ids : Array[(String, String)],
) -> Unit {
  for pair in ids {
    let e = doc.createElement(pair.0)
    e.setAttribute("id", pair.1)
    into.append(e.as_node())
  }
}

///|
/// index.html と同じ器を立て、App を組んで動かす。非同期の試験は閉じる閉包を
/// 通れないので、これを手で持って `defer s.win.close()`。それ以外は `with_stand`
fn stand(known? : Array[String] = []) -> Stand {
  let win = @test_utils.create_happy_window()
  let doc = win.document()
  let body = doc.body().unwrap()
  @web.set_style(doc.documentElement(), "--accent", "#5932ff")
  let bar = doc.createElement("header")
  body.append(bar.as_node())
  mount(doc, bar, [
    ("svg", "logo"),
    ("span", "filename"),
    ("span", "dirty"),
    ("button", "files"),
    ("button", "export"),
    ("button", "export-way"),
    ("button", "more"),
  ])
  mount(doc, body.as_element(), [("main", "panes")])
  mount(doc, doc.getElementById("panes").unwrap(), [
    ("section", "md-pane"),
    ("div", "splitter"),
    ("section", "map-pane"),
  ])
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
  let app = App::new(doc, fake.editor(), memo_disk(known), measure=(_, text) => {
    text.char_length().to_double() * 7.0
  })
  fake.app = Some(app)
  app.boot()
  { win, doc, fake, app, }
}

///|
/// 立てて渡し、済んだら閉じる（parts の `with_doc` と同じ形）
fn with_stand(f : (Stand) -> Unit raise) -> Unit raise {
  let s = stand()
  defer s.win.close()
  f(s)
}

///|
/// 出来事を起こす。`kind` は窓の構築子の名（`FocusEvent` など）、`name` は出来事の名
fn fire(s : Stand, target : @dom.Element, kind : String, name : String) -> Unit {
  let ev = @core.new(s.win.as_any()._get(kind), [@core.any(name)])
  target.as_event_target().dispatchEvent(ev.cast()) |> ignore
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
/// **この試験はピッカーの無い環境で回る**（Node / happy-dom）。だから
/// (b′)「正直な機能オフ」がそのまま見える — 名乗りに拡張子が付かず、`●` は
/// 点かず、押せない理由はファイルを持てないことになる（docs/browsers.md）
test "立ち上がりは空。名乗りは mmm / empty、言い出しが出て、書き出しは沈む。焦点は md へ" {
  with_stand(s => {
    assert_eq(s.doc.title(), "mmm")
    // 持てないブラウザでは `.md` を付けない
    assert_eq(s.text_of("filename"), "empty")
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
    // 押せない理由は**根の深いほう** — 改名を持たないより前に、持てない
    assert_eq(
      s.doc.getElementById("filename").unwrap().getAttribute("title"),
      Some(@parts.no_file_access),
    )
    assert_eq(s.fake.log[1:], ["set_text", "focus"])
  })
}

///|
test "打てば木が生まれ、地図が描かれ、名乗りが変わり、書き出しが開く。印は持てるときだけ" {
  with_stand(s => {
    s.fake.change("# r\n\n## a\n")
    assert_eq(s.nodes(), 2)
    assert_eq(s.doc.title(), "r - mmm")
    assert_eq(s.text_of("filename"), "r")
    assert_false(s.fake.hint)
    // **`●` は点かない。** ピッカーが無いので保存する道が無く、点けば
    // 消える手段の無い印になる（docs/browsers.md の (b′)）
    assert_eq(
      s.doc.getElementById("dirty").unwrap().getAttribute("hidden"),
      Some(""),
    )
    assert_eq(
      s.doc.getElementById("export").unwrap().getAttribute("title"),
      Some("Export the whole Mindmap — Download SVG"),
    )
    // 木が変わらないサイクルは塗り直しだけ（描き直さない）
    let before = s.doc.querySelectorAll(".map-svg .node")[0]
    s.app.cycle(Some(s.fake.survey()), false)
    assert_true(@web.same(before, s.doc.querySelectorAll(".map-svg .node")[0]))
  })
}

///|
test "apply: 操作を md に映し、focus を effect で乗せ、別のノードなら寄せる。できない操作はしらせ" {
  with_stand(s => {
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
  })
}

///|
test "持ち主: 地図に焦点が入れば、そのときの選択を位置にして引き継ぐ。選び直しは位置で CodeMirror へ" {
  with_stand(s => {
    s.fake.change("# r\n\n## a\n")
    let a = s.fake.survey().find("a").unwrap()
    s.fake.selection = { ids: [a], anchor: Some(a), }
    fire(s, s.doc.getElementById("map-pane").unwrap(), "FocusEvent", "focusin")
    assert_eq(
      s.fake.log[s.fake.log.length() - 1],
      "hold map [\"NodeAt\",{\"at\":[8],\"anchor\":8}]",
    )
    // 地図で選び直した（地図は host の set_selection でここへ来る）。位置に写り、寄せる
    s.app.choose(Nodes(sel={ ids: [a], anchor: Some(a), }), true)
    assert_eq(s.fake.log[s.fake.log.length() - 2:], [
      "select [\"NodeAt\",{\"at\":[8],\"anchor\":8}]", "reveal 5",
    ])
  })
}

///|
test "宣言: 頭に書き、引っ越しなら本文の画像も同じ 1 手で追従する" {
  with_stand(s => {
    s.fake.change("# r\n\n![](pics/a.png)\n")
    s.app.set_declared("pics")
    assert_true(s.fake.md.has_prefix("---\n"))
    assert_eq(s.app.declared_folder(), Some("pics/"))
    assert_eq(s.fake.log[s.fake.log.length() - 1], "apply 1")
    s.app.set_declared("img")
    assert_eq(s.app.declared_folder(), Some("img/"))
    assert_true(s.fake.md.contains("![](img/a.png)"))
    assert_eq(s.fake.log[s.fake.log.length() - 1], "apply 2")
  })
}

///|
/// 非同期なので、窓は `with_stand` を通らず手で持つ（閉じる閉包は async を呼べない）
async test "リンクの但し書き: 画像が居れば言う。新規は捨てるか聞き、断れば何も起きない" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n![](pics/a.png)\n")
  assert_eq(s.app.link_caveat(), ["Images won't travel"])
  // 未保存のまま New → たずねが開く。Cancel を押せば文書はそのまま
  let asked = @js_async.Promise::from_async(async fn() { s.app.new_file() })
  let dlg = s.doc.querySelector("dialog.ask").unwrap()
  @web.click(dlg.querySelectorAll(".row button")[0])
  asked.wait()
  assert_eq(s.fake.md, "# r\n\n![](pics/a.png)\n")
  assert_true(s.doc.querySelector("dialog.ask") is None)
}

///|
test "帯: Files は状態を写す（保存していない・覚えているものが無い・フォルダも無い）。⋯ は掴みやすさを持ち物に" {
  with_stand(s => {
    @web.click(s.doc.getElementById("files").unwrap())
    let rows = s.doc
      .querySelectorAll(".menu [role=menuitem]")
      .map(r => r.textContent())
    assert_true(rows.length() > 0)
    let captions = s.doc
      .querySelectorAll(".menu .caption")
      .map(c => c.textContent())
    assert_eq(captions, ["not saved yet", "no folder"])
    assert_eq(s.app.grab, false)
  })
}

// ---- 自動保存（#275）----

///|
/// 札の代役。**happy-dom に File System Access は無い**ので、書いた字は箱へ入る。
/// 本物と同じ形だけ持つ（名前・許可・読み・書き）
extern "js" fn paper(
  name : String,
  text : String,
  into : (String) -> Unit,
) -> @web.FileHandle =
  #| (name, text, into) => ({ name,
  #|   requestPermission: async () => "granted",
  #|   getFile: async () => ({ text: async () => text }),
  #|   createWritable: async () => ({ write: (t) => into(t), close: () => {} }) })

///|
/// `ms` 経つまで返らない。**時計そのものを待つ** — 自動保存は手が止まるのを
/// 時計で待つので、フレームでは代わらない
async fn rest(doc : @dom.Document, ms : Int) -> Unit {
  @web.promise_of(k => wait_ms(doc, ms, () => k(@core.any(0)))).wait() |> ignore
}

///|
extern "js" fn wait_ms(doc : @dom.Document, ms : Int, f : () -> Unit) -> Unit =
  #| (doc, ms, f) => doc.defaultView.setTimeout(() => f(), ms)

///|
/// **ディスクへ勝手に書く道は持たない**（#306 で Autosave を捨てた）。
/// 手が止まっても、書くのは控え（ブラウザの中）だけ。ディスクの .md は
/// 他のアプリや git からも見えるものなので、人が押さないかぎり触らない
async test "手が止まっても、ディスクへは自分で書かない" {
  let s = stand()
  defer s.win.close()
  let written : Array[String] = []
  s.app.open_known(paper("notes.md", "# r\n", t => written.push(t)))
  assert_eq(s.fake.md, "# r\n")
  s.fake.change("# r\n\n## a\n")
  rest(s.doc, quiet * 2)
  // ディスクには 1 字も書かれていない
  assert_eq(written, [])
  // 控えのほうには残っている
  assert_eq(s.app.disk.drafts().list().map(d => d.text), ["# r\n\n## a\n"])
  // 印も立ったまま（ディスクの字とは違う）
  assert_true(s.doc.querySelector("#dirty[hidden]") is None)
}

// ---- 立ち上がりの挨拶（#277）----

///|
/// いま出ているメニュー。**器は 1 個しか作れないものではない**ので、
/// 帯のボタンの分も DOM に居る（出ていないものは畳まれている）
fn shown_menu(s : Stand) -> @dom.Element {
  let shown = s.doc
    .querySelectorAll(".menu")
    .filter(m => {
      m.getAttribute("style").unwrap_or("").contains("display: block")
    })
  guard shown.length() == 1 else {
    abort("出ているメニューが 1 つでない")
  }
  shown[0]
}

///|
/// 札らしいか。手元の置き場には `FileSystemFileHandle` が無いので、形で見る
extern "js" fn looks_like_file(v : @core.Any) -> Bool =
  #| (v) => typeof v === "object" && v !== null && typeof v.name === "string"

///|
/// **覚えているものを真ん中に並べるだけ。** 開くのは人で、ほかを触れば消える。
/// 器は他のメニューと同じなので、閉じ方もそれが持っている
async test "立ち上がり: 覚えているものを真ん中に並べ、外を押せば消える" {
  let s = stand(known=["ideas.md", "todo.md"])
  defer s.win.close()
  // 台帳は IndexedDB の向こうなので、届くまでに一拍ある
  rest(s.doc, 5)
  assert_true(s.app.greeting.is_open())
  let box = shown_menu(s)
  // **名前だけでは足りない。** 同じ名前の .md が 2 つあると押すまで分からないので、
  // 最後に触れた時刻を添える（#309）
  assert_eq(box.querySelectorAll("[role=menuitem]").map(r => r.textContent()), [
    "ideas.md · just now", "todo.md · 1 min ago",
  ])
  assert_eq(box.querySelectorAll(".caption").map(c => c.textContent()), [
    "Recent",
  ])
  // **押されて出たのではない**ので、出どころの座標は無い。真ん中に置く
  // 画面 1024x768 の真ん中（happy-dom は大きさを測らないので、幅 0 の中央）
  inspect(
    shown_menu(s).getAttribute("style").unwrap_or(""),
    content="display: block; left: 512px; top: 384px;",
  )
  // ほかを触れば消える
  fire(s, s.doc.documentElement(), "PointerEvent", "pointerdown")
  assert_false(s.app.greeting.is_open())
}

///|
/// **文書が入れ替われば役目を終える。** 一覧から選んで開いた先で、
/// 一覧が残っていては邪魔になる
async test "立ち上がり: 文書が入れ替われば挨拶は引っ込む" {
  let s = stand(known=["ideas.md"])
  defer s.win.close()
  rest(s.doc, 5)
  assert_true(s.app.greeting.is_open())
  s.app.open_known(paper("ideas.md", "# i\n", _ => ()))
  assert_eq(s.fake.md, "# i\n")
  assert_false(s.app.greeting.is_open())
}

///|
/// 覚えているものが無ければ出さない（並べるものが無い）
async test "立ち上がり: 何も覚えていなければ挨拶は出ない" {
  let s = stand()
  defer s.win.close()
  rest(s.doc, 5)
  assert_false(s.app.greeting.is_open())
}

///|
/// **捨てるものが無ければ聞かない。** `||` の右に async を置くと短絡しないので、
/// この形は書いた側から見て正しく見えるまま壊れる（#295）
async test "捨てる確認: 汚れていなければ、たずねは開かず、そのまま進む" {
  let s = stand()
  defer s.win.close()
  let done = @js_async.Promise::from_async(async fn() { s.app.new_file() })
  assert_true(s.doc.querySelector("dialog.ask") is None)
  done.wait()
  // 保存してから打っていない文書も同じ（保存済みの字と一致している）
  s.fake.change("# r\n")
  s.app.saved_text = "# r\n"
  let again = @js_async.Promise::from_async(async fn() { s.app.new_file() })
  assert_true(s.doc.querySelector("dialog.ask") is None)
  again.wait()
  assert_eq(s.fake.md, "")
}

///|
/// 書き込みに間のかかる札。**待っているあいだに人が打てる** — `paper` の
/// 書き込みはその場で済むので、保存と打鍵の重なりはこちらでしか作れない
extern "js" fn slow_paper(
  doc : @dom.Document,
  name : String,
  text : String,
  into : (String) -> Unit,
  ms : Int,
) -> @web.FileHandle =
  #| (doc, name, text, into, ms) => ({ name,
  #|   requestPermission: async () => "granted",
  #|   getFile: async () => ({ text: async () => text }),
  #|   createWritable: async () => ({
  #|     write: (t) => new Promise((done) => {
  #|       doc.defaultView.setTimeout(() => { into(t); done(); }, ms);
  #|     }),
  #|     close: () => {} }) })

///|
/// **書く字と、書いたと記す字は同じ 1 つ**（#298）。書き込みを待っているあいだに
/// 打った字は、ディスクに無いのだから「保存済み」にしてはいけない
async test "保存: 書いているあいだに打った字は、書かれないまま済んだことにならない" {
  let s = stand()
  defer s.win.close()
  let written : Array[String] = []
  let hold = 200
  s.app.open_known(
    slow_paper(s.doc, "notes.md", "# r\n", t => written.push(t), hold),
  )
  s.fake.change("# r\n\n## a\n")
  // 手で保存 → 書き込みの待ちに入る（待たずに次へ進む）
  @web.spawn(async fn() { s.app.save_file(false) })
  rest(s.doc, hold / 4)
  // まだ書けていない。この隙に 1 つ打つ
  assert_eq(written, [])
  s.fake.change("# r\n\n## a\n\n## b\n")
  rest(s.doc, hold * 2)
  // ディスクに載ったのは打つ前の字
  assert_eq(written, ["# r\n\n## a\n"])
  // 記した字もそれと同じ。印は立ったまま
  assert_eq(s.app.saved_text, "# r\n\n## a\n")
  assert_true(s.doc.querySelector("#dirty[hidden]") is None)
}

///|
/// **積んだ書き込みにも持ち主が居る**（#299）。文書を入れ替えたら、前の文書の
/// ために積んだものは捨てる。捨てないと、**前の文書のために積んだ書き込みが、
/// 入れ替わった後の文書に対して走る** — 名前を手放した後（新規）なら、人が
/// 何も押していないのに保存ダイアログの道へ入る
async test "自動保存: 文書を入れ替えたら、積んでいた書き込みは走らない" {
  let s = stand()
  defer s.win.close()
  let first : Array[String] = []
  let next : Array[String] = []
  s.app.open_known(paper("a.md", "# a\n", t => first.push(t)))
  // 汚す → 手が止まって 1 秒後に書く約束が積まれる
  s.fake.change("# a\n\n## x\n")
  // 鳴る前に別の文書を開く。たずねの Discard（`[1]` は進む側）を押す
  let asked = @js_async.Promise::from_async(async fn() {
    s.app.open_known(paper("b.md", "# b\n", t => next.push(t)))
  })
  let dlg = s.doc.querySelector("dialog.ask").unwrap()
  @web.click(dlg.querySelectorAll(".row button")[1])
  asked.wait()
  assert_eq(s.fake.md, "# b\n")
  rest(s.doc, quiet * 2)
  // 捨てた字は捨てたまま
  assert_eq(first, [])
  // 開いたばかりの文書も、頼まれていないのに書かれない
  assert_eq(next, [])
}

///|
/// **控えに置き場は要らない。** まだ保存していない文書 — いちばん失いやすいもの —
/// がいちばんの客（#306）。ディスクへの自動書き込み（Autosave）とは行き先が違う
async test "控え: 保存していない文書でも、手が止まれば控えが残る" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# r\n\n## a\n")
  rest(s.doc, quiet * 2)
  let rows = s.app.disk.drafts().list()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].text, "# r\n\n## a\n")
  // ディスクに実体が無いので札は持たない
  assert_true(rows[0].doc is None)
  // 同じ字のままなら、二度は書かない
  rest(s.doc, quiet * 2)
  assert_eq(s.app.disk.drafts().list().length(), 1)
}

///|
/// **文書を入れ替えたら控えの流れも切れる。** 前の文書の字は残るが、
/// 続きは別の系列になる（1 つの流れに 2 つの文書の字が混ざらない）
async test "控え: 新規にすると、前の文書の控えは残り、次は別の流れになる" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# first\n")
  rest(s.doc, quiet * 2)
  // 汚れているので、新規はたずねを開く。Discard（`[1]`）を押す
  let asked = @js_async.Promise::from_async(async fn() { s.app.new_file() })
  @web.click(
    s.doc.querySelector("dialog.ask").unwrap().querySelectorAll(".row button")[1],
  )
  asked.wait()
  s.fake.change("# second\n")
  rest(s.doc, quiet * 2)
  let rows = s.app.disk.drafts().list()
  assert_eq(rows.map(d => d.text), ["# second\n", "# first\n"])
  assert_true(rows[0].flow != rows[1].flow)
}

///|
/// 画像フォルダの代役。名前しか要らない
extern "js" fn folder(name : String) -> @web.DirHandle =
  #| (name) => ({ name })

///|
/// **同じ名前の .md が 2 つあっても見分けられる**（#309）。札はディスクのパスを
/// 持たないので、出せるのは画像フォルダの名前と、最後に触れた時刻だけ
test "覚えているものの行: 名前と、見分けに使えるもの" {
  let now = 1_000_000_000.0
  let bare : @disk.Known = {
    id: "1",
    doc: paper("notes.md", "", _ => ()),
    directory: None,
    seen: now,
  }
  let linked : @disk.Known = {
    id: "2",
    doc: paper("notes.md", "", _ => ()),
    directory: Some(folder("pics")),
    seen: now - 3_600_000.0,
  }
  assert_eq(recent_label(bare, now), "notes.md · just now")
  assert_eq(recent_label(linked, now), "notes.md · pics · 1 h ago")
}

///|
/// **控えは Recent の上。** Recent は「また開きたいもの」、控えは「まだ失われうる
/// もの」で、急ぐのは後者（#306）
async test "立ち上がり: 控えと覚えているものを、2 つの塊で並べる" {
  let s = stand(known=["ideas.md"])
  defer s.win.close()
  s.app.disk.drafts().keep(@web.now(), "sketch.md", "# sketch\n", None)
  s.app.refresh_recent()
  s.app.greet()
  let box = shown_menu(s)
  assert_eq(box.querySelectorAll(".caption").map(c => c.textContent()), [
    "Drafts", "Recent",
  ])
  let rows = box.querySelectorAll("[role=menuitem]").map(r => r.textContent())
  assert_eq(rows[0], "sketch.md · just now")
  assert_eq(rows[1], "ideas.md · just now")
}

///|
/// **控えから開けば、本文が戻り、印は立ったまま。** 控えはディスクに届いて
/// いない字なので、開いた瞬間から「ディスクとは違う」と言えているのが正しい。
/// 全部忘れる道は 1 つ（1 件ごとの × は置かない）
async test "控え: 押せば戻る。印は立ったまま。全部忘れれば消える" {
  let s = stand()
  defer s.win.close()
  s.fake.change("# kept\n")
  rest(s.doc, quiet * 2)
  // 新規へ移る。汚れているのでたずねが開く — Discard（`[1]`）を押す
  let asked = @js_async.Promise::from_async(async fn() { s.app.new_file() })
  @web.click(
    s.doc.querySelector("dialog.ask").unwrap().querySelectorAll(".row button")[1],
  )
  asked.wait()
  assert_eq(s.fake.md, "")
  // 控えから戻す
  s.app.refresh_recent()
  assert_eq(s.app.drafts.length(), 1)
  @js_async.Promise::from_async(async fn() { s.app.open_draft(0) }).wait()
  assert_eq(s.fake.md, "# kept\n")
  // ディスクに届いていない字なので、印は立ったまま
  assert_eq(s.app.saved_text, "")
  // 全部忘れる
  @js_async.Promise::from_async(async fn() { s.app.forget_drafts() }).wait()
  assert_eq(s.app.disk.drafts().list().length(), 0)
  assert_eq(s.app.drafts.length(), 0)
}

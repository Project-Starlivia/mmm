// 束ねる場所。文書の真実は md ペインの文字列で、マップはその写し。
// 文書から導けるもの（読み・地図の選択の位置・持ち主・選択）は CodeMirror の
// EditorState（ts の state.ts）に居て、1 トランザクションが 1 サイクル — `cycle` に 1 回届く。
// ここには文書から導く値を置かない（持つのはファイルの状態だけ）。読みは決して書かない。
// ここに居るのは、そのサイクルと、保存とファイル I/O、帯のメニュー。
//
// **操作の入口は 2 つ。** `apply`（持ち主の操作。focus を選ぶ）と `write`（それ以外の
// 書き込み。選択に触らない）。選択を書くのは持ち主の操作だけ（design.md）。
//
// CodeMirror に触ることだけを `Editor` の閉包で受ける。それ以外はここが持つ。

///|
/// md ペイン（CodeMirror）。文書と選択の読み書きと、コードの色分け
pub(all) struct Editor {
  text : () -> String
  /// いまの読み（EditorState の field）
  survey : () -> @read.Survey
  holder : () -> @read.Holder
  selection : () -> @map.Selection
  picked : () -> Int?
  /// 文書を丸ごと入れ替える（履歴も新しく）。続けてサイクルが回る
  set_text : (String) -> Unit
  /// 編集列を順に当てる（undo は 1 手）。`held` なら同じトランザクションで focus の effect が乗る
  apply : (Array[Array[@tree.Edit]], Bool, Int?) -> Unit
  /// 地図で選び直した。位置は地番で写してから渡す
  select : (@read.Anchors?) -> Unit
  /// フォーカスがペインに入った。md → map なら引き継ぐ位置も一緒に
  hold : (@read.Holder, @read.Anchors?) -> Unit
  /// その位置を中央へ
  reveal : (Int) -> Unit
  undo : () -> Unit
  redo : () -> Unit
  focus : () -> Unit
  set_theme : (Bool) -> Unit
  /// 白紙の言い出しを出す / 引っ込める
  show_hint : (Bool) -> Unit
  /// コードの色分け（CodeMirror の言語表）
  tokens : (Array[String], String) -> Array[Array[@render.Token]]
  tokens_block : (String) -> Array[Array[@render.Token]]
  epoch : () -> Int
  /// 言語が後から読み込まれたら呼ばれる（描き直す）
  on_language_ready : (() -> Unit) -> Unit
}

///|
pub struct App {
  doc : @dom.Document
  ed : Editor
  io : @file.Io
  map : @render.Mindmap
  assets : @file.Assets
  theme : @app.Theme
  exporter : @app.Export
  md_pane : @dom.Element
  map_pane : @dom.Element
  filename : @dom.Element
  dirty : @dom.Element
  /// set_text のたびに進む世代。**文書を跨いだ非同期は、必ずこれを見てから物を言う** —
  /// 待っているあいだに New / Open で別の文書へ移っていることがある
  mut gen : Int
  mut saved_text : String
  /// 保存済みのファイル名。まだ保存していない文書では None で、名前は本文の
  /// 見出しから導く（read の name）。「無題」という状態は持たない
  mut saved_name : String?
  /// 覚えている文書。Files の Recent に並ぶ。IndexedDB の向こうに在るので、
  /// 開く・保存するたびに引き直して手元に置く
  mut recent : Array[@web.FileHandle]
  /// お絵描きの窓が開いているか。二重に開かせない
  mut drawing_open : Bool
  /// 掴みやすさ（⋯ の Easy grab）
  mut grab : Bool
}

///|
fn spawn(f : async () -> Unit) -> Unit {
  @js_async.Promise::from_async(f) |> ignore
}

///|
/// index.html の要素。無ければ壊れている
fn el(doc : @dom.Document, id : String) -> @dom.Element {
  guard doc.getElementById(id) is Some(e) else {
    abort("#" + id + " が無い")
  }
  e
}

///|
/// 組む。`io` はディスクの窓口、`measure` は字の実測（試験は手元の置き場と数を渡す）
pub fn App::new(
  doc : @dom.Document,
  ed : Editor,
  io : @file.Io,
  measure? : @map.Measure = @render.measure(doc),
) -> App {
  let md_pane = el(doc, "md-pane")
  let map_pane = el(doc, "map-pane")
  // 地図・画像・書き出しは互いを指す（地図は画像の URL を、画像は地図の描き直しを）。
  // 組み上がってから動くものなので、後から入る自分を通して呼ぶ
  let late : Ref[App?] = { val: None, }
  let app = () => late.val.unwrap()
  let assets = @file.Assets::new(doc, io, {
    failed: msg => @parts.failed(doc, msg),
    refresh: () => app().map.render(),
    declared: () => app().declared_folder(),
    set_declared: value => app().set_declared(value),
  })
  let map = @render.Mindmap::new(
    @dom.HTMLElement::cast_from_element(map_pane),
    {
      survey: ed.survey,
      measure,
      image_url: path => assets.image_url(path),
      image_hint: () => {
        if assets.readable() {
          None
        } else {
          Some("click to connect")
        }
      },
      connect_assets: () => {
        spawn(async fn() { if app().ensure_place() { assets.connect() } })
      },
      holder: ed.holder,
      selection: ed.selection,
      set_selection: (sel, reveal) => app().choose(Nodes(sel~), reveal),
      picked: ed.picked,
      set_picked: id => {
        app().choose(
          match id {
            Some(id) => Card(id~)
            None => @read.nothing
          },
          false,
        )
      },
      block_text: id => app().block_text(id),
      apply: (op, edit) => app().apply(op, edit),
      paste: () => app().paste(),
      copy: k => spawn(async fn() { k(app().copy()) }),
      draw: id => app().draw(id),
      read_clipboard: k => {
        spawn(async fn() { k(@web.read_clipboard(doc).wait()) })
      },
      tokens: ed.tokens,
      tokens_block: ed.tokens_block,
      epoch: ed.epoch,
      failed: msg => @parts.failed(doc, msg),
    },
  )
  let theme = @app.Theme::new(el(doc, "logo"), ed.set_theme)
  let exporter = @app.Export::new(
    doc,
    {
      svg: async fn() { map.to_svg() },
      name: () => app().doc_name(),
      failed: msg => @parts.failed(doc, msg),
      blocked: msg => @parts.blocked(doc, msg),
      empty: () => (ed.survey)().empty(),
    },
    el(doc, "export"),
    el(doc, "export-way"),
  )
  let self : App = {
    doc,
    ed,
    io,
    map,
    assets,
    theme,
    exporter,
    md_pane,
    map_pane,
    filename: el(doc, "filename"),
    dirty: el(doc, "dirty"),
    gen: 0,
    saved_text: "",
    saved_name: None,
    recent: [],
    drawing_open: false,
    grab: @app.load("grab") == Some("on"),
  }
  late.val = Some(self)
  self.wire()
  self
}

// ---------- 読み ----------

///|
fn App::text(self : App) -> String {
  (self.ed.text)()
}

///|
fn App::survey(self : App) -> @read.Survey {
  (self.ed.survey)()
}

///|
/// いま選んでいるもの — カード 1 枚か、ノードの並びか
fn App::choice(self : App) -> @read.Choice {
  match (self.ed.picked)() {
    Some(id) => Card(id~)
    None => Nodes(sel=(self.ed.selection)())
  }
}

///|
/// 選択（id）をいまの木の地番で位置に。CodeMirror へ渡すのはこの形
fn App::anchors_for(self : App, c : @read.Choice) -> @read.Anchors? {
  @read.anchors_for(self.survey(), c)
}

///|
/// 頭が言っている画像フォルダ（正規化済み）。無ければ None
fn App::declared_folder(self : App) -> String? {
  @read.image_folder(self.survey().view.frontmatter).bind(@read.normalize_path)
}

///|
/// その中身の原文。地番で md から切り出す（無ければ空）
fn App::block_text(self : App, id : Int) -> String {
  match self.survey().spots.get(id) {
    Some(sp) => String::unsafe_substring(self.text(), start=sp.from, end=sp.to)
    None => ""
  }
}

///|
/// いまの文書の名前。保存済みならそのファイル名、まだなら本文から導く
fn App::doc_name(self : App) -> String {
  self.saved_name.unwrap_or(self.survey().name() + ".md")
}

// ---------- サイクル ----------

///|
/// 1 トランザクション = 1 サイクル。木が変わっていれば描き直し、そうでなければ塗り直し。
/// **ここが読みのサイクルの唯一の出口** — 打鍵も、開くも、操作も、選び直しも、
/// フォーカスの移動も、全部ここへ 1 回届く。`prev` が None なら文書を丸ごと入れ替えた
pub fn App::cycle(
  self : App,
  prev : @read.Survey?,
  tree_changed : Bool,
) -> Unit {
  let t = self.survey()
  if prev is None || tree_changed {
    self.map.render()
    // 白紙の言い出し。**出る理由は 1 つ**（まだ木が無い）で、マップ側も render() の中で同じことを見ている
    (self.ed.show_hint)(t.empty())
    self.update_dirty()
    self.show_name()
    self.exporter.refresh()
    // 何も無いところに最初の木が生まれた瞬間だけ、真ん中へ寄せる
    let was_empty = match prev {
      Some(p) => p.empty()
      None => true
    }
    if was_empty && !t.empty() {
      self.map.fit_view()
    }
  } else {
    self.map.refresh_selection()
  }
}

///|
/// 地図で選び直した。id を位置に写して CodeMirror に置く（md 側の薄塗りは field が引き直す）。
/// reveal は md 側を anchor の頭へスクロールするか
fn App::choose(self : App, next : @read.Choice, reveal : Bool) -> Unit {
  (self.ed.select)(self.anchors_for(next))
  guard reveal && next is Nodes(sel~) && sel.anchor is Some(anchor) else {
    return
  }
  match self.survey().spots.get(anchor) {
    Some(sp) => (self.ed.reveal)(sp.from)
    None => ()
  }
}

///|
/// 持ち主の操作を md に映す。**選択を書く入口はここ 1 本** — 地図は md に触らない。
/// 操作 1 回 = CodeMirror への 1 回の dispatch（編集列 + focus の effect）で、undo は
/// CodeMirror のもの。focus は anchors が後の木で位置に写す（state.ts）。
/// できない操作は core が空の編集列で言う。いまは雑に、しらせを出すだけ。
///
/// focus はノードとも中身とも限らない。ノードで `edit` ならその場編集を開く。
/// 呼び出し側が続けられるよう focus を返す（Link / Code が使う）
pub fn App::apply(self : App, op : @op.Op, edit : Bool) -> Int? {
  let r = @op.edit(self.text(), op)
  // core は断りを「編集なし・focus なし」で言う。編集が無くても focus が在るのは、
  // 何も変わらなかった操作（同じ名前への Rename など）で、しらせは出さない
  if r.focus is None && r.edits.length() == 0 {
    @parts.failed(self.doc, "Couldn't do that here")
    return None
  }
  let before = (self.ed.selection)().anchor
  (self.ed.apply)([r.edits], true, r.focus)
  guard r.focus is Some(focus) else { return None }
  // 別のノードへ移ったときだけ md を寄せる（同じノードに留まる操作で手元を揺らさない）。
  // 寄せは編集とは別の、スクロールだけのトランザクション — undo の 1 手には入らない
  if before != Some(focus) {
    match self.survey().spots.get(focus) {
      Some(sp) => (self.ed.reveal)(sp.from)
      None => ()
    }
  }
  // 畳まれて埋もれたノードには箱が無く、その場編集を開けない
  if edit && self.survey().is_node(focus) && !self.map.begin_edit(focus, None) {
    @parts.failed(self.doc, "Couldn't start editing — the node is folded")
  }
  Some(focus)
}

///|
/// それ以外の書き込みを md に映す（ファイルの投下・お絵描き・画像の貼り付け）。
/// **選択には触らない** — 地図にフォーカスが無くても起きる操作なので、持ち主が決めた
/// 選択を横から書き換えない（design.md「選択を書くのは持ち主の操作だけ」）
fn App::write(self : App, op : @op.Op) -> Unit {
  let r = @op.edit(self.text(), op)
  if r.edits.length() == 0 {
    if r.focus is None {
      @parts.failed(self.doc, "Couldn't do that here")
    }
    return
  }
  (self.ed.apply)([r.edits], false, None)
}

// ---------- 名乗りと入れ替え ----------

///|
/// 未保存の印。**判定はここ 1 つ**で、帯の `●` とタブの favicon の両方が
/// 同じ答えを見る（別々に数えると、片方だけ古い状態のまま残る）
fn App::update_dirty(self : App) -> Unit {
  let dirty = self.text() != self.saved_text
  if dirty {
    self.dirty.removeAttribute("hidden")
  } else {
    self.dirty.setAttribute("hidden", "")
  }
  self.theme.set_dirty(dirty)
}

///|
/// 名乗りを出し直す。本文を打つそばからタイトルが変わる。
/// タブは名前を持つ文書のときだけ名乗る（`filename.md - mmm`）
fn App::show_name(self : App) -> Unit {
  let named = self.saved_name is Some(_) || !self.survey().empty()
  let title = if named { self.doc_name() + " - mmm" } else { "mmm" }
  // 打鍵のたびに呼ばれるので、変わっていないなら DOM に触らない
  if self.doc.title() != title {
    self.doc.setTitle(title)
  }
  let shown = self.doc_name()
  if self.filename.textContent() != shown {
    self.filename.setTextContent(shown)
  }
  // **押せるときだけ押せる顔をする。** 理由は Files の Rename の行と同じものを使う。
  // 押せなさは `aria-disabled` の 1 つで言う（見た目も読み上げも同じ源）
  match @app.rename_problem(@web.can_rename(), self.saved_name is Some(_)) {
    Some(why) => {
      self.filename.setAttribute("title", why)
      self.filename.setAttribute("aria-disabled", "true")
      self.filename.removeAttribute("tabindex")
    }
    None => {
      self.filename.setAttribute("title", "Rename — click")
      self.filename.removeAttribute("aria-disabled")
      self.filename.setAttribute("tabindex", "0")
    }
  }
}

///|
/// 文書を丸ごと入れ替える。名乗りも、寄せも、ここから
fn App::load_text(self : App, next : String, name : String?) -> Unit {
  self.gen += 1
  self.saved_name = name
  self.assets.clear() // 画像のパスは（新しい）md からの相対
  (self.ed.set_text)(next) // → cycle
  self.map.fit_view()
  // 文書が入れ替わった。**Recent の並びもここで引き直す**
  spawn(async fn() { self.refresh_recent() })
}

// ---------- ファイル ----------

///|
/// 開いた文書を UI に載せる
fn App::apply_doc(self : App, opened : @file.Doc) -> Unit {
  self.saved_text = opened.text
  self.load_text(opened.text, Some(opened.name))
  spawn(async fn() { self.offer_connect() })
}

///|
/// 開いた文書に画像が居るのに、そのフォルダを握っていない。**繋ぎ直しを誘う。**
///
/// 出るのは画像が居るときだけ — 繋ぐものが無い文書に聞く意味は無い。
/// 断っても道は閉じない（Files の Choose folder が入口として残る）。
/// ブラウザはクリックの直後にしかピッカーを開けないので、**箱のボタンが
/// その 1 回**になる。自動で繋ぎに行くことはできない
async fn App::offer_connect(self : App) -> Unit {
  guard self.saved_name is Some(_) && @app.has_images(self.text()) else {
    return
  }
  // 許可を確かめるあいだに別の文書へ移っていたら、もうこの文書の話ではない
  let gen = self.gen
  if self.assets.connected() || gen != self.gen {
    return
  }
  let folder = self.declared_folder().unwrap_or("./")
  let go = @app.asked(self.doc, @app.connect(folder))
  // 箱を読んでいるあいだに移っていることもある。**繋ぐ直前にもう一度見る**
  if go is Some(_) && gen == self.gen {
    self.assets.connect()
  }
}

///|
async fn App::confirm_discard(self : App) -> Bool {
  self.text() == self.saved_text ||
  @app.asked(self.doc, @app.discard()) is Some(_)
}

///|
async fn App::open_file(self : App) -> Unit {
  // ショートカットから来ると、押せない理由を言う行が無い — 同じ理由をここでも言う
  guard @web.can_open() else { @parts.failed(self.doc, @parts.no_file_access) }
  (async fn() -> Unit {
    guard self.confirm_discard() else { return }
    match self.io.open_dialog() {
      Some(opened) => self.apply_doc(opened)
      None => ()
    }
  })() catch {
    _ => @parts.failed(self.doc, "Couldn't open the file")
  }
}

///|
/// 覚えている文書を開く。**許可はここで取り直す** — 押されたことがその資格
async fn App::open_known(self : App, file : @web.FileHandle) -> Unit {
  (async fn() -> Unit {
    guard self.confirm_discard() else { return }
    match self.io.open_known(file) {
      Some(opened) => self.apply_doc(opened)
      None => ()
    }
  })() catch {
    _ => @parts.failed(self.doc, "Couldn't open the file")
  }
}

///|
/// いま開いているファイル**そのもの**の名前を変える。本文の見出しから導く名前とは別の話
async fn App::rename_file(self : App) -> Unit {
  guard self.saved_name is Some(current) else { return }
  guard @app.asked(self.doc, @app.rename(current)) is Some(typed) else {
    return
  }
  let name = typed[0].trim(chars=" \t\r\n").to_owned()
  if name == "" || name == current {
    return
  }
  (async fn() -> Unit {
    match self.io.rename(name) {
      Some(next) => {
        self.saved_name = Some(next)
        self.show_name()
      }
      None => ()
    }
  })() catch {
    _ => @parts.failed(self.doc, "Couldn't rename the file")
  }
}

///|
/// 保存。`as_new`（別名で保存）と、まだ名前の無い文書はダイアログを出す。
/// ダイアログの初期値はいまの名前 — 保存済みならそのファイル名、まだなら本文から導いたもの
async fn App::save_file(self : App, as_new : Bool) -> Unit {
  (async fn() -> Unit {
    if as_new || self.saved_name is None {
      guard @web.can_save_as() else {
        @parts.failed(self.doc, @parts.no_file_access)
      }
      guard self.io.save_as(self.doc_name(), self.text()) is Some(saved) else { // キャンセル
        return
      }
      self.saved_name = Some(saved.name) // ここで初めて名前が決まる
      self.show_name()
      // **写しは別の文書。** 握りは「この md から見たあのフォルダ」という対
      // でしか意味を持たないので、md が別の場所へ移った時点で対ごと無効
      self.assets.clear()
      spawn(async fn() { self.refresh_recent() })
      spawn(async fn() { self.offer_connect() })
    } else {
      self.io.save(self.text())
    }
    self.saved_text = self.text()
    self.update_dirty()
  })() catch {
    _ => @parts.failed(self.doc, "Couldn't save")
  }
}

///|
/// 新しい文書。いまの文書は捨て、ファイルハンドルも手放す
async fn App::new_file(self : App) -> Unit {
  guard self.confirm_discard() else { return }
  self.io.close()
  self.saved_text = ""
  self.load_text("", None)
  (self.ed.focus)()
}

///|
async fn App::refresh_recent(self : App) -> Unit {
  self.recent = self.io.recent() catch { _ => [] }
}

// ---------- リンク ----------

///|
/// 本文へのリンクの綴り。作るのも測るのもこの 1 か所
async fn App::link(self : App) -> String {
  @web.address(self.doc) + @app.to_hash(self.text())
}

///|
/// リンクにまつわる**押す前の但し書き**。無ければ空。
/// 長さは gzip してからでないと分からないので、開くたびに本当に測る（1ms 弱）
async fn App::link_note(self : App) -> Array[String] {
  let notes = []
  if @app.has_images(self.text()) {
    notes.push("Images won't travel")
  }
  if self.link().length() > @app.link_warn_length {
    notes.push("Long link — may be cut")
  }
  notes
}

///|
/// いまの本文へのリンクをクリップボードへ。写せたことは押した行の絵が言う
async fn App::copy_link(self : App) -> Bool {
  (async fn() -> Bool {
    @web.write_clipboard(self.doc, self.link()).wait()
    true
  })() catch {
    _ => {
      @parts.failed(self.doc, "Couldn't copy the link")
      false
    }
  }
}

// ---------- 画像（ローカルファースト。実装は file/assets.mbt） ----------

///|
/// 宣言を頭に書く。頭を書いただけでは本文は古い場所を指したまま。**宣言と本文は同じ 1 つの
/// 引っ越し**なので、続けて映して 1 手（1 回の Undo）に畳む。初めての宣言
/// （prev が無い）では本文は触らない — どこから動かすのか分からない
fn App::set_declared(self : App, value : String) -> Unit {
  // 読めない綴り（空・絶対パス・URL）は欄が先に止めている
  guard @read.normalize_path(value) is Some(next) else { return }
  let prev = self.declared_folder()
  let s = self.survey()
  let sets = [[@read.set_image_folder(s.md, s.view.frontmatter, next)]]
  let mut md = @tree.patched(self.text(), sets[0])
  match prev {
    Some(prev) =>
      for op in @read.retarget(s.view, prev, next) {
        let r = @op.edit(md, op)
        sets.push(r.edits)
        md = @tree.patched(md, r.edits)
      }
    None => ()
  }
  (self.ed.apply)(sets, false, None)
}

///|
/// フォルダを指す一手の**手前の駅**。保存されていなければ、その場で保存まで案内する。
/// **壁ではなく駅。** 行程を先に見せてそのまま通す — 通ればそのまま指せ、断れば何も起きない
async fn App::ensure_place(self : App) -> Bool {
  if self.saved_name is Some(_) {
    return true
  }
  guard @app.asked(self.doc, @app.place()) is Some(_) else { return false }
  self.save_file(true)
  self.saved_name is Some(_)
}

///|
/// 画像をディスクへ置いて、そのノードの中身として足す（Image のブロック）。
/// **貼り付け・ドロップ・お絵描きが通る唯一の道** — WebP への変換も名前の
/// 確認も画像フォルダの結び付けも、`save_to_disk` が 1 か所で持つ
async fn App::attach_image(self : App, id : Int, blob : @core.Any) -> Unit {
  let gen = self.gen
  guard self.ensure_place() else { return }
  // 置いているあいだに文書が入れ替わった（世代）／ノードが消えている（id）ことがある
  guard self.assets.save_to_disk(blob) is Some(rel) &&
    gen == self.gen &&
    self.survey().is_node(id) else {
    return
  }
  self.write(AddBlock(at=In(node=id), content=Image(alt="", src=rel, title="")))
}

///|
/// Shift+D。窓を開いて描いてもらい、確定した絵を保存して足す
fn App::draw(self : App, id : Int) -> Unit {
  if self.drawing_open {
    return
  }
  self.drawing_open = true
  spawn(async fn() {
    (async fn() -> Unit {
      match @app.show_drawing(self.doc) {
        Some(blob) => self.attach_image(id, blob)
        None => ()
      }
    })() catch {
      _ => @parts.failed(self.doc, "Couldn't add the drawing")
    }
    self.drawing_open = false
    @web.focus(self.map_pane)
  })
}

///|
/// 選んでいるものをクリップボードへ写す（Mod+C / Mod+X）。カードを選んでいれば
/// その原文、でなければ選択の部分木（read の copy）。書けたかを返す — Cut は
/// 書けてから消す（render の act）
async fn App::copy(self : App) -> Bool {
  let clip = match (self.ed.picked)() {
    Some(card) => self.block_text(card)
    None => self.survey().copy((self.ed.selection)().ids)
  }
  guard clip != "" else { return false }
  (async fn() -> Bool {
    @web.write_clipboard(self.doc, clip).wait()
    true
  })() catch {
    _ => {
      @parts.failed(self.doc, "Couldn't copy")
      false
    }
  }
}

///|
/// クリップボードを貼る（Mod+V）。画像はテキストより優先し、選んでいる
/// ノード（anchor）へ足す。字は raw のまま `Graft` へ — 何を貼るか（見出し・項目は
/// 形だけ運んで綴りは貼り先に従う、段落は行ごとに子、それ以外の中身はカード）は
/// core が読んで決める。`#` も URL もここでは見ない。
/// 決めは docs/superpowers/specs/2026-09-06-paste-design.md
fn App::paste(self : App) -> Unit {
  let anchor = (self.ed.selection)().anchor
  let gen = self.gen
  spawn(async fn() {
    (async fn() -> Unit {
      // クリップボードに画像があれば、テキストより優先する。読めない / 断られたら字の道へ
      let img = @web.clipboard_image(self.doc).wait()
      guard gen == self.gen else { return }
      if !@core.is_nullish(img) {
        guard anchor is Some(id) else {
          @parts.failed(self.doc, "Select a node to paste an image into")
        }
        self.attach_image(id, img)
        return
      }
      let clip = @web.read_clipboard(self.doc).wait()
      guard gen == self.gen else { return }
      // 空はしくじりではなく「何も無い」なので黙る
      guard clip.trim(chars=" \t\r\n") != "" else { return }
      self.apply(
        Graft(at=In(node=anchor.unwrap_or(@tree.doc_id), side=None), md=clip),
        false,
      )
      |> ignore
    })() catch {
      _ => @parts.failed(self.doc, "Couldn't paste")
    }
  })
}

///|
/// 画像フォルダの状態。**言葉は宣言と許可の 2 つだけ**（file/assets.mbt の冒頭が
/// 名付けたもの）。許可が無いときは宣言のパスを出す — どこを指していて届いて
/// いないのかが見えないと、直しようがない
fn App::folder_caption(self : App) -> String {
  match (self.assets.folder_name(), self.declared_folder()) {
    (None, None) => "no folder"
    (None, Some(declared)) => declared + ", no access"
    (Some(name), Some(_)) => name
    (Some(name), None) => name + ", not declared"
  }
}

// ---------- 配線 ----------

///|
fn App::set_grab(self : App, on : Bool) -> Unit {
  self.grab = on
  self.map.set_grab(on)
  @app.store("grab", if on { "on" } else { "off" })
}

///|
/// 帯・ペイン・キー・ドロップ・持ち主。組み上がった後に 1 度だけ
fn App::wire(self : App) -> Unit {
  let doc = self.doc
  // 選択は持っている側（フォーカスが最後に入ったペイン）が決める。md → map は、その
  // 瞬間のカーソルのノードを位置にして引き継ぐ。map → md は捨てる（md のカーソルは
  // 動かさない）。窓・メニュー・帯へ抜けても変わらない — 2 つのペインの focusin だけを見る
  @web.listen(self.md_pane, "focusin", _ => {
    if (self.ed.holder)() != Md {
      (self.ed.hold)(Md, None)
    }
  })
  @web.listen(self.map_pane, "focusin", _ => {
    if (self.ed.holder)() != Map {
      (self.ed.hold)(Map, self.anchors_for(self.choice()))
    }
  })

  // 帯のメニュー。並びは app の files.mbt / more.mbt の表。ここは状態を写して、押されたら走らせる
  @parts.open_on_click(el(doc, "files"), () => {
    @app.files_menu(
      {
        saved_name: self.saved_name,
        recent: self.recent.map(f => f.name()),
        can_open: @web.can_open(),
        can_save: @web.can_save_as(),
        can_rename: @web.can_rename(),
        can_choose_folder: @web.can_choose_folder(),
        folder: self.folder_caption(),
      },
      {
        new_file: () => spawn(async fn() { self.new_file() }),
        open: () => spawn(async fn() { self.open_file() }),
        open_recent: i => {
          match self.recent.get(i) {
            Some(file) => spawn(async fn() { self.open_known(file) })
            None => ()
          }
        },
        save: () => spawn(async fn() { self.save_file(false) }),
        save_as: () => spawn(async fn() { self.save_file(true) }),
        rename: () => spawn(async fn() { self.rename_file() }),
        choose_folder: () => {
          spawn(async fn() {
            if self.ensure_place() {
              self.assets.choose_folder()
            }
          })
        },
      },
    )
  })
  self.map.set_grab(self.grab)
  @parts.open_on_click(el(doc, "more"), () => {
    @app.more_menu(
      {
        light: self.theme.is_light(),
        grab: self.grab,
        link_note: k => spawn(async fn() { k(self.link_note()) }),
      },
      {
        undo: self.ed.undo,
        redo: self.ed.redo,
        pick_color: () => self.theme.pick_color(),
        toggle_theme: () => self.theme.toggle(),
        toggle_grab: () => self.set_grab(!self.grab),
        copy_link: k => spawn(async fn() { k(self.copy_link()) }),
      },
    )
  })

  // **名前を押したら、名前を変える。** 押せなさは `rename_file` 自身が持つ。
  // `<span role="button">` なので Enter / Space を自分で出す（app/theme.mbt のロゴと同じ）
  @web.listen(self.filename, "click", _ => {
    spawn(async fn() { self.rename_file() })
  })
  @web.listen(self.filename, "keydown", e => {
    let k = @web.keyboard(e)
    guard k.key == "Enter" || k.key == " " else { return }
    @web.prevent(e)
    spawn(async fn() { self.rename_file() })
  })
  @web.on_window(doc, "beforeunload", e => {
    if self.text() != self.saved_text {
      @web.warn_unload(e)
    }
  })

  // 落とされたファイル（file/dnd.mbt）
  @file.init_drop(doc, {
    open_markdown: async fn(file) {
      guard self.confirm_discard() else { return }
      self.apply_doc(self.io.open_handle(file))
    },
    add_image: async fn(blob, node) { self.attach_image(node, blob) },
    mark_drop: at => {
      self.map.mark_file_drop(at.map(p => ({ x: p.0, y: p.1, } : @map.Pt)))
    },
    failed: msg => @parts.failed(doc, msg),
  })

  // ペインと全体のキー（app）
  let panes = @app.Panes::new(
    self.md_pane,
    self.map_pane,
    el(doc, "panes"),
    el(doc, "splitter"),
    self.ed.focus,
  )
  @app.init_shortcuts(doc, {
    save: as_new => spawn(async fn() { self.save_file(as_new) }),
    open: () => spawn(async fn() { self.open_file() }),
    create: () => spawn(async fn() { self.new_file() }),
    toggle_pane: () => panes.toggle(),
    toggle_pane_vis: which => panes.toggle_vis(which),
    undo: self.ed.undo,
    redo: self.ed.redo,
    export_map: choose => {
      if choose {
        self.exporter.choose()
      } else {
        self.exporter.run()
      }
    },
  })
}

///|
/// 動かす。**サイクルの出口（cycle）が繋がってから** — 最初の set_text がもう回す。
/// 本文の控えは持たない。IndexedDB に置くのはハンドルだけで、
/// **起動時に勝手に開き直すことはしない** — 立ち上げたら常に空から始まる
pub fn App::boot(self : App) -> Unit {
  @app.sweep() // 役目を終えた localStorage のキーを捨てる
  self.load_text("", None) // 空 = まだ何も無い。dirty も立たない
  let boot_gen = self.gen
  let hash = @web.hash(self.doc)
  spawn(async fn() {
    guard @app.from_hash(hash) is Some(shared) else { return }
    // リンクで開いた。ハッシュはその場で消す — 文書の身元はあくまで
    // ファイルハンドル 1 つで、リンクは入口でしかない
    @web.drop_hash(self.doc)
    if self.gen == boot_gen && self.text() == "" {
      self.load_text(shared, None)
    }
  })
  // フェンスの言語は後から読み込まれる。届いたら色を載せ直す
  (self.ed.on_language_ready)(() => self.map.render())
  (self.ed.focus)()
}

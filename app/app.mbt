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
  tokens : (Array[String], String) -> Array[Array[@mindmap.Token]]
  tokens_block : (String) -> Array[Array[@mindmap.Token]]
  epoch : () -> Int
  /// 言語が後から読み込まれたら呼ばれる（描き直す）
  on_language_ready : (() -> Unit) -> Unit
}

///|
/// 束ねる場所。地図・画像・書き出し・名乗りは組み上がった自分を呼ぶ（地図は画像の
/// URL を、画像は地図の描き直しを、名乗りは改名を）。閉包は組む時点で固定され、自分は
/// まだ無い — **後から入る自分を 1 つの入れ物で受け、閉包はそれを通して呼ぶ**（`App::new`
/// の `late`）。入れ物を無くすには mindmap の Host を後付けにする必要がある: apply（映した
/// 後の begin_edit）・paste・draw・connect_assets は App の状態（世代・保存名・窓）を要り、
/// images.refresh は地図の render を要る — 地図 ↔ 画像 ↔ App の輪で、どれかを mut Option
/// にすると使うたびに unwrap が要る。読む場所を 1 つに絞るのがいちばん少ない
pub struct App {
  doc : @dom.Document
  ed : Editor
  disk : @disk.Disk
  map : @mindmap.Mindmap
  images : @disk.Images
  theme : @bar.Theme
  exporter : @bar.Export
  md_pane : @dom.Element
  map_pane : @dom.Element
  /// 帯の名乗り（ファイル名・改名の入口・未保存の印）
  name : @bar.Name
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
/// index.html の要素。無ければ壊れている
fn el(doc : @dom.Document, id : String) -> @dom.Element {
  guard doc.getElementById(id) is Some(e) else {
    abort("#" + id + " が無い")
  }
  e
}

///|
/// 組む。`disk` はディスクの窓口、`measure` は字の実測（試験は手元の置き場と数を渡す）
pub fn App::new(
  doc : @dom.Document,
  ed : Editor,
  disk : @disk.Disk,
  measure? : @map.Measure = @mindmap.measure(doc),
) -> App {
  let md_pane = el(doc, "md-pane")
  let map_pane = el(doc, "map-pane")
  // 組み上がってから動くものは、後から入る自分を通して呼ぶ（App の doc comment）
  let late : Ref[App?] = { val: None, }
  let app = () => late.val.unwrap()
  let images = @disk.Images::new(doc, disk, {
    failed: msg => @parts.failed(doc, msg),
    // **1 フレームに 1 回だけ描き直す。** 絵が読めるのは 1 枚ずつで、100 枚の文書なら
    // 100 回「描き直して」と言われる。どれも同じ「いまの絵で描き直せ」なので、
    // 最後の 1 回で足りる（#77）
    refresh: @web.per_frame(doc, () => app().map.render()),
    declared: () => app().declared_folder(),
    set_declared: value => app().set_declared(value),
  })
  let map = @mindmap.Mindmap::new(
    @dom.HTMLElement::cast_from_element(map_pane),
    {
      survey: ed.survey,
      measure,
      image_url: path => images.image_url(path),
      image_hint: () => {
        if images.readable() {
          None
        } else {
          Some("click to connect")
        }
      },
      connect_assets: () => {
        @web.spawn(async fn() { if app().ensure_place() { images.connect() } })
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
      copy: k => @web.spawn(async fn() { k(app().copy()) }),
      draw: id => app().draw(id),
      read_clipboard: k => {
        @web.spawn(async fn() { k(@web.read_clipboard(doc).wait()) })
      },
      tokens: ed.tokens,
      tokens_block: ed.tokens_block,
      epoch: ed.epoch,
      failed: msg => @parts.failed(doc, msg),
      leave: () => @bar.focus_bar(doc),
    },
  )
  let theme = @bar.Theme::new(el(doc, "logo"), ed.set_theme)
  let exporter = @bar.Export::new(
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
    disk,
    map,
    images,
    theme,
    exporter,
    md_pane,
    map_pane,
    name: @bar.Name::new(doc, el(doc, "filename"), el(doc, "dirty"), theme, () => {
      @web.spawn(async fn() { app().rename_file() })
    }),
    gen: 0,
    saved_text: "",
    saved_name: None,
    recent: [],
    drawing_open: false,
    grab: @prefs.load(doc, "grab") == Some("on"),
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
  @read.image_folder(self.survey().doc.frontmatter).bind(@read.normalize_path)
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

///|
/// この文書がディスクに居られるか。
///
/// **居られないブラウザでは、帯も印も警告もファイルの話をしない**
/// （docs/browsers.md の (b′)「正直な機能オフ」）。ピッカーが無ければ保存の
/// 入口そのものが無いので、`●` は消える手段が無いまま点き続け、閉じるたびの
/// 警告は解消する手段が無いまま出続け、帯の `xxx.md` は**これから存在しようも
/// ないファイル**の名前になる。断り書きだけ出してシェルが反対のことを言う形を、
/// この 1 つの問いで閉じる
fn App::can_hold(self : App) -> Bool {
  @web.can_save_as() || self.saved_name is Some(_)
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
fn App::apply(self : App, op : @op.Op, edit : Bool) -> Int? {
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
  self.name.set_dirty(self.can_hold() && self.text() != self.saved_text)
}

///|
/// 名乗りを出し直す。本文を打つそばからタイトルが変わる。
/// タブは名前を持つ文書のときだけ名乗る（`filename.md - mmm`）
fn App::show_name(self : App) -> Unit {
  let named = self.saved_name is Some(_) || !self.survey().empty()
  // **拡張子が付くのは、本当にファイルのときだけ。** 持てないブラウザでは
  // 文書の名前だけを出す（`can_hold`）
  let shown = if self.can_hold() {
    self.doc_name()
  } else {
    self.survey().name()
  }
  self.name.show(shown, named, self.saved_name is Some(_))
}

///|
/// 文書を丸ごと入れ替える。名乗りも、寄せも、ここから
fn App::load_text(self : App, next : String, name : String?) -> Unit {
  self.gen += 1
  self.saved_name = name
  self.images.clear() // 画像のパスは（新しい）md からの相対
  (self.ed.set_text)(next) // → cycle
  self.map.fit_view()
  // 文書が入れ替わった。**Recent の並びもここで引き直す**
  @web.spawn(async fn() { self.refresh_recent() })
}

// ---------- ファイル ----------

///|
/// 開いた文書を UI に載せる
fn App::apply_doc(self : App, opened : @disk.Doc) -> Unit {
  self.saved_text = opened.text
  self.load_text(opened.text, Some(opened.name))
  @web.spawn(async fn() { self.offer_connect() })
}

///|
/// 開いた文書に画像が居るのに、そのフォルダを握っていない。**繋ぎ直しを誘う。**
///
/// 出るのは画像が居るときだけ — 繋ぐものが無い文書に聞く意味は無い。
/// 断っても道は閉じない（Files の Choose folder が入口として残る）。
/// ブラウザはクリックの直後にしかピッカーを開けないので、**箱のボタンが
/// その 1 回**になる。自動で繋ぎに行くことはできない
async fn App::offer_connect(self : App) -> Unit {
  guard self.saved_name is Some(_) && self.survey().has_images() else { return }
  // 許可を確かめるあいだに別の文書へ移っていたら、もうこの文書の話ではない
  let gen = self.gen
  if self.images.connected() || gen != self.gen {
    return
  }
  let folder = self.declared_folder().unwrap_or("./")
  let go = @parts.asked(self.doc, @parts.folder_connection(folder))
  // 箱を読んでいるあいだに移っていることもある。**繋ぐ直前にもう一度見る**
  if go is Some(_) && gen == self.gen {
    self.images.connect()
  }
}

///|
async fn App::confirm_discard(self : App) -> Bool {
  self.text() == self.saved_text ||
  @parts.asked(self.doc, @parts.unsaved_changes()) is Some(_)
}

///|
async fn App::open_file(self : App) -> Unit {
  // ショートカットから来ると、押せない理由を言う行が無い — 同じ理由をここでも言う
  guard @web.can_open() else { @parts.failed(self.doc, @parts.no_file_access) }
  (async fn() -> Unit {
    guard self.confirm_discard() else { return }
    match self.disk.open_dialog() {
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
    match self.disk.open_known(file) {
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
  guard @parts.asked(self.doc, @parts.file_name(current)) is Some(typed) else {
    return
  }
  let name = typed[0].trim(chars=" \t\r\n").to_owned()
  if name == "" || name == current {
    return
  }
  (async fn() -> Unit {
    match self.disk.rename(name) {
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
      guard self.disk.save_as(self.doc_name(), self.text()) is Some(saved) else { // キャンセル
        return
      }
      self.saved_name = Some(saved.name) // ここで初めて名前が決まる
      self.show_name()
      // **写しは別の文書。** 握りは「この md から見たあのフォルダ」という対
      // でしか意味を持たないので、md が別の場所へ移った時点で対ごと無効
      self.images.clear()
      @web.spawn(async fn() { self.refresh_recent() })
      @web.spawn(async fn() { self.offer_connect() })
    } else {
      self.disk.save(self.text())
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
  self.disk.close()
  self.saved_text = ""
  self.load_text("", None)
  (self.ed.focus)()
}

///|
async fn App::refresh_recent(self : App) -> Unit {
  self.recent = self.disk.remembered() catch { _ => [] }
}

// ---------- リンク ----------

///|
/// 本文へのリンク。綴りは link.mbt で、ここはページの住所を渡すだけ
async fn App::link(self : App) -> String {
  link(@web.address(self.doc), self.text())
}

///|
/// リンクにまつわる**押す前の但し書き**（link.mbt）。長さは作ってから測る
async fn App::link_caveat(self : App) -> Array[String] {
  link_caveat(self.survey().has_images(), self.link().length())
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

// ---------- 画像（ローカルファースト。実装は disk/images.mbt） ----------

///|
/// 宣言を頭に書く。頭を書いただけでは本文は古い場所を指したまま。**宣言と本文は同じ 1 つの
/// 引っ越し**なので、続けて映して 1 手（1 回の Undo）に畳む。初めての宣言
/// （prev が無い）では本文は触らない — どこから動かすのか分からない
fn App::set_declared(self : App, value : String) -> Unit {
  // 読めない綴り（空・絶対パス・URL）は欄が先に止めている
  guard @read.normalize_path(value) is Some(next) else { return }
  let prev = self.declared_folder()
  let s = self.survey()
  let sets = [[@read.set_image_folder(s.md, s.doc.frontmatter, next)]]
  let mut md = @tree.patched(self.text(), sets[0])
  match prev {
    Some(prev) =>
      // 判定は宣言を書く前の木、書くのは書いた後の木（`retarget`）
      for op in @read.retarget(s.doc, @tree.build(md).0, prev, next) {
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
  guard @parts.asked(self.doc, @parts.image_place()) is Some(_) else {
    return false
  }
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
  guard self.images.save_to_disk(blob) is Some(rel) &&
    gen == self.gen &&
    self.survey().is_node(id) else {
    return
  }
  self.write(
    AddBlock(at=In(node=id), content=Some(Image(alt="", src=rel, title=""))),
  )
}

///|
/// Shift+D。窓を開いて描いてもらい、確定した絵を保存して足す
fn App::draw(self : App, id : Int) -> Unit {
  if self.drawing_open {
    return
  }
  self.drawing_open = true
  @web.spawn(async fn() {
    (async fn() -> Unit {
      match @parts.show_drawing(self.doc) {
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
  @web.spawn(async fn() {
    (async fn() -> Unit {
      // クリップボードに画像があれば、テキストより優先する。読めない / 断られたら字の道へ
      let img = @web.clipboard_image(self.doc).wait()
      guard gen == self.gen else { return }
      if !@core.is_nullish(img) {
        guard anchor is Some(id) else {
          @parts.blocked(self.doc, "Select a node to paste an image into")
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

// ---------- 配線 ----------

///|
fn App::set_grab(self : App, on : Bool) -> Unit {
  self.grab = on
  self.map.set_grab(on)
  @prefs.store(self.doc, "grab", if on { "on" } else { "off" })
}

///|
/// 組み上がった後に 1 度だけ。持ち主・帯・離脱・投下・キー
fn App::wire(self : App) -> Unit {
  self.wire_holder()
  self.wire_bar()
  self.wire_unload()
  self.wire_drop()
  self.wire_keys()
}

///|
/// 選択は持っている側（フォーカスが最後に入ったペイン）が決める。md → map は、その
/// 瞬間のカーソルのノードを位置にして引き継ぐ。map → md は捨てる（md のカーソルは
/// 動かさない）。窓・メニュー・帯へ抜けても変わらない — 2 つのペインの focusin だけを見る
fn App::wire_holder(self : App) -> Unit {
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
}

///|
/// 帯のメニュー。並びは bar の files.mbt / more.mbt の表。ここは状態を写して、押されたら走らせる
fn App::wire_bar(self : App) -> Unit {
  let doc = self.doc
  @parts.open_on_click(el(doc, "files"), () => {
    @bar.files_menu(
      {
        saved_name: self.saved_name,
        recent: self.recent.map(f => f.name()),
        can_open: @web.can_open(),
        can_save: @web.can_save_as(),
        can_rename: @web.can_rename(),
        can_choose_folder: @web.can_choose_folder(),
        folder: @disk.folder_caption(
          self.images.folder_name(),
          self.declared_folder(),
        ),
      },
      {
        new_file: () => @web.spawn(async fn() { self.new_file() }),
        open: () => @web.spawn(async fn() { self.open_file() }),
        open_recent: i => {
          match self.recent.get(i) {
            Some(file) => @web.spawn(async fn() { self.open_known(file) })
            None => ()
          }
        },
        save: () => @web.spawn(async fn() { self.save_file(false) }),
        save_as: () => @web.spawn(async fn() { self.save_file(true) }),
        rename: () => @web.spawn(async fn() { self.rename_file() }),
        choose_folder: () => {
          @web.spawn(async fn() {
            if self.ensure_place() {
              self.images.choose_folder()
            }
          })
        },
      },
    )
  })
  // 掴みやすさは持ち物から。⋯ の行がその場で切り替える
  self.map.set_grab(self.grab)
  @parts.open_on_click(el(doc, "more"), () => {
    @bar.more_menu(
      {
        light: self.theme.is_light(),
        grab: self.grab,
        link_caveat: k => @web.spawn(async fn() { k(self.link_caveat()) }),
      },
      {
        undo: self.ed.undo,
        redo: self.ed.redo,
        pick_color: () => self.theme.pick_color(),
        toggle_theme: () => self.theme.toggle(),
        toggle_grab: () => self.set_grab(!self.grab),
        copy_link: k => @web.spawn(async fn() { k(self.copy_link()) }),
        visit: url => @web.open_url(doc, url),
      },
    )
  })
}

///|
/// 未保存のまま閉じようとしたら止める
fn App::wire_unload(self : App) -> Unit {
  @web.on_window(self.doc, "beforeunload", e => {
    // 解消する手段が無いなら止めない（`can_hold`）
    if self.can_hold() && self.text() != self.saved_text {
      @web.warn_unload(e)
    }
  })
}

///|
/// 落とされたファイル（disk/drop.mbt）
fn App::wire_drop(self : App) -> Unit {
  let doc = self.doc
  @disk.init_drop(doc, {
    open_markdown: async fn(file) {
      guard self.confirm_discard() else { return }
      self.apply_doc(self.disk.open_handle(file))
    },
    add_image: async fn(blob, node) { self.attach_image(node, blob) },
    mark_drop: at => {
      self.map.mark_file_drop(at.map(p => ({ x: p.0, y: p.1, } : @map.Pt)))
    },
    failed: msg => @parts.failed(doc, msg),
  })
}

///|
/// ペインと全体のキー（panes.mbt / shortcuts.mbt）
fn App::wire_keys(self : App) -> Unit {
  let doc = self.doc
  let panes = Panes::new(
    self.md_pane,
    self.map_pane,
    el(doc, "panes"),
    el(doc, "splitter"),
    self.ed.focus,
  )
  init_shortcuts(doc, {
    save: as_new => @web.spawn(async fn() { self.save_file(as_new) }),
    open: () => @web.spawn(async fn() { self.open_file() }),
    create: () => @web.spawn(async fn() { self.new_file() }),
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
  @prefs.sweep(self.doc) // 役目を終えた localStorage のキーを捨てる
  self.load_text("", None) // 空 = まだ何も無い。dirty も立たない
  let boot_gen = self.gen
  let hash = @web.hash(self.doc)
  @web.spawn(async fn() {
    guard from_hash(hash) is Some(shared) else { return }
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

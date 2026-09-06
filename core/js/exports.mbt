// core を browser から使うための薄い層。**中身は持たない**（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
//
// 木も箱も core から出ない。境界は数・文字列・真偽・持ち手（MoonBit の値を
// そのまま JS へ渡し、そのまま受け取る）だけ — 読みも選択もその位置も持ち手で往復する。
//
// アプリそのものは `mmmMain` が組む（core/main）。ts に残るのは CodeMirror（md ペイン）で、
// その読み書きを閉包で渡す。それ以外の出口は、見本（lab）と EditorState の field
// （state.ts）が読むぶんだけ。どの段で壊れたかを切り分けるために、mdAst・mmmTree・View も出す。

///|
/// md をライブラリがどう読んだか（ブロックの種類と原文の範囲）。
/// mdAst は我々のものではないので、ぜんぶではなく要約を出す。
#export_name("mdAstSig")
pub fn md_ast_sig(md : String) -> String {
  @tree.md_ast_sig(md)
}

///|
/// mmmTree ぜんぶ。JSON への変換は導出（ToJson）なので、手書きの層が無い。
#export_name("mmmTreeJson")
pub fn mmm_tree_json(md : String) -> String {
  @tree.parse(md).to_json().stringify()
}

///|
/// map が見る木。mmmTree から削っただけのもの。
#export_name("mmmViewJson")
pub fn mmm_view_json(md : String) -> String {
  @view.project(@tree.parse(md)).to_json().stringify()
}

///|
/// 型で言えない不変条件の破れ。**parse の出力は必ず空**になるはずで、
/// 空でなければ読みのバグ。
#export_name("mmmCheck")
pub fn mmm_check(md : String) -> String {
  @tree.check(@tree.parse(md)).to_json().stringify()
}

///|
/// 木を書き戻した正規形の md。
#export_name("mmmSerialize")
pub fn mmm_serialize(md : String) -> String {
  @tree.serialize(@tree.parse(md))
}

///|
/// 木を戻した mdAst の指紋。読みの指紋と並べて、どちらの段で形が変わったかを見る。
#export_name("mmmUnbuildSig")
pub fn mmm_unbuild_sig(md : String) -> String {
  @tree.ast_sig(@tree.unbuild(@tree.parse(md)))
}

// ---- 読みと選択 ----
//
// 読み・選択・その位置は持ち手で往復する。EditorState の field（state.ts）が持ち、
// 1 トランザクションごとに写す・導くのに要る問い合わせだけがここに残る

///|
/// 打鍵 1 回ぶんの読み。返るのは読み（木・地番・原文）の持ち手 — 木は出さない
#export_name("mmmSurvey")
pub fn mmm_survey(md : String) -> @core.Any {
  @core.any(@read.survey(md))
}

///|
fn read(handle : @core.Any) -> @read.Survey {
  handle.cast()
}

///|
/// id がノードのものか（中身の id なら false）
#export_name("mmmIsNode")
pub fn mmm_is_node(survey : @core.Any, id : Int) -> Bool {
  read(survey).is_node(id)
}

///|
/// 木が 1 つも無い（白紙）
#export_name("mmmEmpty")
pub fn mmm_empty(survey : @core.Any) -> Bool {
  read(survey).empty()
}

///|
/// その id の地番（from, label, to）。label が無ければ -1。id が無ければ undefined
#export_name("mmmSpot")
pub fn mmm_spot(survey : @core.Any, id : Int) -> FixedArray[Int]? {
  read(survey).spots.get(id).map(sp => [sp.from, sp.label.unwrap_or(-1), sp.to])
}

///|
/// その字のノード（文書順で最初）。見本の md から id を引く
#export_name("mmmFind")
pub fn mmm_find(survey : @core.Any, label : String) -> Int? {
  read(survey).find(label)
}

///|
/// そのノードの中身の id、文書順
#export_name("mmmBlocks")
pub fn mmm_blocks(survey : @core.Any, id : Int) -> FixedArray[Int] {
  fixed(read(survey).blocks(id))
}

///|
fn holder_of(holder : String) -> @read.Holder {
  if holder == "md" {
    Md
  } else {
    Map
  }
}

///|
/// 位置（持ち手。無ければ null）
fn anchors_opt(v : @core.Any) -> @read.Anchors? {
  @core.identity_option(v)
}

///|
fn choice_of(v : @core.Any) -> @read.Choice {
  v.cast()
}

///|
/// 選択。持ち主（"md" / "map"）が決める — md が持つ間はカーソル（ranges は from, to の並び、
/// head は主カーソルの頭）から、地図が持つ間は位置（持ち手。無ければ null）から。返るのは選択の持ち手
#export_name("mmmChosen")
pub fn mmm_chosen(
  survey : @core.Any,
  holder : String,
  ranges : FixedArray[Int],
  head : Int,
  anchors : @core.Any,
) -> @core.Any {
  let rs : Array[@read.Range] = []
  let mut i = 0
  while i + 1 < ranges.length() {
    rs.push({ from: ranges[i], to: ranges[i + 1], })
    i += 2
  }
  @core.any(
    @read.chosen(
      read(survey),
      holder_of(holder),
      { ranges: rs, head, },
      anchors_opt(anchors),
    ),
  )
}

///|
/// 何も選んでいない
#export_name("mmmNothing")
pub fn mmm_nothing() -> @core.Any {
  @core.any(@read.nothing)
}

///|
/// 同じものを選んでいるか
#export_name("mmmSameChoice")
pub fn mmm_same_choice(a : @core.Any, b : @core.Any) -> Bool {
  choice_of(a) == choice_of(b)
}

///|
/// ノードの選択として見る（`{ ids, anchor | null }`）。カードを選んでいれば空
#export_name("mmmSelection")
pub fn mmm_selection(choice : @core.Any) -> @core.Any {
  selection_obj(
    match choice_of(choice) {
      Nodes(sel~) => sel
      Card(_) => @map.none
    },
  )
}

///|
/// カードの選択として見る。ノードを選んでいれば undefined
#export_name("mmmCard")
pub fn mmm_card(choice : @core.Any) -> Int? {
  match choice_of(choice) {
    Card(id~) => Some(id)
    Nodes(_) => None
  }
}

///|
/// focus の id をその木の地番で位置に（持ち手。無ければ null）
#export_name("mmmAnchorsOf")
pub fn mmm_anchors_of(survey : @core.Any, id : Int?) -> @core.Any {
  @core.from_option(@read.anchors_of(read(survey), id))
}

///|
/// 位置を編集で写す。`at` は点の写し（CodeMirror の `changes.mapPos`）
#export_name("mmmCarry")
pub fn mmm_carry(anchors : @core.Any, at : (Int) -> Int) -> @core.Any {
  let a : @read.Anchors = anchors.cast()
  @core.any(@read.carry(a, at))
}

///|
/// ノードの位置（並びと基点）。見本と試験が組む
#export_name("mmmNodeAt")
pub fn mmm_node_at(at : FixedArray[Int], anchor : Int?) -> @core.Any {
  @core.any((@read.NodeAt(at=ints(at), anchor~) : @read.Anchors))
}

///|
/// カードの位置
#export_name("mmmCardAt")
pub fn mmm_card_at(at : Int) -> @core.Any {
  @core.any((@read.CardAt(at~) : @read.Anchors))
}

///|
/// 位置の綴り（`["NodeAt",{at,anchor?}]` / `["CardAt",{at}]`）。試験が読む
#export_name("mmmAnchorsJson")
pub fn mmm_anchors_json(anchors : @core.Any) -> String {
  let a : @read.Anchors = anchors.cast()
  json(a)
}

///|
/// md 側で薄く塗る範囲（from, to の並び）
#export_name("mmmRanges")
pub fn mmm_ranges(survey : @core.Any, choice : @core.Any) -> FixedArray[Int] {
  let out : Array[Int] = []
  for r in @read.ranges(read(survey), choice_of(choice)) {
    out.push(r.from)
    out.push(r.to)
  }
  fixed(out)
}

///|
fn ints(a : FixedArray[Int]) -> Array[Int] {
  Array::from_fixed_array(a)
}

///|
fn fixed(a : Array[Int]) -> FixedArray[Int] {
  FixedArray::from_array(a)
}

///|
fn[T : ToJson] json(v : T) -> String {
  ToJson::to_json(v).stringify()
}

///|
fn defined(v : @core.Any) -> Bool {
  !@core.is_nullish(v)
}

///|
fn str_opt(v : @core.Any) -> String? {
  @core.identity_option(v)
}

///|
fn int_opt(v : @core.Any) -> Int? {
  @core.identity_option(v)
}

///|
/// Selection を ts の形（`{ ids, anchor | null }`）に
fn selection_obj(sel : @map.Selection) -> @core.Any {
  let o = @core.new_object()
  o._set("ids", @core.any(sel.ids))
  o._set("anchor", @core.from_option(sel.anchor))
  o
}

///|
fn selection_of(o : @core.Any) -> @map.Selection {
  { ids: o._get("ids").cast(), anchor: int_opt(o._get("anchor")), }
}

// ---- アプリ ----
//
// 束ねる場所（core/main）。ts が渡すのは CodeMirror の読み書き（`Editor`）だけ。
// 編集列は素の object（`{ from, to, insert }`）の並びで渡る

///|
fn editor_of(e : @core.Any) -> @main.Editor {
  let call = (name : String, args : Array[@core.Any]) => e._call(name, args)
  // 打鍵ごとに何千回も呼ぶものは、関数そのものを取って直に呼ぶ
  let tokens : (Array[String], String) -> Array[Array[@render.Token]] = e
    ._get("tokens")
    .cast()
  {
    text: () => call("text", []).cast(),
    survey: () => call("survey", []).cast(),
    holder: () => holder_of(call("holder", []).cast()),
    selection: () => selection_of(call("selection", [])),
    picked: () => int_opt(call("picked", [])),
    set_text: t => call("setText", [@core.any(t)]) |> ignore,
    apply: (sets, held, focus) => {
      call("apply", [@core.any(sets), @core.any(held), @core.from_option(focus)])
      |> ignore
    },
    select: a => call("select", [@core.from_option(a)]) |> ignore,
    hold: (h, a) => {
      call("hold", [
        @core.any(if h == Md { "md" } else { "map" }),
        @core.from_option(a),
      ])
      |> ignore
    },
    reveal: pos => call("reveal", [@core.any(pos)]) |> ignore,
    undo: () => call("undo", []) |> ignore,
    redo: () => call("redo", []) |> ignore,
    focus: () => call("focus", []) |> ignore,
    set_theme: dark => call("setTheme", [@core.any(dark)]) |> ignore,
    show_hint: on => call("showHint", [@core.any(on)]) |> ignore,
    tokens,
    tokens_block: text => call("tokensBlock", [@core.any(text)]).cast(),
    epoch: () => call("epoch", []).cast(),
    on_language_ready: f => call("onLanguageReady", [@core.any(f)]) |> ignore,
  }
}

///|
/// アプリを組む。返るのは持ち手。動かすのは `mmmBoot`（サイクルの出口が繋がってから）
#export_name("mmmMain")
pub fn mmm_main(editor : @core.Any) -> @core.Any {
  @core.any(
    @main.App::new(
      @dom.document(),
      editor_of(editor),
      @file.Io::new(@file.Handles::new(@file.idb_store())),
    ),
  )
}

///|
fn app_of(handle : @core.Any) -> @main.App {
  handle.cast()
}

///|
#export_name("mmmBoot")
pub fn mmm_boot(app : @core.Any) -> Unit {
  app_of(app).boot()
}

///|
/// 1 トランザクション = 1 サイクル。`prev` は前の読み（文書を丸ごと入れ替えたなら null）
#export_name("mmmCycle")
pub fn mmm_cycle(
  app : @core.Any,
  prev : @core.Any,
  tree_changed : Bool,
) -> Unit {
  app_of(app).cycle(
    if defined(prev) {
      Some(read(prev))
    } else {
      None
    },
    tree_changed,
  )
}

// ---- 見本（lab）が読むもの ----
//
// 地図の器・右クリックの行・帯の並び・書き出しの並び・お絵描き・たずね・絵・しらせ。
// ts は作ってもらって置くだけ

///|
/// 読み（mmmSurvey の持ち手）を置く。見本が右クリックの行を引くためだけに残る
#export_name("mmmLayout")
pub fn mmm_layout(survey : @core.Any) -> @core.Any {
  @core.any(
    @map.layout(
      read(survey).view.roots,
      @map.node_size(@render.measure(@dom.document())),
    ),
  )
}

///|
/// 右クリックの行（地図そのものは core が開く）
#export_name("mmmContextMenu")
pub fn mmm_context_menu(
  layout : @core.Any,
  ids : FixedArray[Int],
  anchor : Int?,
) -> @dom.Element {
  let l : @map.Layout = layout.cast()
  @parts.rows(
    @dom.document(),
    @render.items_of(@map.items(l, { ids: ints(ids), anchor, }), _ => ()),
  )
}

///|
/// ts の host を Host に。字の実測・クリップボード・しらせは core が持つ
fn host_of(h : @core.Any) -> @render.Host {
  let doc = @dom.document()
  let call = (name : String, args : Array[@core.Any]) => h._call(name, args)
  let tokens : (Array[String], String) -> Array[Array[@render.Token]] = h
    ._get("tokens")
    .cast()
  {
    survey: () => call("survey", []).cast(),
    measure: @render.measure(doc),
    image_url: p => str_opt(call("imageUrl", [@core.any(p)])),
    image_hint: () => str_opt(call("imageHint", [])),
    connect_assets: () => call("connectAssets", []) |> ignore,
    holder: () => holder_of(call("holder", []).cast()),
    selection: () => selection_of(call("selection", [])),
    set_selection: (sel, reveal) => {
      call("setSelection", [selection_obj(sel), @core.any(reveal)]) |> ignore
    },
    picked: () => int_opt(call("picked", [])),
    set_picked: id => call("setPicked", [@core.from_option(id)]) |> ignore,
    block_text: id => call("blockText", [@core.any(id)]).cast(),
    apply: (_, _) => None,
    paste: () => (),
    copy: k => k(true),
    draw: _ => (),
    read_clipboard: k => {
      @js_async.Promise::from_async(async fn() {
        k(@web.read_clipboard(doc).wait())
      })
      |> ignore
    },
    tokens,
    tokens_block: text => call("tokensBlock", [@core.any(text)]).cast(),
    epoch: () => call("epoch", []).cast(),
    failed: msg => @parts.failed(doc, msg),
  }
}

///|
/// ペインを地図の器にする。返るのは地図の持ち手
#export_name("mmmMap")
pub fn mmm_map(pane : @dom.HTMLElement, host : @core.Any) -> @core.Any {
  @core.any(@render.Mindmap::new(pane, host_of(host)))
}

///|
fn map_of(handle : @core.Any) -> @render.Mindmap {
  handle.cast()
}

///|
/// 置き直して描く（文書が変わった）
#export_name("mmmMapRender")
pub fn mmm_map_render(map : @core.Any) -> Unit {
  map_of(map).render()
}

///|
/// 全体が収まるように視点を寄せる
#export_name("mmmMapFit")
pub fn mmm_map_fit(map : @core.Any) -> Unit {
  map_of(map).fit_view()
}

///|
/// 選択の塗り直し。レイアウトは見直さない
#export_name("mmmMapRefresh")
pub fn mmm_map_refresh(map : @core.Any) -> Unit {
  map_of(map).refresh_selection()
}

///|
/// その場編集に入る。seed は最初の字。箱が無い（畳まれて埋もれた）ノードは開けない
#export_name("mmmMapBeginEdit")
pub fn mmm_map_begin_edit(map : @core.Any, id : Int, seed : String?) -> Bool {
  map_of(map).begin_edit(id, seed)
}

///|
/// カードをその場で開く
#export_name("mmmMapEditCard")
pub fn mmm_map_edit_card(map : @core.Any, id : Int) -> Unit {
  map_of(map).edit_card(id)
}

///|
/// その名前の絵（Lucide の綴り）
#export_name("mmmIcon")
pub fn mmm_icon(name : String) -> @dom.Element {
  @parts.icon(@dom.document(), name)
}

///|
/// 絵の名前の全部
#export_name("mmmIconNames")
pub fn mmm_icon_names() -> FixedArray[String] {
  FixedArray::from_array(@parts.names())
}

///|
/// しらせ 1 つぶん
#export_name("mmmNotice")
pub fn mmm_notice(mark : String, msg : String, sorry : Bool) -> @dom.Element {
  @parts.notice(@dom.document(), mark, msg, sorry)
}

///|
#export_name("mmmFailedWords")
pub fn mmm_failed_words() -> FixedArray[String] {
  FixedArray::from_array(@parts.failed_words)
}

///|
#export_name("mmmBlockedWords")
pub fn mmm_blocked_words() -> FixedArray[String] {
  FixedArray::from_array(@parts.blocked_words)
}

///|
/// 空のときの言い出し（"md" / "map"）。md ペインは ts（editor.ts）がこれを浮かべる
#export_name("mmmPaneHint")
pub fn mmm_pane_hint(pane : String) -> @dom.Element {
  @parts.pane_hint(@dom.document(), pane)
}

///|
fn strings_of(v : @core.Any) -> Array[String] {
  @core.array_from(v).map(x => x.cast())
}

///|
fn files_of(v : @core.Any) -> @app.Files {
  {
    saved_name: str_opt(v._get("savedName")),
    recent: strings_of(v._get("recent")),
    can_open: v._get("canOpen").cast(),
    can_save: v._get("canSave").cast(),
    can_rename: v._get("canRename").cast(),
    can_choose_folder: v._get("canChooseFolder").cast(),
    folder: v._get("folder").cast(),
  }
}

///|
fn file_acts_of(v : @core.Any) -> @app.FileActs {
  let call = (name : String, args : Array[@core.Any]) => {
    v._call(name, args) |> ignore
  }
  {
    new_file: () => call("newFile", []),
    open: () => call("open", []),
    open_recent: i => call("openRecent", [@core.any(i)]),
    save: () => call("save", []),
    save_as: () => call("saveAs", []),
    rename: () => call("rename", []),
    choose_folder: () => call("chooseFolder", []),
  }
}

///|
/// Files の行
#export_name("mmmFilesRows")
pub fn mmm_files_rows(state : @core.Any, acts : @core.Any) -> @dom.Element {
  @parts.rows(
    @dom.document(),
    @app.files_menu(files_of(state), file_acts_of(acts)),
  )
}

///|
fn more_of(v : @core.Any) -> @app.More {
  {
    light: v._get("light").cast(),
    grab: v._get("grab").cast(),
    link_note: k => {
      @web.after(v._get("linkNote"), texts => k(strings_of(texts)))
    },
  }
}

///|
fn more_acts_of(v : @core.Any) -> @app.MoreActs {
  let call = (name : String, args : Array[@core.Any]) => v._call(name, args)
  {
    undo: () => call("undo", []) |> ignore,
    redo: () => call("redo", []) |> ignore,
    pick_color: () => call("pickColor", []) |> ignore,
    toggle_theme: () => call("toggleTheme", []) |> ignore,
    toggle_grab: () => call("toggleGrab", []) |> ignore,
    copy_link: k => @web.after(call("copyLink", []), ok => k(ok.cast())),
  }
}

///|
/// ⋯ の行
#export_name("mmmMoreRows")
pub fn mmm_more_rows(state : @core.Any, acts : @core.Any) -> @dom.Element {
  @parts.rows(
    @dom.document(),
    @app.more_menu(more_of(state), more_acts_of(acts)),
  )
}

///|
/// 出し方の並び。`empty` なら全部沈む（出す先は無い）
#export_name("mmmExportWays")
pub fn mmm_export_ways(empty : Bool) -> @dom.Element {
  let doc = @dom.document()
  @parts.rows(
    doc,
    @app.export_ways(
      {
        svg: fn() { None },
        name: () => "mmm",
        failed: msg => @parts.failed(doc, msg),
        blocked: msg => @parts.blocked(doc, msg),
        empty: () => empty,
      },
      None,
    ),
  )
}

///|
/// お絵描きの form（押しても何も起きない）
#export_name("mmmDrawForm")
pub fn mmm_draw_form() -> @dom.Element {
  @app.draw_form(@dom.document(), () => (), _ => ()).0
}

///|
/// ts の並び（字か `{ value, check? }`）を Part に。`here`（置き場に既に在る
/// 名前）を渡すと、欄は**本物の検査**を積む — 並べて見る道具が言葉を写さずに
/// 済む。渡さなければ ts の `check` のまま
fn parts_with(v : @core.Any, here : Set[String]?) -> Array[@app.Part] {
  @core.array_from(v).map(x => {
    if @core.typeof_(x) == "string" {
      @app.Text(x.cast())
    } else {
      let check = x._get("check")
      @app.Blank({
        value: x._get("value").cast(),
        check: match here {
          Some(here) => Some(typed => @file.image_name_problem(typed, here))
          None =>
            if defined(check) {
              Some(value => str_opt(check._invoke([@core.any(value)])))
            } else {
              None
            }
        },
      })
    }
  })
}

///|
/// 名前で引くたずね。args は名前ごと（connect / rename は字、imageName は { shape, shot }）
fn named_ask(kind : String, args : @core.Any) -> @app.Ask {
  match kind {
    "discard" => @app.discard()
    "place" => @app.place()
    "connect" => @app.connect(args.cast())
    "rename" => @app.rename(args.cast())
    "imageName" => {
      let taken = args._get("taken")
      let here : Set[String]? = if defined(taken) {
        Some(Set::from_array(@core.array_from(taken).map(x => x.cast())))
      } else {
        None
      }
      @app.image_name(
        parts_with(args._get("shape"), here),
        args._get("shot").cast(),
      )
    }
    "declaration" =>
      @app.declaration(args._get("folder").cast(), folder_field(args))
    "redeclaration" => @app.redeclaration(folder_field(args))
    _ => abort("知らないたずね: " + kind)
  }
}

///|
/// 宣言の欄。**検査は本物**（core/file/assets.mbt）— 並べて見る道具が言葉を
/// 写さずに済むよう、だめな値を渡せばそのまま本物の理由が出る。
/// `dirName` はフォルダの実名（末尾を照合する。計算できていれば渡さない）
fn folder_field(args : @core.Any) -> @app.Field {
  let dir_name = str_opt(args._get("dirName"))
  {
    value: args._get("value").cast(),
    check: Some(typed => @file.folder_problem(typed, dir_name)),
  }
}

///|
/// たずねの中身（form）だけ
#export_name("mmmAskForm")
pub fn mmm_ask_form(kind : String, args : @core.Any) -> @dom.Element {
  @app.ask_form(@dom.document(), named_ask(kind, args), () => ()).0
}

///|
/// ロゴの SVG（favicon の源。ビルド時にも呼ぶ）
#export_name("mmmLogoSvg")
pub fn mmm_logo_svg(fill : String, dirty : Bool) -> String {
  @app.logo_svg(fill, dirty)
}

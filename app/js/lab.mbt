// browser への出口 — **見本（lab/）と試験（test/）と build（vite.config.ts）が呼ぶ面。**
// 本番（src/）は 1 つも呼ばない（#252）。本番の面と糊は exports.mbt。
//
// 見本は「文書は固定で、選択だけ動く」地図と、器を 1 つずつ置く。**できないことは
// ここが決める** — 見本の地図は md に書かない（`lab_host`）、書き出しは出し口を持たない
// （`mmm_export_ways`）、右クリックの行は押しても走らない（`mmm_context_menu`）。
// 試験は読みと選択の問い合わせを数と字で確かめる。どの段で壊れたかを切り分けるために、
// mdAst・mmmTree・書き戻しも出す

// ---- 読みの段（lab/lab.ts） ----

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
/// 型で言えない不変条件の破れ。**parse の出力は必ず空**になるはずで、
/// 空でなければ読みのバグ。
#export_name("mmmCheck")
pub fn mmm_check(md : String) -> String {
  @tree.check(@tree.parse(md)).to_json().stringify()
}

///|
/// 木を書き戻した正規形の md。test/notation.test.ts が冪等を言う
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

///|
/// 触っていない記法構造を md へ書き戻す。**API ではなく物差し** — 呼ぶのは
/// `test/notation.test.ts` だけで、面を跨ぐのは fixtures（523 KB）が
/// ディスクに在って MoonBit から読めないから。
#export_name("mmmNotationBack")
pub fn mmm_notation_back(md : String) -> String {
  @tree.notation_back(md)
}

// ---- 読みと選択の問い合わせ（test/、lab/parts） ----

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
/// 何も選んでいない
#export_name("mmmNothing")
pub fn mmm_nothing() -> @core.Any {
  @core.any(@read.nothing)
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

// ---- 見本の地図（lab/parts/map.ts） ----

///|
/// 読み（mmmSurvey の持ち手）を置く。見本が右クリックの行を引くためだけに残る。
/// **字の実測はここが持つ**（canvas）— 見本は寸法を渡さない
#export_name("mmmLayout")
pub fn mmm_layout(survey : @core.Any) -> @core.Any {
  @core.any(
    @map.layout(
      read(survey).doc.roots,
      @map.node_size(@mindmap.measure(@dom.document())),
    ),
  )
}

///|
/// 右クリックの行。**押しても走らない**（act は `_ => ()`）— 見本は並びを見せるだけで、
/// 地図そのものは core が開く
#export_name("mmmContextMenu")
pub fn mmm_context_menu(
  layout : @core.Any,
  ids : FixedArray[Int],
  anchor : Int?,
) -> @dom.Element {
  let l : @map.Layout = layout.cast()
  @parts.rows(
    @dom.document(),
    @mindmap.items_of(@map.items(l, { ids: ints(ids), anchor, }), _ => ()),
  )
}

///|
/// 見本の地図の Host。**見本にできないことはここが決める** — 文書は固定なので
/// 操作は映さず（`apply` は None）、貼らず（`paste`）、描かず（`draw`）、写しは
/// いつも「写せた」と答える（`copy`）。ts から来るのは読み・選択・画像・色分けだけで、
/// 字の実測・クリップボード・しらせは core が持つ
fn lab_host(h : @core.Any) -> @mindmap.Host {
  let doc = @dom.document()
  let call = (name : String, args : Array[@core.Any]) => h._call(name, args)
  let tokens : (Array[String], String) -> Array[Array[@mindmap.Token]] = h
    ._get("tokens")
    .cast()
  {
    survey: () => call("survey", []).cast(),
    measure: @mindmap.measure(doc),
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
    leave: () => @bar.focus_bar(doc),
  }
}

///|
/// ペインを地図の器にする。返るのは地図の持ち手
#export_name("mmmMap")
pub fn mmm_map(pane : @dom.HTMLElement, host : @core.Any) -> @core.Any {
  @core.any(@mindmap.Mindmap::new(pane, lab_host(host)))
}

///|
fn map_of(handle : @core.Any) -> @mindmap.Mindmap {
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

// ---- 器（lab/parts/parts.ts、test/notice.test.ts） ----

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
fn strings_of(v : @core.Any) -> Array[String] {
  @core.array_from(v).map(x => x.cast())
}

///|
fn files_of(v : @core.Any) -> @bar.Files {
  {
    saved_name: str_opt(v._get("savedName")),
    recent: strings_of(v._get("recent")),
    drafts: strings_of(v._get("drafts")),
    can_open: v._get("canOpen").cast(),
    can_save: v._get("canSave").cast(),
    can_rename: v._get("canRename").cast(),
    can_choose_folder: v._get("canChooseFolder").cast(),
    folder: v._get("folder").cast(),
  }
}

///|
fn file_acts_of(v : @core.Any) -> @bar.FileActs {
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
    open_draft: i => call("openDraft", [@core.any(i)]),
    forget_drafts: () => call("forgetDrafts", []),
  }
}

///|
/// Files の行
#export_name("mmmFilesRows")
pub fn mmm_files_rows(state : @core.Any, acts : @core.Any) -> @dom.Element {
  @parts.rows(
    @dom.document(),
    @bar.files_menu(files_of(state), file_acts_of(acts)),
  )
}

///|
fn more_of(v : @core.Any) -> @bar.More {
  {
    light: v._get("light").cast(),
    grab: v._get("grab").cast(),
    link_caveat: k => {
      @web.after(v._get("linkCaveat"), texts => k(strings_of(texts)))
    },
  }
}

///|
fn more_acts_of(v : @core.Any) -> @bar.MoreActs {
  let call = (name : String, args : Array[@core.Any]) => v._call(name, args)
  {
    undo: () => call("undo", []) |> ignore,
    redo: () => call("redo", []) |> ignore,
    pick_color: () => call("pickColor", []) |> ignore,
    toggle_theme: () => call("toggleTheme", []) |> ignore,
    toggle_grab: () => call("toggleGrab", []) |> ignore,
    copy_link: k => @web.after(call("copyLink", []), ok => k(ok.cast())),
    visit: url => @web.open_url(@dom.document(), url),
  }
}

///|
/// ⋯ の行
#export_name("mmmMoreRows")
pub fn mmm_more_rows(state : @core.Any, acts : @core.Any) -> @dom.Element {
  @parts.rows(
    @dom.document(),
    @bar.more_menu(more_of(state), more_acts_of(acts)),
  )
}

///|
/// 出し方の並び。`empty` なら全部沈む。**出し口は無い** — Host はここが仕立て、
/// SVG は常に None（押せば「出すものが無い」に落ちる）。並びを見せるだけ
#export_name("mmmExportWays")
pub fn mmm_export_ways(empty : Bool) -> @dom.Element {
  let doc = @dom.document()
  @parts.rows(
    doc,
    @bar.export_ways(
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
  @parts.draw_form(@dom.document(), () => (), _ => ()).0
}

///|
/// ts の並び（字か `{ value, check? }`）を Part に。`here`（置き場に既に在る
/// 名前）を渡すと、欄は**本物の検査**を積む — 並べて見る道具が言葉を写さずに
/// 済む。渡さなければ ts の `check` のまま
fn parts_with(v : @core.Any, here : Set[String]?) -> Array[@parts.Part] {
  @core.array_from(v).map(x => {
    if @core.typeof_(x) == "string" {
      @parts.Text(x.cast())
    } else {
      let check = x._get("check")
      @parts.Blank({
        value: x._get("value").cast(),
        check: match here {
          Some(here) => Some(typed => @disk.image_name_problem(typed, here))
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
/// たずねの中身（form）だけ。名で引く表は app/parts/asks.mbt の `named` で、ここは
/// ts の args を読むだけ — 字ならそれが `text`（connect の folder / rename の name）、
/// object なら `folder` / `shape` / `shot` / `taken` / `value` / `dirName` を名ごとに要るぶん。
/// **欄の検査は本物**（app/disk）— `taken`（置き場に既に在る名前）と `dirName`
/// （フォルダの実名。計算できていれば渡さない）を渡せば、だめな値でそのまま本物の理由が出る
#export_name("mmmAskForm")
pub fn mmm_ask_form(kind : String, args : @core.Any) -> @dom.Element {
  let obj = defined(args) && @core.typeof_(args) != "string"
  let get = (key : String) => {
    if obj {
      args._get(key)
    } else {
      @core.undefined()
    }
  }
  let taken = get("taken")
  let here : Set[String]? = if defined(taken) {
    Some(Set::from_array(strings_of(taken)))
  } else {
    None
  }
  let shape = get("shape")
  let ask = @parts.named(
    kind,
    text=str_opt(if obj { get("folder") } else { args }).unwrap_or(""),
    parts=if defined(shape) { parts_with(shape, here) } else { [] },
    shot=str_opt(get("shot")).unwrap_or(""),
    field={
      value: str_opt(get("value")).unwrap_or(""),
      check: Some(typed => @disk.folder_problem(typed, str_opt(get("dirName")))),
    },
  )
  @parts.ask_form(@dom.document(), ask, () => ()).0
}

// ---- build（vite.config.ts） ----

///|
/// ロゴの SVG（favicon の源。ビルド時にも呼ぶ）
#export_name("mmmLogoSvg")
pub fn mmm_logo_svg(fill : String, dirty : Bool) -> String {
  @bar.logo_svg(fill, dirty)
}

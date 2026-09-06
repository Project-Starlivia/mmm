// core を browser から使うための薄い層。**中身は持たない**（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
//
// 木も箱も core から出ない。境界は数・文字列・真偽・持ち手（MoonBit の値を
// そのまま JS へ渡し、そのまま受け取る）と、操作 1 回ぶんの小さな JSON
// （Intent・落とし先・メニューの行・選択）。
//
// どの段で壊れたかを切り分けるために、mdAst・mmmTree・View を並べて出す。

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

///|
/// 打鍵 1 回ぶんの読み。返るのは読み（木・地番・原文）の持ち手 — 木は出さない。
/// 読むには下の問い合わせを使う。選択の持ち越しは core に無い — 位置は ts が
/// CodeMirror に預けて写す
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
/// まだ保存していない文書の名前（拡張子なし）。最初の根の字から
#export_name("mmmName")
pub fn mmm_name(survey : @core.Any) -> String {
  read(survey).name()
}

///|
/// ラベルをファイル名にする
#export_name("mmmToFileName")
pub fn mmm_to_file_name(label : String) -> String {
  @read.to_file_name(label)
}

///|
/// 頭（frontmatter の原文）。無ければ undefined
#export_name("mmmFrontmatter")
pub fn mmm_frontmatter(survey : @core.Any) -> String? {
  read(survey).view.frontmatter
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
/// 選択。持ち主（"md" / "map"）が決める — md が持つ間はカーソル（ranges は from, to の並び、
/// head は主カーソルの頭）から、地図が持つ間は位置（anchors の JSON。無ければ ""）から。
/// 返るのは Choice の JSON
#export_name("mmmChosen")
pub fn mmm_chosen(
  survey : @core.Any,
  holder : String,
  ranges : FixedArray[Int],
  head : Int,
  anchors : String,
) -> String {
  let rs : Array[@read.Range] = []
  let mut i = 0
  while i + 1 < ranges.length() {
    rs.push({ from: ranges[i], to: ranges[i + 1], })
    i += 2
  }
  let a : @read.Anchors? = if anchors == "" {
    None
  } else {
    Some(
      @json.from_json(@json.parse(anchors)) catch {
        e => abort("mmmChosen: Anchors の JSON が読めない — \{e}")
      },
    )
  }
  let h : @read.Holder = if holder == "md" { Md } else { Map }
  json(@read.chosen(read(survey), h, { ranges: rs, head, }, a))
}

///|
fn choice_of(s : String) -> @read.Choice {
  @json.from_json(@json.parse(s)) catch {
    e => abort("Choice の JSON が読めない — \{e}")
  }
}

///|
/// focus の id をその木の地番で位置に（Anchors の JSON。無ければ ""）
#export_name("mmmAnchorsOf")
pub fn mmm_anchors_of(survey : @core.Any, id : Int?) -> String {
  match @read.anchors_of(read(survey), id) {
    Some(a) => json(a)
    None => ""
  }
}

///|
/// 選択（Choice の JSON）をその木の地番で位置に（Anchors の JSON。無ければ ""）
#export_name("mmmAnchorsFor")
pub fn mmm_anchors_for(survey : @core.Any, choice : String) -> String {
  match @read.anchors_for(read(survey), choice_of(choice)) {
    Some(a) => json(a)
    None => ""
  }
}

///|
/// md 側で薄く塗る範囲（from, to の並び）
#export_name("mmmRanges")
pub fn mmm_ranges(survey : @core.Any, choice : String) -> FixedArray[Int] {
  let out : Array[Int] = []
  for r in @read.ranges(read(survey), choice_of(choice)) {
    out.push(r.from)
    out.push(r.to)
  }
  fixed(out)
}

///|
/// 選んだ部分木の原文（Mod+C / Mod+X）
#export_name("mmmCopy")
pub fn mmm_copy(survey : @core.Any, ids : FixedArray[Int]) -> String {
  read(survey).copy(ints(ids))
}

///|
/// 頭が言っている画像フォルダ（綴りのまま）。無ければ undefined
#export_name("mmmImageFolder")
pub fn mmm_image_folder(survey : @core.Any) -> String? {
  @read.image_folder(read(survey).view.frontmatter)
}

///|
/// 画像フォルダの宣言を書き換える編集（Edit の JSON）
#export_name("mmmSetImageFolder")
pub fn mmm_set_image_folder(survey : @core.Any, value : String) -> String {
  let s = read(survey)
  json(@read.set_image_folder(s.md, s.view.frontmatter, value))
}

///|
/// 宣言フォルダの引っ越しに本文の画像を追従させる操作列（Op の列の JSON）
#export_name("mmmRetarget")
pub fn mmm_retarget(survey : @core.Any, from : String, to : String) -> String {
  json(@read.retarget(read(survey).view, from, to))
}

///|
/// 宣言の綴りを揃える。読めなければ undefined
#export_name("mmmNormalizePath")
pub fn mmm_normalize_path(value : String) -> String? {
  @read.normalize_path(value)
}

///|
/// path が folder の下にあるなら、フォルダからの残り。外なら undefined
#export_name("mmmUnder")
pub fn mmm_under(path : String, folder : String) -> String? {
  @read.under(path, folder)
}

///|
/// 先頭の `./` を落とした形
#export_name("mmmBarePath")
pub fn mmm_bare_path(path : String) -> String {
  @tree.bare_path(path)
}

///|
/// 操作を md に映す。op は `@op.Op` の JSON（ToJson の形そのまま）。
/// 返るのは編集列と、編集を当てて読み直した木での focus。
/// 壊れた JSON は ts の側のバグなので、静かに断らず投げる
/// （`raise` にすると JS 側が Result を受け取ってしまう）。
#export_name("mmmEdit")
pub fn mmm_edit(md : String, op : String) -> String {
  let op : @op.Op = @json.from_json(@json.parse(op)) catch {
    e => abort("mmmEdit: op の JSON が読めない — \{e}")
  }
  @edit.edit(md, op).to_json().stringify()
}

// ---- 配置 ----

///|
/// 読み（mmmSurvey の持ち手）を置く。`measure` は ts の canvas（Font, 字 → 幅）。
/// 見本（lab）が右クリックの行を引くためだけに残る — 地図そのものは mmmMap が置く
#export_name("mmmLayout")
pub fn mmm_layout(
  survey : @core.Any,
  measure : (@map.Font, String) -> Double,
) -> @core.Any {
  @core.any(@map.layout(read(survey).view.roots, @map.node_size(measure)))
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
/// 右クリックの行（並べて見るため。地図そのものは core が開く）
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

// ---- 地図 ----
//
// ペインを渡せば core が置いて描き、入力を受ける。ts は host（文書と選択の読み書き、
// ブラウザの API）を関数の入った object で渡し、持ち手で頼むだけ。

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
/// ts の host を Host に。null は None に、Op と行は JSON に、約束は続きに
fn host_of(h : @core.Any) -> @render.Host {
  let call = (name : String, args : Array[@core.Any]) => h._call(name, args)
  // 打鍵ごとに何千回も呼ぶものは、関数そのものを取って直に呼ぶ（名前引きの呼び出しは
  // 5000 ノードで 1 打鍵 +15 ms）。null を None に読み替えるものだけ包む
  let measure : @map.Measure = h._get("measure").cast()
  let tokens : (Array[String], String) -> Array[Array[@render.Token]] = h
    ._get("tokens")
    .cast()
  {
    survey: () => call("survey", []).cast(),
    measure,
    image_url: p => str_opt(call("imageUrl", [@core.any(p)])),
    image_hint: () => str_opt(call("imageHint", [])),
    connect_assets: () => call("connectAssets", []) |> ignore,
    holder: () => {
      let h : String = call("holder", []).cast()
      if h == "md" {
        Md
      } else {
        Map
      }
    },
    selection: () => {
      let o = call("selection", [])
      { ids: o._get("ids").cast(), anchor: int_opt(o._get("anchor")), }
    },
    set_selection: (sel, reveal) => {
      call("setSelection", [selection_obj(sel), @core.any(reveal)]) |> ignore
    },
    picked: () => int_opt(call("picked", [])),
    set_picked: id => call("setPicked", [@core.from_option(id)]) |> ignore,
    block_text: id => call("blockText", [@core.any(id)]).cast(),
    apply: (op, edit) => {
      int_opt(call("apply", [@core.any(json(op)), @core.any(edit)]))
    },
    paste: () => call("paste", []) |> ignore,
    copy: k => call("copy", [])._call("then", [@core.any(k)]) |> ignore,
    draw: id => call("draw", [@core.any(id)]) |> ignore,
    read_clipboard: k => {
      call("readClipboard", [])._call("then", [@core.any(k)]) |> ignore
    },
    tokens,
    tokens_block: text => call("tokensBlock", [@core.any(text)]).cast(),
    epoch: () => call("epoch", []).cast(),
    failed: msg => call("failed", [@core.any(msg)]) |> ignore,
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
/// 全体が入る見え方に
#export_name("mmmMapFit")
pub fn mmm_map_fit(map : @core.Any) -> Unit {
  map_of(map).fit_view()
}

///|
/// 選択（無ければ根）を画面の中心へ
#export_name("mmmMapCenter")
pub fn mmm_map_center(map : @core.Any) -> Unit {
  map_of(map).center_on_target()
}

///|
/// 選択の塗り直し（置き直さない）
#export_name("mmmMapRefresh")
pub fn mmm_map_refresh(map : @core.Any) -> Unit {
  map_of(map).refresh_selection()
}

///|
/// その場編集に入る。seed は最初の字（無ければ undefined）。箱が無ければ false
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
/// 掴みやすさ（⋯ の Easy grab）
#export_name("mmmMapSetGrab")
pub fn mmm_map_set_grab(map : @core.Any, on : Bool) -> Unit {
  map_of(map).set_grab(on)
}

///|
/// ファイルのドラッグ中、その画面の点に落ちる先を予告する。`on` が偽なら予告を消す。
/// 落ちる先のノードの id（無ければ undefined）
#export_name("mmmMapFileDrop")
pub fn mmm_map_file_drop(
  map : @core.Any,
  x : Double,
  y : Double,
  on : Bool,
) -> Int? {
  map_of(map).mark_file_drop(if on { Some({ x, y, }) } else { None })
}

///|
/// 書き出しに写すもの。`rects`（文書順の箱。x, y, w, h）と `edges` / `nodes`（要素）
#export_name("mmmMapSvgParts")
pub fn mmm_map_svg_parts(map : @core.Any) -> @core.Any {
  let (rects, edges, nodes) = map_of(map).svg_parts()
  let o = @core.new_object()
  o._set(
    "rects",
    @core.any(
      FixedArray::from_array(
        rects.map(r => ([r.x, r.y, r.w, r.h] : FixedArray[Double])),
      ),
    ),
  )
  o._set("edges", @core.any(edges))
  o._set("nodes", @core.any(nodes))
  o
}

// ---- 部品 ----
//
// 絵・しらせ・言い出し・道具の器・メニューの器（core/parts）。ts は作ってもらって置くだけ。
// メニューの行は ts の object（label / key / mark / note / disabled / run / done / items /
// caption、または "sep"）で受け、ここで Entry にする

///|
fn defined(v : @core.Any) -> Bool {
  !@core.is_nullish(v)
}

///|
/// ts の行 1 つを Entry に
fn entry_of(v : @core.Any) -> @parts.Entry {
  if @core.typeof_(v) == "string" {
    return Sep
  }
  let caption = v._get("caption")
  if defined(caption) {
    return Caption(caption.cast(), str_opt(v._get("mark")))
  }
  let d = v._get("disabled")
  let disabled : @parts.Disabled = if !defined(d) {
    No
  } else if @core.typeof_(d) == "string" {
    Why(d.cast())
  } else if d.cast() {
    Yes
  } else {
    No
  }
  let note = v._get("note")
  let row = @parts.row(
    v._get("label").cast(),
    key=str_opt(v._get("key")),
    mark=str_opt(v._get("mark")),
    note=if defined(note) {
      Some(k => {
        if @core.is_array(note) {
          k(note.cast())
        } else {
          @web.after(note, texts => k(texts.cast()))
        }
      })
    } else {
      None
    },
    disabled~,
  )
  let run = v._get("run")
  let go = () => run._invoke([]) |> ignore
  let items = v._get("items")
  if defined(items) {
    return Sub(
      row,
      @core.array_from(items).map(entry_of),
      if defined(run) {
        Some(go)
      } else {
        None
      },
    )
  }
  let done = v._get("done")
  if defined(done) {
    return Done(row, k => @web.after(done._invoke([]), ok => k(ok.cast())))
  }
  Run(row, go)
}

///|
fn entries_of(v : @core.Any) -> Array[@parts.Entry] {
  @core.array_from(v).map(entry_of)
}

///|
/// その名前の絵（Lucide の綴り）
#export_name("mmmIcon")
pub fn mmm_icon(name : String) -> @dom.Element {
  @parts.icon(@dom.document(), name)
}

///|
/// 絵の名前の全部（並べて見るため）
#export_name("mmmIconNames")
pub fn mmm_icon_names() -> FixedArray[String] {
  FixedArray::from_array(@parts.names())
}

///|
/// 字と絵を並べたボタンの中身
#export_name("mmmLabel")
pub fn mmm_label(
  text : String,
  name : String,
  after : Bool,
) -> Array[@dom.Node] {
  @parts.label(@dom.document(), text, name, after)
}

///|
/// 押した場所で答える。`work` は Promise[Bool]、済めば `k(ok)`
#export_name("mmmNod")
pub fn mmm_nod(
  work : @core.Any,
  put : (String) -> Unit,
  k : (Bool) -> Unit,
) -> Unit {
  @parts.nod(kk => @web.after(work, ok => kk(ok.cast())), put, k)
}

///|
#export_name("mmmFailed")
pub fn mmm_failed(msg : String) -> Unit {
  @parts.failed(msg)
}

///|
#export_name("mmmBlocked")
pub fn mmm_blocked(msg : String) -> Unit {
  @parts.blocked(msg)
}

///|
/// しらせ 1 つぶん（並べて見るため）
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
/// 空のときの言い出し（"md" / "map"）
#export_name("mmmPaneHint")
pub fn mmm_pane_hint(pane : String) -> @dom.Element {
  @parts.pane_hint(@dom.document(), pane)
}

///|
/// ペインの隅に浮く道具の器
#export_name("mmmPaneTool")
pub fn mmm_pane_tool(name : String) -> @dom.Element {
  @parts.pane_tool(@dom.document(), name)
}

///|
/// そのボタンでメニューを開く。並びは開くたびに `items()` で作る
#export_name("mmmOpenOnClick")
pub fn mmm_open_on_click(
  button : @dom.Element,
  items : () -> @core.Any,
) -> Unit {
  @parts.open_on_click(button, () => entries_of(items()))
}

///|
/// 行だけのメニュー（並べて見るため）
#export_name("mmmMenuRows")
pub fn mmm_menu_rows(items : @core.Any) -> @dom.Element {
  @parts.rows(@dom.document(), entries_of(items))
}

// ---- 帯と枠 ----
//
// 持ち物（localStorage）・ペインの出し分け・全体のキー・見た目の好み・たずね（core/app）。
// 閉包は ts の関数をそのまま受け、たずねの並びは ts の object で受ける

///|
/// 持ち物を読む（名前は theme / color / way / grab）。無ければ undefined
#export_name("mmmLoad")
pub fn mmm_load(name : String) -> String? {
  @app.load(name)
}

///|
#export_name("mmmStore")
pub fn mmm_store(name : String, value : String) -> Unit {
  @app.store(name, value)
}

///|
/// 役目を終えた localStorage のキーを捨てる
#export_name("mmmSweep")
pub fn mmm_sweep() -> Unit {
  @app.sweep()
}

///|
fn pane_of(which : String) -> @app.Pane {
  match which {
    "md" => Md
    "map" => Map
    _ => abort("知らないペイン: " + which)
  }
}

///|
/// ペインの出し分けと分割線。返るのは持ち手
#export_name("mmmPanes")
pub fn mmm_panes(
  md_pane : @dom.Element,
  map_pane : @dom.Element,
  panes_el : @dom.Element,
  splitter : @dom.Element,
  focus_editor : () -> Unit,
) -> @core.Any {
  @core.any(
    @app.Panes::new(md_pane, map_pane, panes_el, splitter, focus_editor),
  )
}

///|
fn panes_of(handle : @core.Any) -> @app.Panes {
  handle.cast()
}

///|
/// Mod+/: もう片方のペインへ。隠れていれば出す
#export_name("mmmTogglePane")
pub fn mmm_toggle_pane(panes : @core.Any) -> Unit {
  panes_of(panes).toggle()
}

///|
/// そのペイン（"md" / "map"）の表示 / 非表示
#export_name("mmmTogglePaneVis")
pub fn mmm_toggle_pane_vis(panes : @core.Any, which : String) -> Unit {
  panes_of(panes).toggle_vis(pane_of(which))
}

///|
/// アプリ全体のキー。`deps` は関数の入った object（save / open / create / togglePane /
/// togglePaneVis / undo / redo / export）
#export_name("mmmShortcuts")
pub fn mmm_shortcuts(deps : @core.Any) -> Unit {
  let call = (name : String, args : Array[@core.Any]) => {
    deps._call(name, args) |> ignore
  }
  @app.init_shortcuts(@dom.document(), {
    save: as_new => call("save", [@core.any(as_new)]),
    open: () => call("open", []),
    create: () => call("create", []),
    toggle_pane: () => call("togglePane", []),
    toggle_pane_vis: p => {
      call("togglePaneVis", [
        @core.any(
          match p {
            Md => "md"
            Map => "map"
          },
        ),
      ])
    },
    undo: () => call("undo", []),
    redo: () => call("redo", []),
    export_map: choose => call("export", [@core.any(choose)]),
  })
}

///|
/// いまのアクセントカラー（`#rrggbb`）。読めなければ undefined
#export_name("mmmAccent")
pub fn mmm_accent() -> String? {
  @app.accent(@dom.document())
}

///|
/// ロゴの SVG（favicon の源。ビルド時にも呼ぶ）
#export_name("mmmLogoSvg")
pub fn mmm_logo_svg(fill : String, dirty : Bool) -> String {
  @app.logo_svg(fill, dirty)
}

///|
/// カラーとテーマの配線と、保存値の復元。返るのは持ち手
#export_name("mmmTheme")
pub fn mmm_theme(
  logo : @dom.Element,
  set_editor_theme : (Bool) -> Unit,
) -> @core.Any {
  @core.any(@app.Theme::new(logo, set_editor_theme))
}

///|
fn theme_of(handle : @core.Any) -> @app.Theme {
  handle.cast()
}

///|
#export_name("mmmThemeToggle")
pub fn mmm_theme_toggle(theme : @core.Any) -> Unit {
  theme_of(theme).toggle()
}

///|
#export_name("mmmThemeIsLight")
pub fn mmm_theme_is_light(theme : @core.Any) -> Bool {
  theme_of(theme).is_light()
}

///|
#export_name("mmmThemePickColor")
pub fn mmm_theme_pick_color(theme : @core.Any) -> Unit {
  theme_of(theme).pick_color()
}

///|
/// 未保存かどうかが変わった。タブの印を描き直す
#export_name("mmmThemeSetDirty")
pub fn mmm_theme_set_dirty(theme : @core.Any, dirty : Bool) -> Unit {
  theme_of(theme).set_dirty(dirty)
}

///|
/// ts の並び（字か `{ value, check? }`）を Part に
fn parts_of(v : @core.Any) -> Array[@app.Part] {
  @core.array_from(v).map(x => {
    if @core.typeof_(x) == "string" {
      @app.Text(x.cast())
    } else {
      let check = x._get("check")
      @app.Blank({
        value: x._get("value").cast(),
        check: if defined(check) {
          Some(value => str_opt(check._invoke([@core.any(value)])))
        } else {
          None
        },
      })
    }
  })
}

///|
/// ts のたずね（title / note? / ok / cancel? / parts? / preview?）を Ask に
fn ask_of(v : @core.Any) -> @app.Ask {
  let parts = v._get("parts")
  @app.ask_of(
    v._get("title").cast(),
    v._get("ok").cast(),
    note=str_opt(v._get("note")),
    cancel=str_opt(v._get("cancel")),
    parts=if defined(parts) { parts_of(parts) } else { [] },
    preview=str_opt(v._get("preview")),
  )
}

///|
/// 名前で引くたずね。args は名前ごと（connect / rename は字、imageName は { shape, shot }）
fn named_ask(kind : String, args : @core.Any) -> @app.Ask {
  match kind {
    "discard" => @app.discard()
    "place" => @app.place()
    "connect" => @app.connect(args.cast())
    "rename" => @app.rename(args.cast())
    "imageName" =>
      @app.image_name(parts_of(args._get("shape")), args._get("shot").cast())
    _ => abort("知らないたずね: " + kind)
  }
}

///|
/// 欄の値の並び（断りは null）を続きに
fn answer(k : (@core.Any) -> Unit) -> (Array[String]?) -> Unit {
  out => {
    k(
      match out {
        Some(values) => @core.any(values)
        None => @core.null()
      },
    )
  }
}

///|
/// たずねる。続きには欄の値の並び（断られたら null）
#export_name("mmmAsk")
pub fn mmm_ask(a : @core.Any, k : (@core.Any) -> Unit) -> Unit {
  @app.ask(@dom.document(), ask_of(a), answer(k))
}

///|
/// 名前で引くたずね
#export_name("mmmAskNamed")
pub fn mmm_ask_named(
  kind : String,
  args : @core.Any,
  k : (@core.Any) -> Unit,
) -> Unit {
  @app.ask(@dom.document(), named_ask(kind, args), answer(k))
}

///|
/// たずねの中身（form）だけ（並べて見るため）
#export_name("mmmAskForm")
pub fn mmm_ask_form(kind : String, args : @core.Any) -> @dom.Element {
  @app.ask_form(@dom.document(), named_ask(kind, args), () => ()).0
}

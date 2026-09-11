// browser への出口 — **本番（src/）が呼ぶ面。** 中身は持たない（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
//
// 木も箱も core から出ない。境界は数・文字列・真偽・持ち手（MoonBit の値を
// そのまま JS へ渡し、そのまま受け取る）だけ — 読みも選択もその位置も持ち手で往復する。
//
// アプリそのものは `mmmMain` が組む（app/app.mbt）。ts に残るのは CodeMirror（md ペイン）で、
// その読み書きを閉包で渡す。それ以外はここに無い — 見本（lab）と試験（test）と build が
// 呼ぶ面は lab.mbt（同じ package、同じ出口の綴り）。
//
// 境界の糊（JS の値 ↔ MoonBit の値）は冒頭の 1 塊。lab.mbt も同じ糊を使う

// ---- 糊 ----

///|
fn read(handle : @core.Any) -> @read.Survey {
  handle.cast()
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
/// 頭の `image-folder:` が `base` から引っ越したなら、本文の画像を追従させる
/// 編集の列（**順に当てる**）。動いていなければ空。
///
/// `base` は**打ち替えを始めた時の md**。1 打鍵前を基準にすると、途中で通る
/// `./` が md の下の相対パスを全部掴む（#57）。ts はこれを打鍵と同じ
/// トランザクションに足すので、Undo は 1 手のまま
#export_name("mmmFollowDeclaration")
pub fn mmm_follow_declaration(
  base : String,
  now : String,
) -> Array[Array[@tree.Edit]] {
  @read.follow_declaration(base, now)
}

///|
/// 2 つの md が同じ頭を持つか。追従の基準をいつ捨てるかを決める（state.ts の `base`）
#export_name("mmmSameHead")
pub fn mmm_same_head(a : String, b : String) -> Bool {
  @read.same_head(a, b)
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

// ---- アプリ ----
//
// 束ねる場所（app/app.mbt）。ts が渡すのは CodeMirror の読み書き（`Editor`）だけ。
// 編集列は素の object（`{ from, to, insert }`）の並びで渡る

///|
fn editor_of(e : @core.Any) -> @app.Editor {
  let call = (name : String, args : Array[@core.Any]) => e._call(name, args)
  // 打鍵ごとに何千回も呼ぶものは、関数そのものを取って直に呼ぶ
  let tokens : (Array[String], String) -> Array[Array[@mindmap.Token]] = e
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
    @app.App::new(
      @dom.document(),
      editor_of(editor),
      @disk.Disk::new(@disk.Recent::new(@disk.idb_store())),
    ),
  )
}

///|
fn app_of(handle : @core.Any) -> @app.App {
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

///|
/// 空のときの言い出し（"md" / "map"）。md ペインは ts（editor.ts）がこれを浮かべる
#export_name("mmmPaneHint")
pub fn mmm_pane_hint(pane : String) -> @dom.Element {
  @parts.pane_hint(
    @dom.document(),
    match pane {
      "md" => Md
      "map" => Map
      _ => abort("知らないペイン: " + pane)
    },
  )
}

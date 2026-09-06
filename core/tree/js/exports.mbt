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
/// 読み（mmmSurvey の持ち手）を置く。`measure` は ts の canvas（Font, 字 → 幅）。返るのは Layout の持ち手 —
/// 箱は出さない。読むには下の問い合わせを使う
#export_name("mmmLayout")
pub fn mmm_layout(
  survey : @core.Any,
  measure : (@map.Font, String) -> Double,
) -> @core.Any {
  @core.any(@map.layout(read(survey).view.roots, @map.node_size(measure)))
}

///|
fn lay(handle : @core.Any) -> @map.Layout {
  handle.cast()
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
fn selection(ids : FixedArray[Int], anchor : Int?) -> @map.Selection {
  { ids: ints(ids), anchor, }
}

///|
fn cam(k : Double, tx : Double, ty : Double) -> @map.Camera {
  { k, tx, ty, }
}

///|
fn triple(c : @map.Camera) -> FixedArray[Double] {
  [c.k, c.tx, c.ty]
}

///|
fn quad(r : @map.Rect) -> FixedArray[Double] {
  [r.x, r.y, r.w, r.h]
}

///|
fn[T : ToJson] json(v : T) -> String {
  ToJson::to_json(v).stringify()
}

///|
/// 在る箱の矩形（world）。無い id は飛ばす
fn rects_of(l : @map.Layout, ids : Array[Int]) -> Array[@map.Rect] {
  let out = []
  for id in ids {
    match l.boxes.get(id) {
      Some(b) => out.push(b.rect())
      None => ()
    }
  }
  out
}

///|
fn all_rects(l : @map.Layout) -> Array[@map.Rect] {
  rects_of(l, l.order)
}

// ---- 箱の問い合わせ ----

///|
/// world の点がどの箱に居るか。grab は ⋯ の Easy grab
#export_name("mmmHit")
pub fn mmm_hit(layout : @core.Any, x : Double, y : Double, grab : Bool) -> Int? {
  @map.hit(lay(layout), x, y, if grab { @map.grab } else { @map.exact })
}

///|
/// 在る箱の矩形（world）。輪・落とし先の線・書き出しの範囲
#export_name("mmmRects")
pub fn mmm_rects(
  layout : @core.Any,
  ids : FixedArray[Int],
) -> FixedArray[FixedArray[Double]] {
  FixedArray::from_array(rects_of(lay(layout), ints(ids)).map(quad))
}

///|
/// 描くノードの id、文書順（= 重なり順）
#export_name("mmmOrder")
pub fn mmm_order(layout : @core.Any) -> FixedArray[Int] {
  fixed(lay(layout).order)
}

///|
/// そのノードの字（Implicit は ""）。箱が無ければ undefined
#export_name("mmmLabel")
pub fn mmm_label(layout : @core.Any, id : Int) -> String? {
  lay(layout).boxes.get(id).map(b => @map.label_of(b.node))
}

///|
/// その中身（ブロック id）の矩形（world）。持ち主が畳まれていれば undefined
#export_name("mmmCardRect")
pub fn mmm_card_rect(layout : @core.Any, block : Int) -> FixedArray[Double]? {
  guard @map.owner_of(lay(layout), block) is Some((b, i)) else { return None }
  guard @map.card_rect(b, i) is Some(r) else { return None }
  Some([b.x + r.x, b.y + r.y, r.w, r.h])
}

///|
/// `data-card` の「ノードの id, 何枚目」から中身の id
#export_name("mmmBlockAt")
pub fn mmm_block_at(layout : @core.Any, node : Int, index : Int) -> Int? {
  guard lay(layout).boxes.get(node) is Some(b) else { return None }
  b.node.blocks.get(index).map(blk => blk.id)
}

///|
/// 選んだものとその子孫（文書順）。落とし先から外す部分木
#export_name("mmmSubtree")
pub fn mmm_subtree(
  layout : @core.Any,
  ids : FixedArray[Int],
) -> FixedArray[Int] {
  let l = lay(layout)
  let set : Set[Int] = Set::from_array(ints(ids))
  // order は親が子より先なので、前から 1 回なめれば「親が部分木に居るか」で決まる
  for id in l.order {
    guard l.boxes.get(id) is Some(b) else { continue }
    if b.parent is Some(p) && set.contains(p.id) {
      set.add(id)
    }
  }
  fixed(l.order.filter(id => set.contains(id)))
}

// ---- 選択 ----

///|
/// 選ぶ。mod は 0 = 素 / 1 = Shift / 2 = Mod。返るのは Selection の JSON
#export_name("mmmClick")
pub fn mmm_click(
  layout : @core.Any,
  ids : FixedArray[Int],
  anchor : Int?,
  id : Int,
  mod : Int,
) -> String {
  let m : @map.Modifier = match mod {
    1 => Shift
    2 => Mod
    _ => Plain
  }
  json(@map.click(selection(ids, anchor), id, m, lay(layout).order))
}

///|
/// 矩形（world）に触れる箱を全部。Selection の JSON
#export_name("mmmRubber")
pub fn mmm_rubber(
  layout : @core.Any,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> String {
  json(@map.rubber(lay(layout), { x, y, w, h, }))
}

///|
/// キー 1 回ぶん。Intent の JSON。拾わなければ ""
#export_name("mmmKeyed")
pub fn mmm_keyed(
  layout : @core.Any,
  ids : FixedArray[Int],
  anchor : Int?,
  key : String,
  shift : Bool,
  mod : Bool,
  alt : Bool,
) -> String {
  match
    @map.keyed(lay(layout), selection(ids, anchor), { key, shift, mod, alt, }) {
    Some(i) => json(i)
    None => ""
  }
}

///|
/// カードを選んでいるときのキー。Intent の JSON。拾わなければ ""
#export_name("mmmKeyedCard")
pub fn mmm_keyed_card(
  layout : @core.Any,
  picked : Int,
  key : String,
  shift : Bool,
  mod : Bool,
  alt : Bool,
) -> String {
  match @map.keyed_card(lay(layout), picked, { key, shift, mod, alt, }) {
    Some(i) => json(i)
    None => ""
  }
}

///|
/// 右クリックの行。Entry の列の JSON
#export_name("mmmContext")
pub fn mmm_context(
  layout : @core.Any,
  ids : FixedArray[Int],
  anchor : Int?,
) -> String {
  json(@map.items(lay(layout), selection(ids, anchor)))
}

// ---- 落とし先 ----

///|
/// どこへ落とすか。Drop の JSON。無ければ ""
#export_name("mmmDrop")
pub fn mmm_drop(
  layout : @core.Any,
  x : Double,
  y : Double,
  dragging : FixedArray[Int],
) -> String {
  match @map.resolve(lay(layout), { x, y, }, ints(dragging)) {
    Some(d) => json(d)
    None => ""
  }
}

///|
/// 落とし先を Op に。返るのは Op の JSON（mmmEdit にそのまま渡せる）
#export_name("mmmDropOp")
pub fn mmm_drop_op(drop : String, ids : FixedArray[Int]) -> String {
  let d : @map.Drop = @json.from_json(@json.parse(drop)) catch {
    e => abort("mmmDropOp: Drop の JSON が読めない — \{e}")
  }
  json(@map.drop_op(d, ints(ids)))
}

// ---- 視点 ----

///|
#export_name("mmmToWorld")
pub fn mmm_to_world(
  k : Double,
  tx : Double,
  ty : Double,
  x : Double,
  y : Double,
) -> FixedArray[Double] {
  let p = @map.to_world(cam(k, tx, ty), x, y)
  [p.x, p.y]
}

///|
#export_name("mmmZoomAt")
pub fn mmm_zoom_at(
  k : Double,
  tx : Double,
  ty : Double,
  x : Double,
  y : Double,
  delta_y : Double,
) -> FixedArray[Double] {
  triple(@map.zoom_at(cam(k, tx, ty), x, y, delta_y))
}

///|
#export_name("mmmPanBy")
pub fn mmm_pan_by(
  k : Double,
  tx : Double,
  ty : Double,
  dx : Double,
  dy : Double,
) -> FixedArray[Double] {
  triple(@map.pan_by(cam(k, tx, ty), dx, dy))
}

///|
/// 2 本指の前後（from a, from b, to a, to b）から見え方を 1 つ
#export_name("mmmPinch")
pub fn mmm_pinch(
  k : Double,
  tx : Double,
  ty : Double,
  from : FixedArray[Double],
  to : FixedArray[Double],
) -> FixedArray[Double] {
  let span = (p : FixedArray[Double]) => {
    ({ a: { x: p[0], y: p[1], }, b: { x: p[2], y: p[3], }, } : @map.Span)
  }
  triple(@map.pinch(cam(k, tx, ty), span(from), span(to)))
}

///|
/// 全部が入る見え方。箱が無ければ undefined
#export_name("mmmFit")
pub fn mmm_fit(
  layout : @core.Any,
  width : Double,
  height : Double,
  margin : Double,
) -> FixedArray[Double]? {
  @map.fit(all_rects(lay(layout)), { width, height, }, margin).map(triple)
}

///|
/// 選択（無ければ根）を画面の中心へ。拡大率は変えない。どちらも無ければ undefined
#export_name("mmmCenter")
pub fn mmm_center(
  layout : @core.Any,
  ids : FixedArray[Int],
  k : Double,
  tx : Double,
  ty : Double,
  width : Double,
  height : Double,
) -> FixedArray[Double]? {
  let l = lay(layout)
  let target = match @map.union(rects_of(l, ints(ids))) {
    Some(r) => Some(r)
    None => @map.root_box(l).map(b => b.rect())
  }
  target.map(r => triple(@map.center_on(cam(k, tx, ty), r, { width, height, })))
}

///|
/// その箱が画面に入るまでだけ寄せる。箱が無ければ undefined
#export_name("mmmShow")
pub fn mmm_show(
  layout : @core.Any,
  id : Int,
  k : Double,
  tx : Double,
  ty : Double,
  width : Double,
  height : Double,
  margin : Double,
) -> FixedArray[Double]? {
  lay(layout).boxes
  .get(id)
  .map(b => {
    triple(
      @map.pan_to_show(cam(k, tx, ty), b.rect(), { width, height, }, margin),
    )
  })
}

///|
/// 見失った選択（無ければ根）を指す針（x, y, 角度）。見失っていなければ undefined
#export_name("mmmIndicator")
pub fn mmm_indicator(
  layout : @core.Any,
  ids : FixedArray[Int],
  k : Double,
  tx : Double,
  ty : Double,
  width : Double,
  height : Double,
) -> FixedArray[Double]? {
  let l = lay(layout)
  let c = cam(k, tx, ty)
  let pane : @map.Pane = { width, height, }
  let sel = rects_of(l, ints(ids))
  // 見失ったかは、選択があれば選択の話。無ければ文書の話
  let watched = if sel.length() > 0 { sel } else { all_rects(l) }
  guard @map.is_lost(watched, c, pane) else { return None }
  // 指す先は、選択ならいちばん近いやつ。無ければ根 — 帰る場所は 1 つでいい
  let target = if sel.length() > 0 {
    @map.nearest(sel, c, pane)
  } else {
    @map.root_box(l).map(b => b.rect())
  }
  target.map(r => {
    let i = @map.indicator_for(r, c, pane)
    [i.x, i.y, i.angle]
  })
}

// ---- 欄の重ね ----

///|
/// 欄の style に入れる数（left, top, width, height, fontSize, padding, border, lineHeight）。
/// ts は数を入れるだけで、数えない
fn place(
  p : @map.Placement,
  border : Double,
  line_height : Double,
) -> FixedArray[Double] {
  [
    p.left,
    p.top,
    p.width,
    p.height,
    p.font_size,
    p.padding,
    border,
    line_height,
  ]
}

///|
/// ラベルの欄をノードの箱に重ねる。`text` は欄のいまの字（幅は measure で測る）。
/// 箱が無ければ undefined
#export_name("mmmLabelPlace")
pub fn mmm_label_place(
  layout : @core.Any,
  id : Int,
  k : Double,
  tx : Double,
  ty : Double,
  text : String,
  measure : (@map.Font, String) -> Double,
) -> FixedArray[Double]? {
  lay(layout).boxes
  .get(id)
  .map(b => {
    let w = measure(@map.label_font(@map.row_of(b.node)), text)
    place(@map.label_place(b, cam(k, tx, ty), w), @map.label_border, 0)
  })
}

///|
/// カードの欄をその中身の矩形に重ねる。`text` は欄のいまの字（行に割り、いちばん広い行を
/// コードの字で測る）。持ち主が畳まれていれば undefined
#export_name("mmmCardPlace")
pub fn mmm_card_place(
  layout : @core.Any,
  block : Int,
  k : Double,
  tx : Double,
  ty : Double,
  text : String,
  measure : (@map.Font, String) -> Double,
) -> FixedArray[Double]? {
  mmm_card_rect(layout, block).map(r => {
    let (x, y, w, h) = (r[0], r[1], r[2], r[3])
    let lines = text.split("\n").map(l => l.to_owned()).collect()
    let font : @map.Font = { px: @map.card_font_px.to_int(), mono: true, }
    let mut widest = 0.0
    for l in lines {
      widest = @cmp.maximum(widest, measure(font, l))
    }
    place(
      @map.card_place({ x, y, w, h, }, cam(k, tx, ty), lines.length(), widest),
      @map.card_border,
      @map.code_line * k,
    )
  })
}

// ---- 指 ----

///|
#export_name("mmmFingers")
pub fn mmm_fingers() -> @core.Any {
  @core.any(@map.Fingers::new())
}

///|
fn fingers(handle : @core.Any) -> @map.Fingers {
  handle.cast()
}

///|
#export_name("mmmFingerDown")
pub fn mmm_finger_down(
  handle : @core.Any,
  id : Int,
  x : Double,
  y : Double,
) -> Unit {
  fingers(handle).down(id, x, y)
}

///|
/// 組の片方が動いたときだけ、前後（from a, from b, to a, to b）。他は undefined
#export_name("mmmFingerMoved")
pub fn mmm_finger_moved(
  handle : @core.Any,
  id : Int,
  x : Double,
  y : Double,
) -> FixedArray[Double]? {
  fingers(handle)
  .moved(id, x, y)
  .map(g => {
    let (from, to) = g
    [from.a.x, from.a.y, from.b.x, from.b.y, to.a.x, to.a.y, to.b.x, to.b.y]
  })
}

///|
#export_name("mmmFingerUp")
pub fn mmm_finger_up(handle : @core.Any, id : Int) -> Unit {
  fingers(handle).up(id)
}

///|
/// ちょうど 1 本だけなら、その「いま」の位置
#export_name("mmmFingerOnly")
pub fn mmm_finger_only(handle : @core.Any) -> FixedArray[Double]? {
  fingers(handle).only().map(p => [p.x, p.y])
}

///|
#export_name("mmmPinching")
pub fn mmm_pinching(handle : @core.Any) -> Bool {
  fingers(handle).pinching()
}

// ---- 描画 ----

///|
/// 描き手。`handle` を mmmDraw / mmmPaint / mmmNodeEl に渡す。
/// `edgeLayer` / `nodeLayer` は ts が world の <g> に並べる
#export_name("mmmRenderer")
pub fn mmm_renderer() -> @core.Any {
  let r = @render.Renderer::new(@dom.document())
  let o = @core.new_object()
  o._set("handle", @core.any(r))
  o._set("edgeLayer", r.edge_layer.as_any())
  o._set("nodeLayer", r.node_layer.as_any())
  o
}

///|
/// 場面を DOM に写す。`image_url` は path → objectURL（無ければ null）、
/// `image_hint` は場所取りに添える字（無ければ null）、`tokens` はコードの色分け
/// （行, 言語 → 行ごとの {text, cls}）、`epoch` は言語の読み込みの世代
#export_name("mmmDraw")
pub fn mmm_draw(
  handle : @core.Any,
  layout : @core.Any,
  measure : (@map.Font, String) -> Double,
  image_url : (String) -> @core.Any,
  image_hint : @core.Any,
  tokens : (Array[String], String) -> Array[Array[@render.Token]],
  epoch : Int,
) -> Unit {
  let r : @render.Renderer = handle.cast()
  let scene : @render.Scene = {
    layout: lay(layout),
    measure,
    image_url: p => @core.identity_option(image_url(p)),
    image_hint: @core.identity_option(image_hint),
    tokens,
    epoch,
  }
  r.draw(scene)
}

///|
/// 選ばれた箱に印を付ける（変わった箱だけ触る）
#export_name("mmmPaint")
pub fn mmm_paint(handle : @core.Any, ids : FixedArray[Int]) -> Unit {
  let r : @render.Renderer = handle.cast()
  r.paint(ints(ids))
}

///|
/// そのノードの <g>。無ければ null
#export_name("mmmNodeEl")
pub fn mmm_node_el(handle : @core.Any, id : Int) -> @core.Any {
  let r : @render.Renderer = handle.cast()
  @core.from_option(r.node_el(id))
}

///|
/// そのノードへの線の <path>。無ければ null
#export_name("mmmEdgeEl")
pub fn mmm_edge_el(handle : @core.Any, id : Int) -> @core.Any {
  let r : @render.Renderer = handle.cast()
  @core.from_option(r.edge_el(id))
}

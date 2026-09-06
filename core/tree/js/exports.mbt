// core を browser から使うための薄い層。**中身は持たない**（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
//
// データは JSON で渡し（ts の coreApi が形を確かめる）、MoonBit の値
// （View / Layout / Renderer）は不透明な持ち手としてそのまま JS へ渡して、
// そのまま受け取る — JSON を 2 度組まない、2 度 parse しない。
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
/// 打鍵 1 回ぶんの読み。`json` が View と地番（読みは打鍵ごとに 1 回に保つ）、
/// `view` が View の持ち手（`mmmLayout` に渡す）。
/// 選択の持ち越しは core に無い — 位置は ts が CodeMirror に預けて写す。
#export_name("mmmSurvey")
pub fn mmm_survey(md : String) -> @core.Any {
  let (doc, spots) = @tree.survey(md)
  let view = @view.project(doc)
  let out : Survey = { view, spots, }
  let o = @core.new_object()
  o._set("json", @core.any(ToJson::to_json(out).stringify()))
  o._set("view", @core.any(view))
  o
}

///|
/// mmmSurvey の JSON の形
priv struct Survey {
  view : @view.View
  spots : Map[Int, @tree.Spot]
} derive(ToJson)

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

// ---- map ----

///|
/// 寸法のうち、ts の入力側（drop の帯・label / card の欄）が読むもの。
/// 起動時に 1 度。数字を ts に書かないための出口
#export_name("mmmMetrics")
pub fn mmm_metrics() -> String {
  let j : Json = {
    "gap": @map.gap.to_json(),
    "row": { "normal": @map.normal.to_json(), "hidden": @map.hidden.to_json() },
    "codeLine": @map.code_line.to_json(),
  }
  j.stringify()
}

///|
/// View を置く。`measure` は ts の canvas（Font, 字 → 幅）。
/// `json` が ts の入力側が読む数（箱とカードの矩形）、`layout` が Layout の持ち手（`mmmDraw` に渡す）
#export_name("mmmLayout")
pub fn mmm_layout(
  view : @core.Any,
  measure : (@map.Font, String) -> Double,
) -> @core.Any {
  let v : @view.View = view.cast()
  let l = @map.layout(v.roots, @map.node_size(measure))
  let o = @core.new_object()
  o._set("json", @core.any(layout_json(l)))
  o._set("layout", @core.any(l))
  o
}

///|
/// mmmLayout の JSON の 1 箱。`cards` は行ごとの中身の矩形（箱の左上から）—
/// ts は矩形を読むだけで、積み方を知らない。node は無い（ts が View の id から引く）
priv struct BoxOut {
  id : Int
  parent : @map.Edge?
  buried : Int
  x : Double
  y : Double
  w : Double
  h : Double
  cards : Array[@map.Rect]
} derive(ToJson)

///|
priv struct LayoutOut {
  order : Array[Int]
  boxes : Array[BoxOut]
} derive(ToJson)

///|
fn layout_json(l : @map.Layout) -> String {
  let boxes = []
  for id in l.order {
    guard l.boxes.get(id) is Some(b) else { continue }
    let cards = []
    for i, _ in b.cards {
      match @map.card_rect(b, i) {
        Some(r) => cards.push(r)
        None => ()
      }
    }
    boxes.push({
      id,
      parent: b.parent,
      buried: b.buried,
      x: b.x,
      y: b.y,
      w: b.w,
      h: b.h,
      cards,
    })
  }
  let out : LayoutOut = { order: l.order, boxes, }
  ToJson::to_json(out).stringify()
}

// ---- render ----

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
    layout: layout.cast(),
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
pub fn mmm_paint(handle : @core.Any, ids : Array[Int]) -> Unit {
  let r : @render.Renderer = handle.cast()
  r.paint(ids)
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

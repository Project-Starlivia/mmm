// mmmTree を browser から見るための薄い層。**中身は持たない**（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
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
/// 打鍵 1 回ぶんの読み。View と地番と、前のサイクルの目印がいまどのノードかを
/// **1 度の parse で**返す（読みは打鍵ごとに 1 回に保つ）。edits は反映の Edit の形
/// （前の座標、from 順）、marks は前のサイクルの地番から ts が抜いた目印。
/// 壊れた JSON は ts の側のバグなので、静かに断らず投げる。
#export_name("mmmSurvey")
pub fn mmm_survey(md : String, edits : String, marks : String) -> String {
  let edits : Array[@tree.Edit] = try @json.from_json(@json.parse(edits)) catch {
    e => abort("mmmSurvey: edits の JSON が読めない — \{e}")
  }
  let marks : Array[@tree.Mark] = try @json.from_json(@json.parse(marks)) catch {
    e => abort("mmmSurvey: marks の JSON が読めない — \{e}")
  }
  let (doc, spots) = @tree.survey(md)
  let out : Survey = {
    view: @view.project(doc),
    spots,
    // Trail? のまま並べると、MoonBit の ToJson は Some を配列 1 つに包んでしまい
    // （builtin の Option::to_json）、ts の Trail | null と形が揃わない。
    // ここで当たり/外れを素の object / null に均す
    trails: @tree.follow(spots, edits, marks).map(t => match t {
      Some(x) => ToJson::to_json(x)
      None => Json::null()
    }),
  }
  ToJson::to_json(out).stringify()
}

///|
/// mmmSurvey の返り値の形。JSON にするためだけの器
priv struct Survey {
  view : @view.View
  spots : Map[Int, @tree.Spot]
  trails : Array[Json]
} derive(ToJson)

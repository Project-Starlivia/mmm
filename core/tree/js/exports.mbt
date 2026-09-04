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
/// 地番の指紋。`id[from,to]`。
#export_name("mmmSpansSig")
pub fn mmm_spans_sig(md : String) -> String {
  @tree.spans_sig(md)
}

///|
/// 反映の試し。id のノードを how（relabel / delete / adopt）で変え、
/// 編集列と当てた後の md を出す。知らない how は空。
#export_name("mmmTrial")
pub fn mmm_trial(md : String, id : Int, how : String) -> String {
  match @tree.change_of(how) {
    Some(c) => @tree.trial(md, id, c).to_json().stringify()
    None => ""
  }
}

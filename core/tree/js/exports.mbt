// mmmTree を browser から見るための薄い層。**中身は持たない**（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
//
// 出しているのは見るための 3 本だけ。どの段で壊れたかを切り分けるために、
// mdAst と mmmTree を並べて出す。

///|
/// md をライブラリがどう読んだか（ブロックの種類と原文の範囲）。
#export_name("mdAstSig")
pub fn md_ast_sig(md : String) -> String {
  @tree.md_ast_sig(md)
}

///|
/// mmmTree を 1 行にしたもの。
#export_name("mmmTreeSig")
pub fn mmm_tree_sig(md : String) -> String {
  @tree.sig(@tree.parse(md))
}

///|
/// mmmTree ぜんぶ。畳んで探るのはこちら。
#export_name("mmmTreeJson")
pub fn mmm_tree_json(md : String) -> String {
  @tree.json(@tree.parse(md))
}

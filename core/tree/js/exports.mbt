// 木を browser から見るための薄い層。**中身は持たない**（持つと、
// 試験できる本体と、試験できないここで規則が二重になる）。
//
// 出しているのは見るための 3 本だけ。どの段で壊れたかを切り分けるために、
// AST の指紋と木を並べて出す。

///|
/// md をライブラリがどう読んだか（ブロックの種類と原文の範囲）。
#export_name("astSig")
pub fn ast_sig(md : String) -> String {
  @tree.ast_sig(md)
}

///|
/// 木を 1 行にしたもの。
#export_name("treeSig")
pub fn tree_sig(md : String) -> String {
  @tree.sig(@tree.parse(md))
}

///|
/// 木ぜんぶ。畳んで探るのはこちら。
#export_name("treeJson")
pub fn tree_json(md : String) -> String {
  @tree.json(@tree.parse(md))
}

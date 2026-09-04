// 木への操作。Doc を Doc にする純粋な関数の、入力の形。
//
// 席は隣の id で言い、添字は持たない（DOM の before / after / append と同じ形）。
// ノードの列と中身の列は交わらないので型を分け、同じ文法を使っていることは
// 型名が言う。構築子が位置を、ラベルが相手を言う。

///|
/// ノードの席。子の列の中。
pub(all) enum NodePlace {
  Before(node~ : Int)
  After(node~ : Int)
  /// 子の列の末尾。side は node が根のときだけ意味を持つ。
  /// node が doc_id なら新しい根
  In(node~ : Int, side~ : @tree.Side?)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 中身の席。body の列の中。
pub(all) enum BlockPlace {
  Before(block~ : Int)
  After(block~ : Int)
  /// body の末尾。node が doc_id なら文書の散文
  In(node~ : Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 操作。1 つの値が 1 回の操作で、apply が木に当てる。
pub(all) enum Op {
  AddNode(at~ : NodePlace, labels~ : Array[String])
  AddBlock(at~ : BlockPlace, content~ : @tree.Content)
  Rename(id~ : Int, label~ : String)
  SetBlock(id~ : Int, content~ : @tree.Content)
  MoveNode(ids~ : Array[Int], at~ : NodePlace)
  MoveBlock(ids~ : Array[Int], at~ : BlockPlace)
  /// ノードも中身も。席を取らないので 1 つ
  Delete(ids~ : Array[Int])
  Wrap(id~ : Int, label~ : String)
  FlipSide(id~ : Int)
  Fold(id~ : Int, open~ : Bool)
  Unfold(id~ : Int)
  Graft(at~ : NodePlace, md~ : String)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 操作後の木と、そこで選ぶべき id（消した後は None）。
pub(all) struct Done {
  doc : @tree.Doc
  focus : Int?
} derive(Eq, Debug, ToJson)

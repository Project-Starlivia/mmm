// map が見る木。Doc と同じ意味を、描くのに要る形だけで持つ。
//
// Doc が 3 種に分けているノード（見出し・項目・Implicit）は、md の書き方の
// 制約で分かれているだけで、描く側には 1 つも要らない。ここでは 1 つの
// struct に潰し、Implicit は「ラベルが無い」で言う。

///|
/// 木 1 本。側は Doc の Root と同じく根の子と並走する。
pub(all) struct Tree {
  node : Node
  sides : Array[@tree.Side]
} derive(Eq, Debug, ToJson)

///|
/// ノード 1 つ。種類は無い。
pub(all) struct Node {
  id : Int
  /// Implicit だけ None。空の見出し（`## `）は Some("")
  label : String?
  fold : @tree.Fold?
  /// 中身のうち、mmm が読み解いたもの。Opaque だけがここに来ない
  blocks : Array[@tree.Block]
  children : Array[Node]
} derive(Eq, Debug, ToJson)

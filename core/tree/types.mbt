// mmm の木。md と同じ意味を、md と違う形で持つ。
//
// 役割ごとに型を分ける。根だけが翼を持ち、翼だけが側を持ち、枝は一様に
// 枝分かれする。こうすると「深いノードの側」や「側があるのに綴りが無い」
// といった、あり得ない状態が型ごと消える。

///|
/// 文書ぜんぶ。木は何本でも生える（`# a` と `# b` は別の木）。
pub(all) struct Doc {
  /// 封筒（frontmatter）の逐語。無ければ None
  frontmatter : String?
  eol : Eol
  /// 最初の骨格より前の散文
  body : Array[Block]
  roots : Array[Root]
}

///|
/// 木 1 本の根。**翼を持つ唯一の型**。
pub(all) struct Root {
  id : Int
  node : Node
  wings : Array[Wing]
}

///|
/// 左右に伸びるもの。**側はここにしか無い**（占有者ではなく場所の属性）。
/// id を持たないのは、翼を指すときは占有者の id で足りるから。
pub(all) struct Wing {
  side : Side
  branch : Branch
}

///|
/// 枝分かれするもの。深さ 3 以降は一様。
pub(all) struct Branch {
  id : Int
  node : Node
  children : Array[Branch]
}

///|
/// ノードの中身そのもの。
pub(all) enum Node {
  /// 骨格行が無い。階層の飛びが綴り。ラベルも本文も型ごと持たない
  Implicit
  Explicit(sign~ : Sign, label~ : String, folded~ : Bool, body~ : Array[Block])
}

///|
/// 骨格の記述方式。Implicit を入れないのは、これが「何に変えるか」の引数型だから。
pub(all) enum Sign {
  Heading
  Item
} derive(Eq)

///|
pub(all) enum Side {
  Right
  Left
} derive(Eq)

///|
/// 原文の改行の流儀。保存して書き戻す。
pub(all) enum Eol {
  Lf
  Crlf
} derive(Eq)

///|
/// ノードにぶら下がる中身。
pub(all) enum Block {
  Content(Content)
  /// 飾りの水平線（`***`）。側のトグル（`---`）とはチャンネルが違う
  Rule
  /// 読み解かない逐語
  Opaque(String)
}

///|
/// 絵になる中身。ここに無いものは Opaque。
pub(all) enum Content {
  Image(alt~ : String, src~ : String)
  Link(text~ : String, href~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
}

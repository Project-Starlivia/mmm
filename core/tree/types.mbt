// mmm の木。md と同じ意味を、md と違う形で持つ。
//
// 節の種類ごとに型を分ける。**子に来られるものが親の種類で決まる**ので、
// 一様な木では「項目の子が見出し」のようなあり得ない状態を型で止められない。
// 分けることで、単調性・順序法則・根と翼の対応が構造から不可能になる。

///|
/// 文書ぜんぶ。木は何本でも生える（`# a` と `# b` は別の木）。
pub(all) struct Doc {
  /// 封筒（frontmatter）の逐語。無ければ None
  frontmatter : String?
  eol : Eol
  /// 最初の骨格より前の散文
  body : Array[Block]
  roots : Array[Root]
} derive(Eq, Debug, ToJson)

///|
/// 木 1 本の根。**翼を持つ唯一の型**。
/// 種類ごとに翼の中身が決まる — 項目の根に見出しは生えない。
pub(all) enum Root {
  Implicit(id~ : Int, headings~ : Array[Wing[Heading]])
  Explicit(
    node~ : Node,
    items~ : Array[Wing[Item]],
    headings~ : Array[Wing[Heading]]
  )
  Item(node~ : Node, items~ : Array[Wing[Item]])
} derive(Eq, Debug, ToJson)

///|
/// 左右に伸びるもの。**側はここにしか無い**（占有者ではなく場所の属性）。
/// id を持たないのは、翼を指すときは占有者の id で足りるから。
pub(all) struct Wing[T] {
  side : Side
  branch : T
} derive(Eq, Debug, ToJson)

///|
/// 見出し。綴られたものと、飛びで暗黙になったもの。
///
/// Implicit を別の型にしないのは、**飛びを作れるのが見出しだけ**だから
/// （項目は相対記法なので飛べない）。Implicit は綴られなかった見出しそのもの。
///
/// 項目の子を別の配列に出しているのは、**文書順で項目が必ず先**だから。
/// 1 本の配列だと操作が順序を壊せるが、分けてあれば壊せない。
pub(all) enum Heading {
  /// 骨格行が無い。id だけ。項目は付かない（項目は直近の綴られた見出しに付く）
  Implicit(id~ : Int, headings~ : Array[Heading])
  Explicit(node~ : Node, items~ : Array[Item], headings~ : Array[Heading])
} derive(Eq, Debug, ToJson)

///|
/// 項目。**子も項目**（単調性）。飛びが無いので Implicit も無い。
pub(all) struct Item {
  node : Node
  children : Array[Item]
} derive(Eq, Debug, ToJson)

///|
/// 綴られた節の中身。Implicit はこれを持たない。
pub(all) struct Node {
  id : Int
  label : String
  folded : Bool
  body : Array[Block]
} derive(Eq, Debug, ToJson)

///|
/// 骨格の記述方式。「何に変えるか」の引数型。
pub(all) enum Sign {
  Heading
  Item
} derive(Eq, Debug, ToJson)

///|
pub(all) enum Side {
  Right
  Left
} derive(Eq, Debug, ToJson)

///|
/// 原文の改行の流儀。保存して書き戻す。
pub(all) enum Eol {
  Lf
  Crlf
} derive(Eq, Debug, ToJson)

///|
/// ノードにぶら下がる中身。
pub(all) enum Block {
  Content(Content)
  /// 飾りの水平線（`***`）。側のトグル（`---`）とはチャンネルが違う
  Rule
  /// 読み解かない逐語
  Opaque(String)
} derive(Eq, Debug, ToJson)

///|
/// 絵になる中身。ここに無いものは Opaque。
pub(all) enum Content {
  Image(alt~ : String, src~ : String)
  Link(text~ : String, href~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
} derive(Eq, Debug, ToJson)

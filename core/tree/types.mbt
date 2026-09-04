// mmm の木。md と同じ意味を、md と違う形で持つ。
//
// md の裁定（何がどういう意味か）は docs/spec.md、内部の決めは docs/core.md。
//
// **型が言うのは「あり得ない形」だけ**で、仕様を満たすのは実装の仕事。
// 型で殺しているのは、項目の子孫が項目であること・Implicit が綴りを持たない
// こと・側が根の子にしか無いことの 3 つ。それ以外は実装とテストが受け持つ。

///|
/// 文書ぜんぶ。木は何本でも生える（`# a` と `# b` は別の木）。
pub(all) struct Doc {
  /// 封筒（frontmatter）の原文。無ければ None
  frontmatter : String?
  eol : Eol
  /// 最初の骨格より前の中身
  body : Array[Block]
  roots : Array[Root]
} derive(Eq, Debug, ToJson)

///|
/// 木 1 本。**側を持つ唯一の型**で、根の子と 1 対 1 に並ぶ。
/// 組にせず並走させているのは、`children` を全部の深さで `Array[Node]` の
/// まま保つため（深さで型が変わると走査も操作も割れる）。
/// 長さが揃うことは型では言えないので check が見る。
pub(all) struct Root {
  node : Node
  sides : Array[Side]
} derive(Eq, Debug, ToJson)

///|
/// ノード 1 つ。種類はこの 3 つしかない。
/// 構築子は型名と同じ — **タグ自体に意味は無く**、無名 union が書けないから
/// 置いているだけなので、別の語を作らない。
pub(all) enum Node {
  HeadingNode(HeadingNode)
  ListNode(ListNode)
  ImplicitNode(ImplicitNode)
} derive(Eq, Debug, ToJson)

///|
/// 畳み。**在ること自体が「このノードは畳まれている」**で、中身は書き戻すのに
/// 要る綴り。`<details>` と `</details>` は固定なので入らない。
pub(all) struct Fold {
  /// `<details open>` と書いてあった
  open : Bool
  /// `<summary>…</summary>` の中身。行が無ければ None
  /// （空文字と区別する — 無いものに空の行を生やすと触っていない場所が動く）
  summary : String?
} derive(Eq, Debug, ToJson)

///|
/// 見出し（`# a`）。子は何でも来る。
pub(all) struct HeadingNode {
  id : Int
  label : String
  /// `<details>` がこのノードの定義ごと包んでいた
  fold : Fold?
  body : Array[Block]
  children : Array[Node]
} derive(Eq, Debug, ToJson)

///|
/// 項目（`- a`）。**子も項目**（単調性）。相対記法なので飛びが無く、
/// 綴られない項目も存在しない。
pub(all) struct ListNode {
  id : Int
  label : String
  fold : Fold?
  body : Array[Block]
  children : Array[ListNode]
} derive(Eq, Debug, ToJson)

///|
/// 綴られなかった見出し。階層の飛びが綴りなので、**ラベルも中身も畳みも
/// 型ごと持たない**（包む骨格行が無いので畳めない）。
pub(all) struct ImplicitNode {
  id : Int
  children : Array[Node]
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
/// ノードにぶら下がる中身 1 枚。**id はノードと同じ列**（文書順の通し番号）。
/// ノードも中身も同じ番号で引き当てるので、操作も選択も型が割れない。
pub(all) struct Block {
  id : Int
  content : Content
} derive(Eq, Debug, ToJson)

///|
/// 中身そのもの。**解釈の包みは作らない** —
/// 「解釈できた / できなかった」は Opaque という名前が担う。
/// カードかどうかは描画側の分類で、core は意味だけを持つ。
pub(all) enum Content {
  Image(alt~ : String, src~ : String, title~ : String)
  Link(text~ : String, href~ : String, title~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
  /// 水平線。md の要素名そのまま
  ThematicBreak
  /// `<details>`。**中を読み解かない** — 触っていない畳みが正規形に落ちるのを
  /// 防ぐため、領域を原文のまま持つ。表示名は覗いて導出する
  Details(String)
  /// 読み解かない原文。コメントもここ
  Opaque(String)
} derive(Eq, Debug, ToJson)

// mmm の木。md と同じ意味を、md と違う形で持つ。
//
// md の裁定（何がどういう意味か）は docs/spec.md、内部の決めは docs/core.md。
//
// **型が言うのは「あり得ない形」だけ**で、仕様を満たすのは実装の仕事。
// **型が払うのは、走査から分岐が消えるときだけ。** 殺しているのは側が根の子にしか
// 無いことの 1 つで、それ以外は check とテストが受け持つ。

///|
/// 文書ぜんぶ。木は何本でも生える（`# a` と `# b` は別の木）。
pub(all) struct Doc {
  /// frontmatter の原文。無ければ None
  frontmatter : String?
  /// 最初の骨格より前の中身
  body : Array[Block]
  roots : Array[Root]
} derive(Eq, Debug, ToJson)

///|
/// derive が作る `to_json` を method 形（`x.to_json()`）で呼ぶための宣言。
/// **上流は「derive のメソッドが暗黙に昇格する挙動を将来やめる」と言っている**ので、
/// 昇格に頼らず明示する — 無いと呼び出し側に非推奨の印が出る（#68）
pub extend Doc with ToJson::{to_json}

///|
/// 木 1 本。**側を持つ唯一の型**で、根の子と 1 対 1 に並ぶ。
/// 組にせず並走させているのは、`children` を全部の深さで `Array[Node]` の
/// まま保つため（深さで型が変わると走査も操作も割れる）。
/// `sides` の長さが揃うことは型では言えないので check が見る。
pub(all) struct Root {
  node : Node
  sides : Array[Side]
  /// 側を変えた行の原文。`sides` と並走し、無い所は空。**書き戻すためだけの欄**で、
  /// 短くても足りない所は `---` になるだけなので check は見ない
  rules : Array[String]
} derive(Eq, Debug, ToJson)

///|
/// ノード 1 つ。**種類は無い** — 見出しと項目は意味の欄が同じで、違うのは
/// 綴り（`mark`）だけ。種類で型を割ると、種類を問わない操作（動かす・選ぶ・
/// 名を付ける・畳む）が全部そのぶん分岐する。
///
/// **項目の中は、その項目の深さを 0 とした文書**（docs/spec.md「項目の中」）なので、
/// 項目の子に見出しが生え、見出しの子に項目が生える。
pub(all) struct Node {
  id : Int
  label : String
  /// `<details>` がこのノードの定義ごと包んでいた
  fold : Fold?
  body : Array[Block]
  children : Array[Node]
  /// 読んだ綴り。**無ければ Implicit** — 行を省いた空の見出しで、記法が要るもの
  /// （名前・畳み・中身・見出しの直後の席）は綴ってから当てる。隣の行で決まる
  /// 規則なので、型ではなく check（`Unmarked`）が見る
  mark : Mark?
} derive(Eq, Debug, ToJson)

///|
/// 骨格の行の綴り。**種類はこれが持つ唯一の在り処。**
pub(all) enum Mark {
  /// 見出し（`# a`）。setext（`a` の次の行が `===`）は深さ 1〜2 でだけ書ける。
  /// closing は読んだ閉じの `#` の本数（`# a ##` なら 2）で、飾りなので 0 は付けない。
  /// 新しく作るときは ATX で閉じ無し
  Heading(setext~ : Bool, closing~ : Int)
  /// 項目（`- a`）。marker は読んだ字（`-` `*` `+`、または `3.` `3)` — 数字ごと）、
  /// offset は読んだラベルの桁（マーカーの頭からラベルの頭まで。中身と入れ子も
  /// この桁に座る）、loose は読んだ列が loose だった（項目の間に空行）。
  /// 新しく作るときは `-` / 2 / 詰める
  Item(marker~ : String, offset~ : Int, loose~ : Bool)
} derive(Eq, Debug, ToJson)

///|
/// 新しく作る見出しの綴り。読んだ書き方は持ち込まない。
pub let atx : Mark = Heading(setext=false, closing=0)

///|
/// 新しく作る項目の綴り。マーカーとラベルの桁は席が決め直す（`spell_at`）。
pub let bullet : Mark = Item(marker="-", offset=2, loose=false)

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
/// 綴りの種類。「何に変えるか」の引数型で、綴りそのもの（`Mark`）から
/// 書き方の欄を落としたもの。席が綴りを決め直すので、操作は種類だけを言う。
pub(all) enum Sign {
  Heading
  Item
} derive(Eq, Debug, ToJson)

///|
/// その綴りの種類。飛び（Implicit）は綴りが無いので None。
pub fn sign_of(n : Node) -> Sign? {
  match n.mark {
    Some(Heading(..)) => Some(Heading)
    Some(Item(..)) => Some(Item)
    None => None
  }
}

///|
pub(all) enum Side {
  Right
  Left
} derive(Eq, Debug, ToJson, FromJson)

///|
/// ノードにぶら下がる中身 1 枚。**id はノードと同じ列**（文書順の通し番号）。
/// ノードも中身も同じ番号で引き当てるので、操作も選択も型が割れない。
pub(all) struct Block {
  id : Int
  /// 読み解いた意味。**無ければ読み解いていない** — 散文・表・引用・コメントは
  /// みなここ。そのときは `source` が原文をそのまま持つ
  content : Content?
  /// 読んだ原文（字下げを剥いだ塊の字）。**書き戻しはこれを返す。** 操作が作った
  /// 中身は None で、そのときだけ意味から綴る。決めは
  /// docs/superpowers/specs/2026-09-06-verbatim-design.md
  ///
  /// **読んだ字はここ 1 か所。** 意味の側は原文を持たない（同じ字を 2 か所に
  /// 置くと、書き戻す側と読み直す側が食い違う）。意味も原文も無い中身は
  /// 書けないので check（`Wordless`）が言う
  source : String?
} derive(Eq, Debug, ToJson)

///|
/// 中身の意味。**読み解けたものだけ**で、読み解かなかったことは `Block.content`
/// の不在が言う（解釈の包みは作らない）。
/// カードかどうかは描画側の分類で、core は意味だけを持つ。
pub(all) enum Content {
  Image(alt~ : String, src~ : String, title~ : String)
  Link(text~ : String, href~ : String, title~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
  /// 水平線。md の要素名そのまま
  ThematicBreak
  /// `<details>`。**中を読み解かない** — 触っていない畳みが正規形に落ちるのを
  /// 防ぐため、書き戻しは `source` の原文だけを使う。
  /// open / summary / body は読み取り（GitHub が描くのと同じもの）で、導出はしない。
  /// body は開き（と summary）の後ろから閉じの手前までの原文
  Details(open~ : Bool, summary~ : String?, body~ : String)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// derive が作る `to_json` を method 形（`x.to_json()`）で呼ぶための宣言。
/// **上流は「derive のメソッドが暗黙に昇格する挙動を将来やめる」と言っている**ので、
/// 昇格に頼らず明示する — 無いと呼び出し側に非推奨の印が出る（#68）
pub extend Content with ToJson::{to_json}

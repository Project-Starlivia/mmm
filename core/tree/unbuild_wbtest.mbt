// mmmTree → md を固定する。**木は手で組む** — `parse` で作ると、書きの
// テスト全部が読みに依存する（往復・冪等は両側が揃ってからの別段）。
//
// 見ているのは serialize の文字列。字下げ・フェンス長・空行・エスケープの
// 流儀はライブラリのもので、ここで固定するのは「我々の骨格がどう綴られるか」。
// ライブラリの正規化（`_em_` → `*em*`、定義行の移動、setext → ATX）は
// **この段では素直に受ける**。補正するなら反映（差分更新）の段。

///|
fn doc(
  roots : Array[Root],
  body? : Array[Block] = [],
  frontmatter? : String? = None,
  eol? : Eol = Lf,
) -> Doc {
  { frontmatter, eol, body, roots }
}

///|
fn root(node : Node, sides? : Array[Side] = []) -> Root {
  { node, sides }
}

///|
/// id は書きに関係しないので 0 のまま。
fn h(
  label : String,
  children? : Array[Node] = [],
  body? : Array[Block] = [],
  fold? : Fold? = None,
) -> Node {
  HeadingNode({ id: 0, label, fold, body, children })
}

///|
fn li(
  label : String,
  children? : Array[ListNode] = [],
  body? : Array[Block] = [],
  fold? : Fold? = None,
) -> ListNode {
  { id: 0, label, fold, body, children }
}

///|
fn item(
  label : String,
  children? : Array[ListNode] = [],
  body? : Array[Block] = [],
  fold? : Fold? = None,
) -> Node {
  ListNode(li(label, children~, body~, fold~))
}

///|
fn gap(children : Array[Node]) -> Node {
  ImplicitNode({ id: 0, children })
}

// ══════════════════════════════════════════════════════════════════
// 骨格 — 深さは `#` の数、項目は入れ子、Implicit は深さだけ消費する
// ══════════════════════════════════════════════════════════════════

///|
test "見出しは深さぶんの #" {
  inspect(
    serialize(doc([root(h("root", children=[h("a"), h("b")]))])),
    content=(
      #|# root
      #|
      #|## a
      #|
      #|## b
      #|
    ),
  )
}

///|
/// 飛びは綴られない。深さだけが進む。
test "Implicit は何も書かず深さを消費する" {
  inspect(
    serialize(doc([root(h("root", children=[gap([h("x")])]))])),
    content=(
      #|# root
      #|
      #|### x
      #|
    ),
  )
}

///|
test "根の Implicit なら深さ 2 から始まる" {
  inspect(
    serialize(doc([root(gap([h("a"), h("b")]))])),
    content=(
      #|## a
      #|
      #|## b
      #|
    ),
  )
}

///|
test "木は何本でも" {
  inspect(
    serialize(doc([root(h("a")), root(h("b"))])),
    content=(
      #|# a
      #|
      #|# b
      #|
    ),
  )
}

///|
test "項目は入れ子。兄弟は詰める" {
  inspect(
    serialize(doc([root(item("root", children=[li("a"), li("b")]))])),
    content=(
      #|- root
      #|  - a
      #|  - b
      #|
    ),
  )
}

///|
test "見出しの下の項目" {
  inspect(
    serialize(doc([root(h("r", children=[item("a"), item("b")]))])),
    content=(
      #|# r
      #|
      #|- a
      #|- b
      #|
    ),
  )
}

///|
/// 順序法則 — 兄弟は項目が先、見出しが後。
test "項目と見出しの兄弟" {
  inspect(
    serialize(doc([root(h("r", children=[item("b"), h("a")]))])),
    content=(
      #|# r
      #|
      #|- b
      #|
      #|## a
      #|
    ),
  )
}

///|
/// ライブラリは setext を書かない。2 行目は段落に落ちる — **この段では受ける**
/// （spec の「改行が在る見出しは setext」は反映の段か上流で）。
test "改行入りの見出しラベルは ATX のまま" {
  inspect(
    serialize(doc([root(h("a\nb"))])),
    content=(
      #|# a
      #|b
      #|
    ),
  )
}

///|
test "改行入りの項目ラベルは続きの行になる" {
  inspect(
    serialize(doc([root(item("a\nb", children=[li("c")]))])),
    content=(
      #|- a
      #|  b
      #|  - c
      #|
    ),
  )
}

///|
test "空のラベル" {
  inspect(
    serialize(doc([root(h("", children=[item("", children=[li("x")])]))])),
    content=(
      #|#
      #|
      #|- - x
      #|
    ),
  )
}

// ══════════════════════════════════════════════════════════════════
// 側 — 根の子の側が直前の兄弟と違えば、その直前に水平線
// （ライブラリは `***` で書く。読みは記法を差別しないので、そのまま受ける）
// ══════════════════════════════════════════════════════════════════

///|
test "側の変わり目に ---" {
  inspect(
    serialize(
      doc([root(h("r", children=[h("a"), h("b")]), sides=[Right, Left])]),
    ),
    content=(
      #|# r
      #|
      #|## a
      #|
      #|***
      #|
      #|## b
      #|
    ),
  )
}

///|
test "最初の子が左なら先頭に ---" {
  inspect(
    serialize(doc([root(h("r", children=[h("a")]), sides=[Left])])),
    content=(
      #|# r
      #|
      #|***
      #|
      #|## a
      #|
    ),
  )
}

///|
test "同じ側が続く間は書かない" {
  inspect(
    serialize(
      doc([
        root(h("r", children=[h("a"), h("b"), h("c"), h("d")]), sides=[
          Right,
          Left,
          Left,
          Right,
        ]),
      ]),
    ),
    content=(
      #|# r
      #|
      #|## a
      #|
      #|***
      #|
      #|## b
      #|
      #|## c
      #|
      #|***
      #|
      #|## d
      #|
    ),
  )
}

///|
/// 深い見出しの側は Implicit 越し。`---` の直後が `### x` になる。
test "Implicit 越しの側" {
  inspect(
    serialize(
      doc([root(h("r", children=[h("a"), gap([h("x")])]), sides=[Right, Left])]),
    ),
    content=(
      #|# r
      #|
      #|## a
      #|
      #|***
      #|
      #|### x
      #|
    ),
  )
}

///|
/// 項目の列は境界で割れる。
test "項目の側" {
  inspect(
    serialize(
      doc([
        root(h("r", children=[item("a"), item("b"), item("c")]), sides=[
          Right,
          Left,
          Left,
        ]),
      ]),
    ),
    content=(
      #|# r
      #|
      #|- a
      #|
      #|***
      #|
      #|- b
      #|- c
      #|
    ),
  )
}

// mmmTree → md を固定する。**木は手で組む** — `parse` で作ると、書きの
// テスト全部が読みに依存する（往復・冪等は両側が揃ってからの別段）。
//
// 見ているのは serialize の文字列。字下げ・フェンス長・空行・エスケープの
// 流儀はライブラリのもので、ここで固定するのは「我々の骨格がどう綴られるか」。
// ライブラリの正規化（`_em_` → `*em*`、定義行の移動、setext → ATX）は
// **この段では素直に受ける**。補正するなら合流の段。

///|
fn doc(
  roots : Array[Root],
  body? : Array[Content] = [],
  frontmatter? : String? = None,
  eol? : Eol = Lf,
) -> Doc {
  { frontmatter, eol, body: blocks(body), roots }
}

///|
fn root(node : Node, sides? : Array[Side] = []) -> Root {
  { node, sides }
}

///|
/// id は書きに関係しないので 0 のまま。
fn blocks(body : Array[Content]) -> Array[Block] {
  body.map(content => ({ id: 0, content } : Block))
}

///|
fn h(
  label : String,
  children? : Array[Node] = [],
  body? : Array[Content] = [],
  fold? : Fold? = None,
) -> Node {
  HeadingNode({ id: 0, label, fold, body: blocks(body), children })
}

///|
fn li(
  label : String,
  children? : Array[ListNode] = [],
  body? : Array[Content] = [],
  fold? : Fold? = None,
) -> ListNode {
  { id: 0, label, fold, body: blocks(body), children }
}

///|
fn item(
  label : String,
  children? : Array[ListNode] = [],
  body? : Array[Content] = [],
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
/// （spec の「改行が在る見出しは setext」は合流の段か上流で）。
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
      #|---
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
      #|---
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
      #|---
      #|
      #|## b
      #|
      #|## c
      #|
      #|---
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
      #|---
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
      #|---
      #|
      #|- b
      #|- c
      #|
    ),
  )
}

// ══════════════════════════════════════════════════════════════════
// 中身 — 絵の 4 つは md の形に、原文で持つものは読み直して並べる
// ══════════════════════════════════════════════════════════════════

///|
test "中身は文書順に、塊ごとに空行を挟んで" {
  inspect(
    serialize(
      doc([
        root(
          h("a", body=[
            Opaque("text"),
            Image(alt="p", src="x.png", title=""),
            Link(text="記事", href="https://e", title=""),
            Code(info="js", text="let x = 1\n"),
            Svg("<svg><rect/></svg>\n"),
            ThematicBreak,
          ]),
        ),
      ]),
    ),
    content=(
      #|# a
      #|
      #|text
      #|
      #|![p](x.png)
      #|
      #|[記事](https://e)
      #|
      #|```js
      #|let x = 1
      #|```
      #|
      #|<svg><rect/></svg>
      #|
      #|---
      #|
    ),
  )
}

///|
test "画像とリンクのタイトル" {
  inspect(
    serialize(
      doc([
        root(
          h("a", body=[
            Image(alt="p", src="x.png", title="t"),
            Link(text="l", href="/u", title="v"),
          ]),
        ),
      ]),
    ),
    content=(
      #|# a
      #|
      #|![p](x.png "t")
      #|
      #|[l](/u "v")
      #|
    ),
  )
}

///|
test "最初の骨格より前の中身は文書のもの" {
  inspect(
    serialize(doc([root(h("a"))], body=[Opaque("intro")])),
    content=(
      #|intro
      #|
      #|# a
      #|
    ),
  )
}

///|
/// 原文は md として読み直すので、ライブラリの正規化を受ける。
test "Opaque は正規化される" {
  inspect(
    serialize(doc([root(h("a", body=[Opaque("_em_ と *x*")]))])),
    content=(
      #|# a
      #|
      #|*em* と *x*
      #|
    ),
  )
}

///|
/// 定義行は文書ぜんぶで 1 列。ライブラリは末尾に集める。
test "定義行は末尾へ" {
  inspect(
    serialize(doc([root(h("a", body=[Opaque("[q]: /r")], children=[h("b")]))])),
    content=(
      #|# a
      #|
      #|## b
      #|
      #|[q]: /r
      #|
    ),
  )
}

///|
/// 畳みに立たなかった `<details>` は領域ごと原文。読み直しても形は同じ。
test "Details はそのまま" {
  inspect(
    serialize(
      doc([
        root(
          h("r", body=[
            Details(
              text="<details>\n<summary>h</summary>\n\ninner\n\n</details>",
              open=false,
              summary=Some("h"),
              body="inner",
            ),
          ]),
        ),
      ]),
    ),
    content=(
      #|# r
      #|
      #|<details>
      #|<summary>h</summary>
      #|
      #|inner
      #|
      #|</details>
      #|
    ),
  )
}

///|
/// 中身を持つ項目はラベルと中身を空行で分ける（分けないと 1 つの段落になる）。
test "項目の中身は項目の列に字下げ" {
  inspect(
    serialize(
      doc([root(h("r", children=[item("a", body=[Opaque("text")]), item("b")]))]),
    ),
    content=(
      #|# r
      #|
      #|- a
      #|
      #|  text
      #|- b
      #|
    ),
  )
}

///|
test "項目の中のコードは塊ごと字下げ" {
  inspect(
    serialize(doc([root(item("a", body=[Code(info="", text="x\n\ny\n")]))])),
    content=(
      #|- a
      #|
      #|  ```
      #|  x
      #|
      #|  y
      #|  ```
      #|
    ),
  )
}

///|
/// 項目の中の見出しは骨格にならず中身（単調性）。書いても項目の中に居る。
test "項目の中の見出しは中身のまま" {
  inspect(
    serialize(doc([root(item("a", body=[Opaque("# x")]))])),
    content=(
      #|- a
      #|
      #|  # x
      #|
    ),
  )
}

///|
test "コードの中に ``` があれば外を長くする" {
  inspect(
    serialize(
      doc([root(h("a", body=[Code(info="md", text="```js\nx\n```\n")]))]),
    ),
    content=(
      #|# a
      #|
      #|````md
      #|```js
      #|x
      #|```
      #|````
      #|
    ),
  )
}

///|
/// ライブラリは閉じの `---` の直後に空行を置かない。読みは同じなので受ける。
test "frontmatter は頭に。本文との間は空行 1 つ" {
  inspect(
    serialize(doc([root(h("a"))], frontmatter=Some("k: v\n"))),
    content=(
      #|---
      #|k: v
      #|---
      #|
      #|# a
      #|
    ),
  )
}

///|
test "CRLF の文書は CRLF で" {
  inspect(
    serialize(doc([root(h("a", children=[h("b")]))], eol=Crlf)),
    content="# a\r\n\r\n## b\r\n",
  )
}

// ══════════════════════════════════════════════════════════════════
// 畳み — 定義ごと `<details>` で包む。開きは「開き」か「開き + 名前」
// ══════════════════════════════════════════════════════════════════

///|
test "見出しの畳み" {
  inspect(
    serialize(
      doc([
        root(
          h("r", children=[
            h("h", fold=Some({ open: false, summary: Some("h") }), body=[
              Opaque("body"),
            ]),
          ]),
        ),
      ]),
    ),
    content=(
      #|# r
      #|
      #|<details>
      #|<summary>h</summary>
      #|
      #|## h
      #|
      #|body
      #|
      #|</details>
      #|
    ),
  )
}

///|
test "open と、名前の無い畳み" {
  inspect(
    serialize(
      doc([
        root(
          h("r", children=[h("h", fold=Some({ open: true, summary: None }))]),
        ),
      ]),
    ),
    content=(
      #|# r
      #|
      #|<details open>
      #|
      #|## h
      #|
      #|</details>
      #|
    ),
  )
}

///|
test "入れ子の畳み" {
  inspect(
    serialize(
      doc([
        root(
          h("r", children=[
            h("a", fold=Some({ open: false, summary: Some("a") }), children=[
              h("a1", fold=Some({ open: false, summary: Some("a1") })),
            ]),
          ]),
        ),
      ]),
    ),
    content=(
      #|# r
      #|
      #|<details>
      #|<summary>a</summary>
      #|
      #|## a
      #|
      #|<details>
      #|<summary>a1</summary>
      #|
      #|### a1
      #|
      #|</details>
      #|
      #|</details>
      #|
    ),
  )
}

///|
/// 畳まれた項目は自分の `<details>` に包まれるので、列がそこで割れる。
test "項目の畳みは列を割る" {
  inspect(
    serialize(
      doc([
        root(
          h("r", children=[
            item("a"),
            item("b", fold=Some({ open: false, summary: Some("b") })),
            item("c"),
          ]),
        ),
      ]),
    ),
    content=(
      #|# r
      #|
      #|- a
      #|
      #|<details>
      #|<summary>b</summary>
      #|
      #|- b
      #|
      #|</details>
      #|
      #|- c
      #|
    ),
  )
}

///|
/// 入れ子の項目の畳みは親の中身の列に字下げ。`<details>` の塊は空行で
/// 終わるので、前後を空行で分けないと `- b` が塊に飲み込まれる。
test "入れ子項目の畳みは親の列に" {
  inspect(
    serialize(
      doc([
        root(
          item("a", children=[
            li("b", fold=Some({ open: false, summary: None })),
            li("c"),
          ]),
        ),
      ]),
    ),
    content=(
      #|- a
      #|
      #|  <details>
      #|
      #|  - b
      #|
      #|  </details>
      #|
      #|  - c
      #|
    ),
  )
}

///|
/// 境界の水平線は部分木のものではないので `<details>` の外。
test "畳みと側" {
  inspect(
    serialize(
      doc([
        root(
          h("r", children=[
            h("a"),
            h("b", fold=Some({ open: false, summary: None })),
          ]),
          sides=[Right, Left],
        ),
      ]),
    ),
    content=(
      #|# r
      #|
      #|## a
      #|
      #|---
      #|
      #|<details>
      #|
      #|## b
      #|
      #|</details>
      #|
    ),
  )
}

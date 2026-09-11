// mmmTree → md を固定する。**木は手で組む** — `parse` で作ると、書きの
// テスト全部が読みに依存する（往復・冪等は両側が揃ってからの別段）。
//
// 見ているのは serialize の文字列。ブロックの並びと字下げはライブラリのもので、
// ここで固定するのは「我々の骨格がどう綴られるか」。
//
// 中身の字はライブラリに渡さない — 読んだ原文（`Block.source`）はそのまま返り、
// 綴るのは mmm が新しく作ったものだけ。

///|
fn doc(
  roots : Array[Root],
  body? : Array[Block] = [],
  frontmatter? : String? = None,
) -> Doc {
  { frontmatter, body, roots, }
}

///|
fn root(
  node : Node,
  sides? : Array[Side] = [],
  rules? : Array[String] = [],
) -> Root {
  { node, sides, rules, }
}

///|
/// mmm が作った中身の列。**原文を持たない**ので、意味から綴られる。
/// id は書きに関係しないので 0 のまま
fn blocks(body : Array[Content]) -> Array[Block] {
  body.map(content => ({ id: 0, content: Some(content), source: None, } : Block))
}

///|
/// 読み解かなかった中身。意味は無く、原文がそのまま書き戻る
fn raw(source : String) -> Block {
  { id: 0, content: None, source: Some(source), }
}

///|
/// mmm が作った中身。原文を持たないので、意味から綴られる
fn made(content : Content) -> Block {
  { id: 0, content: Some(content), source: None, }
}

///|
/// 読んだ中身。意味も原文も持つので、書き戻しは原文のまま
fn read_block(content : Content, source : String) -> Block {
  { id: 0, content: Some(content), source: Some(source), }
}

///|
fn h(
  label : String,
  children? : Array[Node] = [],
  body? : Array[Block] = [],
  fold? : Fold? = None,
  setext? : Bool = false,
  closing? : Int = 0,
) -> Node {
  {
    id: 0,
    label,
    fold,
    body,
    children,
    mark: Some(Heading(setext~, closing~)),
  }
}

///|
fn item(
  label : String,
  children? : Array[Node] = [],
  body? : Array[Block] = [],
  fold? : Fold? = None,
  marker? : String = "-",
  offset? : Int = 2,
  loose? : Bool = false,
) -> Node {
  {
    id: 0,
    label,
    fold,
    body,
    children,
    mark: Some(Item(marker~, offset~, loose~)),
  }
}

///|
fn gap(children : Array[Node]) -> Node {
  { id: 0, label: "", fold: None, body: [], children, mark: None, }
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
/// #203 — 桁 0 に並ぶ項目は md では 1 本の列。木が本ごとに分かれるのは読みの
/// 都合なので、書くときは 1 つの列に戻す（分けると間に空行が入る）
test "桁 0 の項目の木は 1 本の列に戻る。見出しの木を挟めばそこで割れる" {
  inspect(
    serialize(doc([root(item("a")), root(item("b"))])),
    content=(
      #|- a
      #|- b
      #|
    ),
  )
  inspect(
    serialize(doc([root(item("a")), root(h("h")), root(item("b"))])),
    content=(
      #|- a
      #|
      #|# h
      #|
      #|- b
      #|
    ),
  )
  // 読んだ列が loose なら空行のまま
  inspect(
    serialize(doc([root(item("a", loose=true)), root(item("b", loose=true))])),
    content=(
      #|- a
      #|
      #|- b
      #|
    ),
  )
  // 種類が変われば md でも別の列
  inspect(
    serialize(doc([root(item("a")), root(item("b", marker="1."))])),
    content=(
      #|- a
      #|
      #|1. b
      #|
    ),
  )
}

///|
test "項目は入れ子。兄弟は詰める" {
  inspect(
    serialize(doc([root(item("root", children=[item("a"), item("b")]))])),
    content=(
      #|- root
      #|  - a
      #|  - b
      #|
    ),
  )
}

///|
/// #84 — マーカーは項目が持つ。種類が変われば md でも別の列なので、そこで割る。
test "項目のマーカーは読んだ綴り — 列ごとに 1 つ、違えば別の列" {
  inspect(
    serialize(
      doc([
        root(h("a", children=[item("b", marker="*"), item("c", marker="*")])),
      ]),
    ),
    content="# a\n\n* b\n* c\n",
  )
  inspect(
    serialize(
      doc([
        root(
          h("a", children=[
            item("b", marker="1.", offset=3),
            item("c", marker="2.", offset=3),
          ]),
        ),
      ]),
    ),
    content="# a\n\n1. b\n2. c\n",
  )
  inspect(
    serialize(
      doc([
        root(h("a", children=[item("b", marker="-"), item("c", marker="+")])),
      ]),
    ),
    content="# a\n\n- b\n\n+ c\n",
  )
}

///|
/// #84 — 詰めは列のもの。loose なら項目の間に空行が入る。
test "項目の詰めは読んだ綴り — loose なら空行" {
  inspect(
    serialize(
      doc([
        root(h("a", children=[item("b", loose=true), item("c", loose=true)])),
      ]),
    ),
    content="# a\n\n- b\n\n- c\n",
  )
}

///|
/// #84 — 字下げ幅も項目のもの。ラベルの桁に中身も入れ子も座る。
test "項目の字下げは読んだ綴り — 入れ子はその桁から" {
  inspect(
    serialize(
      doc([
        root(
          item("a", marker="*", offset=3, children=[
            item("b", marker="*", offset=3),
          ]),
        ),
      ]),
    ),
    content="*  a\n   *  b\n",
  )
}

///|
/// ラベルの直後に空の項目が続けば、`-` 1 本が setext の下線に読まれてラベルが
/// 消える。その列だけ loose にして空行で分ける — 正規形は並びで変わる。
/// 空の項目でも直前が段落でなければ（前に兄弟が居る）詰めたまま。
test "ラベルの直後の空の項目は空行で分ける" {
  inspect(
    serialize(
      doc([root(item("root", children=[item("a", children=[item("")])]))]),
    ),
    content=(
      #|- root
      #|  - a
      #|
      #|    -
      #|
    ),
  )
  inspect(
    serialize(doc([root(item("root", children=[item("a"), item("")]))])),
    content=(
      #|- root
      #|  - a
      #|  -
      #|
    ),
  )
  inspect(
    serialize(
      doc([
        root(item("root", children=[item("a", children=[item("x"), item("")])])),
      ]),
    ),
    content=(
      #|- root
      #|  - a
      #|    - x
      #|    -
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
/// #85 — 書き方は木が持つ。setext は深さ 1〜2 でだけ書けるので、深ければ ATX。
/// 閉じの `#` は読んだ本数。
test "見出しの書き方は読んだ綴り — setext と閉じの #" {
  inspect(serialize(doc([root(h("a", setext=true))])), content="a\n===\n")
  inspect(
    serialize(doc([root(h("a", children=[h("b", setext=true)]))])),
    content="# a\n\nb\n---\n",
  )
  inspect(serialize(doc([root(h("a", closing=2))])), content="# a ##\n")
  // 深さ 3 は setext を書けない → ATX
  inspect(
    serialize(
      doc([root(h("a", children=[h("b", children=[h("c", setext=true)])]))]),
    ),
    content="# a\n\n## b\n\n### c\n",
  )
}

///|
/// #85 — 改行を含む名前は setext でしか書けない（深さ 1〜2）ので、読んだ綴りが
/// setext でなくても setext で書く。深さ 3 以上では書けないので check が `DeepSetext` で断る
test "改行を含む名前は setext で書く" {
  inspect(serialize(doc([root(h("a\nb", setext=true))])), content="a\nb\n===\n")
  inspect(serialize(doc([root(h("a\nb"))])), content="a\nb\n===\n")
}

///|
test "改行入りの項目ラベルは続きの行になる" {
  inspect(
    serialize(doc([root(item("a\nb", children=[item("c")]))])),
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
    serialize(doc([root(h("", children=[item("", children=[item("x")])]))])),
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
// （読んだ綴りが `rules` に在ればそれ。無ければ `---`）
// ══════════════════════════════════════════════════════════════════

///|
test "境界は読んだ綴りで返す — 無ければ ---" {
  let kids = [h("b"), h("c"), h("d")]
  inspect(
    serialize(
      doc([
        root(h("a", children=kids), sides=[Right, Left, Right], rules=[
          "", "***", "",
        ]),
      ]),
    ),
    content="# a\n\n## b\n\n***\n\n## c\n\n---\n\n## d\n",
  )
}

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
// 中身 — 読んだ原文はそのまま返す。綴るのは mmm が作ったものだけ
// ══════════════════════════════════════════════════════════════════

///|
test "読んだ中身は原文のまま — 表の桁は揃えず、フェンスも変えない" {
  let table = "| a | 日本語 |\n|---|---|\n| 1 | 2 |"
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      root({
        id: 0,
        label: "a",
        fold: None,
        body: [raw(table), read_block(Code(info="", text="x\n"), "~~~\nx\n~~~")],
        children: [],
        mark: Some(atx),
      }),
    ],
  }
  inspect(serialize(doc), content="# a\n\n" + table + "\n\n~~~\nx\n~~~\n")
}

///|
test "mmm が作った中身は既定で綴る — source が無ければ種類ごと" {
  inspect(
    serialize(
      doc([
        root(
          h("a", body=[
            made(Code(info="js", text="1\n")),
            made(Image(alt="", src="p.png", title="")),
          ]),
        ),
      ]),
    ),
    content="# a\n\n```js\n1\n```\n\n![](p.png)\n",
  )
}

///|
test "中身は文書順に、塊ごとに空行を挟んで" {
  inspect(
    serialize(
      doc([
        root(
          h("a", body=[
            raw("text"),
            made(Image(alt="p", src="x.png", title="")),
            made(Link(text="記事", href="https://e", title="")),
            made(Code(info="js", text="let x = 1\n")),
            made(Svg("<svg><rect/></svg>\n")),
            made(ThematicBreak),
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
            made(Image(alt="p", src="x.png", title="t")),
            made(Link(text="l", href="/u", title="v")),
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
    serialize(doc([root(h("a"))], body=[raw("intro")])),
    content=(
      #|intro
      #|
      #|# a
      #|
    ),
  )
}

///|
/// Raw は生の塊のまま置く。読み直さないので、強調の綴りも変わらない。
test "Raw の字はそのまま — 強調の綴りも直さない" {
  inspect(
    serialize(doc([root(h("a", body=[raw("_em_ と *x*")]))])),
    content=(
      #|# a
      #|
      #|_em_ と *x*
      #|
    ),
  )
}

///|
/// 定義行は原文の中に居るので、書かれた場所に残る。
test "定義行は書かれた場所に残る" {
  inspect(
    serialize(doc([root(h("a", body=[raw("[q]: /r")], children=[h("b")]))])),
    content=(
      #|# a
      #|
      #|[q]: /r
      #|
      #|## b
      #|
    ),
  )
}

///|
/// 畳みに立たなかった `<details>` は領域ごと原文。そのまま置く。
test "Details はそのまま" {
  inspect(
    serialize(
      doc([
        root(
          h("r", body=[
            read_block(
              Details(open=false, summary=Some("h"), body="inner"),
              "<details>\n<summary>h</summary>\n\ninner\n\n</details>",
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
      doc([root(h("r", children=[item("a", body=[raw("text")]), item("b")]))]),
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
    serialize(
      doc([root(item("a", body=[made(Code(info="", text="x\n\ny\n"))]))]),
    ),
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
/// 木が中身として持っているなら、見出しの形の行でも中身。読みは項目の子に
/// するが、書きは木が言うとおりに字下げして置くだけ。
test "中身の見出しの形の行は、字下げした中身のまま" {
  inspect(
    serialize(doc([root(item("a", body=[raw("# x")]))])),
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
      doc([root(h("a", body=[made(Code(info="md", text="```js\nx\n```\n"))]))]),
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
            h("h", fold=Some({ open: false, summary: Some("h"), }), body=[
              raw("body"),
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
          h("r", children=[h("h", fold=Some({ open: true, summary: None, }))]),
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
            h("a", fold=Some({ open: false, summary: Some("a"), }), children=[
              h("a1", fold=Some({ open: false, summary: Some("a1"), })),
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
            item("b", fold=Some({ open: false, summary: Some("b"), })),
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
            item("b", fold=Some({ open: false, summary: None, })),
            item("c"),
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
            h("b", fold=Some({ open: false, summary: None, })),
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

// ══════════════════════════════════════════════════════════════════
// 名前 — md の 1 行の原文。mmm は字を足しも引きもしない
// ══════════════════════════════════════════════════════════════════

///|
test "名前の字はそのまま — 逃がさず、強調にも直さない" {
  inspect(serialize(doc([root(h("foo_bar"))])), content="# foo_bar\n")
  inspect(serialize(doc([root(h("__init__"))])), content="# __init__\n")
  inspect(serialize(doc([root(h("a\\_b"))])), content="# a\\_b\n")
  inspect(serialize(doc([root(h("# node"))])), content="# # node\n")
  inspect(serialize(doc([root(h("foo ##"))])), content="# foo ##\n")
  inspect(serialize(doc([root(h("a</summary>b"))])), content="# a</summary>b\n")
  inspect(serialize(doc([root(item("foo_bar"))])), content="- foo_bar\n")
  inspect(serialize(doc([root(item("__init__"))])), content="- __init__\n")
  inspect(serialize(doc([root(item("a\\_b"))])), content="- a\\_b\n")
  inspect(serialize(doc([root(item("# node"))])), content="- # node\n")
  inspect(serialize(doc([root(item("foo ##"))])), content="- foo ##\n")
  inspect(
    serialize(doc([root(item("a</summary>b"))])),
    content="- a</summary>b\n",
  )
}

///|
test "名前の字はそのまま — 子と中身を持っても行は変わらない" {
  inspect(
    serialize(
      doc([root(h("a_b", children=[item("c*d", children=[item("e_f")])]))]),
    ),
    content="# a_b\n\n- c*d\n  - e_f\n",
  )
}

///|
/// **項目の中は、その項目の深さを 0 とした文書。** 中の見出しは項目からの
/// 深さぶんの `#` で書き戻る（塊なので間は空行）。
test "項目の中の見出しは、項目からの深さの # で書き戻る" {
  inspect(serialize(parse("- # node\n")), content="- # node\n")
  inspect(
    serialize(parse("- x\n  # n\n  ## s\n")),
    content=(
      #|- x
      #|  # n
      #|
      #|  ## s
      #|
    ),
  )
}

///|
/// #93 — 題は原文のまま置く。逃がしは打つ人の仕事で、mmm は足しも引きもしない
test "Link の題はそのまま — 逃がしを足さず、消さない" {
  inspect(
    serialize(
      doc([
        root(
          h("a", body=[
            made(
              Link(text="\\[WIP\\] design", href="https://e.com/x", title=""),
            ),
          ]),
        ),
      ]),
    ),
    content="# a\n\n[\\[WIP\\] design](https://e.com/x)\n",
  )
  inspect(
    serialize(
      doc([
        root(
          h("a", body=[
            made(Link(text="[WIP] design", href="https://e.com/x", title="")),
          ]),
        ),
      ]),
    ),
    content="# a\n\n[[WIP] design](https://e.com/x)\n",
  )
}

///|
/// #179 — 名前の無い項目が 3 段続くとマーカーだけが 1 行に並び、md は水平線を
/// 優先する（`- - -`）。子を次の行へ落として桁で入れ子を言う。
/// 名前が在る行は直さない — `- ---` が水平線に読まれるのは md の文法どおり
test "名前の無い項目が 3 段続いても、水平線には化けない" {
  inspect(
    serialize(parse("- \n  - \n    - \n")),
    content=(
      #|-
      #|  - -
      #|
    ),
  )
  inspect(
    serialize(parse("- \n  - \n    - \n      - \n")),
    content=(
      #|- -
      #|    - -
      #|
    ),
  )
  // 名前が 1 つでも付けば並ばない
  inspect(serialize(parse("- - - a\n")), content="- - - a\n")
  // 印が変わっても同じ（`*` も `_` も水平線）
  inspect(
    serialize(parse("* \n  * \n    * \n")),
    content=(
      #|*
      #|  * *
      #|
    ),
  )
}

///|
/// #179 — 読み直せば同じ木で、書き直しても同じ字（往復と冪等）
test "名前の無い深い入れ子は、往復しても木が変わらない" {
  let cases = [
    "- \n  - \n    - \n", "- \n  - \n    - \n      - \n", "* \n  * \n    * \n", "# r\n\n- \n  - \n    - \n",
  ]
  for md in cases {
    let once = serialize(parse(md))
    inspect(parse(once) == parse(md), content="true")
    inspect(serialize(parse(once)) == once, content="true")
  }
}

// ══════════════════════════════════════════════════════════════════
// 断片 — 部分木 1 つを md にする。合流が dirty の地番に差すもの
// ══════════════════════════════════════════════════════════════════

///|
test "見出しは渡した深さから" {
  inspect(
    fragment(h("a", children=[h("b")]), 2, [], []),
    content=(
      #|## a
      #|
      #|### b
      #|
    ),
  )
}

///|
/// 入れ子は列 0 で出る。容器の桁に合わせるのは差す側の仕事
test "項目は入れ子込み" {
  inspect(
    fragment(item("a", children=[item("b")]), 0, [], []),
    content=(
      #|- a
      #|  - b
      #|
    ),
  )
}

///|
test "Implicit は子だけを書き、側は水平線。綴りが在ればそれ" {
  inspect(
    fragment(gap([h("a"), h("b")]), 1, [Right, Left], []),
    content=(
      #|## a
      #|
      #|---
      #|
      #|## b
      #|
    ),
  )
  inspect(
    fragment(gap([h("a"), h("b")]), 1, [Right, Left], ["", "___"]),
    content=(
      #|## a
      #|
      #|___
      #|
      #|## b
      #|
    ),
  )
}

///|
test "畳みは部分木ごと包む" {
  inspect(
    fragment(
      h("a", children=[h("b")], fold=Some({ open: false, summary: None, })),
      2,
      [],
      [],
    ),
    content=(
      #|<details>
      #|
      #|## a
      #|
      #|### b
      #|
      #|</details>
      #|
    ),
  )
}

///|
/// 定義行は断片の中に留まる。文書の尻へ動かすと、触っていない場所が動く
test "定義行は断片の中" {
  inspect(
    fragment(h("a", body=[raw("[q]: /r")]), 1, [], []),
    content=(
      #|# a
      #|
      #|[q]: /r
      #|
    ),
  )
}

///|
test "散文は根を持たない中身の列" {
  inspect(
    prose([raw("hello"), ..blocks([ThematicBreak])]),
    content=(
      #|hello
      #|
      #|---
      #|
    ),
  )
}

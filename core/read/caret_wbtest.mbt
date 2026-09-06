// md のカーソルと地図の位置が、どのノード（またはカード）に掛かっているか。
// 区間の重なりだけの層。木と地番は手で組む（読みは tree の wbtest が固定済み）。

///|
fn node(
  id : Int,
  label : String?,
  children? : Array[@view.Node] = [],
  blocks? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @view.Node {
  { id, label, fold, blocks, children, }
}

///|
fn view(roots : Array[@view.Node]) -> @view.View {
  {
    frontmatter: None,
    roots: roots.map(n => {
      ({ node: n, sides: n.children.map(_ => Right), } : @view.Root)
    }),
  }
}

///|
/// (id, from, label, to) の並びから地番の表
fn spots(rows : Array[(Int, Int, Int?, Int)]) -> Map[Int, @tree.Spot] {
  let out : Map[Int, @tree.Spot] = Map([])
  for r in rows {
    let (id, from, label, to) = r
    out[id] = { from, label, to, }
  }
  out
}

///|
fn reading(view : @view.View, spots : Map[Int, @tree.Spot]) -> Survey {
  { md: "", view, spots, }
}

///|
/// "# r\n\n## a\n\nhello\n\n## b\n"
fn doc() -> Survey {
  reading(
    view([node(2, Some("r"), children=[node(3, Some("a")), node(5, Some("b"))])]),
    spots([
      (1, 0, None, 0),
      (2, 0, Some(2), 23),
      (3, 5, Some(8), 17),
      (5, 18, Some(21), 23),
    ]),
  )
}

///|
fn point(p : Int) -> Array[Range] {
  [{ from: p, to: p, }]
}

///|
fn caret(p : Int, to? : Int = p) -> Caret {
  { ranges: [{ from: p, to, }], head: to, }
}

///|
fn nodes(ids : Array[Int], anchor : Int?) -> Choice {
  Nodes(sel={ ids, anchor, })
}

///|
test "最も深いノードだけ。自身の文は地番の頭から最初の子の頭まで" {
  let d = doc()
  assert_eq(caret_ids(d, point(1)), [2])
  assert_eq(caret_ids(d, point(7)), [3])
  assert_eq(caret_ids(d, point(12)), [3]) // hello の中
  assert_eq(caret_ids(d, point(20)), [5])
}

///|
test "閉じ際は中と見なす。点が継ぎ目ちょうどなら始まる側 1 つ" {
  let d = doc()
  assert_eq(caret_ids(d, point(5)), [3]) // r の文が閉じ、a が始まる → a
  assert_eq(caret_ids(d, point(17)), [3]) // a の文の閉じ際。b は 18 から
  assert_eq(caret_ids(d, point(23)), [5]) // 文書の末尾で追記中も出る
}

///|
test "範囲と複数カーソルは掛かるもの全部。無ければ空" {
  let d = doc()
  assert_eq(caret_ids(d, [{ from: 1, to: 20, }]), [2, 3, 5])
  assert_eq(caret_ids(d, [{ from: 1, to: 1, }, { from: 20, to: 20, }]), [2, 5])
  assert_eq(caret_ids(d, [{ from: 5, to: 6, }]), [2, 3]) // 範囲なら継ぎ目の両側
  assert_eq(caret_ids(d, []), [])
}

///|
test "Implicit は行が無く自身の文が空なので掛からない" {
  // "# r\n\n### x\n": r=2, Implicit=3, x=4
  let gap = reading(
    view([
      node(2, Some("r"), children=[node(3, None, children=[node(4, Some("x"))])]),
    ]),
    spots([
      (1, 0, None, 0),
      (2, 0, Some(2), 11),
      (3, 5, None, 11),
      (4, 5, Some(9), 11),
    ]),
  )
  assert_eq(caret_ids(gap, point(7)), [4])
  assert_eq(caret_ids(gap, point(5)), [4])
}

///|
/// "# r\n\n## a\n\n### x\n\n## b\n" で a が畳まれている: r=2, a=3, x=4, b=5
fn hidden() -> Survey {
  reading(
    view([
      node(2, Some("r"), children=[
        node(
          3,
          Some("a"),
          children=[node(4, Some("x"))],
          fold=Some({ open: false, summary: Some("a"), }),
        ),
        node(5, Some("b")),
      ]),
    ]),
    spots([
      (1, 0, None, 0),
      (2, 0, Some(2), 23),
      (3, 5, Some(8), 17),
      (4, 11, Some(15), 17),
      (5, 18, Some(21), 23),
    ]),
  )
}

///|
test "buried — 畳まれたノードの子孫。畳まれたノード自身は入らない" {
  assert_eq(buried(hidden().view).iter().collect(), [4])
  assert_eq(buried(doc().view).length(), 0)
}

///|
test "derive — md が持つ間はカーソルから。anchor は主カーソルの頭のノード" {
  let d = doc()
  assert_eq(chosen(d, Md, caret(12), None), nodes([3], Some(3)))
  assert_eq(chosen(d, Md, caret(1, to=20), None), nodes([2, 3, 5], Some(5)))
  // anchors が在っても見ない
  assert_eq(
    chosen(d, Md, caret(12), Some(NodeAt(at=[21], anchor=Some(21)))),
    nodes([3], Some(3)),
  )
  // 埋もれたノードは選択に居ない
  assert_eq(chosen(hidden(), Md, caret(13), None), nodes([], None))
}

///|
test "derive — 地図が持つ間は位置から。点はラベルの頭、カードは中身の頭" {
  let d = doc()
  assert_eq(
    chosen(d, Map, caret(1), Some(NodeAt(at=[8, 21], anchor=Some(21)))),
    nodes([3, 5], Some(5)),
  )
  // 潰れて同じノードに落ちた点は 1 つに
  assert_eq(
    chosen(d, Map, caret(1), Some(NodeAt(at=[8, 9], anchor=Some(9)))),
    nodes([3], Some(3)),
  )
  // 無ければ何も選んでいない
  assert_eq(chosen(d, Map, caret(1), None), nothing)
  // カード: a(3) の中身 code(4) が [10, 18) に書かれている（地番は手で組む）
  let card : @tree.Block = { id: 4, content: Code(info="", text="x"), }
  let card_at = spots([
    (1, 0, None, 0),
    (2, 0, Some(2), 18),
    (3, 5, Some(8), 18),
    (4, 10, None, 18),
  ])
  let carded = reading(
    view([node(2, Some("r"), children=[node(3, Some("a"), blocks=[card])])]),
    card_at,
  )
  assert_eq(chosen(carded, Map, caret(1), Some(CardAt(at=10))), Card(id=4))
  assert_eq(chosen(carded, Map, caret(1), Some(CardAt(at=3))), nothing)
  // 埋もれたノードに掛かる位置は落とす
  assert_eq(
    chosen(hidden(), Map, caret(1), Some(NodeAt(at=[15, 21], anchor=Some(15)))),
    nodes([5], Some(5)),
  )
  // 畳まれたノードのカードは選べない。開けば選べる
  let shut = reading(
    view([
      node(2, Some("r"), children=[
        node(
          3,
          Some("a"),
          blocks=[card],
          fold=Some({ open: false, summary: Some("a"), }),
        ),
      ]),
    ]),
    card_at,
  )
  assert_eq(chosen(shut, Map, caret(1), Some(CardAt(at=10))), nothing)
}

///|
test "anchors_of / anchors_for / ranges — id と位置の往復。カードは中身の頭" {
  // "# r\n\n## a\n\n```\nx\n```\n": r=2 [0,2,21] a=3 [5,8,21] code=4 [11,-,21]
  let s = survey("# r\n\n## a\n\n```\nx\n```\n")
  assert_eq(anchors_of(s, Some(3)), Some(NodeAt(at=[8], anchor=Some(8))))
  assert_eq(anchors_of(s, Some(4)), Some(CardAt(at=11)))
  assert_eq(anchors_of(s, None), None)
  assert_eq(anchors_of(s, Some(99)), None)
  assert_eq(
    anchors_for(s, nodes([2, 3], Some(3))),
    Some(NodeAt(at=[2, 8], anchor=Some(8))),
  )
  assert_eq(anchors_for(s, Card(id=4)), Some(CardAt(at=11)))
  assert_eq(anchors_for(s, nothing), Some(NodeAt(at=[], anchor=None)))
  assert_eq(ranges(s, nodes([3], Some(3))), [{ from: 5, to: 21, }])
  assert_eq(ranges(s, nodes([2], Some(2))), [{ from: 0, to: 21, }])
  assert_eq(ranges(s, Card(id=4)), [{ from: 11, to: 21, }])
}

// splice を固定する。id の席を f の返した列に置き換え、根までの道を組み直す。
// check の書き込み版 — 3 つの約束（項目の子は項目 / Implicit は子を持つ /
// sides は根の子と並走）を破らないように組む唯一の場所。

///|
test "深いラベルを替えると、根までの道が組み直る" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[Right]),
  ])
  let got = splice(d, 4, n => {
    match n {
      HeadingNode(x) => [@tree.HeadingNode({ ..x, label: "y" })]
      _ => [n]
    }
  })
  assert_eq(
    got,
    Some(
      doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "y")])]), sides=[
          Right,
        ]),
      ]),
    ),
  )
}

///|
test "空にすると抜ける。根の子なら side も減る" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Right, Left]),
  ])
  assert_eq(
    splice(d, 3, _ => []),
    Some(doc([root(h(2, "r", children=[h(4, "b")]), sides=[Left])])),
  )
}

///|
test "消して Implicit の子が尽きれば Implicit も消える" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(splice(d, 4, _ => []), Some(doc([root(h(2, "r"), sides=[])])))
}

///|
test "根の Implicit が空になれば Root ごと消える" {
  let d = doc([root(gap(2, [h(3, "x")]), sides=[Right]), root(h(4, "s"))])
  assert_eq(splice(d, 3, _ => []), Some(doc([root(h(4, "s"))])))
}

///|
test "根の子の隣に差すと、隣の side が複製される" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Right, Left]),
  ])
  assert_eq(
    splice(d, 4, n => [h(9, "c"), n]),
    Some(
      doc([
        root(h(2, "r", children=[h(3, "a"), h(9, "c"), h(4, "b")]), sides=[
          Right,
          Left,
          Left,
        ]),
      ]),
    ),
  )
}

///|
test "根を包むと、新しい根の sides は Right × 子の数" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    splice(d, 2, n => [h(9, "top", children=[n])]),
    Some(
      doc([
        root(h(9, "top", children=[h(2, "r", children=[h(3, "a")])]), sides=[
          Right,
        ]),
      ]),
    ),
  )
}

///|
test "根を同じ id で替えれば sides は保つ" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    splice(d, 2, n => {
      match n {
        HeadingNode(x) => [@tree.HeadingNode({ ..x, label: "q" })]
        _ => [n]
      }
    }),
    Some(doc([root(h(2, "q", children=[h(3, "a")]), sides=[Left])])),
  )
}

///|
test "根の隣に差せば新しい根になる" {
  let d = doc([root(h(2, "r")), root(h(3, "s"))])
  assert_eq(
    splice(d, 3, n => [h(9, "m"), n]),
    Some(doc([root(h(2, "r")), root(h(9, "m")), root(h(3, "s"))])),
  )
}

///|
test "項目の席には項目しか置けない" {
  let d = doc([root(item(2, "a", children=[li(3, "b")]), sides=[Right])])
  assert_eq(
    splice(d, 3, n => [n, item(9, "c")]),
    Some(
      doc([
        root(item(2, "a", children=[li(3, "b"), li(9, "c")]), sides=[
          Right,
          Right,
        ]),
      ]),
    ),
  )
  assert_eq(splice(d, 3, n => [n, h(9, "c")]), None)
}

///|
test "見出しの下には項目も置ける" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Right])])
  assert_eq(
    splice(d, 3, n => [n, item(9, "c")]),
    Some(
      doc([
        root(h(2, "r", children=[h(3, "a"), item(9, "c")]), sides=[Right, Right]),
      ]),
    ),
  )
}

///|
test "知らない id なら None" {
  let d = doc([root(h(2, "r"))])
  assert_eq(splice(d, 9, n => [n]), None)
}

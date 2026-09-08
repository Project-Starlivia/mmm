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
      x if @tree.sign_of(x) is Some(Heading) => [{ ..x, label: "y", }]
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
/// 子が尽きた Implicit の掃除は門（mend）の仕事。途中の席が消えないように、
/// splice は残す
test "消して Implicit の子が尽きても、splice は Implicit を残す" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(
    splice(d, 4, _ => []),
    Some(doc([root(h(2, "r", children=[gap(3, [])]), sides=[Right])])),
  )
  let e = doc([root(gap(2, [h(3, "x")]), sides=[Right]), root(h(4, "s"))])
  assert_eq(
    splice(e, 3, _ => []),
    Some(doc([root(gap(2, []), sides=[]), root(h(4, "s"))])),
  )
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
        x if @tree.sign_of(x) is Some(Heading) => [{ ..x, label: "q", }]
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
/// **席は種類を選ばない** — 項目の中は、その項目の深さを 0 とした文書。
test "項目の席には見出しも置ける" {
  let d = doc([root(item(2, "a", children=[item(3, "b")]), sides=[Right])])
  assert_eq(
    splice(d, 3, n => [n, item(9, "c")]),
    Some(
      doc([
        root(item(2, "a", children=[item(3, "b"), item(9, "c")]), sides=[
          Right,
          Right,
        ]),
      ]),
    ),
  )
  assert_eq(
    splice(d, 3, n => [n, h(9, "c")]),
    Some(
      doc([
        root(item(2, "a", children=[item(3, "b"), h(9, "c")]), sides=[
          Right,
          Right,
        ]),
      ]),
    ),
  )
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

///|
test "append は子の末尾。根なら side も足す" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Right])])
  assert_eq(
    append(d, node=2, [h(9, "b")]),
    Some(
      doc([
        root(h(2, "r", children=[h(3, "a"), h(9, "b")]), sides=[Right, Right]),
      ]),
    ),
  )
  assert_eq(
    append(d, node=2, side=Left, [h(9, "b")]),
    Some(
      doc([
        root(h(2, "r", children=[h(3, "a"), h(9, "b")]), sides=[Right, Left]),
      ]),
    ),
  )
  assert_eq(
    append(d, node=3, [h(9, "x")]),
    Some(
      doc([
        root(h(2, "r", children=[h(3, "a", children=[h(9, "x")])]), sides=[
          Right,
        ]),
      ]),
    ),
  )
}

///|
test "append の side は、無ければ末尾の子の側、子が無ければ Right" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    append(d, node=2, [h(9, "b")]),
    Some(
      doc([root(h(2, "r", children=[h(3, "a"), h(9, "b")]), sides=[Left, Left])]),
    ),
  )
  let e = doc([root(h(2, "r"))])
  assert_eq(
    append(e, node=2, [h(9, "b")]),
    Some(doc([root(h(2, "r", children=[h(9, "b")]), sides=[Right])])),
  )
}

///|
test "append を doc_id にすれば新しい根" {
  let d = doc([root(h(2, "r"))])
  assert_eq(
    append(d, node=@tree.doc_id, [h(9, "s", children=[h(10, "t")])]),
    Some(
      doc([
        root(h(2, "r")),
        root(h(9, "s", children=[h(10, "t")]), sides=[Right]),
      ]),
    ),
  )
}

///|
test "append は席の末尾に足す。種類は選ばない" {
  let d = doc([root(item(2, "a"), sides=[])])
  assert_eq(
    append(d, node=2, [item(9, "b")]),
    Some(doc([root(item(2, "a", children=[item(9, "b")]), sides=[Right])])),
  )
  assert_eq(
    append(d, node=2, [h(9, "b")]),
    Some(doc([root(item(2, "a", children=[h(9, "b")]), sides=[Right])])),
  )
  assert_eq(append(d, node=99, [h(9, "b")]), None)
}

///|
test "body は持ち主の中身を配列として直す" {
  let d = doc([
    root(h(2, "r", body=[pic(3)], children=[gap(4, [h(5, "x")])]), sides=[Right]),
  ])
  assert_eq(
    body(d, node=2, bs => [..bs, code(9)]),
    Some(
      doc([
        root(
          h(2, "r", body=[pic(3), code(9)], children=[gap(4, [h(5, "x")])]),
          sides=[Right],
        ),
      ]),
    ),
  )
  assert_eq(
    body(d, node=@tree.doc_id, bs => [..bs, code(9)]),
    Some(
      doc(
        [
          root(h(2, "r", body=[pic(3)], children=[gap(4, [h(5, "x")])]), sides=[
            Right,
          ]),
        ],
        body=[code(9)],
      ),
    ),
  )
  assert_eq(body(d, node=4, bs => bs), None)
  assert_eq(body(d, node=99, bs => bs), None)
}

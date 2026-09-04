// Op ごとに「この木にこの操作でこの木」を固定する。木は手で組む。
// 最後に「apply の結果は check を通る」を法則として回す。

///|
fn run(d : @tree.Doc, op : Op) -> Done? {
  apply(d, op)
}

///|
test "Rename はラベルを替える。Implicit は見出しになる" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(
    run(d, Rename(id=4, label="y")),
    Some({
      doc: doc([root(h(2, "r", children=[gap(3, [h(4, "y")])]), sides=[Right])]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, Rename(id=3, label="a")),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(3),
    }),
  )
  let e = doc([root(item(2, "a"))])
  assert_eq(
    run(e, Rename(id=2, label="b")),
    Some({ doc: doc([root(item(2, "b"))]), focus: Some(2) }),
  )
}

///|
test "Rename は中身と知らない id に None" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(run(d, Rename(id=3, label="y")), None)
  assert_eq(run(d, Rename(id=9, label="y")), None)
}

///|
test "Fold は定義ごと畳み、名前はラベル。畳み済みなら open だけ替わる" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[Right]),
  ])
  let folded : @tree.Fold = { open: false, summary: Some("a") }
  assert_eq(
    run(d, Fold(id=3, open=false)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", fold=Some(folded), children=[h(4, "x")]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(3),
    }),
  )
  let f = doc([
    root(h(2, "r", children=[h(3, "a", fold=Some(folded))]), sides=[Right]),
  ])
  assert_eq(
    run(f, Fold(id=3, open=true)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", fold=Some({ open: true, summary: Some("a") })),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(3),
    }),
  )
}

///|
test "Fold は書けない名前なら名無しで畳む" {
  let d = doc([root(h(2, "a</summary>b"))])
  assert_eq(
    run(d, Fold(id=2, open=false)),
    Some({
      doc: doc([
        root(h(2, "a</summary>b", fold=Some({ open: false, summary: None }))),
      ]),
      focus: Some(2),
    }),
  )
}

///|
test "Fold は Implicit と中身に None。Unfold は畳んでいなければ None" {
  let d = doc([
    root(h(2, "r", body=[pic(3)], children=[gap(4, [h(5, "x")])]), sides=[Right]),
  ])
  assert_eq(run(d, Fold(id=4, open=false)), None)
  assert_eq(run(d, Fold(id=3, open=false)), None)
  assert_eq(run(d, Unfold(id=2)), None)
}

///|
test "Unfold は畳みを外す" {
  let folded : @tree.Fold = { open: false, summary: Some("a") }
  let d = doc([root(item(2, "a", fold=Some(folded)))])
  assert_eq(
    run(d, Unfold(id=2)),
    Some({ doc: doc([root(item(2, "a"))]), focus: Some(2) }),
  )
}

///|
test "Delete は部分木ごと。根の子なら side も、Implicit の掃除も" {
  let d = doc([
    root(
      h(2, "r", children=[h(3, "a", children=[h(4, "x")]), gap(5, [h(6, "y")])]),
      sides=[Right, Left],
    ),
  ])
  assert_eq(
    run(d, Delete(ids=[4, 6, 3])),
    Some({ doc: doc([root(h(2, "r"), sides=[])]), focus: None }),
  )
}

///|
test "Delete は中身も 1 枚ずつ。根も Root ごと" {
  let d = doc([root(h(2, "r", body=[pic(3), code(4)])), root(h(5, "s"))])
  assert_eq(
    run(d, Delete(ids=[3])),
    Some({
      doc: doc([root(h(2, "r", body=[code(4)])), root(h(5, "s"))]),
      focus: None,
    }),
  )
  assert_eq(
    run(d, Delete(ids=[5])),
    Some({ doc: doc([root(h(2, "r", body=[pic(3), code(4)]))]), focus: None }),
  )
}

///|
test "Delete は空と知らない id に None" {
  let d = doc([root(h(2, "r"))])
  assert_eq(run(d, Delete(ids=[])), None)
  assert_eq(run(d, Delete(ids=[2, 9])), None)
}

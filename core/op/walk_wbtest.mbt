// 読みの道具を固定する。歩きは each 1 本で、他はその上に乗る。

///|
/// # r(2) / ![](3) / ## a(4) / ### x(5) / --- / ## b(6) / ![](7)
/// # s(8)
fn sample() -> @tree.Doc {
  doc([
    root(
      h(2, "r", body=[pic(3)], children=[
        h(4, "a", children=[h(5, "x")]),
        h(6, "b", body=[pic(7)]),
      ]),
      sides=[Right, Left],
    ),
    root(h(8, "s")),
  ])
}

///|
test "each は文書順に、中身も含めて訪ねる" {
  let seen = []
  each(sample(), fn(id, is_block, path) {
    seen.push((id, is_block, path.copy()))
  })
  json_inspect(seen, content=[
    [2, false, []],
    [3, true, [2]],
    [4, false, [2]],
    [5, false, [2, 4]],
    [6, false, [2]],
    [7, true, [2, 6]],
    [8, false, []],
  ])
}

///|
test "kids は項目の子も Node に包む" {
  let n = item(2, "a", children=[li(3, "b"), li(4, "c")])
  json_inspect(kids(n).map(id_of), content=[3, 4])
  json_inspect(kids(gap(5, [h(6, "x")])).map(id_of), content=[6])
  json_inspect(kids(h(7, "y")).map(id_of), content=[])
}

///|
test "find はノードだけに応える" {
  inspect(find(sample(), 5).map(id_of), content="Some(5)")
  inspect(find(sample(), 8).map(id_of), content="Some(8)")
  inspect(find(sample(), 3).map(id_of), content="None")
  inspect(find(sample(), 99).map(id_of), content="None")
}

///|
test "seat は根の添字から辿る道で、長さが深さ" {
  inspect(seat(sample(), 2), content="Some([0])")
  inspect(seat(sample(), 6), content="Some([0, 1])")
  inspect(seat(sample(), 5), content="Some([0, 0, 0])")
  inspect(seat(sample(), 8), content="Some([1])")
  inspect(seat(sample(), 3), content="None")
}

///|
test "owner は中身の持ち主。散文なら doc_id" {
  inspect(owner(sample(), block=7), content="Some(6)")
  inspect(owner(sample(), block=3), content="Some(2)")
  inspect(owner(doc([], body=[pic(2)]), block=2), content="Some(1)")
  inspect(owner(sample(), block=4), content="None")
}

///|
test "parent は親の id。根なら doc_id、中身なら持ち主" {
  inspect(parent(sample(), 5), content="Some(4)")
  inspect(parent(sample(), 2), content="Some(1)")
  inspect(parent(sample(), 7), content="Some(6)")
  inspect(parent(sample(), 99), content="None")
}

///|
test "pick は文書順に並べ、祖先に含まれる子孫を落とす" {
  json_inspect(pick(sample(), [6, 5, 4]), content=[4, 6])
  json_inspect(pick(sample(), [7, 6]), content=[6])
  json_inspect(pick(sample(), [99, 8]), content=[8])
  json_inspect(pick(sample(), []), content=[])
}

///|
test "within は自分か祖先が ids に居るか" {
  assert_true(within(sample(), 5, [4]))
  assert_true(within(sample(), 4, [4]))
  assert_true(within(sample(), 7, [2]))
  assert_false(within(sample(), 6, [4]))
  assert_false(within(sample(), @tree.doc_id, [2]))
}

///|
test "fresh は最大 + 1。空の文書なら doc_id + 1" {
  inspect(fresh(sample()), content="9")
  inspect(fresh(doc([])), content="2")
}

///|
test "has はノードにも中身にも応える" {
  assert_true(has(sample(), 5))
  assert_true(has(sample(), 7))
  assert_false(has(sample(), 99))
}

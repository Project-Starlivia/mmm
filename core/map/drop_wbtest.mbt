// ドラッグしたものをどこへ落とすか。マップでいちばん込み入った判断なので、
// 見た目から切り離してここだけを固定する。

///|
/// r(1) → a(2), b(3)。両方右側
fn drop_l() -> Layout {
  layout(
    [
      root(node(1, "r", children=[node(2, "a"), node(3, "b")]), sides=[
        Right,
        Right,
      ]),
    ],
    size,
  )
}

///|
fn drop_at(l : Layout, at : Pt, dragging? : Array[Int] = []) -> Drop? {
  resolve(l, at, dragging)
}

///|
test "箱の中心 → その子" {
  let l = drop_l()
  assert_eq(drop_at(l, box(l, 2).rect().center()), Some(Node(id=2, pos=0)))
}

///|
test "箱の上下の帯 → 直前 / 直後" {
  let l = drop_l()
  let a = box(l, 2)
  let c = a.rect().center()
  assert_eq(drop_at(l, { x: c.x, y: a.y - 10.0, }), Some(Node(id=2, pos=1)))
  // 下は gap.y ぶんしか空いていない（b がすぐ下）ので、a に近い範囲で当てる
  assert_eq(
    drop_at(l, { x: c.x, y: a.y + a.h + 3.0, }),
    Some(Node(id=2, pos=2)),
  )
}

///|
test "箱の外側ゾーン（成長する側）→ 子" {
  let l = drop_l()
  let a = box(l, 2)
  let c = a.rect().center()
  // 帯（slop）の外・外側ゾーン（reach）の内で当てる
  assert_eq(
    drop_at(l, { x: a.x + a.w + 30.0, y: c.y, }),
    Some(Node(id=2, pos=0)),
  )
}

///|
test "根の外側 / 根の箱の中（中心より右） → 側・右（子が居る側）" {
  let l = drop_l()
  let r = box(l, 1)
  let c = r.rect().center()
  assert_eq(
    drop_at(l, { x: r.x + r.w + 10.0, y: c.y, }),
    Some(Side(root=1, left=false)),
  )
  assert_eq(
    drop_at(l, { x: r.x + r.w - 5.0, y: c.y, }),
    Some(Side(root=1, left=false)),
  )
}

///|
test "根の左外側（子が居ない側） → 側・左" {
  let l = drop_l()
  let r = box(l, 1)
  let c = r.rect().center()
  assert_eq(
    drop_at(l, { x: r.x - 10.0, y: c.y, }),
    Some(Side(root=1, left=true)),
  )
}

///|
test "遠い空所 → None" {
  assert_eq(drop_at(drop_l(), { x: 5000, y: 5000, }), None)
}

///|
test "掴んでいる部分木は落とし先から外れる" {
  // a(2) を掴んだままその中心へ落としても、a 自身は候補に出ない
  let l = drop_l()
  assert_eq(
    drop_at(l, box(l, 2).rect().center(), dragging=[2]),
    Some(Node(id=3, pos=1)),
  )
}

///|
test "drop_op — node の 3 形と side" {
  assert_eq(
    drop_op(Node(id=2, pos=0), [5]),
    MoveNode(ids=[5], at=In(node=2, side=None)),
  )
  assert_eq(
    drop_op(Node(id=2, pos=1), [5]),
    MoveNode(ids=[5], at=Before(node=2)),
  )
  assert_eq(
    drop_op(Node(id=2, pos=2), [5]),
    MoveNode(ids=[5], at=After(node=2)),
  )
  assert_eq(
    drop_op(Side(root=1, left=true), [5]),
    MoveNode(ids=[5], at=In(node=1, side=Some(Left))),
  )
}

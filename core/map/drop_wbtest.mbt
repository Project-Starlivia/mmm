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
  assert_eq(drop_at(l, box(l, 2).rect.center()), Some(Node(id=2, slot=Into)))
}

///|
test "箱の上下の帯 → 直前 / 直後" {
  let l = drop_l()
  let a = box(l, 2).rect
  let c = a.center()
  assert_eq(
    drop_at(l, { x: c.x, y: a.y - 10.0, }),
    Some(Node(id=2, slot=Before)),
  )
  // 下は gap.y ぶんしか空いていない（b がすぐ下）ので、a に近い範囲で当てる
  assert_eq(
    drop_at(l, { x: c.x, y: a.y + a.h + 3.0, }),
    Some(Node(id=2, slot=After)),
  )
}

///|
test "箱の外側ゾーン（成長する側）→ 子" {
  let l = drop_l()
  let a = box(l, 2).rect
  let c = a.center()
  // 帯（slop）の外・外側ゾーン（reach）の内で当てる
  assert_eq(
    drop_at(l, { x: a.x + a.w + 30.0, y: c.y, }),
    Some(Node(id=2, slot=Into)),
  )
}

///|
test "根の外側 / 根の箱の中（中心より右） → 側・右（子が居る側）" {
  let l = drop_l()
  let r = box(l, 1).rect
  let c = r.center()
  assert_eq(
    drop_at(l, { x: r.x + r.w + 10.0, y: c.y, }),
    Some(Side(root=1, side=Right)),
  )
  assert_eq(
    drop_at(l, { x: r.x + r.w - 5.0, y: c.y, }),
    Some(Side(root=1, side=Right)),
  )
}

///|
test "根の左外側（子が居ない側） → 側・左" {
  let l = drop_l()
  let r = box(l, 1).rect
  let c = r.center()
  assert_eq(
    drop_at(l, { x: r.x - 10.0, y: c.y, }),
    Some(Side(root=1, side=Left)),
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
    drop_at(l, box(l, 2).rect.center(), dragging=[2]),
    Some(Node(id=3, slot=Before)),
  )
}

///|
test "drop_op — node の 3 形と side" {
  assert_eq(
    drop_op(Node(id=2, slot=Into), [5]),
    MoveNode(ids=[5], at=In(node=2, side=None)),
  )
  assert_eq(
    drop_op(Node(id=2, slot=Before), [5]),
    MoveNode(ids=[5], at=Before(node=2)),
  )
  assert_eq(
    drop_op(Node(id=2, slot=After), [5]),
    MoveNode(ids=[5], at=After(node=2)),
  )
  assert_eq(
    drop_op(Side(root=1, side=Left), [5]),
    MoveNode(ids=[5], at=In(node=1, side=Some(Left))),
  )
}

///|
/// r(1) → a(2), b(3) → c(4), d(5)。a に子は無く、a の通路の先に隣の枝 b の子の列が居る
fn drop_next_column() -> Layout {
  layout(
    [
      root(
        node(1, "r", children=[
          node(2, "a"),
          node(3, "b", children=[node(4, "c"), node(5, "d")]),
        ]),
        sides=[Right, Right],
      ),
    ],
    size,
  )
}

///|
test "列の端の外 — 帯の先 open_band まで、端のノードの直前 / 直後が受ける" {
  let l = drop_l()
  let a = box(l, 2).rect
  let b = box(l, 3).rect
  let x = a.center().x
  // 上端 a の上、帯より遠く
  assert_eq(
    drop_at(l, { x, y: a.y - band - 20.0, }),
    Some(Node(id=2, slot=Before)),
  )
  // 下端 b の下、帯より遠く
  assert_eq(
    drop_at(l, { x, y: b.y + b.h + band + 20.0, }),
    Some(Node(id=3, slot=After)),
  )
  // open_band を越えたら誰も取らない — 列の x に居たまま上下に離してもキャンセルできる
  assert_eq(drop_at(l, { x, y: b.y + b.h + open_band + 1.0, }), None)
  // 横は帯と同じ幅（slop）。列から外せば受けない
  assert_eq(
    drop_at(l, { x: b.x + b.w + slop + 1.0, y: b.y + b.h + band + 20.0, }),
    None,
  )
}

///|
test "通路の手前 near までは子（外側ゾーン）が帯に勝ち、先は次の列の帯が勝つ" {
  let l = drop_next_column()
  let a = box(l, 2).rect
  let c = box(l, 4).rect
  // c の帯（直前）に届く高さ。a の通路にも掛かる
  let y = c.y - 5.0
  let inside = { x: a.x + a.w + near - 5.0, y, }
  // a を掴んで外せば、この場所は c の帯が取る（帯は届いている）
  assert_eq(drop_at(l, inside, dragging=[2]), Some(Node(id=4, slot=Before)))
  // 居れば a の子が勝つ — 右に置いたのに兄弟になる、を防ぐ
  assert_eq(drop_at(l, inside), Some(Node(id=2, slot=Into)))
  // near を越えたら、そこは次の列の住人のもの
  assert_eq(
    drop_at(l, { x: a.x + a.w + near + 15.0, y, }),
    Some(Node(id=4, slot=Before)),
  )
}

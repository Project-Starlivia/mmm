// View の木 → 箱の配置。寸法は数で渡すので、DOM 無しで置き方だけを固定できる。

///|
/// 全部 100 × 30
fn size(_n : @view.Node, _cards : Array[Card], _buried : Int) -> Size {
  { w: 100, h: 30, }
}

///|
fn node(
  id : Int,
  label : String,
  children? : Array[@view.Node] = [],
  fold? : @tree.Fold? = None,
  blocks? : Array[@tree.Block] = [],
) -> @view.Node {
  { id, label: Some(label), fold, blocks, children, }
}

///|
fn root(n : @view.Node, sides? : Array[@tree.Side] = []) -> @view.Root {
  { node: n, sides, }
}

///|
fn box(l : Layout, id : Int) -> Box {
  l.boxes.get(id).unwrap()
}

///|
test "根は x = 0 で親を持たず、子は右へ gap.x 離れて親に繋がる" {
  let l = layout([root(node(1, "r", children=[node(2, "a")]))], size)
  assert_eq(box(l, 1).x, 0)
  assert_eq(box(l, 1).parent, None)
  assert_eq(box(l, 2).x, 100.0 + gap.x)
  assert_eq(box(l, 2).parent, Some({ id: 1, side: Right, }))
}

///|
test "親は第 1 子と最終子の中心の中点に立つ" {
  let l = layout(
    [root(node(1, "r", children=[node(2, "a"), node(3, "b"), node(4, "c")]))],
    size,
  )
  // 子の中心は 15, 55, 95（高さ 30 + 隙間 10）。中点 55 → 上端 40
  assert_eq(box(l, 1).y, 40)
  assert_eq(box(l, 2).y, 0)
  assert_eq(box(l, 4).y, 80)
}

///|
test "側は根の子が sides から受け、孫は親から継ぐ" {
  let l = layout(
    [
      root(
        node(1, "r", children=[
          node(2, "a"),
          node(3, "b", children=[node(4, "c")]),
        ]),
        sides=[Right, Left],
      ),
    ],
    size,
  )
  assert_eq(box(l, 3).x, -gap.x - 100.0)
  assert_eq(box(l, 3).parent, Some({ id: 1, side: Left, }))
  assert_eq(box(l, 4).x, box(l, 3).x - gap.x - 100.0)
  assert_eq(box(l, 4).parent, Some({ id: 3, side: Left, }))
}

///|
test "sides が足りなければ右" {
  let l = layout(
    [root(node(1, "r", children=[node(2, "a"), node(3, "b")]), sides=[Left])],
    size,
  )
  assert_eq(box(l, 2).parent.unwrap().side, Left)
  assert_eq(box(l, 3).parent.unwrap().side, Right)
}

///|
test "畳んだノードの下は置かず、埋もれた子孫の数だけ残る" {
  let folded = node(
    2,
    "a",
    children=[node(3, "b", children=[node(4, "c")])],
    fold=Some({ open: false, summary: None, }),
  )
  let l = layout([root(node(1, "r", children=[folded]))], size)
  assert_eq(l.order, [1, 2])
  assert_eq(l.boxes.contains(3), false)
  assert_eq(box(l, 2).buried, 2)
  assert_eq(box(l, 1).buried, 0)
}

///|
test "順は文書順（親が先、子はその後）" {
  let l = layout(
    [
      root(
        node(1, "r", children=[
          node(2, "a", children=[node(3, "x")]),
          node(4, "b"),
        ]),
      ),
    ],
    size,
  )
  assert_eq(l.order, [1, 2, 3, 4])
}

///|
test "木は縦に積まれ、隙間は gap.root" {
  let l = layout([root(node(1, "a")), root(node(2, "b"))], size)
  assert_eq(box(l, 1).y, 0)
  assert_eq(box(l, 2).y, 30.0 + gap.root)
  assert_eq(root_box(l).unwrap().node.id, 1)
}

///|
test "左右の側は、それぞれの中点が根の中心に乗る" {
  let l = layout(
    [
      root(node(1, "r", children=[node(2, "a"), node(3, "b"), node(4, "c")]), sides=[
        Right,
        Left,
        Left,
      ]),
    ],
    size,
  )
  // 右は a だけ（中心 15 → 根の中心 15）。左は b, c（中心 15, 55 → 中点 35）を 15 へ寄せる
  let r = box(l, 1).rect().center().y
  assert_eq(box(l, 2).rect().center().y, r)
  assert_eq(
    (box(l, 3).rect().center().y + box(l, 4).rect().center().y) / 2.0,
    r,
  )
  // 上へはみ出したぶんは押し下げられ、木は 0 から始まる
  assert_eq(box(l, 3).y, 0)
}

///|
test "同じ辺から 2 本以上出る線は、付け根を帯の中に配る" {
  let l = layout(
    [root(node(1, "r", children=[node(2, "a"), node(3, "b"), node(4, "c")]))],
    size,
  )
  // 帯は親の高さの 6 割 = 18。3 本なら -6, 0, +6（浮動小数なので 1e-9 で見る）
  assert_true((box(l, 2).fan + 6.0).abs() < 1.0e-9)
  assert_eq(box(l, 3).fan, 0)
  assert_true((box(l, 4).fan - 6.0).abs() < 1.0e-9)
  assert_eq(box(l, 1).fan, 0)
  let one = layout([root(node(1, "r", children=[node(2, "a")]))], size)
  assert_eq(box(one, 2).fan, 0)
}

///|
test "線は親の育つ辺（ずらし込み）から出て、子の入る辺へ入る" {
  let l = layout(
    [root(node(1, "r", children=[node(2, "a"), node(3, "b")]))],
    size,
  )
  // 親の中心 y = 35、右辺 x = 100。a の付け根は -4.5（帯 18 を 2 本で配る）
  assert_eq(edge_ends(l, 2), Some(({ x: 100, y: 30.5, }, { x: 145, y: 15, })))
  assert_eq(edge_ends(l, 1), None)
  assert_eq(edge_ends(l, 9), None)
}

///|
test "カードの矩形は箱の左上から見た座標。無い行は None" {
  let blocks : Array[@tree.Block] = [
    { id: 9, content: Link(text="t", href="https://x.example/", title=""), },
  ]
  let l = layout([root(node(1, "r", blocks~))], size)
  let b = box(l, 1)
  assert_eq(b.cards, [Link(title="t", url="https://x.example/")])
  assert_eq(card_rect(b, 0), Some({ x: 12, y: 34, w: 76, h: 18, }))
  assert_eq(card_rect(b, 1), None)
  // 中身の持ち主
  let (owner, i) = owner_of(l, 9).unwrap()
  assert_eq(owner.node.id, 1)
  assert_eq(i, 0)
  assert_eq(owner_of(l, 8) is None, true)
}

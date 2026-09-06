// 座標と線の形。マップの見た目はここから組み上がるので、
// ドロップ判定（ts の drop.test.ts）が立つ土台として固定しておく。

///|
let box : Rect = { x: 10, y: 20, w: 100, h: 40, }

///|
test "箱の中心と、線が触れる左右の辺の中点" {
  assert_eq(box.center(), { x: 60, y: 40, })
  assert_eq(box.right(), { x: 110, y: 40, })
  assert_eq(box.left(), { x: 10, y: 40, })
}

///|
test "育つ辺と入る辺は、枝の向きで左右が入れ替わる" {
  assert_eq(box.growth_edge(1), box.right())
  assert_eq(box.entry_edge(1), box.left())
  assert_eq(box.growth_edge(-1), box.left())
  assert_eq(box.entry_edge(-1), box.right())
  assert_eq(dir(Right), 1)
  assert_eq(dir(Left), -1)
}

///|
test "点から線分までの距離。端より外なら端までの距離になる" {
  let a : Pt = { x: 0, y: 0, }
  let b : Pt = { x: 10, y: 0, }
  assert_eq(dist_to_seg({ x: 5, y: 3, }, a, b), 3) // 真横
  assert_eq(dist_to_seg({ x: -4, y: 0, }, a, b), 4) // 手前の外
  assert_eq(dist_to_seg({ x: 14, y: 0, }, a, b), 4) // 先の外
  assert_eq(dist_to_seg({ x: 3, y: 0, }, a, a), 3) // 長さ 0 の線分
}

///|
test "折れ線の真ん中は、長さで測った中央" {
  let pts : Array[Pt] = [{ x: 0, y: 0, }, { x: 10, y: 0, }, { x: 10, y: 10, }]
  assert_eq(mid_of_polyline(pts), { x: 10, y: 0, })
}

///|
test "座標は小数 2 桁に丸める（d 属性を短く保つため）" {
  assert_eq(round2(1.23456), 1.23)
  assert_eq(round2(-1.005), -1)
}

///|
test "複数の箱を包む最小の箱" {
  assert_eq(
    union([{ x: 0, y: 10, w: 20, h: 5, }, { x: 100, y: 0, w: 10, h: 40, }]),
    Some({ x: 0, y: 0, w: 110, h: 40, }),
  )
}

///|
test "箱が 1 つなら、その箱そのもの" {
  let one : Rect = { x: 5, y: 5, w: 20, h: 20, }
  assert_eq(union([one]), Some(one))
}

///|
test "箱が無ければ None" {
  assert_eq(union([]), None)
}

// 画面外にある対象を指す針。何を指すかの決めと、位置と向きの算術を固定する。

///|
let flat : Camera = { k: 1, tx: 0, ty: 0, }

///|
/// その場所に置いた、ありふれた大きさの箱
fn at(x : Double, y : Double) -> Rect {
  { x, y, w: 100, h: 60, }
}

///|
test "画面の中に少しでも重なっていれば見えている。完全に外れていれば見えていない" {
  assert_true(is_visible({ x: 0, y: 0, w: 10, h: 10, }, flat, pane))
  assert_true(is_visible({ x: 790, y: 590, w: 100, h: 100, }, flat, pane)) // 角だけ重なる
  assert_true(!is_visible({ x: 900, y: 0, w: 10, h: 10, }, flat, pane)) // 右
  assert_true(!is_visible({ x: -100, y: 0, w: 50, h: 10, }, flat, pane)) // 左
  assert_true(!is_visible({ x: 0, y: -100, w: 10, h: 50, }, flat, pane)) // 上
  assert_true(!is_visible({ x: 0, y: 900, w: 10, h: 10, }, flat, pane)) // 下
}

///|
test "真右にある対象は右の縁を、真下は下の縁を指す" {
  let right = indicator_for({ x: 5000, y: 300, w: 0, h: 0, }, flat, pane)
  assert_true(almost(right.y, 300)) // 高さは変わらない
  assert_true(right.x < pane.width && right.x > pane.width / 2.0)
  assert_true(almost(right.angle, 0)) // 0度 = 真右
  let down = indicator_for({ x: 400, y: 9000, w: 0, h: 0, }, flat, pane)
  assert_true(almost(down.x, 400))
  assert_true(down.y < pane.height && down.y > pane.height / 2.0)
  assert_true(almost(down.angle, 90)) // 90度 = 真下
}

///|
test "縁ぎりぎりには置かない。パン・ズームしても world 上の位置関係で向きが決まる" {
  let ind = indicator_for({ x: 100000, y: 0, w: 0, h: 0, }, flat, pane)
  assert_true(ind.x < pane.width && ind.x > 0.0)
  let zoomed : Camera = { k: 3, tx: -1000, ty: -1000, }
  let far = indicator_for({ x: 5000, y: 5000, w: 0, h: 0, }, zoomed, pane)
  // 中心から見て右下方向のまま
  assert_true(far.angle > 0.0 && far.angle < 90.0)
}

///|
test "見失っているか — どれも見えていなければ。1 つでも見えていれば違う。1 つも無ければ針は出ない" {
  assert_true(is_lost([at(5000, 300), at(-5000, 0)], flat, pane))
  assert_true(!is_lost([at(-5000, 0), at(100, 100)], flat, pane))
  assert_true(is_lost([], flat, pane))
  assert_true(nearest([], flat, pane) is None)
}

///|
test "指す先 — 画面の中心にいちばん近いもの。近さは今の視点で測る" {
  assert_eq(
    nearest([at(5000, 300), at(1000, 300)], flat, pane),
    Some(at(1000, 300)),
  )
  // 画面を左右から挟んでいても、近いほう（箱の中心 -250 は 650、950 は 550）
  assert_eq(
    nearest([at(-300, 270), at(900, 270)], flat, pane),
    Some(at(900, 270)),
  )
  let a = at(0, 0)
  let b = at(1000, 0)
  assert_eq(nearest([a, b], flat, pane), Some(a))
  assert_eq(nearest([a, b], { k: 1, tx: -1000, ty: 0, }, pane), Some(b))
}

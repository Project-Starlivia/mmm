// 線の形。d 属性の綴りは ts が出していたものと同じにする（style.css も書き出しも同じ線を見る）。

///|
test "真横に並ぶ親子は直線で結ぶ" {
  assert_eq(edge_segs(100, 0), [L(100, 0)])
}

///|
test "段差があれば三次ベジェ 1 本" {
  match edge_segs(100, 40) {
    [C(_, _, _, _, _, _)] => ()
    _ => fail("三次ベジェ 1 本のはず")
  }
}

///|
test "d 属性は始点から始まり、終点で終わる" {
  assert_eq(
    edge_path({ x: 10, y: 20, }, { x: 110, y: 60, }),
    "M 10 20 C 18 30.8, 52 58, 110 60",
  )
  assert_eq(
    edge_path({ x: 10, y: 20, }, { x: 110, y: 20, }),
    "M 10 20 L 110 20",
  )
}

///|
test "数の綴りは JS と同じ。整数は小数点なし、-0 は 0" {
  assert_eq(num(1.0), "1")
  assert_eq(num(1.5), "1.5")
  assert_eq(num(-0.0), "0")
  assert_eq(num(round2(-0.001)), "0")
  assert_eq(num(0.07), "0.07")
}

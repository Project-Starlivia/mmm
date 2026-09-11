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
  // du 100, dv 40。h1 = (100 × 0.08, 40 × 0.27) = (8, 10.8) → 18 30.8、
  // h2 = (100 − 100 × 0.58, 40 − 40 × 0.05) = (42, 38) → 52 58
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
test "d 属性の数は web の num（JS の `${n}`）と同じ字 — 整数は小数点なし、-0 は 0" {
  assert_eq(1.0.to_string(), "1")
  assert_eq(1.5.to_string(), "1.5")
  assert_eq((-0.0).to_string(), "0")
  assert_eq(round2(-0.001).to_string(), "0")
  assert_eq(0.07.to_string(), "0.07")
}

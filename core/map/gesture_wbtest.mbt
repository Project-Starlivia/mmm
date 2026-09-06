// 指の台帳。「いま何本か」を取り違えると、2 本目を置いた瞬間に地図が
// 跳ねたり、1 本離しても掴んだままになったりする。

///|
test "1 本だけでは何も言わない。2 本目が乗ると pinch が始まり、動くと前後の位置が出る" {
  let f = Fingers::new()
  f.down(1, 10, 10)
  assert_eq(f.pinching(), false)
  assert_true(f.moved(1, 20, 20) is None)
  let g = Fingers::new()
  g.down(1, 0, 0)
  g.down(2, 100, 0)
  assert_eq(g.pinching(), true)
  assert_eq(
    g.moved(2, 140, 0),
    Some(
      (
        { a: { x: 0, y: 0, }, b: { x: 100, y: 0, }, },
        { a: { x: 0, y: 0, }, b: { x: 140, y: 0, }, },
      ),
    ),
  )
  // 動いた分だけを次の起点にする（覚え直さないと、2 回目以降が「最初の位置からの差」になって加速する）
  assert_eq(g.moved(2, 160, 0).unwrap().0.b, { x: 140, y: 0, })
  // 動いていない指は何も言わない
  assert_true(g.moved(2, 160, 0) is None)
}

///|
test "1 本離すと pinch は終わる。3 本目は組に入れない — 最初の 2 本を使い続ける" {
  let f = Fingers::new()
  f.down(1, 0, 0)
  f.down(2, 100, 0)
  f.up(2)
  assert_eq(f.pinching(), false)
  assert_true(f.moved(1, 50, 50) is None)
  // 途中で組が入れ替わると、指を足した瞬間に地図が跳ぶ
  let g = Fingers::new()
  g.down(1, 0, 0)
  g.down(2, 100, 0)
  g.down(3, 200, 0)
  assert_true(g.moved(3, 260, 0) is None)
  assert_eq(g.moved(2, 140, 0).unwrap().1.b, { x: 140, y: 0, })
}

///|
test "only: 0 本なら None、1 本ならその位置、2 本なら None。離せば残った指の「いま」の位置" {
  let f = Fingers::new()
  assert_true(f.only() is None)
  f.down(1, 10, 20)
  assert_eq(f.only(), Some({ x: 10, y: 20, }))
  f.down(2, 100, 0)
  assert_true(f.only() is None)
  // 着地した場所ではなく、離すまでに動いた「いま」の位置でないと、
  // パンを立て直したときに指の下から地図がずれる
  f.moved(1, 30, 40) |> ignore
  f.up(2)
  assert_eq(f.only(), Some({ x: 30, y: 40, }))
}

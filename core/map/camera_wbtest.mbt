// パン・ズーム・寄せの算術。符号を 1 つ間違えても「動きはする」ので、
// 目で気づけない。値として固定しておく。

///|
let pane : Pane = { width: 800, height: 600, }

///|
let v : Camera = { k: 1, tx: 60, ty: 60, }

///|
fn almost(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
test "world と画面は互いの逆" {
  let c : Camera = { k: 2.5, tx: -30, ty: 17, }
  let w = to_world(c, 400, 300)
  assert_true(almost(w.x * c.k + c.tx, 400))
  assert_true(almost(w.y * c.k + c.ty, 300))
}

///|
test "ズームしても、カーソルの下の world は動かない" {
  // これが崩れると、拡大するたびに見ていた場所が画面の外へ逃げる
  for
    start in (
      [{ k: 1, tx: 60, ty: 60, }, { k: 0.3, tx: -200, ty: 90, }] : Array[Camera]) {
    for delta in ([-300.0, -40, 40, 300] : Array[Double]) {
      let before = to_world(start, 512, 331)
      let after = to_world(zoom_at(start, 512, 331, delta), 512, 331)
      assert_true(almost(before.x, after.x) && almost(before.y, after.y))
    }
    for k in ([0.2, 0.5, 1, 2.5] : Array[Double]) {
      let before = to_world(start, 512, 331)
      let after = to_world(zoom_to(start, 512, 331, k), 512, 331)
      assert_true(almost(before.x, after.x) && almost(before.y, after.y))
    }
  }
}

///|
test "ホイールを上へ回すと拡大、下で縮小。倍率は上下の限界で止まる" {
  assert_true(zoom_at(v, 0, 0, -100).k > v.k)
  assert_true(zoom_at(v, 0, 0, 100).k < v.k)
  let mut c = v
  for _ in 0..<50 {
    c = zoom_at(c, 0, 0, -500)
  }
  assert_eq(c.k, max_zoom)
  for _ in 0..<50 {
    c = zoom_at(c, 0, 0, 500)
  }
  assert_eq(c.k, min_zoom)
  assert_eq(zoom_to(v, 0, 0, 99).k, max_zoom)
  assert_eq(zoom_to(v, 0, 0, 0.001).k, min_zoom)
}

///|
test "パンは倍率を変えない" {
  assert_eq(pan_by({ k: 2, tx: 10, ty: 20, }, 5, -7), { k: 2, tx: 15, ty: 13, })
}

///|
let cam_box : Rect = { x: 100, y: 100, w: 120, h: 30, }

///|
test "既に見えている箱では動かない" {
  assert_eq(pan_to_show(v, cam_box, pane, margin=40), v)
}

///|
test "左と上へはみ出していれば、余白のぶんだけ入れる" {
  let c = pan_to_show({ k: 1, tx: -150, ty: -120, }, cam_box, pane, margin=40)
  assert_eq(cam_box.x * c.k + c.tx, 40)
  assert_eq(cam_box.y * c.k + c.ty, 40)
}

///|
test "右と下へはみ出していれば、外縁が余白の内側に入る" {
  let c = pan_to_show({ k: 1, tx: 760, ty: 580, }, cam_box, pane, margin=40)
  assert_eq(cam_box.x * c.k + c.tx + cam_box.w * c.k, pane.width - 40.0)
  assert_eq(cam_box.y * c.k + c.ty + cam_box.h * c.k, pane.height - 40.0)
}

///|
test "寄せても倍率は変えない（キーで辿るたびに拡大したりしない）" {
  assert_eq(
    pan_to_show({ k: 0.5, tx: -900, ty: -900, }, cam_box, pane, margin=40).k,
    0.5,
  )
}

///|
test "全部を収める見え方は、中身の中心をペインの中心に置く" {
  let c = fit(
    [{ x: 0, y: 0, w: 100, h: 40, }, { x: 300, y: 200, w: 100, h: 40, }],
    pane,
    margin=60,
  ).unwrap()
  let cx = 200.0
  let cy = 120.0
  assert_true(almost(cx * c.k + c.tx, pane.width / 2.0))
  assert_true(almost(cy * c.k + c.ty, pane.height / 2.0))
}

///|
test "小さい文書でも 1 倍を超えて寄らない。大きい文書は収まるまで引くが、下限では止まる。箱が無ければ決めない" {
  assert_eq(fit([{ x: 0, y: 0, w: 10, h: 10, }], pane, margin=60).unwrap().k, 1)
  let wide = fit([{ x: 0, y: 0, w: 4000, h: 100, }], pane, margin=60).unwrap()
  assert_true(wide.k < 1.0 && wide.k > min_zoom)
  assert_eq(
    fit([{ x: 0, y: 0, w: 400000, h: 100, }], pane, margin=60).unwrap().k,
    min_zoom,
  )
  assert_true(fit([], pane, margin=60) is None)
}

///|
test "寄せる先は箱の中心を画面の中心に置く。倍率は変えない" {
  let c = center_on({ k: 2, tx: 999, ty: 999, }, cam_box, pane)
  assert_eq(c.k, 2)
  let cx = cam_box.x + cam_box.w / 2.0
  let cy = cam_box.y + cam_box.h / 2.0
  assert_true(almost(cx * c.k + c.tx, pane.width / 2.0))
  assert_true(almost(cy * c.k + c.ty, pane.height / 2.0))
}

///|
fn span(ax : Double, ay : Double, bx : Double, by : Double) -> Span {
  { a: { x: ax, y: ay, }, b: { x: bx, y: by, }, }
}

///|
test "2 本指を離すと拡大、近づけると縮小" {
  let from = span(100, 100, 200, 100)
  assert_true(pinch(v, from, span(50, 100, 250, 100)).k > v.k)
  assert_true(pinch(v, from, span(140, 100, 160, 100)).k < v.k)
}

///|
test "pinch は、2 点の中点の下の world を中点へ運ぶ" {
  // 拡大しながら指をずらしても、掴んでいた場所が指の下に留まる
  let from = span(100, 200, 300, 200) // 中点 (200, 200)
  let to = span(140, 260, 460, 260) // 中点 (300, 260)、距離は 1.6 倍
  let w = to_world(v, 200, 200)
  let after = pinch(v, from, to)
  assert_true(almost(w.x * after.k + after.tx, 300))
  assert_true(almost(w.y * after.k + after.ty, 260))
}

///|
test "距離が変わらない 2 本指は、ただのパン。重なっても倍率は壊れない" {
  assert_eq(pinch(v, span(0, 0, 100, 0), span(30, -20, 130, -20)), {
    k: 1,
    tx: 90,
    ty: 40,
  })
  // 距離 0 で割ると無限大が k に流れ込み、以降すべての描画が消える
  assert_eq(pinch(v, span(50, 50, 50, 50), span(60, 60, 80, 80)).k, v.k)
}

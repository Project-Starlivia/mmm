// 入力欄を SVG の上のどこに置くか。枠と余白は CSS ピクセルでズームに
// 追従しないので、world の単位で組んでから倍率を掛け、追従しないぶんを別に足す。

///|
fn place_box() -> Box {
  {
    node: node(2, "a"),
    parent: None,
    buried: 0,
    fan: 0,
    x: 10,
    y: 20,
    w: 100,
    h: 30,
    cards: [],
  }
}

///|
test "ラベル — 倍率 1: 箱の左上から枠のぶん外へ。字は箱の pad から始まる" {
  let p = label_place(place_box(), { k: 1, tx: 0, ty: 0, }, 30)
  assert_eq(p.left, 10.0 - label_border)
  assert_eq(p.top, 20.0 - label_border)
  assert_eq(p.width, 100.0 + label_border * 2.0)
  assert_eq(p.height, normal.h + label_border * 2.0)
  assert_eq(p.font_size, normal.px.to_double())
  assert_eq(p.padding, normal.pad)
}

///|
test "ラベル — 倍率 2: 位置と字と余白は倍になり、枠は倍にならない" {
  let p = label_place(place_box(), { k: 2, tx: 5, ty: 7, }, 30)
  assert_eq(p.left, 10.0 * 2.0 + 5.0 - label_border)
  assert_eq(p.top, 20.0 * 2.0 + 7.0 - label_border)
  assert_eq(p.width, 100.0 * 2.0 + label_border * 2.0)
  assert_eq(p.font_size, normal.px.to_double() * 2.0)
  assert_eq(p.padding, normal.pad * 2.0)
}

///|
test "ラベル — 字が箱より長ければ右へ伸びる。倍率が小さくても余白は最低ぶん残す" {
  let p = label_place(place_box(), { k: 1, tx: 0, ty: 0, }, 200)
  assert_eq(p.width, 200.0 + normal.pad * 2.0 + label_border * 2.0)
  let q = label_place(place_box(), { k: 0.1, tx: 0, ty: 0, }, 30)
  assert_eq(q.padding, label_min_pad)
}

///|
let card_rect_sample : Rect = { x: 40, y: 60, w: 100, h: 40, }

///|
test "カード — 倍率 1: 枠はカードの矩形に載り、余白は内側" {
  let p = card_place(card_rect_sample, { k: 1, tx: 0, ty: 0, }, 1, 8)
  assert_eq(p.left, card_rect_sample.x)
  assert_eq(p.top, card_rect_sample.y)
  assert_eq(p.width, card_rect_sample.w + card_border * 2.0)
  assert_eq(p.height, card_rect_sample.h + card_border * 2.0)
  assert_eq(p.padding, card_pad)
}

///|
test "カード — 倍率 2: 位置と余白は倍率に乗り、枠は乗らない" {
  let p = card_place(card_rect_sample, { k: 2, tx: 37, ty: -14, }, 1, 8)
  assert_eq(p.left, card_rect_sample.x * 2.0 + 37.0)
  assert_eq(p.top, card_rect_sample.y * 2.0 - 14.0)
  assert_eq(p.width, card_rect_sample.w * 2.0 + card_border * 2.0)
  assert_eq(p.padding, card_pad * 2.0)
  assert_eq(
    p.font_size,
    card_place(card_rect_sample, { k: 1, tx: 0, ty: 0, }, 1, 8).font_size * 2.0,
  )
}

///|
test "カード — 中身がカードに収まればぴったり、はみ出せば右・下へ伸びる" {
  let cam : Camera = { k: 1, tx: 0, ty: 0, }
  let small = card_place(card_rect_sample, cam, 1, 8)
  let wide = card_place(card_rect_sample, cam, 1, 400)
  assert_eq(wide.width, 400.0 + card_pad * 2.0 + card_border * 2.0)
  assert_eq(wide.height, small.height)
  let tall = card_place(card_rect_sample, cam, 20, 8)
  assert_true(tall.height > small.height)
  assert_eq(tall.width, small.width)
}

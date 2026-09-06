// 選択の値と、入力でそれがどう変わるか。箱は layout に組ませる（配置は layout_wbtest が固定済み）。

///|
/// 四方に pad だけ。端の伸びは無し
fn grow(pad : Double) -> Reach {
  { pad, edge: 0, }
}

///|
/// r(1) → a(2), b(3) → c(4)。b は左の枝
fn sel_l() -> Layout {
  layout(
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
}

///|
/// r(1) → a(2), b(3) → c(4)。みな右の枝、100 × 30。
/// r (0, 20) / a (145, 0) / b (145, 40) / c (290, 40)。端（子が見えない）は a と c
fn sel_m() -> Layout {
  layout(
    [
      root(
        node(1, "r", children=[
          node(2, "a"),
          node(3, "b", children=[node(4, "c")]),
        ]),
        sides=[Right, Right],
      ),
    ],
    size,
  )
}

///|
test "クリック — 選ぶ。Shift は anchor から文書順に範囲、Mod は足す・外す" {
  let l = sel_l()
  let one = click(none, 3, Plain, l.order)
  assert_eq(one, { ids: [3], anchor: Some(3), })
  assert_eq(click(one, 1, Shift, l.order), { ids: [1, 2, 3], anchor: Some(3), })
  assert_eq(click(one, 1, Mod, l.order), { ids: [1, 3], anchor: Some(1), })
  assert_eq(click({ ids: [1, 3], anchor: Some(1), }, 3, Mod, l.order), {
    ids: [1],
    anchor: Some(1),
  })
  // anchor が無ければ Shift も普通のクリック
  assert_eq(click(none, 2, Shift, l.order), { ids: [2], anchor: Some(2), })
}

///|
test "矩形 — 触れる箱を全部。anchor は文書順の最後" {
  let l = sel_l()
  // a は (100 + gap.x, 0) から 100 × 30
  let x = 100.0 + gap.x
  assert_eq(rubber(l, { x: x + 90.0, y: 20, w: 20, h: 20, }), {
    ids: [2],
    anchor: Some(2),
  })
  assert_eq(rubber(l, { x: -1000, y: -1000, w: 3000, h: 3000, }), {
    ids: [1, 2, 3, 4],
    anchor: Some(4),
  })
  assert_eq(rubber(l, { x: 5000, y: 5000, w: 1, h: 1, }), none)
}

///|
test "点 — どの箱に居るか。外なら None" {
  let l = sel_l()
  let a = box(l, 2)
  assert_eq(hit(l, a.x + 1.0, a.y + 1.0, grow(0)), Some(2))
  assert_eq(hit(l, a.x + a.w + 1.0, a.y, grow(0)), None)
}

///|
test "点 — 範囲のぶん箱の外でも当たる。角も範囲の矩形どおり" {
  // r は (0, 0) から 100 × 30、a は右隣 (145, 0) から。隙間は 100 〜 145
  let l = sel_l()
  assert_eq(hit(l, 105, 15, grow(8)), Some(1))
  assert_eq(hit(l, 105, 15, grow(0)), None)
  assert_eq(hit(l, 110, 15, grow(8)), None)
  assert_eq(hit(l, 107, 37, grow(8)), Some(1))
  assert_eq(hit(l, 109, 37, grow(8)), None)
}

///|
test "端の伸び — 子の見えない端だけ、枝の向きに edge。根と親は伸びない。左の枝は左へ" {
  let l = sel_l()
  let m = sel_m()
  let r : Reach = { pad: 8, edge: 60, }
  assert_eq(hit(m, 390.0 + 8.0 + 30.0, 55, r), Some(4)) // c の右 38 は far の中
  assert_eq(hit(m, 390.0 + 8.0 + 30.0, 55, grow(8)), None)
  assert_eq(hit(m, 245.0 + 8.0 + 20.0, 55, r), None) // b の右へは伸びない（子が居る）。c の帯(290 − 8)にも届かない
  assert_eq(hit(m, -8.0 - 30.0, 35, r), None) // 根の左へも伸びない
  assert_eq(hit(l, -290.0 - 8.0 - 30.0, 15, r), Some(4)) // 左の枝の端 c は左へ伸びる
  assert_eq(hit(l, -190.0 + 8.0 + 20.0, 15, r), None) // 右（親側）へは伸びない。親 b の帯(−145 − 8)にも届かない
}

///|
test "点 — 端の伸びだけで届く箱が居れば、y の近さ → x の近さで選ぶ" {
  // 端の a が右へ 60 伸びると、弟 b の子 c の列（x 290〜）に届く
  let m = sel_m()
  let r : Reach = { pad: 15, edge: 60, }
  // (285, 29): c の帯の中（dx 5, dy 11）。a は far だけで届き、y は a の行の中（dy 0）→ 行で読んで a
  assert_eq(hit(m, 285, 29, r), Some(2))
  // 伸びが無ければ直線距離で c
  assert_eq(hit(m, 285, 29, grow(15)), Some(4))
  // (285, 35): y は a も c も 5 → x が近い c
  assert_eq(hit(m, 285, 35, r), Some(4))
}

///|
test "点 — 余白が被ったら近い箱。同じ距離なら文書順の後ろ" {
  let l = sel_l()
  assert_eq(hit(l, 115, 15, grow(30)), Some(1))
  assert_eq(hit(l, 130, 15, grow(30)), Some(2))
  assert_eq(hit(l, 122.5, 15, grow(30)), Some(2))
}

///|
test "矢印 — 上下は同じ深さの列を端でループ、何も選んでいなければ先頭" {
  let l = sel_l()
  assert_eq(arrow(l, None, Down), Some(1))
  assert_eq(arrow(l, Some(2), Down), Some(3))
  assert_eq(arrow(l, Some(3), Down), Some(2))
  assert_eq(arrow(l, Some(2), Up), Some(3))
  // 根の列は 1 つだけなので自分に戻る
  assert_eq(arrow(l, Some(1), Down), Some(1))
  assert_eq(arrow(layout([], size), None, Down), None)
}

///|
test "矢印 — 左右は画面の向き。右の枝は ← が親、左の枝は鏡像。子が無ければ先頭へ" {
  let l = sel_l()
  assert_eq(arrow(l, Some(2), Left), Some(1))
  assert_eq(arrow(l, Some(1), Right), Some(2))
  assert_eq(arrow(l, Some(2), Right), Some(1)) // a に子は無い → 先頭
  assert_eq(arrow(l, Some(3), Right), Some(1)) // b は左の枝。→ が親
  assert_eq(arrow(l, Some(3), Left), Some(4)) // ← が子
  assert_eq(arrow(l, Some(1), Left), None) // 根に親は無い
  assert_eq(arrow_of("ArrowUp"), Some(Up))
  assert_eq(arrow_of("Enter"), None)
}

///|
test "Shift+矢印 — 行き先を足す。既に選んでいれば、いま居た側を外して縮める" {
  let two = extend_to({ ids: [2], anchor: Some(2), }, 3)
  assert_eq(two, { ids: [2, 3], anchor: Some(3), })
  assert_eq(extend_to(two, 2), { ids: [2], anchor: Some(2), })
  // 行き先が anchor 自身なら何もしない（同じ深さが 1 つだけ・回った先）
  assert_eq(extend_to({ ids: [1, 2], anchor: Some(1), }, 1), {
    ids: [1, 2],
    anchor: Some(1),
  })
}

///|
test "全部と、兄弟と親 — 同じ親の文書順で前後。根の兄弟は根どうし" {
  let l = sel_l()
  assert_eq(all(l), { ids: [1, 2, 3, 4], anchor: Some(4), })
  assert_eq(parent_of(l, 2), Some(1))
  assert_eq(parent_of(l, 1), None)
  assert_eq(prev_sibling(l, 3), Some(2))
  assert_eq(next_sibling(l, 2), Some(3))
  assert_eq(prev_sibling(l, 2), None)
  assert_eq(next_sibling(l, 3), None)
  assert_eq(next_sibling(l, 4), None)
  assert_eq(solo({ ids: [3], anchor: Some(3), }), Some(3))
  assert_eq(solo({ ids: [2, 3], anchor: Some(3), }), None)
}

// 寸法の規則。字の実測は「1 文字 7px」の物差しで置き換えて、数だけを固定する。

///|
fn leaf(label : String?, fold? : @tree.Fold? = None) -> @view.Node {
  { id: 1, label, fold, blocks: [], children: [], }
}

///|
/// 1 文字 7px。実測の代わり
fn seven(_font : Font, text : String) -> Double {
  text.char_length().to_double() * 7.0
}

///|
test "畳んだノードの字は summary > ラベル" {
  assert_eq(
    fold_name(leaf(Some("a"), fold=Some({ open: false, summary: Some("s"), }))),
    "s",
  )
  assert_eq(
    fold_name(leaf(Some("a"), fold=Some({ open: false, summary: None, }))),
    "a",
  )
  assert_eq(
    fold_name(leaf(Some(""), fold=Some({ open: false, summary: None, }))),
    "",
  )
}

///|
test "Implicit の字は空" {
  assert_eq(label_of(leaf(None)), "")
  assert_eq(label_of(leaf(Some(""))), "")
}

///|
test "カードの高さと、行の枠から中身までの余白" {
  assert_eq(row_h(Link(title="", url="")), 26)
  assert_eq(row_h(Image(path="", name="")), 76)
  assert_eq(row_h(Code(lang="", lines=["a", "b"])), 46)
  assert_eq(row_h(Break), 12)
  assert_eq(row_h(Details(open=false, summary=None, lines=["a"])), 26)
  assert_eq(row_h(Details(open=true, summary=None, lines=["a"])), 49)
  assert_eq(card_inset(Code(lang="", lines=[])), 5)
  assert_eq(card_inset(Link(title="", url="")), 4)
  assert_eq(card_inset(Break), 2)
  assert_eq(card_inset(Svg(markup="")), 6)
  assert_eq(card_bleed(Code(lang="", lines=[])), 5)
  assert_eq(card_bleed(Break), 0)
}

///|
test "row_top は i 枚目の上端。i = 枚数なら箱の高さ" {
  let cards = [Link(title="", url=""), Break]
  assert_eq(row_top(cards, 0), 30)
  assert_eq(row_top(cards, 1), 56)
  assert_eq(row_top(cards, 2), 68)
}

///|
test "箱の幅はいちばん広い行の実測 + 左右の余白、高さはラベル行 + カード行" {
  let size = node_size(seven)
  assert_eq(size(leaf(Some("ab")), [], 0), { w: 38, h: 30, })
  assert_eq(
    size(
      leaf(Some("ab")),
      [Link(title="t", url="u"), Code(lang="", lines=["x", "y"])],
      0,
    ),
    { w: 53, h: 102, },
  )
  // 画像は最低幅を持つ。空のラベルはプレースホルダの幅
  assert_eq(size(leaf(Some("")), [Svg(markup="")], 0), { w: 224, h: 106, })
  assert_eq(size(leaf(Some("")), [], 0).w, 7.0 * 7.0 + 24.0)
}

///|
test "畳んだノードは字を幅で詰め、バッジは詰めない" {
  let n = leaf(
    Some("abcdefghijklmnopqrstuvwxyz"),
    fold=Some({ open: false, summary: None, }),
  )
  assert_eq(hidden_label(n, 3, seven), "abcdefghijklm…  +3")
  assert_eq(node_size(seven)(n, [], 3), { w: 144, h: 24, })
  // 収まるなら詰めない
  assert_eq(
    hidden_label(
      leaf(Some("ab"), fold=Some({ open: false, summary: None, })),
      0,
      seven,
    ),
    "ab",
  )
}

///|
test "詰めの切り口はサロゲートペアの前半で止まらない" {
  let font : Font = { px: 11, mono: false, }
  // 😀 は UTF-16 で 2 単位。文字で数える物差しなら 3 文字（21px）に収まる
  assert_eq(clip_label("a😀bc", font, 21, seven), "a😀…")
  // 単位で数える物差しだと「a + 前半 + …」が 21px に収まってしまう。前半で切らず 1 つ戻す
  fn units(_font : Font, text : String) -> Double {
    text.length().to_double() * 7.0
  }

  assert_eq(clip_label("a😀bc", font, 21, units), "a…")
}

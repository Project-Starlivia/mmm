// copy — 選んだ部分木の原文を地番で切り出す。貼る側（Graft）の対。

///|
test "copy: 部分木を原文のまま。子・孫の行も一緒に" {
  // r(2) → a(3) → b(4) / c(5)
  let s = survey("# r\n\n## a\n\n### b\n\nbody\n\n## c\n")
  assert_eq(s.copy([3]), "## a\n\n### b\n\nbody\n")
  assert_eq(s.copy([2]), "# r\n\n## a\n\n### b\n\nbody\n\n## c\n")
}

///|
test "copy: 複数は文書順に空行で継ぐ。選んだ祖先の中の子孫は数えない" {
  let s = survey("# r\n\n## a\n\n### b\n\n## c\n")
  assert_eq(s.copy([5, 3]), "## a\n\n### b\n\n## c\n")
  assert_eq(s.copy([4, 3]), "## a\n\n### b\n")
}

///|
test "copy: 項目は入れ子ごと。容器の字下げは頭に残らない" {
  // a(2) → b(3) → c(4)
  let s = survey("- a\n  - b\n    - c\n")
  assert_eq(s.copy([3]), "- b\n    - c\n")
}

///|
/// 境界は中身の持ち主を変えないので、野菜の メモ は、境界で置き直された肉より下に
/// 書かれている。野菜を写すと、跨いだ肉とその手前の境界の水平線を抜いて継ぐ
test "copy: 置き直された行を跨ぐ持ち主は、跨いだ所を抜いて空行で継ぐ" {
  let md = "- 買い物\n  - 野菜\n\n    ---\n\n    - 肉\n\n    メモ\n\n    - 魚\n"
  let s = survey(md)
  assert_eq(s.copy([s.find("野菜").unwrap()]), "- 野菜\n\n    メモ\n")
  assert_eq(s.copy([s.find("買い物").unwrap()]), md)
}

///|
test "copy: 選んでいなければ空。知らない id は飛ばす" {
  let s = survey("# r\n")
  assert_eq(s.copy([]), "")
  assert_eq(s.copy([9]), "")
}

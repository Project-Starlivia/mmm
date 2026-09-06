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
test "copy: 選んでいなければ空。知らない id は飛ばす" {
  let s = survey("# r\n")
  assert_eq(s.copy([]), "")
  assert_eq(s.copy([9]), "")
}

///|
test "survey — is_node / empty / find / blocks" {
  let s = survey("# r\n\n## a\n\n---\n\n```\nx\n```\n")
  assert_eq(s.is_node(2), true)
  assert_eq(s.is_node(3), true)
  assert_eq(s.is_node(4), false)
  assert_eq(s.empty(), false)
  assert_eq(survey("").empty(), true)
  assert_eq(s.find("a"), Some(3))
  assert_eq(s.find("z"), None)
  assert_eq(s.blocks(3), [4, 5])
  assert_eq(s.blocks(2), [])
}

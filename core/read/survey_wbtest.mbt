// Survey — 打鍵 1 回ぶんの読み。木と地番への問い合わせを md の字で固定する。

///|
test "is_node / empty / find / blocks" {
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

///|
/// **読み解かなかった中身（散文）は誰にも見せない。** 印の付けようも矩形の
/// 引きようも無いので、id を配ると選んだ先で外れる
test "散文は中身に数えない" {
  let s = survey("# r\n\nprose\n\n---\n")
  assert_eq(s.blocks(2), [4])
}

///|
/// Implicit（`## ` を飛ばした深さ）は字を持たないのであって、空の字ではない
test "find は Implicit を名乗らせない" {
  let s = survey("# r\n\n### x\n")
  assert_eq(s.is_node(3), true)
  assert_eq(s.find(""), None)
  assert_eq(survey("# r\n\n## \n").find(""), Some(3))
}

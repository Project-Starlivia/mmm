// 文書の名前。ラベルをファイル名にする規則と、最初の根から導くこと。

///|
test "to_file_name: 使えない字で分けて - で繋ぐ。空白はそのまま" {
  assert_eq(to_file_name("設計/検討"), "設計-検討")
  assert_eq(to_file_name("A: B"), "A-B")
  assert_eq(to_file_name("a  b"), "a  b")
  assert_eq(to_file_name("x<y>z|w"), "x-y-z-w")
}

///|
test "to_file_name: 末尾の . と空白は落ちる。予約名には _ を足す。何も残らなければ空" {
  assert_eq(to_file_name("memo. "), "memo")
  assert_eq(to_file_name("CON"), "CON_")
  assert_eq(to_file_name("com3"), "com3_")
  assert_eq(to_file_name("comx"), "comx")
  assert_eq(to_file_name("///"), "")
  assert_eq(to_file_name(""), "")
}

///|
test "to_file_name: 250 バイトで切る。文字の境界で" {
  let long = "あ".repeat(100) // 300 バイト
  let cut = to_file_name(long)
  assert_eq(cut.char_length(), 83)
}

///|
test "name: 最初の根の字。Implicit と空は empty" {
  assert_eq(survey("# 設計メモ\n\n## a\n").name(), "設計メモ")
  assert_eq(survey("# a/b\n").name(), "a-b")
  assert_eq(survey("").name(), "empty")
  assert_eq(survey("### x\n").name(), "empty")
  assert_eq(survey("# ///\n").name(), "empty")
}

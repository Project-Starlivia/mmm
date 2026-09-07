// 持ち物の綴り

///|
test "key_of: 持ち物の綴りはここだけ" {
  assert_eq(key_of("theme"), "mmm.theme")
  assert_eq(key_of("way"), "mmm.exportWay")
  assert_eq(key_of("grab"), "mmm.grab")
}

// 色

///|
test "hex_of: 6 桁の hex だけ。# は有っても無くても" {
  assert_eq(hex_of("#7c5cff"), Some("#7c5cff"))
  assert_eq(hex_of(" 7C5CFF "), Some("#7C5CFF"))
  assert_eq(hex_of("#fff"), None)
  assert_eq(hex_of("red"), None)
  assert_eq(hex_of(""), None)
}

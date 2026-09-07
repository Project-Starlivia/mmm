// ロゴ

///|
test "logo_svg: 印の有無" {
  assert_true(logo_svg("#ff0000", false).has_prefix("<svg width=\"144\""))
  assert_false(logo_svg("#ff0000", false).contains("circle"))
  assert_true(logo_svg("#ff0000", true).contains("<circle cx=\"118\""))
  assert_true(logo_inner("currentColor").contains("fill=\"currentColor\""))
}

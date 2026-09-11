// 画像フォルダの状態の一言。宣言と許可の 2 つから言う — 純粋

///|
test "folder_caption: 言葉は宣言と許可の 2 つだけ。許可が無いときは宣言のパスを出す" {
  assert_eq(folder_caption(None, None), "no folder")
  assert_eq(folder_caption(None, Some("pics/")), "pics/, no access")
  assert_eq(folder_caption(Some("pics"), Some("pics/")), "pics")
  assert_eq(folder_caption(Some("pics"), None), "pics, not declared")
}

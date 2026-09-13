// クリップボードを読む窓口。happy-dom の窓から辿り、許しは permissions で断る

///|
/// ブラウザがクリップボードを読ませない（人が断った・組織の方針で切ってある）
extern "js" fn deny_clipboard(doc : @dom.Document) -> @js_async.Promise[Unit] =
  #| async (doc) => { (await doc.defaultView.navigator.permissions.query({ name: "clipboard-read" })).state = "denied"; }

///|
/// **断られたことは空に潰さない。** 空は「何も無い」、断られたのは「許せば通る」で、
/// 呼び手が言うことが違う（#308）
async test "read_clipboard / clipboard_image: 空は Some、断られれば None" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  assert_eq(read_clipboard(doc), Some(""))
  assert_true(clipboard_image(doc) is Some(None))
  write_clipboard(doc, "x").wait()
  assert_eq(read_clipboard(doc), Some("x"))
  deny_clipboard(doc).wait()
  assert_eq(read_clipboard(doc), None)
  assert_true(clipboard_image(doc) is None)
}

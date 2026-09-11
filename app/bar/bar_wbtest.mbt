// 帯の試験の道具。窓の用意はここ 1 つ — 各ファイルの試験はこれを借りる

///|
/// happy-dom の文書を 1 つ用意して渡し、済んだら閉じる
fn with_doc(f : (@dom.Document) -> Unit raise) -> Unit raise {
  let w = @test_utils.create_happy_window()
  defer w.close()
  f(w.document())
}

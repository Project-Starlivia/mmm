// 帯の試験の道具。窓の用意はここ 1 つ — 各ファイルの試験はこれを借りる

///|
/// happy-dom の文書を 1 つ用意して渡し、済んだら閉じる
fn with_doc(f : (@dom.Document) -> Unit raise) -> Unit raise {
  let w = @test_utils.create_happy_window()
  defer w.close()
  f(w.document())
}

///|
test "focus_bar: 帯の最初の押せるものへ。沈んだボタンは飛ばし、tabindex=0 の顔も数える。帯が無ければ何もしない" {
  with_doc(d => {
    let body = d.body().unwrap()
    focus_bar(d) // #bar が無い
    let bar = d.createElement("header")
    bar.setAttribute("id", "bar")
    body.append(bar.as_node())
    let logo = d.createElement("span")
    logo.setAttribute("tabindex", "0")
    let off = d.createElement("button")
    off.setAttribute("disabled", "")
    let on = d.createElement("button")
    for e in [off, logo, on] {
      bar.append(e.as_node())
    }
    focus_bar(d)
    let active : @dom.Element? = @core.identity_option(
      d.activeElement().as_any(),
    )
    match active {
      Some(a) => assert_true(@web.same(a, logo))
      None => fail("帯に焦点が落ちていない")
    }
  })
}

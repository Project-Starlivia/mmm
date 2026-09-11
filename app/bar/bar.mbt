// 帯そのもの（index.html の `#bar`）。並びは files / more / export、名乗りは name、
// ロゴと色は theme。ここに居るのは、帯へ焦点を落とすことだけ

///|
/// 帯へ抜ける（Escape）。**ペインは Tab を飲む** — 地図は子を足すのに、md は
/// 字下げに使うので、キーボードだけで帯やブラウザへ戻る道が他に無い（WCAG 2.1.2）。
/// 落ちる先は帯の最初の押せるもの。そこから Tab で帯を辿り、Shift+Tab でブラウザへ出る
pub fn focus_bar(doc : @dom.Document) -> Unit {
  guard doc.querySelector("#bar") is Some(bar) else { return }
  // `button` と `tabindex="0"` の両方（ロゴとファイル名は字ではなくボタンの顔）。
  // querySelectorAll は文書順に返すので、先頭が帯のいちばん左
  for e in bar.querySelectorAll("button:not([disabled]), [tabindex=\"0\"]") {
    @web.focus(e)
    return
  }
}

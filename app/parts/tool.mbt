// ペインの隅に浮く小さな道具の器（見た目は style.css の `.pane-tool`）。
//
// **押しても下へ抜けない。** 道具はペインの上に乗っているだけで、下の
// キャンバスとは別のものだから。マップは背景を押されると矩形選択を始めて
// ポインタを捕まえるので、抜けると pointerup がペインへ行き、**ボタンの
// click がそもそも起きない**。

///|
pub fn pane_tool(doc : @dom.Document, name : String) -> @dom.Element {
  let box = @web.html(doc, "div", "pane-tool " + name)
  @web.listen(box, "pointerdown", e => @web.stop(e))
  box
}

// 空のときの言い出し。**2 つのペインが同じ器を使う。**
//
// md とマップは、それぞれ**自分のペインでできること**だけを言う
// （md は `# 見出しを書く`、マップは `Enter を押す`）。片方に両方を書いて
// 隣のペインを指さす形だと、そのペインを隠したときに文言が嘘になる。
//
// 器を 1 つにしてあるのは、**対に見えることそのものが役**だから — 別々に
// 組むと、片方だけ字の大きさや寄せ方が変わって対の関係が崩れる。
//
// **出る理由は 1 つ**（まだノードが 1 つも無いか）。決めるのは `cycle`
// （app/app.mbt）ひとつで、そこから両方へ渡る — 片方だけ別の理由で出入りすると、
// 対ではなく別々の 2 つに見える。

///|
/// どちらのペインか。ペインは 2 つしか無い
pub(all) enum Pane {
  Md
  Map
}

///|
/// 言い出しの綴り。**2 つで 1 つ**なので、字もここに並べて持つ — 片方だけ
/// 別の場所で変わると、対が崩れる。真ん中がその一手そのもの
fn hint_words(pane : Pane) -> (String, String, String) {
  match pane {
    Md => ("Write a ", "# Title", " to start")
    Map => ("Press ", "Enter", " to start")
  }
}

///|
/// ペインの真ん中に浮かべる言い出し。真ん中の一手（`# Title` / `Enter`）だけが
/// **明るくなる**。
///
/// 太字にはしない — このアプリに太字は実質無く、沈む（`--ink-dim`）と
/// 立つ（`--ink`）の明るさの差が、hover でもフォーカスでも使っている
/// ただ 1 つの強調の軸。ヒント 2 つのために軸を増やさない。
pub fn pane_hint(doc : @dom.Document, pane : Pane) -> @dom.Element {
  let (before, act, after) = hint_words(pane)
  let box = @web.html(doc, "div", "pane-hint")
  // 見えているものは飾りで、読み上げには別の道がある
  // （md は `aria-placeholder`、マップはペイン自身の名前）
  box.setAttribute("aria-hidden", "true")
  let lit = @web.html_text(doc, "span", "act", act)
  // **文は 1 つの塊にまとめてから入れる。** 外側は真ん中へ寄せるための
  // flex なので、字を直に入れると 3 つが別々の flex アイテムになり、
  // 文の途中の空白（`Press ` の末尾、` to …` の先頭）が行組みで潰れる
  let line = doc.createElement("span")
  line.append(doc.createTextNode(before).as_node())
  line.append(lit.as_node())
  line.append(doc.createTextNode(after).as_node())
  box.append(line.as_node())
  box
}

// 写す（Mod+C / Mod+X）。選んだ部分木の原文を地番で切り出す。貼る側（core の
// Graft）が断片を形として読み直すので、深さも綴りも付け直さない。

///|
/// 選んだノードの原文を文書順に空行で継ぐ。地番の範囲は部分木を丸ごと覆う
/// （子の中身まで）ので、選んだ祖先の中の子孫には降りない（core の Delete /
/// MoveNode と同じ決め）。末尾は改行 1 つ。何も選んでいなければ空
pub fn Survey::copy(self : Survey, ids : Array[Int]) -> String {
  let chosen : Set[Int] = Set::from_array(ids)
  let parts : Array[String] = []
  fn walk(n : @view.Node) -> Unit {
    if chosen.contains(n.id) && self.spots.get(n.id) is Some(sp) {
      parts.push(
        trim_eol(String::unsafe_substring(self.md, start=sp.from, end=sp.to)),
      )
      return
    }
    for k in n.children {
      walk(k)
    }
  }

  for t in self.view.roots {
    walk(t.node)
  }
  if parts.length() == 0 {
    ""
  } else {
    parts.join("\n\n") + "\n"
  }
}

///|
/// 末尾の改行（\r\n の並び）を落とす
fn trim_eol(s : String) -> String {
  let mut end = s.length()
  while end > 0 && (s[end - 1] == '\n' || s[end - 1] == '\r') {
    end -= 1
  }
  String::unsafe_substring(s, start=0, end~)
}

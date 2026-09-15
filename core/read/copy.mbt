// 写す（Mod+C / Mod+X）。選んだ部分木の原文を切り出す。貼る側（core の
// Graft）が断片を形として読み直すので、深さも綴りも付け直さない。

///|
/// 選んだノードの原文を文書順に空行で継ぐ。部分木の原文（`cover`）を丸ごと写す
/// （子の中身まで）ので、選んだ祖先の中の子孫には降りない（core の Delete /
/// MoveNode と同じ決め）。部分木の外の物を跨いで割れた範囲も空行で継ぐ。
/// **切れはどれも行の頭から切り、継いだ後で共通の左余白を落とす** — 頭の切れだけ字下げを
/// 落とすと、割れた後ろの切れが手前の行の子に読まれる（肉と魚が兄弟でなくなる）。
/// 末尾は改行 1 つ。何も選んでいなければ空
pub fn Survey::copy(self : Survey, ids : Array[Int]) -> String {
  let chosen : Set[Int] = Set::from_array(ids)
  let parts : Array[String] = []
  fn walk(n : @tree.Node) -> Unit {
    if chosen.contains(n.id) && self.spots.get(n.id) is Some(_) {
      for r in self.cover(n.id) {
        let text = trim_eol(
          trim_bol(
            String::unsafe_substring(
              self.md,
              start=line_head(self.md, r.from),
              end=r.to,
            ),
          ),
        )
        if text != "" {
          parts.push(text)
        }
      }
      return
    }
    for k in n.children {
      walk(k)
    }
  }

  for t in self.doc.roots {
    walk(t.node)
  }
  if parts.length() == 0 {
    ""
  } else {
    @tree.dedent(parts.join("\n\n")) + "\n"
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

///|
/// 頭の空行を落とす。字下げは容器の桁なので残す（貼る側が断片の左余白を落とす）
fn trim_bol(s : String) -> String {
  let mut start = 0
  let mut line = 0
  while start < s.length() &&
        (
          s[start] == ' ' ||
          s[start] == '\t' ||
          s[start] == '\r' ||
          s[start] == '\n'
        ) {
    if s[start] == '\n' {
      line = start + 1
    }
    start += 1
  }
  String::unsafe_substring(s, start=line, end=s.length())
}

// 見出し行を書く・整える・探すための道具。コマンドの意味論は持たない。
// （どの `#` を何本書くか・どこに改行を挟むか・行き先の行をどう見つけるか）

///|
fn hashes(n : Int) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < n; i = i + 1 {
    sb.write_string("#")
  }
  sb.to_string()
}

///|
fn sanitize_label(label : String) -> String {
  let sb = StringBuilder::new()
  for ch in label.iter() {
    if ch == '\n' || ch == '\r' {
      sb.write_char(' ')
    } else {
      sb.write_char(ch)
    }
  }
  let s = sb.to_string()
  let mut a = 0
  let mut b = s.length()
  while a < b && is_space(cc(s, a)) {
    a = a + 1
  }
  while b > a && is_space(cc(s, b - 1)) {
    b = b - 1
  }
  sub(s, a, b)
}

///|
/// Dominant newline of the current document ("\r\n" or "\n").
fn nl() -> String {
  for i = 0; i < st.text.length(); i = i + 1 {
    if cc(st.text, i) == 10 {
      return if i > 0 && cc(st.text, i - 1) == 13 { "\r\n" } else { "\n" }
    }
  }
  "\n"
}

///|
/// True if block-boundary offset `at` is already preceded by a blank line
/// (or sits at the start of the text).
fn preceded_by_blank(at : Int) -> Bool {
  let mut p = at
  if p == 0 {
    return true
  }
  if cc(st.text, p - 1) != 10 {
    return false
  }
  p = p - 1
  if p > 0 && cc(st.text, p - 1) == 13 {
    p = p - 1
  }
  while p > 0 && is_space(cc(st.text, p - 1)) {
    p = p - 1
  }
  p == 0 || cc(st.text, p - 1) == 10
}

///|
/// Insert a new empty heading of `depth` at block boundary `at`.
/// Returns the edit plus the prefix length (the new heading line starts at
/// `at + prefix` once applied).
fn insert_heading_edit(at : Int, depth : Int) -> (Edit, Int) {
  let br = nl()
  let sb = StringBuilder::new()
  let mut prefix_len = 0
  if at > 0 && cc(st.text, at - 1) != 10 {
    sb.write_string(br)
    sb.write_string(br)
    prefix_len = br.length() * 2
  } else if !preceded_by_blank(at) {
    sb.write_string(br)
    prefix_len = br.length()
  }
  sb.write_string(hashes(depth))
  sb.write_string(" ")
  sb.write_string(br)
  if at != st.text.length() {
    sb.write_string(br)
  }
  (Edit::{ from: at, to: at, insert: sb.to_string(), removed: "" }, prefix_len)
}

///|
/// When a block reaching EOF is removed, its leading blank separator would
/// be left dangling at the end of the file; extend the deletion start
/// backwards to just after the previous non-blank line's newline.
fn tidy_del_start(ss : Int) -> Int {
  let mut q = ss
  while q > 0 {
    let c = cc(st.text, q - 1)
    if c == 10 || c == 13 || is_space(c) {
      q = q - 1
    } else {
      break
    }
  }
  if q == 0 {
    return 0
  }
  let mut r = q
  while r < ss && is_space(cc(st.text, r)) {
    r = r + 1
  }
  if r < ss && cc(st.text, r) == 13 {
    r = r + 1
  }
  if r < ss && cc(st.text, r) == 10 {
    r = r + 1
  }
  r // always <= ss: every advance above is guarded by `< ss`
}

///|
fn focus_node_at(hs : Int) -> Unit {
  st.focus = -1
  for nd in st.nodes {
    if nd.hs == hs {
      st.focus = nd.id
      break
    }
  }
}

///|
/// 同じ区間の中の前の兄弟。区間（`---` の区切り）をまたいだ相手は兄弟としない。
/// またぐのを許すと、reorder（Mod+↑）で区間の壁を越えてノードが飛び、
/// 区間の中身が入れ替わってしまう。indent も同じ理由で区間をまたがない。
fn prev_sibling(i : Int) -> Int {
  let nd = st.nodes[i]
  for j = i - 1; j >= 0; j = j - 1 {
    if st.nodes[j].depth < nd.depth {
      return -1
    }
    if st.nodes[j].depth == nd.depth {
      if st.nodes[j].group != nd.group {
        return -1
      }
      // same depth before any shallower heading == same parent
      return j
    }
  }
  -1
}

///|
/// 同じ区間の中の次の兄弟。理由は prev_sibling と同じ。
fn next_sibling(i : Int) -> Int {
  let nd = st.nodes[i]
  for j = i + 1; j < st.nodes.length(); j = j + 1 {
    if st.nodes[j].depth < nd.depth {
      return -1
    }
    if st.nodes[j].depth == nd.depth {
      if st.nodes[j].group != nd.group {
        return -1
      }
      return j
    }
  }
  -1
}

///|
/// Headings inside [ss, se) in document order (indexes into st.nodes).
fn subtree_nodes(ss : Int, se : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i = 0; i < st.nodes.length(); i = i + 1 {
    if st.nodes[i].hs >= ss && st.nodes[i].hs < se {
      out.push(i)
    }
  }
  out
}

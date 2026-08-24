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
  while a < b && is_space(code_at(s, a)) {
    a = a + 1
  }
  while b > a && is_space(code_at(s, b - 1)) {
    b = b - 1
  }
  slice(s, a, b)
}

///|
/// 書き足す改行。**常に LF**。
///
/// 読み込みで CRLF を LF へ正規化し、保存も LF で書く（src/app/io.ts）ので、
/// 文書の中に CR が残ることは無い。以前はここで「その文書の流儀」を毎回
/// 探していたが、アプリからは到達できない一般性だった。
let eol : String = "\n"

///|
/// True if block-boundary offset `at` is already preceded by a blank line
/// (or sits at the start of the text).
fn preceded_by_blank(at : Int) -> Bool {
  let mut p = at
  if p == 0 {
    return true
  }
  if code_at(st.text, p - 1) != 10 {
    return false
  }
  p = p - 1
  if p > 0 && code_at(st.text, p - 1) == 13 {
    p = p - 1
  }
  while p > 0 && is_space(code_at(st.text, p - 1)) {
    p = p - 1
  }
  p == 0 || code_at(st.text, p - 1) == 10
}

///|
/// Insert a new empty heading of `depth` at block boundary `at`.
/// Returns the edit plus the prefix length (the new heading line starts at
/// `at + prefix` once applied).
fn insert_heading_edit(at : Int, depth : Int) -> (Edit, Int) {
  let br = eol
  let sb = StringBuilder::new()
  let mut prefix_len = 0
  if at > 0 && code_at(st.text, at - 1) != 10 {
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
    let c = code_at(st.text, q - 1)
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
  while r < ss && is_space(code_at(st.text, r)) {
    r = r + 1
  }
  if r < ss && code_at(st.text, r) == 13 {
    r = r + 1
  }
  if r < ss && code_at(st.text, r) == 10 {
    r = r + 1
  }
  r // always <= ss: every advance above is guarded by `< ss`
}

///|
fn focus_node_at(from : Int) -> Unit {
  st.focus = -1
  for nd in st.nodes {
    if nd.from == from {
      st.focus = nd.id
      break
    }
  }
}

///|
/// Previous sibling at the same depth.
fn prev_sibling(i : Int) -> Int {
  let nd = st.nodes[i]
  for j = i - 1; j >= 0; j = j - 1 {
    if st.nodes[j].depth < nd.depth {
      return -1
    }
    if st.nodes[j].depth == nd.depth {
      // same depth before any shallower heading == same parent
      return j
    }
  }
  -1
}

///|
/// Next sibling at the same depth.
fn next_sibling(i : Int) -> Int {
  let nd = st.nodes[i]
  for j = i + 1; j < st.nodes.length(); j = j + 1 {
    if st.nodes[j].depth < nd.depth {
      return -1
    }
    if st.nodes[j].depth == nd.depth {
      return j
    }
  }
  -1
}

///|
/// ノード i の部分木に含まれる見出しの添字（自分を含む、文書順）。
///
/// 文書順なので部分木は必ず**連続した添字の並び**になる。毎回すべての
/// ノードを舐めていたころ、まとめて段下げすると「選んだ数 × ノード数」に
/// なっていた。
fn subtree_of(i : Int) -> Array[Int] {
  let out : Array[Int] = []
  let se = st.nodes[i].to
  let n = st.nodes.length()
  for j = i; j < n && st.nodes[j].from < se; j = j + 1 {
    out.push(j)
  }
  out
}

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
fn spaces(n : Int) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < n; i = i + 1 {
    sb.write_string(" ")
  }
  sb.to_string()
}

///|
/// 深さ d の構造行の接頭辞。**書く形はモード（st.list_from）が決める** —
/// 深さ b 未満は `#`、b 以上は 2 スペース刻みの `- `。
/// 読みは常に両方を受けるので、ここが書きの唯一の分岐になる。
///
/// **前提: モードと本文が揃っていること。** ここは字下げをモードだけから
/// 出すが、読み（`parser.mbt`）は「直近の見出しの深さ + 字下げの段数」で
/// 深さを決める。`set_list_from` を `reformat` なしで叩くと 2 つが食い違い、
/// 深さの書き直しが「同じ文字列での置換」になって段上げが不発になる
/// （兄弟がいると、深さは変わらないまま順序だけ入れ替わる）。
/// UI は必ず `setListFrom` の直後に `reformat` を通すので到達しない
/// （`src/main.ts` の書き方ピッカー）。直すなら字下げを直近の見出しから
/// 数える形に揃えることになるが、読み書き両方に触る作り替えになる。
fn prefix_for(depth : Int) -> String {
  let b = st.list_from
  if b == 0 || depth < b {
    hashes(depth) + " "
  } else {
    spaces(2 * (depth - b)) + "- "
  }
}

///|
/// ノード i の構造行を深さ new_depth の接頭辞に書き直す編集。
/// `#` を 1 本ずつ足し引きしていた頃と違い、**形の境界をまたぐ変更**
/// （見出し → リスト項目）も同じ 1 つの編集になる。
fn prefix_edit(i : Int, new_depth : Int) -> Edit {
  let nd = st.nodes[i]
  Edit::{
    from: nd.from,
    to: nd.label_start,
    insert: prefix_for(new_depth),
    removed: slice(st.text, nd.from, nd.label_start),
  }
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
/// ブロックの境目 `at` へ `body` を差し込む文字列と、その中で body が始まる位置。
/// `body` は末尾に `eol` を含んでいる前提。
///
/// **前後の空行の出し分けはここ 1 か所しか無い。** 見出し・本文の 1 行・区切りの
/// 3 つが同じ規則を別々に持っていて、直すときに揃わない危険があった。
fn block_insert(at : Int, body : String) -> (String, Int) {
  let sb = StringBuilder::new()
  let mut prefix_len = 0
  if at > 0 && code_at(st.text, at - 1) != 10 {
    sb.write_string(eol)
    sb.write_string(eol)
    prefix_len = eol.length() * 2
  } else if !preceded_by_blank(at) {
    sb.write_string(eol)
    prefix_len = eol.length()
  }
  sb.write_string(body)
  if at != st.text.length() {
    sb.write_string(eol)
  }
  (sb.to_string(), prefix_len)
}

///|
/// Insert a new empty heading of `depth` at block boundary `at`.
/// Returns the edit plus the prefix length (the new heading line starts at
/// `at + prefix` once applied).
fn insert_heading_edit(at : Int, depth : Int) -> (Edit, Int) {
  let (insert, prefix_len) = block_insert(at, prefix_for(depth) + eol)
  (Edit::{ from: at, to: at, insert, removed: "" }, prefix_len)
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

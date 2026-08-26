// 文書ぜんぶをいまのモードの正規形に整える。
//
// 接頭辞を書き直すだけでは足りない。**リストの形では、外の Markdown パーサが
// 木を同じに読めるかどうかが字下げと空行で決まる**:
//
//   - 中身の行が項目の中身の列まで字下げされていないと、そこでリストが閉じる。
//     続く項目は別のリストになり、深い字下げはコードブロックに化ける
//   - ラベルと中身の間に空行が無いと、中身がラベルの段落に融合する
//   - 兄弟の間の空行は要らない（詰めるのが慣習。CommonMark の tight list）
//
// 見出しの形は今までどおり「ブロックの間は空行 1 つ」。
//
// 中身の行は**塊ごと動かす**。その節点の中身のうち最も浅い字下げを基準にして
// 差を保つので、フェンスの中の相対的な字下げは崩れない。

///|
/// その節点の中身を置く列。見出しの下は 0、`  - x` の下はその項目の
/// ラベルが始まる列（= 印の列 + 2）。
fn content_col_of(i : Int) -> Int {
  let nd = st.nodes[i]
  if st.list_from == 0 || nd.depth < st.list_from {
    return 0
  }
  2 * (nd.depth - st.list_from) + 2
}

///|
/// 行 [a, b) が空白だけか。
fn blank_line(a : Int, b : Int) -> Bool {
  for p = a; p < b; p = p + 1 {
    if !is_space(code_at(st.text, p)) && code_at(st.text, p) != 13 {
      return false
    }
  }
  true
}

///|
/// 行頭の空白の幅（タブは 2 桁）と、中身が始まる位置。
fn indent_of(a : Int, b : Int) -> (Int, Int) {
  let mut p = a
  let mut col = 0
  while p < b && is_space(code_at(st.text, p)) {
    col = col + (if code_at(st.text, p) == 9 { 2 } else { 1 })
    p = p + 1
  }
  (col, p)
}

///|
/// 整形の編集。昇順・非重複で返す（apply_edit_set の約束）。
///
/// 構造行は接頭辞を、中身の行は字下げを書き直し、行の間の空行を
/// 「どちらかが中身なら 1 つ、構造どうしなら 0（リストの形のみ）」に揃える。
fn format_edits() -> Array[Edit] {
  let set : Array[Edit] = []
  let lines = scan_lines(st.text)
  let n = st.nodes.length()
  if n == 0 {
    return set
  }
  // 行 → その行を持つ節点の添字（構造行より前の行は -1）
  let owner : Array[Int] = Array::make(lines.length(), -1)
  let is_struct : Array[Bool] = Array::make(lines.length(), false)
  let mut k = 0
  for li = 0; li < lines.length(); li = li + 1 {
    while k + 1 < n && st.nodes[k + 1].from <= lines[li].start {
      k = k + 1
    }
    if st.nodes[k].from <= lines[li].start {
      owner[li] = k
      is_struct[li] = st.nodes[k].from == lines[li].start
    }
  }
  // 各節点の中身のうち、いちばん浅い字下げ（塊ごと動かすための基準）
  let base : Array[Int] = Array::make(n, -1)
  for li = 0; li < lines.length(); li = li + 1 {
    let o = owner[li]
    if o < 0 || is_struct[li] || blank_line(lines[li].start, lines[li].end) {
      continue
    }
    let (col, _) = indent_of(lines[li].start, lines[li].end)
    if base[o] < 0 || col < base[o] {
      base[o] = col
    }
  }
  // フェンスの中の行（開き行の次から閉じ行まで）。**中身はコードなので、
  // 空行を足したり詰めたりしてはいけない**。字下げだけ塊で動かす
  let inside : Array[Bool] = Array::make(lines.length(), false)
  for f in st.fences {
    for li = 0; li < lines.length(); li = li + 1 {
      if lines[li].start > f.start && lines[li].start <= f.end {
        inside[li] = true
      }
    }
  }
  // 直前に出した「中身のある行」が構造行だったか（空行の要否の判定用）
  let mut prev_struct = false
  let mut prev_seen = false
  let mut pending_blank_from = -1 // 詰めるべき空行の始まり
  for li = 0; li < lines.length(); li = li + 1 {
    let l = lines[li]
    let o = owner[li]
    if o < 0 {
      continue // 最初の構造行より前は触らない
    }
    if inside[li] {
      // 空行かどうかに関わらず、行の並びには触らない
      if !blank_line(l.start, l.end) {
        indent_edit(set, o, l, base)
      }
      prev_seen = true
      prev_struct = false
      pending_blank_from = -1
      continue
    }
    if blank_line(l.start, l.end) {
      if pending_blank_from < 0 {
        pending_blank_from = l.start
      }
      continue
    }
    // ---- 行の間の空行を揃える ----
    if prev_seen {
      let want_blank = st.list_from == 0 || !prev_struct || !is_struct[li]
      if want_blank {
        if pending_blank_from < 0 {
          // 足りない: この行の直前に 1 つ入れる
          set.push(Edit::{ from: l.start, to: l.start, insert: eol, removed: "" })
        } else if pending_blank_from < l.start - eol.length() {
          // 多すぎる: 1 つぶんだけ残す
          let keep = l.start - eol.length()
          set.push(Edit::{
            from: pending_blank_from,
            to: keep,
            insert: "",
            removed: slice(st.text, pending_blank_from, keep),
          })
        }
      } else if pending_blank_from >= 0 {
        // 要らない: まとめて落とす
        set.push(Edit::{
          from: pending_blank_from,
          to: l.start,
          insert: "",
          removed: slice(st.text, pending_blank_from, l.start),
        })
      }
    }
    pending_blank_from = -1
    prev_seen = true
    prev_struct = is_struct[li]
    // ---- 行そのもの ----
    if is_struct[li] {
      let e = prefix_edit(o, st.nodes[o].depth)
      if e.insert != e.removed {
        set.push(e)
      }
    } else {
      indent_edit(set, o, l, base)
    }
  }
  set
}

///|
/// 中身の行 1 本の字下げを、その節点の中身の列へ。**塊ごと動かす**ので、
/// その節点の中でいちばん浅い字下げ（base）との差は保たれる
/// — フェンスの中の相対的な字下げが崩れない。
fn indent_edit(
  set : Array[Edit],
  o : Int,
  l : Line,
  base : Array[Int],
) -> Unit {
  let (col, text_at) = indent_of(l.start, l.end)
  let want = content_col_of(o) + col - (if base[o] < 0 { col } else { base[o] })
  let indent = spaces(if want < 0 { 0 } else { want })
  let old = slice(st.text, l.start, text_at)
  if indent != old {
    set.push(Edit::{ from: l.start, to: text_at, insert: indent, removed: old })
  }
}

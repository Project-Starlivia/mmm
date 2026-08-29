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
/// 深さ `depth` の節点が中身を置く列。見出しの下は 0、`  - x` の下は
/// その項目のラベルが始まる列（= 印の列 + 2）。
fn content_col_for(depth : Int) -> Int {
  if st.list_from == 0 || depth < st.list_from {
    return 0
  }
  2 * (depth - st.list_from) + 2
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
///
/// `depth_of(i)` はノード i を**どの深さとして**書くかを決める。文書全体の
/// reformat では `st.nodes[i].depth`（そのまま）を渡す。貼り付けの relevel
/// では、断片を単独で読み直した depth ではなく、**貼り先での本当の深さ**を
/// 外から渡す — 断片だけを再走査すると、周りの見出しが無い分、入れ子の
/// 段数が浅く数え直されてしまうため（実際に踏んだ）。
fn format_edits(depth_of : (Int) -> Int) -> Array[Edit] {
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
  // 出す形の唯一の分岐点。ここだけ depth_of を通す
  let content_col = fn(o : Int) -> Int { content_col_for(depth_of(o)) }
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
  // 区切り行（生きている境界のもの）。**どのノードの中身でもない**ので、
  // 直前のノードの中身として字下げしてはいけない。owner だけで見ていたころは
  // 深い枝の下にある `---` がその枝の中身の列（深さ 6 なら 10 桁）まで
  // 押し込まれ、しかも 1 つの境界の 2 行のあいだに空行が入っていた
  // （`sep_body` が決して書かない形）。列はルートの中身の列に揃える —
  // そこなら外の CommonMark パーサから見てもリストは閉じない。
  let sep_line : Array[Bool] = Array::make(lines.length(), false)
  let sep_first : Array[Bool] = Array::make(lines.length(), false)
  for b in st.bounds {
    let mut first = true
    for li = 0; li < lines.length(); li = li + 1 {
      if lines[li].start >= b.start && lines[li].start < b.end {
        sep_line[li] = true
        sep_first[li] = first
        first = false
      }
    }
  }
  // 直前に出した「中身のある行」が構造行だったか（空行の要否の判定用）
  let mut prev_struct = false
  let mut prev_sep = false // 直前の「中身のある行」が区切り行だったか
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
        indent_edit(set, o, l, base, content_col)
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
      // 1 つの境界の中は空行なし（`sep_body` が書く形）。境界の手前と
      // 後ろは、どちらの形でも空行 1 つで区切る
      let want_blank = if sep_line[li] {
        sep_first[li] // 境界の 2 行目以降は詰める
      } else if prev_sep {
        true // 境界の直後は空行 1 つ
      } else {
        st.list_from == 0 || !prev_struct || !is_struct[li]
      }
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
    prev_sep = sep_line[li]
    // ---- 行そのもの ----
    if sep_line[li] {
      // 区切りはルート直下の話。**その木の根の中身の列**に揃える
      // （`sep_body` が書くのと同じ列。深い枝の中身の列まで押し込むと、
      // どの枝に属するのかを嘘で語ることになる）
      let want = spaces(content_col_for(st.nodes[root_index_of(o)].depth))
      let (_, text_at) = indent_of(l.start, l.end)
      let old = slice(st.text, l.start, text_at)
      if want != old {
        set.push(Edit::{ from: l.start, to: text_at, insert: want, removed: old })
      }
    } else if is_struct[li] {
      let e = prefix_edit(o, depth_of(o))
      if e.insert != e.removed {
        set.push(e)
      }
    } else {
      indent_edit(set, o, l, base, content_col)
    }
  }
  set
}

///|
/// 文書ぜんぶを、いま各ノードが持つ深さのまま正規形に整える
/// （`reformat` の中身。identity の depth_of で `format_edits` を呼ぶだけ）。
fn reformat_edits() -> Array[Edit] {
  format_edits(fn(i) { st.nodes[i].depth })
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
  content_col : (Int) -> Int,
) -> Unit {
  let (col, text_at) = indent_of(l.start, l.end)
  let want = content_col(o) + col - (if base[o] < 0 { col } else { base[o] })
  let indent = spaces(if want < 0 { 0 } else { want })
  let old = slice(st.text, l.start, text_at)
  if indent != old {
    set.push(Edit::{ from: l.start, to: text_at, insert: indent, removed: old })
  }
}

///|
/// ノード i の本文の末尾へ、1 行を追加する編集。前後の空行の出し分けは
/// block_insert（heading.mbt）に任せる。着地点は Node.content_end
/// （doc.mbt が has_content と同じ規則で計算し、snapshot にも同じ値を出す
/// — ここで再導出しない）。
///
/// **リストの形で書かれたノードなら、その項目の中身の列まで字下げする。**
/// 字下げしないと、外の Markdown パーサはそこでリストを閉じ、続く兄弟が
/// 迷子になる（貼り付け・ドロップ・お絵描き・リンクで実際に踏んだ）。
fn append_content_edit(i : Int, line : String) -> Edit {
  let at = st.nodes[i].content_end
  let col = content_col_for(st.nodes[i].depth)
  let body = if col > 0 { spaces(col) + line } else { line }
  let (insert, _) = block_insert(at, body + eol)
  Edit::{ from: at, to: at, insert, removed: "" }
}

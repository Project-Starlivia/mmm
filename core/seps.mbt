// `---` の境界と、グループ・左右。
//
// **どの区切り行が構造として効くかを決めるのはここだけ。** 行の並び（連続した
// かたまり）はパーサが数え、木の形を見た有効性の判定と、グループ番号・左右の
// 割り当てをここが持つ。
//
// 記法: `---` 1 本 = 分割（同じ側に次のグループ）、2 本以上 = 分割 + 切り替え
// （そこから先は反対側）。本数の偶奇に意味を持たせないのは、手で 1 本足した
// だけで遠くの表示が変わる形を避けるため。

///|
/// 有効な境界 1 つ。`flip` なら、ここから先のグループは反対側へ伸びる。
priv struct Bound {
  start : Int // かたまりの最初の区切り行の行頭
  end : Int // 最後の区切り行の次の行頭
  flip : Bool // 区切り行が 2 本以上
}

///|
/// 区切りのかたまりのうち、**構造として効くもの**だけ。
///
/// 有効なのは「直前にノード P があり、直後の最初のノード F が P の木のルートの
/// 直下」であるとき。この 1 つの判定だけで
///   - front matter の `---`（P が無い）
///   - 木をまたぐ `---`（F が別の木のルート = 親なし）
///   - 深い階層の `---`（F の親がルートでない）
/// が、特別扱い無しに全部落ちる。
fn valid_bounds(
  seps : Array[SepRun],
  heads : Array[Heading],
  pidx : Array[Int],
) -> Array[Bound] {
  let out : Array[Bound] = []
  let hn = heads.length()
  let mut k = 0
  for r in seps {
    // k = そのかたまりより後ろの最初のノード。区切りもノードも文書順なので
    // 巻き戻らない(両方を 1 度ずつ歩けば足りる)
    while k < hn && heads[k].from < r.start {
      k = k + 1
    }
    if k == 0 || k >= hn {
      continue
    }
    let mut root = k - 1
    while pidx[root] >= 0 {
      root = pidx[root]
    }
    if pidx[k] != root {
      continue
    }
    out.push(Bound::{ start: r.start, end: r.end, flip: r.lines >= 2 })
  }
  out
}

///|
/// 境界で範囲を切る。**切るのは「その境界の直前で終わるノード」だけ** —
/// 一律に切ると、子を全部含むはずのルートの範囲まで切れて、境界の後ろの
/// グループがルートの子でなくなる（v1 で実際に踏んだ）。
///
/// 切る相手は、境界の直後のノード F の行頭でちょうど終わっているノード。
/// 後ろから辿り、境界を越えて伸びるノード（ルート）に当たったら止める。
fn cut_ranges(
  bounds : Array[Bound],
  heads : Array[Heading],
  range_end : Array[Int],
) -> Unit {
  let hn = heads.length()
  let mut k = 0
  for b in bounds {
    while k < hn && heads[k].from < b.start {
      k = k + 1
    }
    if k >= hn {
      continue
    }
    let f = heads[k].from
    for i = k - 1; i >= 0; i = i - 1 {
      if range_end[i] > f {
        break // 境界を越えて伸びる = この境界で終わっていない
      }
      if range_end[i] == f {
        range_end[i] = b.start
      }
    }
  }
}

///|
/// 木ごとにグループ番号と左右を割る。
///
/// **グループはルート直下の話**だが、値は枝の中の全ノードに配る — UI が
/// 「この枝はどっち側か」を導き直さなくていいように（同じ規則が 2 か所に
/// あると、片方だけ直したときに静かに食い違う）。
fn assign_groups(bounds : Array[Bound]) -> Unit {
  let mut bi = 0
  let mut group = 0
  let mut left = false
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    while bi < bounds.length() && bounds[bi].start < nd.from {
      group = group + 1
      if bounds[bi].flip {
        left = !left
      }
      bi = bi + 1
    }
    if nd.parent == -1 {
      // 新しい木。番号も側も振り出しに戻る（各木が自分の区切りを読む）
      group = 0
      left = false
    }
    nd.group = group
    nd.left = left
  }
}

// ---- 境界を書く ----
//
// 書くのは**操作と掃除だけ**（ルート脇へのドラッグ / Mod+ドロップ / Flip side）。
// md を手打ちしたときは読むだけで、勝手に書き直さない。

///|
/// 境界 1 つぶんの本文。`flip` なら 2 行、そうでなければ 1 行。
///
/// **列はルートの形が決める。** リスト項目のルートなら、その項目の中身の列まで
/// 字下げする — 列 0 に書くと、外の CommonMark パーサはそこで外側のリストを
/// 閉じ、木そのものが割れる（insert_content と同じ理屈）。
fn sep_body(root_depth : Int, flip : Bool) -> String {
  let line = spaces(content_col_for(root_depth)) + "---" + eol
  if flip { line + line } else { line }
}

///|
/// 境界をブロックの境目 `at` へ書き入れる編集。前後の空行の出し分けは
/// 見出しの挿入（insert_heading_edit）と同じ式。
fn insert_sep_edit(at : Int, root_depth : Int, flip : Bool) -> Edit {
  let sb = StringBuilder::new()
  if at > 0 && code_at(st.text, at - 1) != 10 {
    sb.write_string(eol)
    sb.write_string(eol)
  } else if !preceded_by_blank(at) {
    sb.write_string(eol)
  }
  sb.write_string(sep_body(root_depth, flip))
  if at != st.text.length() {
    sb.write_string(eol)
  }
  Edit::{ from: at, to: at, insert: sb.to_string(), removed: "" }
}

///|
/// 既にある境界を、`flip` の正規形に書き直す編集。
fn set_sep_edit(b : Bound, root_depth : Int, flip : Bool) -> Edit {
  Edit::{
    from: b.start,
    to: b.end,
    insert: sep_body(root_depth, flip),
    removed: slice(st.text, b.start, b.end),
  }
}

///|
/// 境界を消す編集。**直後の空行も 1 つ道連れにする** — 残すと空行が 2 つ
/// 並んで、次に書くものの前後の空行の判定が狂う。
fn remove_sep_edit(b : Bound) -> Edit {
  let n = st.text.length()
  let mut to = b.end
  // 直後の空行 1 つぶん（あれば）
  let mut p = to
  while p < n && is_space(code_at(st.text, p)) {
    p = p + 1
  }
  if p < n && code_at(st.text, p) == 13 {
    p = p + 1
  }
  if p < n && code_at(st.text, p) == 10 {
    to = p + 1
  }
  Edit::{ from: b.start, to, insert: "", removed: slice(st.text, b.start, to) }
}

///|
/// ノード添字 → その木の根の添字。
fn root_index_of(i : Int) -> Int {
  let mut k = i
  while st.nodes[k].parent != -1 {
    let up = find_node(st.nodes[k].parent)
    if up < 0 {
      break
    }
    k = up
  }
  k
}

///|
/// その木（根の添字）の中にある境界だけ、文書順。グループ g の手前の境界は
/// `tree_bounds(root)[g - 1]`（グループは 0 始まり、境界を 1 つ越えるたび +1）。
fn tree_bounds(root : Int) -> Array[Bound] {
  let nd = st.nodes[root]
  let out : Array[Bound] = []
  for b in st.bounds {
    if b.start > nd.from && b.start < nd.to {
      out.push(b)
    }
  }
  out
}

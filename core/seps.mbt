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
/// block_insert（heading.mbt）に任せる。
fn insert_sep_edit(at : Int, root_depth : Int, flip : Bool) -> Edit {
  let (insert, _) = block_insert(at, sep_body(root_depth, flip))
  Edit::{ from: at, to: at, insert, removed: "" }
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

///|
/// `at` より手前で終わっている最後の境界。
fn last_bound_before(bounds : Array[Bound], at : Int) -> Bound? {
  let mut hit : Bound? = None
  for b in bounds {
    if b.end <= at {
      hit = Some(b)
    }
  }
  hit
}

///|
/// `at` 以降から始まる最初の境界。
fn first_bound_after(bounds : Array[Bound], at : Int) -> Bound? {
  for b in bounds {
    if b.start >= at {
      return Some(b)
    }
  }
  None
}

// ---- 掃除 ----
//
// **不変条件: どの操作の前後でも、操作対象でないグループの側は変わらない。**
//
// グループが空になると両脇の境界が隣り合う。読みの規則（1 本 = 分割 /
// 2 本以上 = 切り替え）は足し算にならないので、隣り合ったものは xor して
// 1 つに書き直す:
//   分割 + 分割 = 分割 / 分割 + 切り替え = 切り替え / 切り替え + 切り替え = 分割
//
// **触ってよいのは「直前まで境界として効いていた行」だけ。** 見分けるために、
// 編集の前に境界の位置を控え、ノード id と同じ仕掛け（map_offsets）で編集を
// またいで写す。手で書いた本文の `---` は控えに入らないので、決して触らない。
//
// ただし書き直し・削除は、境界 1 つぶんの区切り行のかたまり（run,
// `[b.start, b.end)`）ごと行う。手書きの `---` が空いたグループを挟んで
// 目印つきの境界と地続きに融合していれば、その行も同じ run に含まれて
// 書き直しの対象になる —— 融合した時点でその行はもう独立した本文ではなく、
// 境界の意味（行数）の一部になっているため。

///|
/// 掃除の目印 = 編集前に効いていた境界。位置は `map_offsets` で写すので
/// `Array[Int]`、flip は**同じ添字**の別配列（組の配列にすると写せない）。
priv struct SepMarks {
  at : Array[Int]
  flip : Array[Bool]
}

///|
fn sep_marks() -> SepMarks {
  let at : Array[Int] = []
  let flip : Array[Bool] = []
  for b in st.bounds {
    at.push(b.start)
    flip.push(b.flip)
  }
  SepMarks::{ at, flip }
}

///|
/// 位置 `at` にある区切り行のかたまり（境界として効いていなくても拾う）。
/// 掃除で「もう境界ではなくなった行」を消すのに使う。
fn dangling_run_at(at : Int) -> Bound? {
  for r in st.seps {
    if at >= r.start && at < r.end {
      return Some(Bound::{ start: r.start, end: r.end, flip: r.lines >= 2 })
    }
  }
  None
}

///|
/// その位置を含む木の、ルートの添字。木が無ければ -1。
fn root_index_at(at : Int) -> Int {
  for i = st.nodes.length() - 1; i >= 0; i = i - 1 {
    if st.nodes[i].from < at {
      return root_index_of(i)
    }
  }
  -1
}

///|
/// その位置を含む木の、ルートの深さ（境界を書く列を決めるのに要る）。
fn root_depth_at(at : Int) -> Int {
  let ri = root_index_at(at)
  if ri < 0 {
    1
  } else {
    st.nodes[ri].depth
  }
}

///|
/// `at` と同じ木の中で、`at` 以降にある最初の生きた境界。無ければ `None`。
/// 掃除が、無効になった境界の反転ぶんを畳む先を探すのに使う。
fn next_live_bound_after(at : Int) -> Bound? {
  let ri = root_index_at(at)
  if ri < 0 {
    return None
  }
  first_bound_after(tree_bounds(ri), at)
}

///|
/// 編集集合は昇順・非重複でなければならない（apply_edit_set の約束）。
/// **`set` をその場で並べ替える**（呼び出し側の配列そのものが変わる。
/// 新しい配列を返しているのではない）。
fn sort_edits(set : Array[Edit]) -> Unit {
  for i = 1; i < set.length(); i = i + 1 {
    let e = set[i]
    let mut j = i - 1
    while j >= 0 && set[j].from > e.from {
      set[j + 1] = set[j]
      j = j - 1
    }
    set[j + 1] = e
  }
}

///|
/// 空いたグループの境界を畳む。`from_set` 以降に積まれた編集集合をまたいで
/// 目印を写してから、いまの文書と突き合わせる。
///
/// 判断は 3 つ:
///   - いま効いている境界に**目印が 2 つ以上**入っている = 空いてくっついた。
///     正しい flip は行数ではなく**元の flip の xor**（1 本 + 1 本 = 2 行だが、
///     反転 0 回なので分割のまま、という食い違いがここで起きる）
///   - 目印がどの境界にも入っていない = もう境界として効いていない
///     （末尾のグループが空いた場合だけでなく、段下げで見出しの親が
///     ルートでなくなり valid_bounds の判定そのものを満たさなくなる
///     場合も含む）。その行は消すが、**反転ぶんは捨てない** — 同じ木の中で
///     それより後ろにある最初の生きた境界へ xor で畳む（無ければそこで
///     初めて捨てる）。隣り合わずに無効化した境界も、隣り合って空いた
///     境界とまったく同じ「反転を次へ渡す」規則の対象であり、経路が違う
///     だけで特別扱いする理由が無い
fn sweep_seps(marks : SepMarks, from_set : Int) -> Unit {
  for k = from_set; k < st.last_sets.length(); k = k + 1 {
    map_offsets(marks.at, st.last_sets[k])
  }
  let nb = st.bounds.length()
  let hit : Array[Int] = Array::make(nb, 0)
  let flip : Array[Bool] = Array::make(nb, false)
  // どの生きた境界にも入らなかった目印（添字）。除去と、後ろへの畳み込みの
  // 両方がこれを見る
  let dead : Array[Int] = []
  for k = 0; k < marks.at.length(); k = k + 1 {
    let m = marks.at[k]
    if m < 0 {
      continue // 編集そのものに飲まれて消えた -> 畳む先も無い
    }
    let mut found = -1
    for i = 0; i < nb; i = i + 1 {
      let b = st.bounds[i]
      if m >= b.start && m < b.end {
        found = i
        break
      }
    }
    if found >= 0 {
      hit[found] = hit[found] + 1
      if marks.flip[k] {
        flip[found] = !flip[found]
      }
    } else {
      dead.push(k)
    }
  }
  // 生きていない目印は、同じ木の中でそれより後ろにある最初の生きた境界へ
  // 反転ぶんを畳む
  let folded : Array[Bool] = Array::make(nb, false)
  for k in dead {
    match next_live_bound_after(marks.at[k]) {
      Some(b) =>
        for i = 0; i < nb; i = i + 1 {
          if st.bounds[i].start == b.start {
            folded[i] = true
            if marks.flip[k] {
              flip[i] = !flip[i]
            }
            break
          }
        }
      None => ()
    }
  }
  let set : Array[Edit] = []
  for i = 0; i < nb; i = i + 1 {
    // 目印が 2 つ以上 = 空いてくっついた。空行を挟んで地続きになった生の
    // 区切り行は、行数で読むと桁が合わない（1 本 + 1 本 = 2 行だが反転
    // 0 回）だけでなく、挟まった空行も正規形には無いので、xor が今の
    // flip とたまたま一致していても正規形に書き直して余りを削る。
    // 畳み込みを受けた境界も、反転ぶんが変わりうるので同じく書き直す
    if hit[i] >= 2 || folded[i] {
      set.push(set_sep_edit(st.bounds[i], root_depth_at(st.bounds[i].start), flip[i]))
    }
  }
  // 複数の目印が「もう効いていない」側に落ちても、地続きの生ランは 1 つに
  // 潰れていることがある（隣り合う末尾グループが 2 つ同時に空く等）。
  // 同じランを 2 度消そうとすると編集が重なって apply_edit_set が壊れるので、
  // ランの開始位置で重複を弾く
  let removed_runs : Array[Int] = []
  for k in dead {
    let m = marks.at[k]
    match dangling_run_at(m) {
      Some(b) => {
        let mut seen = false
        for s in removed_runs {
          if s == b.start {
            seen = true
            break
          }
        }
        if seen {
          continue
        }
        removed_runs.push(b.start)
        // 末尾のグループが空になった: 後ろに続く見出しがもう無いので、
        // 直後の空行ではなく手前の空行を EOF まで畳む
        // （cmd_delete が EOF に届く削除で tidy_del_start を使うのと同じ理屈）
        if b.end == st.text.length() {
          let from = tidy_del_start(b.start)
          set.push(
            Edit::{ from, to: b.end, insert: "", removed: slice(st.text, from, b.end) },
          )
        } else {
          set.push(remove_sep_edit(b))
        }
      }
      None => ()
    }
  }
  if set.length() > 0 {
    sort_edits(set)
    apply_sets([set], "")
  }
}

///|
/// 構造を変えるコマンドを、掃除つきで走らせる。掃除は同じトランザクションに
/// 積むので **undo は 1 回**。既にトランザクションが開いていればそれに乗る。
fn with_sweep(body : () -> Unit) -> Unit {
  let opened = match st.tx {
    None => {
      begin_tx("")
      true
    }
    Some(_) => false
  }
  let marks = sep_marks()
  let base = st.last_sets.length()
  body()
  let keep = st.focus
  sweep_seps(marks, base)
  st.focus = keep
  if opened {
    commit_tx()
  }
}

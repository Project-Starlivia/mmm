// ノードを動かすコマンド。D&D の移動・並べ替え・インデント。
// 移動はすべて「ブロックを消して別の場所に書き直す」1 セットの編集で、
// id は書き直した位置で拾い直す（move_block）。

///|
/// Indent: subtree headings gain one '#'; the node becomes the last child
/// of its previous sibling. No line moves. Skips nodes with no previous
/// sibling.
fn cmd_indent(ids : Array[Int]) -> Unit {
  with_sweep(fn() {
    let idxs = normalize_selection(ids)
    let set : Array[Edit] = []
    let keep : Array[Int] = []
    for k in idxs {
      if prev_sibling(k) >= 0 {
        keep.push(st.nodes[k].id)
        for m in subtree_of(k) {
          set.push(prefix_edit(m, st.nodes[m].depth + 1))
        }
      }
    }
    if set.length() == 0 {
      return
    }
    apply_sets([set], "")
    if keep.length() > 0 {
      st.focus = keep[0]
    }
  })
}

///|
/// Outdent: the subtree moves to just after its parent's subtree and every
/// heading in it loses one '#'. Runs per node inside one transaction.
fn cmd_outdent(ids : Array[Int]) -> Unit {
  let idxs = normalize_selection(ids)
  let todo : Array[Int] = []
  // reverse document order: outdenting later siblings first keeps the
  // original sibling order intact after every node moves past its parent.
  // 深さ 2 は据え置き。段上げすると `#` 1 個になり、同じツリーの中で
  // 浅くなるのではなく「別ツリーとして独立する」ので、驚きが大きい
  for k = idxs.length() - 1; k >= 0; k = k - 1 {
    if st.nodes[idxs[k]].depth >= 3 {
      todo.push(st.nodes[idxs[k]].id)
    }
  }
  if todo.length() == 0 {
    return
  }
  begin_tx("")
  let mut first_focus = -1
  for id in todo {
    let i = find_node(id)
    if i < 0 {
      continue
    }
    let nd = st.nodes[i]
    let pi = find_node(nd.parent)
    if pi < 0 {
      continue
    }
    let pe = st.nodes[pi].to
    if pe == nd.to {
      // already the last block in the parent: pure depth change
      let set : Array[Edit] = []
      for m in subtree_of(i) {
        set.push(prefix_edit(m, st.nodes[m].depth - 1))
      }
      apply_sets([set], "")
      focus_node_at(nd.from)
    } else {
      // unhide は nd.from より前のマーカー行を消しうるので、pe（親の
      // to）はunhide後に取り直さないと古いオフセットのまま挿入
      // 先を指してしまう
      let rehide = unhide_for_move([nd.id])
      let mi = find_node(nd.id)
      let pi2 = find_node(nd.parent)
      if mi >= 0 && pi2 >= 0 {
        move_block(mi, st.nodes[pi2].to, nd.depth - 1)
      }
      for rid in rehide {
        cmd_toggle_hidden(rid)
      }
    }
    if first_focus == -1 {
      first_focus = st.focus
    }
  }
  commit_tx()
  if first_focus != -1 {
    st.focus = first_focus
  }
}

///|
/// Move node i's subtree so its heading lands at `at` with depth `new_depth`.
/// `at` must be a block boundary outside the subtree. Sets st.focus to the
/// moved node's new id.
fn move_block(i : Int, at : Int, new_depth : Int) -> Unit {
  let nd = st.nodes[i]
  let old_id = nd.id
  let delta = new_depth - nd.depth
  // shift every heading in the block by delta '#'; remember each heading's
  // id and its offset inside the rebuilt block so ids survive the move
  let heads = subtree_of(i)
  let rels : Array[(Int, Int)] = []
  let sb = StringBuilder::new()
  let mut pos = nd.from
  let mut acc = 0
  for m in heads {
    let h = st.nodes[m]
    rels.push((h.id, h.from - nd.from + acc))
    // 接頭辞を目的の深さの正規形に書き直す。長さの差を積んで、
    // 各構造行の新しい相対位置（rels）を出す
    let np = prefix_for(h.depth + delta)
    acc = acc + np.length() - (h.label_start - h.from)
    sb.write_string(slice(st.text, pos, h.from))
    sb.write_string(np)
    pos = h.label_start
  }
  sb.write_string(slice(st.text, pos, nd.to))
  let mut moved = sb.to_string()
  // keep block boundaries tidy: blank-line separated, single newline at EOF
  let br = eol
  while moved.length() > 0 &&
        (
          code_at(moved, moved.length() - 1) == 10 ||
          code_at(moved, moved.length() - 1) == 13
        ) {
    moved = slice(moved, 0, moved.length() - 1)
  }
  let len = st.text.length()
  let del_from = if nd.to == len { tidy_del_start(nd.from) } else { nd.from }
  // an insertion point inside the widened deletion collapses onto its start
  let at2 = if at > del_from && at <= nd.from { del_from } else { at }
  // does the insertion point land at EOF once the old block is gone?
  let eof_effective = at2 == len || (nd.to == len && at2 == del_from)
  moved = if eof_effective { moved + br } else { moved + br + br }
  // context immediately before the insertion point in the post-delete text
  let ctx = if at2 == nd.to { del_from } else { at2 }
  let mut prefix_len = 0
  if !preceded_by_blank(ctx) {
    moved = br + moved
    prefix_len = br.length()
  }
  let del = Edit::{
    from: del_from,
    to: nd.to,
    insert: "",
    removed: slice(st.text, del_from, nd.to),
  }
  let ins = Edit::{ from: at2, to: at2, insert: moved, removed: "" }
  let set : Array[Edit] = if at2 <= del_from { [ins, del] } else { [del, ins] }
  apply_sets([set], "")
  let new_from = if at2 >= nd.to {
    at2 - (nd.to - del_from)
  } else {
    at2
  }
  // restore the block's original ids at their new positions
  let base = new_from + prefix_len
  let at_from : Map[Int, Int] = Map([]) // from -> node index
  for idx = 0; idx < st.nodes.length(); idx = idx + 1 {
    at_from[st.nodes[idx].from] = idx
  }
  for r in rels {
    let (rid, rel) = r
    match at_from.get(base + rel) {
      Some(idx) => st.nodes[idx].id = rid
      None => ()
    }
  }
  reindex() // id を貼り直したので表も作り直す
  recompute_parents()
  refresh_entry_after()
  st.focus = old_id
}

///|
/// 行き先が「動かす範囲の中」にある移動は成立しない。
/// コマンドの入口で丸ごと弾くためのチェック。
fn move_lands_outside(order : Array[Int], target : Int) -> Bool {
  let t = find_node(target)
  if t < 0 {
    return false
  }
  let t_hs = st.nodes[t].from
  for id in order {
    let i = find_node(id)
    if i >= 0 && t_hs >= st.nodes[i].from && t_hs < st.nodes[i].to {
      return false
    }
  }
  true
}

///|
/// pos: 0 = as last child of target, 1 = before target, 2 = after target.
fn cmd_move(ids : Array[Int], target : Int, pos : Int) -> Unit {
  begin_tx("")
  with_sweep(fn() {
    let order : Array[Int] = []
    for k in normalize_selection(ids) {
      order.push(st.nodes[k].id)
    }
    if !move_lands_outside(order, target) {
      return
    }
    let rehide = unhide_for_move(order)
    let first_focus = move_steps(ids, target, pos)
    for id in rehide {
      cmd_toggle_hidden(id)
    }
    if first_focus != -1 {
      st.focus = first_focus
    }
  })
  commit_tx()
}

///|
/// A -> B の線に C を落としたときの「割り込み」。C を B の直前へ動かしてから
/// B の部分木を 1 段下げるので、A -> C -> B になる。ドラッグ 1 回の操作なので
/// undo も 1 回で戻したい → 2 つの編集を同じトランザクションに積む。
fn cmd_move_as_parent(ids : Array[Int], target : Int) -> Unit {
  begin_tx("")
  with_sweep(fn() {
    let order : Array[Int] = []
    for k in normalize_selection(ids) {
      order.push(st.nodes[k].id)
    }
    if !move_lands_outside(order, target) {
      return
    }
    let rehide = unhide_for_move(order)
    let first_focus = move_steps(ids, target, 1)
    // 移動が一切起きなかったときに indent だけ走らせると、B が無関係な
    // 前の兄弟の下に潜ってしまう
    if first_focus != -1 {
      cmd_indent([target])
    }
    for id in rehide {
      cmd_toggle_hidden(id)
    }
    if first_focus != -1 {
      st.focus = first_focus
    }
  })
  commit_tx()
}

///|
/// st.hide_regions のインデックス。nd 自身の範囲だけを包んでいる hide 領域
/// （兄弟ごと包んでいるのではなく nd 単独）があればそれを返す。無ければ -1。
/// move / delete / outdent / reorder が「マーカーだけ外に取り残す」事故を
/// 避けるための共通の判定はここに一本化する。
fn sole_hide_region(nd : Node) -> Int {
  let mut idx = -1
  for i = 0; i < st.hide_regions.length(); i = i + 1 {
    let r = st.hide_regions[i]
    if r.open_next == nd.from && r.close_start == nd.to {
      idx = i
      break
    }
  }
  idx
}

///|
/// 移動の前に hide を外し、行き先で畳み直すための下ごしらえ。
///
/// hide のマーカーはノードの範囲の外にある（範囲に含めると、畳んだ子を
/// 削除したときにマーカーだけ残るため意図的にそうしてある）。そのため
/// 畳んだノードをそのまま動かすと、**マーカーが元の場所に置き去りになり**、
/// hide が黙って外れて空のマーカー対がゴミとして残っていた。
///
/// 対象は「その hide 領域の中身がちょうどそのノードだけ」の場合に限る。
/// 兄弟をまとめて包んでいる領域まで外すと、動かしていないノードの
/// hide 状態まで変わってしまう。
fn unhide_for_move(order : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for id in order {
    let i = find_node(id)
    if i < 0 || !st.nodes[i].hidden {
      continue
    }
    if sole_hide_region(st.nodes[i]) >= 0 {
      cmd_toggle_hidden(id)
      out.push(id)
    }
  }
  out
}

///|
/// 実際の移動。トランザクションは呼び出し側が張る（他のコマンドと 1 つに
/// まとめたいことがあるため）。最初に動かしたノードの id を返す。
fn move_steps(ids : Array[Int], target : Int, pos : Int) -> Int {
  let idxs = normalize_selection(ids)
  if idxs.length() == 0 {
    return -1
  }
  let order : Array[Int] = []
  for k in idxs {
    order.push(st.nodes[k].id)
  }
  let mut anchor = target
  let mut anchor_pos = pos
  let mut first_focus = -1
  for id in order {
    let i = find_node(id)
    let t = find_node(anchor)
    if i < 0 || t < 0 {
      continue
    }
    let nd = st.nodes[i]
    let tn = st.nodes[t]
    // reject drops inside the moving subtree
    if tn.from >= nd.from && tn.from < nd.to {
      continue
    }
    let (at, depth) = if anchor_pos == 0 {
      (tn.to, tn.depth + 1)
    } else if anchor_pos == 1 {
      (tn.from, tn.depth)
    } else {
      (tn.to, tn.depth)
    }
    if (at == nd.from || at == nd.to) && depth == nd.depth {
      // dropping where it already is (also covers "as last child" of the
      // parent it is already the last child of)
      anchor = id
      anchor_pos = 2
      if first_focus == -1 {
        first_focus = id
      }
      continue
    }
    move_block(i, at, depth)
    anchor = st.focus
    anchor_pos = 2
    if first_focus == -1 {
      first_focus = st.focus
    }
  }
  first_focus
}

///|
/// dir: -1 = swap with previous sibling, 1 = swap with next sibling.
fn cmd_reorder(id : Int, dir : Int) -> Unit {
  if find_node(id) < 0 {
    return
  }
  begin_tx("")
  with_sweep(fn() {
    // hide されたノード単独の並べ替えでマーカーが置き去りにならないよう、
    // 動かす前に外し、行き先で畳み直す（cmd_move と同じ手当て）
    let rehide = unhide_for_move([id])
    let i = find_node(id)
    if i < 0 {
      return
    }
    if dir < 0 {
      let p = prev_sibling(i)
      if p >= 0 {
        move_block(i, st.nodes[p].from, st.nodes[i].depth)
      }
    } else {
      let nx = next_sibling(i)
      if nx >= 0 {
        move_block(i, st.nodes[nx].to, st.nodes[i].depth)
      }
    }
    for rid in rehide {
      cmd_toggle_hidden(rid)
    }
  })
  commit_tx()
}

///|
/// そのノードの属するグループを**丸ごと反対側へ**。
///
/// 実体は「両脇の境界の flip を反転する」だけ。両方を反転するので、
/// **そのグループだけが移り、下のグループは 1 つも動かない**。
/// 手前に境界が無い（= 先頭のグループ）ときは、そのグループの**最初の枝の
/// 手前**に切り替えを書き足す — 「全部左」はこれで表せる。
///
/// 書き足す位置を「ルート見出しの直後」にしないのは、そこが**ブロックの
/// 境目ではない**ため（見出しの次の行は空行で、そこへ入れると空行が 2 つ
/// 並ぶ）。枝の行頭は必ずブロックの境目なので、前後の空行が正しく出る。
fn cmd_flip_side(id : Int) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  let ri = root_index_of(i)
  let root = st.nodes[ri]
  let root_id = root.id
  let g = st.nodes[i].group
  let bounds = tree_bounds(ri)
  let set : Array[Edit] = []
  // 後ろの境界（あれば）を先に積む — 編集は昇順でなければならない
  if g < bounds.length() {
    set.push(set_sep_edit(bounds[g], root.depth, !bounds[g].flip))
  }
  if g > 0 {
    set.push(set_sep_edit(bounds[g - 1], root.depth, !bounds[g - 1].flip))
  } else {
    // 先頭のグループ: その最初の枝の手前へ切り替えを書き足す
    let mut first_from = -1
    for nd in st.nodes {
      if nd.parent == root_id && nd.group == 0 {
        first_from = nd.from
        break
      }
    }
    if first_from < 0 {
      return // 直下の枝が無い = 動かすものが無い
    }
    set.push(insert_sep_edit(first_from, root.depth, true))
  }
  if set.length() == 0 {
    return
  }
  with_sweep(fn() {
    sort_edits(set)
    apply_sets([set], "")
  })
  st.focus = id
}

///|
/// 選んだ枝を、その側の**末尾**へ。ルートの脇へ素でドラッグしたときの実体。
///
/// 規則は 2 つだけ:
///   - その側にグループがある → 区切りは書かない。最後のグループの末尾へ入れる
///   - その側にグループが無い → ルートの範囲の末尾に切り替え + 枝
///
/// 「無い側」に置くとき手前は必ず反対側なので、**素のドラッグが書く境界は
/// 常に切り替え**（分割を書くことは無い）。
fn cmd_move_side_end(ids : Array[Int], root : Int, left : Bool) -> Unit {
  let ri = find_node(root)
  if ri < 0 {
    return
  }
  // その側の最後の直下の枝
  let mut last = -1
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    if nd.parent == root && nd.left == left {
      last = nd.id
    }
  }
  with_sweep(fn() {
    let order : Array[Int] = []
    for k in normalize_selection(ids) {
      order.push(st.nodes[k].id)
    }
    let rehide = unhide_for_move(order)
    if last >= 0 {
      // その側の最後のグループの末尾へ（区切りは書かない）
      ignore(move_steps(ids, last, 2))
    } else {
      // その側は空。ルートの最後の子にしてから、その手前に切り替えを書く
      let first = move_steps(ids, root, 0)
      if first >= 0 {
        let i = find_node(first)
        if i >= 0 {
          let at = st.nodes[i].from
          apply_sets([[insert_sep_edit(at, st.nodes[find_node(root)].depth, true)]], "")
        }
      }
    }
    for id in rehide {
      cmd_toggle_hidden(id)
    }
  })
}

///|
/// 選んだ枝を、`target` の直前 / 直後へ**新しいグループ**として置く。
///
/// 決め方は 1 つ: **置いた場所の手前と後ろの境界を、側がつながるように直す
/// （無ければ足す）**。既にあるグループの真ん中に置けば、その規則の結果と
/// してそのグループが 2 つに割れる（割るための特別な処理は持たない）。
fn cmd_move_new_group(
  ids : Array[Int],
  target : Int,
  before : Bool,
  left : Bool,
) -> Unit {
  let ti = find_node(target)
  if ti < 0 {
    return
  }
  let root_id = st.nodes[root_index_of(ti)].id
  with_sweep(fn() {
    // 1) まず動かす。境界を書くのは、位置が決まってから
    let order : Array[Int] = []
    for k in normalize_selection(ids) {
      order.push(st.nodes[k].id)
    }
    let rehide = unhide_for_move(order)
    // 動かした枝がそのグループで唯一のメンバーだったときは、両脇の境界が
    // くっついて生の行数がそのまま flip として読めてしまう（xor 前の値）。
    // ここで一度畳んでおかないと、直後に読む prev/next の側が
    // まだ畳んでいない生の値のままになり、want の判定を誤る
    let move_marks = sep_marks()
    let move_base = st.last_sets.length()
    let first = move_steps(ids, target, if before { 1 } else { 2 })
    for id in rehide {
      cmd_toggle_hidden(id)
    }
    sweep_seps(move_marks, move_base)
    let ri = find_node(root_id)
    if first < 0 || ri < 0 {
      return
    }
    let root_depth = st.nodes[ri].depth
    // 2) 動かした塊の範囲。**id は移動をまたいで生きている**ので、
    //    動かしたものを引き直して端を取る
    let mut head_from = -1
    let mut tail_to = -1
    for id in order {
      let i = find_node(id)
      if i < 0 {
        continue
      }
      let nd = st.nodes[i]
      if head_from < 0 || nd.from < head_from {
        head_from = nd.from
      }
      if nd.to > tail_to {
        tail_to = nd.to
      }
    }
    if head_from < 0 {
      return
    }
    // 3) 塊の手前・後ろにある「ルート直下の枝」の側
    let mut prev : Node? = None
    let mut next : Node? = None
    for nd in st.nodes {
      if nd.parent != root_id {
        continue
      }
      if nd.to <= head_from {
        prev = Some(nd)
      } else if nd.from >= tail_to && next is None {
        next = Some(nd)
      }
    }
    // 4) 手前と後ろの境界を、側がつながるように直す。
    //    後ろから積む（編集集合は昇順でなければならない）
    let bounds = tree_bounds(ri)
    let set : Array[Edit] = []
    match next {
      Some(nx) => {
        let want = left != nx.left
        // 塊と次の枝の**間**に境界があればそれを直す。無ければ足す
        match first_bound_after(bounds, tail_to) {
          Some(b) =>
            if b.start < nx.from {
              set.push(set_sep_edit(b, root_depth, want))
            } else {
              set.push(insert_sep_edit(tail_to, root_depth, want))
            }
          None => set.push(insert_sep_edit(tail_to, root_depth, want))
        }
      }
      None => () // 末尾に置いた = 後ろの境界は要らない
    }
    match prev {
      Some(pv) => {
        let want = pv.left != left
        match last_bound_before(bounds, head_from) {
          Some(b) =>
            if b.start >= pv.to {
              set.push(set_sep_edit(b, root_depth, want))
            } else {
              set.push(insert_sep_edit(head_from, root_depth, want))
            }
          None => set.push(insert_sep_edit(head_from, root_depth, want))
        }
      }
      None => {
        // 手前に枝が無い = 先頭のグループ。虚の「手前」は側 false（右）から
        // 始まると考える。ここでも Some(pv) の腕とまったく同じ規則
        // 「既にある境界は必ず正す」にかける — 手前に枝が無くても、
        // ルート直後に境界が既にある（左始まりの文書）ことはあるため、
        // それを無視すると古い側がそのまま塊に被ってしまう
        // （手前に「境界を正す相手」が居ない、というだけで判定式は同じ）。
        // 違いは「境界が無いとき」だけ: 新しく書くのは側を変えたいときに限る
        // （書く境界の位置は head_from = 枝自身の行頭。ルート見出しの直後は
        // ブロックの境目ではないため書けない — cmd_flip_side と同じ理由）
        let want = left
        match last_bound_before(bounds, head_from) {
          Some(b) => set.push(set_sep_edit(b, root_depth, want))
          None =>
            if want {
              set.push(insert_sep_edit(head_from, root_depth, want))
            }
        }
      }
    }
    if set.length() > 0 {
      sort_edits(set)
      apply_sets([set], "")
    }
  })
}

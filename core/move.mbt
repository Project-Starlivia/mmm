// ノードを動かすコマンド。D&D の移動・並べ替え・インデント。
// 移動はすべて「ブロックを消して別の場所に書き直す」1 セットの編集で、
// id は書き直した位置で拾い直す（move_block）。

///|
/// Indent: subtree headings gain one '#'; the node becomes the last child
/// of its previous sibling. No line moves. Skips nodes with no previous
/// sibling.
///
/// **グループの壁で止まる**（`Tab` は Alt+↑↓ と同じ扱い。cmd_reorder と同じ
/// 判定）。壁を越えて子にすると、その境界を巻き込んで無関係なグループの側
/// まで動いてしまう — 壁を越える版は存在しない（Mod+Alt+↑↓ に Tab 相当は無い）。
fn cmd_indent(ids : Array[Int]) -> Unit {
  with_sweep(fn() {
    let idxs = normalize_selection(ids)
    let set : Array[Edit] = []
    let keep : Array[Int] = []
    for k in idxs {
      let peer = prev_sibling(k)
      if peer >= 0 && st.nodes[peer].group == st.nodes[k].group {
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
///
/// **掃除を通さない**（with_sweep で包んでいない）。段上げは深さを浅く
/// するだけで境界を空けないので、ふだんは掃除の出番が無い —
/// ただし手書きの無効な `---`（valid_bounds を満たしていなかった行）を
/// 段上げが**有効化してしまう**ことはある。見出しが浅くなってルート直下の
/// 深さに達すると、次の再構築でその `---` がそのまま境界として読まれる
/// （例: `## a` の下の深い `---` は無効だが、その直後の見出しを 2 回
/// 段上げしてルート直下まで浅くすると有効になり、後続グループの側が
/// 動く）。これはテキストから素直に導き直した結果であり、掃除で防ぐ
/// 種類の副作用ではないので、挙動はそのままにする。
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
/// 落とし先が畳んであれば先に開く。**着地点を計算する前に呼ぶこと。**
///
/// hide のマーカーはノードの範囲の外にあるので、畳んだままの相手の `to`
/// （= 閉じマーカーの手前）へ挿し込むと、動かした枝が領域の中に入り、
/// マップから消えて `+N` バッジに呑まれる。予告線は普通の挿入に見えるので
/// 「惜しい」の中でも最悪の類。`unfold_before_add` と同じ理由。
///
/// **落とし先を自分で導き出すコマンドは、導き出した相手に対して呼ぶ**
/// （`cmd_move_side_end` の `last` のように、利用者が指した相手とは限らない）。
fn unfold_target(id : Int) -> Unit {
  let i = find_node(id)
  if i >= 0 && st.nodes[i].hidden {
    cmd_toggle_hidden(id)
  }
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
    let ti = find_node(target)
    let target_folded = ti >= 0 && st.nodes[ti].hidden
    unfold_target(target)
    let rehide = unhide_for_move(order)
    let before = st.text
    let first_focus = move_steps(ids, target, pos)
    // **空振りなら、開いた落とし先は畳み直す。** 「もう其処に居る」かどうかは
    // 開いたあとの位置でしか判定できない（畳んだままだと `to` が閉じマーカーの
    // 手前を指す）ので、開くのが先になる。位置が 1 つも変わらなかったときに
    // 畳みだけ解けて、埋もれていた子が湧いて見えるのを防ぐ。本文が元に戻れば
    // `commit_tx` が「変わっていない」と見て undo にも積まない
    if target_folded && st.text == before {
      cmd_toggle_hidden(target)
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
    unfold_target(target)
    let rehide = unhide_for_move(order)
    let first_focus = move_steps(ids, target, 1)
    // 移動が一切起きなかったときに indent だけ走らせると、B が無関係な
    // 前の兄弟の下に潜ってしまう
    if first_focus != -1 {
      cmd_indent([target])
    }
    for id in rehide {
      // **子が増えた枝は畳み直さない。** 割り込みでは掴んだ枝が相手の親に
      // なるので、畳み直すと相手（と其の子孫）まで領域に呑まれて消える。
      // `unfold_before_add` が「足したら開いたままにする」のと同じ理由。
      if first_focus == -1 || id != first_focus {
        cmd_toggle_hidden(id)
      }
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
/// **位置のバイト厳密一致では狭すぎる。** マーカーと見出しのあいだに空行が
/// 1 行あるだけで外れ、マーカーが置き去りになって空の対がゴミとして残り、
/// hidden も黙って落ちていた（`docs/spec.md` はマーカーの判定を
/// 「エディタや GitHub と同じ」= 寛容と明言しており、読む側は実際に緩い。
/// 動かす/消す/足す側だけが厳しかった）。あいだが空白だけなら同じとみなす。
fn sole_hide_region(nd : Node) -> Int {
  let mut idx = -1
  for i = 0; i < st.hide_regions.length(); i = i + 1 {
    let r = st.hide_regions[i]
    let head_ok = r.open_next <= nd.from && is_blank_range(r.open_next, nd.from)
    let tail_ok = r.close_start >= nd.to && is_blank_range(nd.to, r.close_start)
    if head_ok && tail_ok {
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
/// `cross` ならグループの壁を越える（越えた先の側になる）。
fn cmd_reorder(id : Int, dir : Int, cross : Bool) -> Unit {
  if find_node(id) < 0 {
    return
  }
  begin_tx("")
  with_sweep(fn() {
    // hide されたノード単独の並べ替えでマーカーが置き去りにならないよう、
    // 動かす前に外し、行き先で畳み直す（cmd_move と同じ手当て）
    let rehide = unhide_for_move([id])
    let i = find_node(id)
    if i >= 0 {
      let peer = if dir < 0 { prev_sibling(i) } else { next_sibling(i) }
      // グループの壁。越えるのは cross のときだけ（普段の並べ替えで
      // 側が変わると、押した本人にも何が起きたか分からない）
      let ok = peer >= 0 && (cross || st.nodes[peer].group == st.nodes[i].group)
      if ok {
        let at = if dir < 0 { st.nodes[peer].from } else { st.nodes[peer].to }
        move_block(i, at, st.nodes[i].depth)
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
  // 手前の境界は、このグループが**反対側**になるように整える。
  // 先頭のグループでは「要らない境界は消す」まで含めて before_sep_edit が持つ
  let mut first_from = -1
  for nd in st.nodes {
    if nd.parent == root_id && nd.group == g {
      first_from = nd.from
      break
    }
  }
  if first_from < 0 {
    return // 直下の枝が無い = 動かすものが無い
  }
  let mut prev : Node? = None
  for nd in st.nodes {
    if nd.parent == root_id && nd.to <= first_from {
      prev = Some(nd)
    }
  }
  match
    before_sep_edit(bounds, prev, first_from, root.depth, !st.nodes[i].left) {
    Some(e) => set.push(e)
    None => ()
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
/// 「無い側」に置くとき、書く境界の flip は**手前（ルート直下の最後の枝）の
/// 側との差**から出す。ルートに枝が 1 つも無ければ、手前は無いのでルート
/// 自身の側（右）とみなす — その場合、右脇へ落とすのは手前と同じ側なので
/// 境界は要らない（何も書かない）。枝が 1 つでもあれば、その側は必ず目的の
/// 側と反対（でなければ「無い側」ではない）なので、常に切り替えになる。
fn cmd_move_side_end(ids : Array[Int], root : Int, left : Bool) -> Unit {
  let ri = find_node(root)
  if ri < 0 {
    return
  }
  // その側の最後の直下の枝。**掴んでいる枝は数に入れない** — これから
  // 居なくなるので、着地点は残るほうの末尾でなければならない。数に入れて
  // いたころは、選択にその側の末尾が含まれているだけで `move_lands_outside`
  // が必ず false になり、**操作まるごとが黙って捨てられて**いた（枝を全部
  // 選んで片側へ寄せる、という最も素直な使い方が必ず踏む）。
  // 除いた結果 `last < 0` になれば、既にある「その側は空」の枝がそのまま
  // 正しい答えになる。UI 側の `lastKidOf` も同じ理由で掴んだ枝を除いている。
  let moving : Array[Int] = []
  for k in normalize_selection(ids) {
    for m in subtree_of(k) {
      moving.push(st.nodes[m].id)
    }
  }
  let mut last = -1
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    if nd.parent == root && nd.left == left && !moving.contains(nd.id) {
      last = nd.id
    }
  }
  with_sweep(fn() {
    let order : Array[Int] = []
    for k in normalize_selection(ids) {
      order.push(st.nodes[k].id)
    }
    // 行き先（その側の最後の枝、無ければルート）が動かす範囲の中にあれば
    // 何もしない（cmd_move / cmd_move_as_parent と同じ判定）
    if !move_lands_outside(order, if last >= 0 { last } else { root }) {
      return
    }
    // 着地点は**こちらで導いた** `last`。それが畳んでいれば、その閉じマーカーの
    // 手前へ挿し込むことになるので、先に開く
    if last >= 0 {
      unfold_target(last)
    }
    let rehide = unhide_for_move(order)
    if last >= 0 {
      // その側の最後のグループの末尾へ（区切りは書かない）
      ignore(move_steps(ids, last, 2))
    } else {
      // その側は空。ルートの最後の子にしてから、手前の境界を整える。
      //
      // **側を読む前に一度掃除する。** 動かした枝が単独グループだったときは
      // 両脇の境界が空行を挟んで地続きになり、生の行数がそのまま flip として
      // 読めてしまう（1 本 + 1 本 = 2 行 = 切り替え）。畳む前の側で `prev` を
      // 読むと `want` が反転し、**頼んだ側と反対に着地**していた。
      // `cmd_move_new_group` は同じ理由で既にこの手当てを持っている。
      let move_marks = sep_marks()
      let move_base = st.last_sets.length()
      let first = move_steps(ids, root, 0)
      sweep_seps(move_marks, move_base)
      if first >= 0 {
        // 塊の範囲は、動かしたものを id で引き直して出す（id は移動をまたいで生きる）
        let mut head_from = -1
        for id in order {
          let i = find_node(id)
          if i >= 0 && (head_from < 0 || st.nodes[i].from < head_from) {
            head_from = st.nodes[i].from
          }
        }
        let ri2 = find_node(root)
        if head_from >= 0 && ri2 >= 0 {
          // **手前の枝は、動かした後に本当に前に居るもの**。動かす塊自身を
          // 数えると、塊が全部だったとき「自分の今の側」を手前と誤読する
          let mut prev : Node? = None
          for nd in st.nodes {
            if nd.parent == root && nd.to <= head_from {
              prev = Some(nd)
            }
          }
          match
            before_sep_edit(
              tree_bounds(ri2), prev, head_from, st.nodes[ri2].depth, left,
            ) {
            Some(e) => apply_sets([[e]], "")
            None => ()
          }
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
  // target はルート直下でなければならない。深い場所を渡されると、区切りが
  // 枝の中に書かれてしまう（valid_bounds には落ちて側は動かないが、
  // 掃除の効かない無効な `---` が文書に溜まっていく）
  if st.nodes[ti].parent != root_id {
    return
  }
  with_sweep(fn() {
    // 1) まず動かす。境界を書くのは、位置が決まってから
    let order : Array[Int] = []
    for k in normalize_selection(ids) {
      order.push(st.nodes[k].id)
    }
    // 行き先が動かす範囲の中にあれば何もしない（cmd_move と同じ判定）
    if !move_lands_outside(order, target) {
      return
    }
    unfold_target(target)
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
    match before_sep_edit(bounds, prev, head_from, root_depth, left) {
      Some(e) => set.push(e)
      None => ()
    }
    if set.length() > 0 {
      sort_edits(set)
      apply_sets([set], "")
    }
  })
}

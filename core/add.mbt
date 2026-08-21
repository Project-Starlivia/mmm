// ノードを作るコマンド。子・兄弟・親・ルート。
// `#` の数は必ずテキスト上の深さ（raw_depth）から決める。構造上の深さは
// 区切りの後ろでは読み替えられていて、そのまま書くと「子を作ったのに兄弟」になる。

///|
/// 畳んだノードに何かを足すときは、先に開く。
///
/// 畳んだままだと、新しい見出しが hide 領域の中に生まれてマップに出ない。
/// 呼び出し側は focus に対して編集を開こうとするが、そのノードは描かれて
/// いないので入力欄も出ず、「何も起きないのに空の見出しだけ増える」状態に
/// なっていた。開いてから足せば、そのまま編集に入れる。
/// 戻り値は「開いたので、以降を同じトランザクションに積むべきか」。
/// tag を受け取るのは undo の粒度のため: 続く rename が同じ tag で
/// 1 つの undo に併合されるのは、エントリの tag が一致するときだけ。
fn unfold_before_add(i : Int, tag : String) -> Bool {
  let nd = st.nodes[i]
  if !nd.hidden {
    return false
  }
  for r in st.hide_regions {
    if r.open_next == nd.hs && r.close_start == nd.sub_end {
      begin_tx(tag)
      cmd_toggle_hidden(nd.id)
      return true
    }
  }
  false
}

///|
/// `unfold_before_add` を挟んでから `body` を走らせ、開いていたら
/// トランザクションを閉じる（focus は commit_tx が書き換えるので退避して
/// 戻す）。cmd_add_* 4 つがこの手順を個別に手書きしていたのをまとめた。
/// id が見つからなければ何もしない。
fn with_unfold(id : Int, tag : String, body : () -> Unit) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  let opened = unfold_before_add(i, tag)
  body()
  if opened {
    let keep = st.focus
    commit_tx()
    st.focus = keep
  }
}

///|
fn cmd_add_child(id : Int, tag : String) -> Unit {
  with_unfold(id, tag, fn() {
    let nd = st.nodes[find_node(id)]
    // `#` の数はテキスト上の深さから決める。構造上の深さ（区切りの後ろでは
    // 読み替えられる）を使うと、子を作ったつもりが兄弟になる
    let (e, prefix) = insert_heading_edit(nd.sub_end, nd.raw_depth + 1)
    apply_sets([[e]], tag)
    focus_node_at(nd.sub_end + prefix)
  })
}

///|
fn cmd_add_sibling(id : Int, tag : String) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  if st.nodes[i].depth == 1 {
    // ルートに兄弟は作らず子にする（`#` を増やすと別ツリーになってしまう）
    cmd_add_child(id, tag)
    return
  }
  with_unfold(id, tag, fn() {
    let nd = st.nodes[find_node(id)]
    let (e, prefix) = insert_heading_edit(nd.sub_end, nd.raw_depth)
    apply_sets([[e]], tag)
    focus_node_at(nd.sub_end + prefix)
  })
}

///|
/// Insert a new sibling ABOVE the node (keyboard `O`).
fn cmd_add_sibling_before(id : Int, tag : String) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  if st.nodes[i].depth == 1 {
    cmd_add_child(id, tag)
    return
  }
  with_unfold(id, tag, fn() {
    let nd = st.nodes[find_node(id)]
    let (e, prefix) = insert_heading_edit(nd.hs, nd.raw_depth)
    apply_sets([[e]], tag)
    focus_node_at(nd.hs + prefix)
  })
}

///|
/// Wrap the node in a NEW PARENT (keyboard `Shift+Tab`): a heading of the
/// node's depth is inserted just above it and the whole subtree gains one
/// '#'. 深さ 1（ルート）は包まない。包むともう 1 つの `#` ができて、
/// それは「同じツリーの親」ではなく別ツリーになってしまうため。
fn cmd_add_parent(id : Int, tag : String) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  if st.nodes[i].depth == 1 {
    return
  }
  with_unfold(id, tag, fn() {
    let nd = st.nodes[find_node(id)]
    let (head, prefix) = insert_heading_edit(nd.hs, nd.raw_depth)
    let set : Array[Edit] = [head]
    for m in subtree_nodes(nd.hs, nd.sub_end) {
      set.push(Edit::{
        from: st.nodes[m].hs,
        to: st.nodes[m].hs,
        insert: "#",
        removed: "",
      })
    }
    apply_sets([set], tag)
    focus_node_at(nd.hs + prefix)
  })
}

///|
fn cmd_add_root(tag : String) -> Unit {
  // 2 つ目以降の `#` も別ツリーとして出るようになったので、既にルートが
  // あっても足せる（前は「構造から外れて消える」ため止めていた）
  let at = st.text.length()
  let (e, prefix) = insert_heading_edit(at, 1)
  apply_sets([[e]], tag)
  focus_node_at(at + prefix)
}

///|
/// 側の末尾に新しい子を作る。ルートの左右の ＋ ボタンの実体。
///
/// その側に既にノードがあれば、いちばん下のノードの後ろに挿すだけ。
/// **左側が空のときだけ** `---` を 1 本書いてから見出しを置く
/// （cmd_move_side_end と同じ、区切りを増やす唯一の経路）。
/// 右側が空なら、最初の区切りの手前に置く。
fn cmd_add_side_end(left : Bool, tag : String) -> Unit {
  let ri = root_index()
  if ri < 0 {
    return
  }
  let rid = st.nodes[ri].id
  let mut at = -1
  for nd in st.nodes {
    if nd.parent == rid && (nd.group % 2 == 1) == left {
      at = nd.sub_end
    }
  }
  if at >= 0 {
    let (e, prefix) = insert_heading_edit(at, 2)
    apply_sets([[e]], tag)
    focus_node_at(at + prefix)
    return
  }
  if left {
    // 左が空 = 有効な区切りが無い。末尾に `---` + 見出しを 1 編集で書く
    let p = st.nodes[ri].sub_end
    let br = nl()
    let sb = StringBuilder::new()
    let mut prefix = 0
    if p > 0 && cc(st.text, p - 1) != 10 {
      sb.write_string(br)
      sb.write_string(br)
      prefix = br.length() * 2
    } else if !preceded_by_blank(p) {
      sb.write_string(br)
      prefix = br.length()
    }
    sb.write_string("---")
    sb.write_string(br)
    sb.write_string(br)
    prefix = prefix + 3 + br.length() * 2
    sb.write_string("## ")
    sb.write_string(br)
    if p != st.text.length() {
      sb.write_string(br)
    }
    apply_sets(
      [[Edit::{ from: p, to: p, insert: sb.to_string(), removed: "" }]],
      tag,
    )
    focus_node_at(p + prefix)
  } else {
    // 右が空 = 最初の有効な区切りの手前へ
    let p = if st.seps.length() > 0 {
      st.seps[0]
    } else {
      st.nodes[ri].sub_end
    }
    let (e, prefix) = insert_heading_edit(p, 2)
    apply_sets([[e]], tag)
    focus_node_at(p + prefix)
  }
}

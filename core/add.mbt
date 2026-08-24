// ノードを作るコマンド。子・兄弟・親・ルート。

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
    if r.open_next == nd.from && r.close_start == nd.to {
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
    let (e, prefix) = insert_heading_edit(nd.to, nd.depth + 1)
    apply_sets([[e]], tag)
    focus_node_at(nd.to + prefix)
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
    let (e, prefix) = insert_heading_edit(nd.to, nd.depth)
    apply_sets([[e]], tag)
    focus_node_at(nd.to + prefix)
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
    let (e, prefix) = insert_heading_edit(nd.from, nd.depth)
    apply_sets([[e]], tag)
    focus_node_at(nd.from + prefix)
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
    let (head, prefix) = insert_heading_edit(nd.from, nd.depth)
    let set : Array[Edit] = [head]
    for m in subtree_nodes(nd.from, nd.to) {
      set.push(Edit::{
        from: st.nodes[m].from,
        to: st.nodes[m].from,
        insert: "#",
        removed: "",
      })
    }
    apply_sets([set], tag)
    focus_node_at(nd.from + prefix)
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

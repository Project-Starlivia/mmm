///|
/// スナップショットの中で、ラベル `label` のノードが hidden か。
///
/// 生の JSON の**隣り合わせ**（`"hidden":true,"label":"a"`）で見ていたころ、
/// スナップショットに鍵を 1 つ足しただけで 7 本のテストが黙って落ちた。
/// ノード 1 つは 1 つの `{…}` に収まるので、その塊の中だけを見る。
fn node_hidden(snap : String, label : String) -> Bool {
  let needle = "\"label\":\"" + label + "\""
  let at = match snap.find(needle) {
    Some(i) => i
    None => abort("node_hidden: label not found in snapshot: " + label)
  }
  let head = snap[0:at]
  let brace = match head.rev_find("{") {
    Some(i) => i
    None => abort("node_hidden: no enclosing { before label: " + label)
  }
  snap[brace:at].contains("\"hidden\":true")
}

///|
test "parse basic structure" {
  ignore(init_doc("# root\n\n## a\n\n### b\n\nbody of b\n\n## c\n"))
  // root(1) a(2) b(3) c(4) — verify via selection_text of the whole doc
  let all = selection_text([1])
  assert_eq(all, "# root\n\n## a\n\n### b\n\nbody of b\n\n## c\n")
}

///|
test "depth beyond six is a heading" {
  ignore(init_doc("# r\n\n####### seven\n"))
  let t = selection_text([2])
  assert_eq(t, "####### seven\n")
}

///|
test "fenced code hash lines are not headings" {
  ignore(
    init_doc(
      "# r\n\n```sh\n# not a heading\n```\n\n## real\n",
    ),
  )
  // node ids: 1 = r, 2 = real (the fenced line must not become a node)
  let t = selection_text([2])
  assert_eq(t, "## real\n")
}

///|
test "round trip: init then get_text is byte identical" {
  let src = "# r\r\n\r\n##   spaced   label\t\r\n\r\nbody\r\n"
  ignore(init_doc(src))
  assert_eq(get_text(), src)
}

///|
test "add child and sibling" {
  ignore(init_doc("# root\n\n## a\n"))
  // add child to a (id 2)
  ignore(add_child(2, ""))
  assert_eq(get_text(), "# root\n\n## a\n\n### \n")
  // the new node got id 3; add sibling to it
  ignore(add_sibling(3, ""))
  assert_eq(get_text(), "# root\n\n## a\n\n### \n\n### \n")
}

///|
test "rename normalizes only the edited line" {
  ignore(init_doc("# root\n\n##   messy   \n\nbody\n"))
  ignore(rename_node(2, "clean", ""))
  assert_eq(get_text(), "# root\n\n## clean\n\nbody\n")
}

///|
test "delete removes whole subtree" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\nbody\n\n## b\n"))
  ignore(delete_nodes([2]))
  assert_eq(get_text(), "# r\n\n## b\n")
}

///|
test "delete normalizes ancestor+descendant selection" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n## b\n"))
  // selecting a (2) and its child a1 (3) must not double-delete
  ignore(delete_nodes([3, 2]))
  assert_eq(get_text(), "# r\n\n## b\n")
}

///|
test "indent needs a previous sibling" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  // b (id 3) indents under a; a (id 2) has no previous sibling so stays
  ignore(indent_nodes([2]))
  assert_eq(get_text(), "# r\n\n## a\n\n## b\n")
  ignore(indent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n")
}

///|
test "indent moves the whole subtree depths" {
  ignore(init_doc("# r\n\n## a\n\n## b\n\n### b1\n"))
  ignore(indent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n\n#### b1\n")
}

///|
test "outdent last child is a pure depth change" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  ignore(outdent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n## a1\n")
}

///|
test "outdent from the middle moves after parent" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n### a2\n"))
  // outdent a1 (id 3): must move after a's subtree, not swallow a2
  ignore(outdent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n### a2\n\n## a1\n")
}

///|
test "move as child" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  // move b (3) as child of a (2)
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n")
}

///|
test "move before" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(move_nodes([3], 2, 1))
  assert_eq(get_text(), "# r\n\n## b\n\n## a\n")
}

///|
test "move rejects drop inside own subtree" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  let before = get_text()
  ignore(move_nodes([2], 3, 0))
  assert_eq(get_text(), before)
}

///|
test "undo redo shared stack" {
  ignore(init_doc("# r\n"))
  ignore(add_child(1, ""))
  assert_eq(get_text(), "# r\n\n## \n")
  ignore(undo())
  assert_eq(get_text(), "# r\n")
  ignore(redo())
  assert_eq(get_text(), "# r\n\n## \n")
}

///|
test "multi-node command is one undo step" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n### a2\n"))
  // outdent both children in one command
  ignore(outdent_nodes([3, 4]))
  assert_eq(get_text(), "# r\n\n## a\n\n## a1\n\n## a2\n")
  ignore(undo())
  assert_eq(get_text(), "# r\n\n## a\n\n### a1\n\n### a2\n")
}

///|
test "typing coalesces into one undo entry by tag" {
  ignore(init_doc("# r\n"))
  ignore(replace_text(3, 3, "x", "s1"))
  ignore(replace_text(4, 4, "y", "s1"))
  assert_eq(get_text(), "# rxy\n")
  ignore(undo())
  assert_eq(get_text(), "# r\n")
  ignore(redo())
  assert_eq(get_text(), "# rxy\n")
}

///|
test "reorder swaps sibling blocks" {
  ignore(init_doc("# r\n\n## a\n\nbody a\n\n## b\n"))
  ignore(reorder_node(3, -1, false))
  assert_eq(get_text(), "# r\n\n## b\n\n## a\n\nbody a\n")
  ignore(reorder_node(3, 1, false))
  // b moved back down past a
  assert_eq(get_text(), "# r\n\n## a\n\nbody a\n\n## b\n")
}

///|
test "selection text for copy" {
  ignore(init_doc("# r\n\n## a\n\nbody\n\n## b\n"))
  assert_eq(selection_text([2]), "## a\n\nbody\n")
}

///|
test "ids and parents survive a move" {
  ignore(init_doc("# r\n\n## a\n\n## b\n\n### b1\n"))
  // move b (3) with child b1 (4) under a (2)
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n\n#### b1\n")
  // b must still answer to id 3: rename it
  ignore(rename_node(3, "b2", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n### b2\n\n#### b1\n")
  // b1 must still answer to id 4 AND know its parent is b: outdent puts it
  // after b's subtree at b's depth
  ignore(outdent_nodes([4]))
  assert_eq(get_text(), "# r\n\n## a\n\n### b2\n\n### b1\n")
}

///|
test "insert before an existing heading does not steal its id" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  // add a sibling after a (2): the new heading is inserted right where
  // b (3) starts; b must keep id 3
  ignore(add_sibling(2, ""))
  ignore(rename_node(3, "b-renamed", ""))
  let t = get_text()
  assert_eq(t, "# r\n\n## a\n\n## \n\n## b-renamed\n")
}

///|
test "deleting adjacent blocks incl. the last one does not overlap edits" {
  ignore(init_doc("# r\n\n## a\n\nbody\n\n## b\n\n## c\n"))
  // b and c are adjacent and c reaches EOF: the EOF cleanup for c must not
  // overlap b's deletion range
  ignore(delete_nodes([3, 4]))
  assert_eq(get_text(), "# r\n\n## a\n\nbody\n")
  ignore(undo())
  assert_eq(get_text(), "# r\n\n## a\n\nbody\n\n## b\n\n## c\n")
}

///|
/// 区切りが有効な境界になった（2026-08-27, core/seps.mbt）ので、テキストには
/// 残るがノードの範囲には含まれない。
test "thematic breaks split ranges but stay in the raw text" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  assert_eq(selection_text([2]).contains("---"), false)
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## b\n")
}

///|
test "add sibling before" {
  ignore(init_doc("# r\n\n## a\n\nbody\n"))
  ignore(add_sibling_before(2, ""))
  assert_eq(get_text(), "# r\n\n## \n\n## a\n\nbody\n")
}

///|
test "add parent wraps the subtree" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n## b\n"))
  ignore(add_parent(2, ""))
  assert_eq(get_text(), "# r\n\n## \n\n### a\n\n#### a1\n\n## b\n")
  ignore(undo())
  assert_eq(get_text(), "# r\n\n## a\n\n### a1\n\n## b\n")
}

///|
/// 2 つ目以降の `#` も普通のノードとして出す（親なしの別ツリー）。
/// 以前は構造から外していて、テキストに在るのにマップから消えていた。
test "a second # is a node of its own, not dropped" {
  let snap = init_doc("# a\n\n# b\n\n## c\n")
  // a(1), b(2), c(3) の 3 つ。b は親なし、c は b の子
  assert_eq(snap.contains("\"label\":\"b\""), true)
  ignore(rename_node(2, "b2", ""))
  assert_eq(get_text(), "# a\n\n# b2\n\n## c\n")
}

///|
test "a second # keeps its own subtree" {
  ignore(init_doc("# a\n\n## a1\n\n# b\n\n## b1\n"))
  // b1 は b の子。b を消せば b1 も一緒に消える（以前は b1 が浮いていた）
  ignore(delete_nodes([3]))
  assert_eq(get_text(), "# a\n\n## a1\n")
}

///|
test "adding a sibling to the root adds a child instead" {
  ignore(init_doc("# r\n"))
  ignore(add_sibling(1, ""))
  assert_eq(get_text(), "# r\n\n## \n")
}

///|
test "outdent stops at depth 2 (no duplicate roots)" {
  ignore(init_doc("# r\n\n## a\n"))
  ignore(outdent_nodes([2]))
  assert_eq(get_text(), "# r\n\n## a\n")
}

///|
test "pre-root nodes form their own separate tree" {
  ignore(init_doc("## L\n\n### L1\n\n# r\n\n## R\n"))
  // kept order: L(1), L1(2), r(3), R(4); L is an independent top-level
  // tree (not a child of the root)
  // sibling of L inserts at L's to — still before the root
  ignore(add_sibling(1, ""))
  assert_eq(get_text(), "## L\n\n### L1\n\n## \n\n# r\n\n## R\n")
  ignore(undo())
  // outdenting L1 keeps it before the root (after L's subtree)
  ignore(outdent_nodes([2]))
  assert_eq(get_text(), "## L\n\n## L1\n\n# r\n\n## R\n")
}

///|
test "separate trees can be deleted together" {
  ignore(init_doc("## L\n\n# r\n\n## R\n"))
  // L(1) is an independent tree outside the root's text range;
  // selecting both must delete both
  ignore(delete_nodes([1, 2]))
  assert_eq(get_text(), "")
}

///|
test "indent keeps node ids (line-prefix inserts survive mapping)" {
  ignore(init_doc("# r\n\n## a\n\n## b\n\n### b1\n"))
  ignore(indent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n\n#### b1\n")
  // b must still answer to id 3 and b1 to id 4
  ignore(rename_node(3, "b2", ""))
  ignore(rename_node(4, "b1x", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n### b2\n\n#### b1x\n")
}

///|
test "add_parent keeps the wrapped subtree's ids" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n## b\n"))
  ignore(add_parent(2, ""))
  assert_eq(get_text(), "# r\n\n## \n\n### a\n\n#### a1\n\n## b\n")
  ignore(rename_node(2, "a2", ""))
  ignore(rename_node(3, "a1x", ""))
  ignore(rename_node(4, "b2", ""))
  assert_eq(get_text(), "# r\n\n## \n\n### a2\n\n#### a1x\n\n## b2\n")
}

///|
test "undo and redo keep node ids" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n")
  ignore(undo())
  // after undoing the move, b must still answer to id 3
  ignore(rename_node(3, "b2", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n## b2\n")
  ignore(undo()) // undo the rename
  ignore(redo()) // redo the rename — id still stable afterwards
  ignore(rename_node(3, "b3", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n## b3\n")
}

///|
test "move to the same spot is a no-op" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  // a1 is already the last child of a
  let before = get_text()
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), before)
  ignore(undo()) // must not revert anything else — stack should be empty
  assert_eq(get_text(), before)
}

///|
/// 既にある行のバイト列には触らないが、**書き足す改行は常に LF**。
/// 読み込みが CRLF を LF へ正規化する（src/app/io.ts）ので、アプリから
/// この状態にはならない — その前提をここで固定しておく。
test "existing bytes are kept, but inserted newlines are always LF" {
  ignore(init_doc("# r\r\n\r\n## a\r\n"))
  ignore(add_sibling(2, ""))
  assert_eq(get_text(), "# r\r\n\r\n## a\r\n\n## \n")
}

///|
test "hide wraps the subtree in comment markers" {
  ignore(init_doc("# r\n\n## a\n\nbody\n\n### a1\n\n## b\n"))
  // a = id 2; hiding wraps [from, to)
  ignore(toggle_hidden(2))
  assert_eq(
    get_text(),
    "# r\n\n<!--\n## a\n\nbody\n\n### a1\n\n-->\n## b\n",
  )
  // nodes inside the region stay in the structure, flagged hidden,
  // with their ids preserved
  let snap = toggle_hidden(2) // toggle back = show
  ignore(snap)
  assert_eq(get_text(), "# r\n\n## a\n\nbody\n\n### a1\n\n## b\n")
}

///|
test "hidden nodes keep ids and undo restores markers" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(toggle_hidden(2))
  // rename by id still works while hidden (id 2 survived the wrap)
  ignore(rename_node(2, "a2", ""))
  assert_eq(get_text(), "# r\n\n<!--\n## a2\n\n-->\n## b\n")
  ignore(undo()) // undo rename
  ignore(undo()) // undo hide
  assert_eq(get_text(), "# r\n\n## a\n\n## b\n")
}

///|
test "show removes markers from any node in the region" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  ignore(toggle_hidden(2))
  // toggling the CHILD (id 3) unhides the whole region
  ignore(toggle_hidden(3))
  assert_eq(get_text(), "# r\n\n## a\n\n### a1\n")
}

///|
/// Nested folds stay a no-op: HTML comments do not nest, so wrapping a range
/// that already contains a `<!--`/`-->` pair would let the inner closer end
/// the outer region. The child's region sits wholly inside the parent's
/// range (the boundary rule below deliberately does NOT cut there, or
/// folding a child would detach it from its parent), so the guard fires.
test "hide with nested markers is a no-op" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  ignore(toggle_hidden(3)) // hide a1 first
  let before = get_text()
  ignore(toggle_hidden(2)) // hiding a would nest markers -> refused
  assert_eq(get_text(), before)
}

///|
/// …and the parent still owns the folded child (the range was not cut).
test "folding a child keeps it under its parent" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  ignore(toggle_hidden(3))
  let s = init_doc(get_text())
  assert_eq(node_hidden(s, "a1"), true)
  // deleting the parent must still take the folded child AND its markers
  ignore(delete_nodes([2]))
  assert_eq(get_text(), "# r\n")
}

///|
/// A node's range must stop at a comment marker. Otherwise deleting a folded
/// node takes the closing `-->` with it, orphaning the `<!--` and silently
/// hiding every following node.
test "deleting a folded node does not orphan its markers" {
  ignore(init_doc("# root\n\n## a\n\n本文A\n\n## b\n\n本文B\n"))
  ignore(toggle_hidden(2))
  ignore(delete_nodes([2]))
  assert_eq(get_text(), "# root\n\n## b\n\n本文B\n")
}

///|
/// outdent で最後の子でないノードは move_block を経由する。hide 単独の
/// ノードをこの経路で動かすと、以前はマーカーが元の場所に置き去りになり
/// hidden 状態も失われていた。
test "outdenting a folded node keeps it hidden and leaves no orphan marker" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n### a2\n\n## b\n"))
  ignore(toggle_hidden(3)) // a1
  ignore(outdent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n### a2\n\n<!--\n## a1\n\n-->\n## b\n")
}

///|
/// reorder も move_block を経由する。単独 hide ノードの並べ替えでマーカーが
/// 置き去りにならないこと。
test "reordering a folded node keeps it hidden and leaves no orphan marker" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(toggle_hidden(2)) // a
  ignore(reorder_node(2, 1, false)) // swap with next sibling (b)
  assert_eq(get_text(), "# r\n\n## b\n\n<!--\n## a\n-->\n")
}

///|
test "copying a folded node yields no unpaired marker" {
  ignore(init_doc("# root\n\n## a\n\n本文A\n\n## b\n"))
  ignore(toggle_hidden(2))
  let clip = selection_text([2])
  assert_eq(clip.contains("-->"), false)
  assert_eq(clip.contains("<!--"), false)
}

///|
/// 2 つ目の `#` は前のノードの範囲の中に入ってはいけない（消すと巻き添えになる）。
test "a second # is not swallowed by the previous node" {
  ignore(init_doc("# root\n\n## a\n\n本文A\n\n# second\n\n## b\n"))
  assert_eq(selection_text([2]).contains("# second"), false)
  ignore(delete_nodes([2]))
  assert_eq(get_text().contains("# second"), true)
}

///|
test "comment markers inside code fences are content" {
  ignore(init_doc("# r\n\n```\n<!--\n```\n\n## real\n"))
  // the fenced <!-- must not open a hide region: real stays visible,
  // so hiding it wraps normally
  ignore(toggle_hidden(2))
  assert_eq(get_text(), "# r\n\n```\n<!--\n```\n\n<!--\n## real\n-->\n")
}

///|
/// 末尾に改行が無い文書でも、hide → show でバイト単位に元へ戻ること（F-007）。
/// 閉じマーカーの後ろに改行を足さないので、show 側が「hide が足した改行」を
/// 見分けられる。以前はここで末尾の改行が 1 つ増えていた。
test "hide at EOF without trailing newline round-trips" {
  ignore(init_doc("# r\n\n## a"))
  ignore(toggle_hidden(2))
  assert_eq(get_text(), "# r\n\n<!--\n## a\n-->")
  ignore(toggle_hidden(2))
  assert_eq(get_text(), "# r\n\n## a")
}

///|
test "hide at EOF with trailing newline round-trips" {
  ignore(init_doc("# r\n\n## a\n"))
  ignore(toggle_hidden(2))
  assert_eq(get_text(), "# r\n\n<!--\n## a\n-->\n")
  ignore(toggle_hidden(2))
  assert_eq(get_text(), "# r\n\n## a\n")
}

///|
test "comment markers follow renderer behaviour, not exact strings" {
  // `--->` closes a comment in HTML (it is `-` then `-->`), so it must
  // close one here too. Being stricter hid the rest of a real document.
  ignore(init_doc("# r\n\n<!--\n## a\n--->\n\n## b\n"))
  let s = init_doc("# r\n\n<!--\n## a\n--->\n\n## b\n")
  assert_eq(node_hidden(s, "a"), true)
  assert_eq(node_hidden(s, "b"), false)
}

///|
test "comment opener tolerates extra dashes" {
  let s = init_doc("# r\n\n<!---\n## a\n-->\n\n## b\n")
  assert_eq(node_hidden(s, "a"), true)
  assert_eq(node_hidden(s, "b"), false)
}

///|
test "unclosed comment hides everything after it" {
  let s = init_doc("# r\n\n<!--\n## a\n\n## b\n")
  assert_eq(node_hidden(s, "a"), true)
  assert_eq(node_hidden(s, "b"), true)
}

///|
test "move as parent: dropping on the a->b edge makes c sit between them" {
  ignore(init_doc("# r\n\n## a\n\n### b\n\n## c\n"))
  // c(4) を a(2) -> b(3) の線に落とす
  ignore(move_as_parent([4], 3))
  assert_eq(get_text(), "# r\n\n## a\n\n### c\n\n#### b\n")
}

///|
test "move as parent takes the whole subtree of b down one level" {
  ignore(init_doc("# r\n\n## a\n\n### b\n\n#### b1\n\n## c\n"))
  ignore(move_as_parent([5], 3))
  assert_eq(get_text(), "# r\n\n## a\n\n### c\n\n#### b\n\n##### b1\n")
}

///|
test "move as parent leaves the other children of a alone" {
  ignore(init_doc("# r\n\n## a\n\n### b1\n\n### b2\n\n## c\n"))
  ignore(move_as_parent([5], 4))
  assert_eq(get_text(), "# r\n\n## a\n\n### b1\n\n### c\n\n#### b2\n")
}

///|
test "move as parent is one undo step" {
  let before = "# r\n\n## a\n\n### b\n\n## c\n"
  ignore(init_doc(before))
  ignore(move_as_parent([4], 3))
  ignore(undo())
  assert_eq(get_text(), before)
}

///|
test "add root works even when a root already exists" {
  ignore(init_doc("# a\n\n## a1\n"))
  ignore(add_root(""))
  assert_eq(get_text(), "# a\n\n## a1\n\n# \n")
}

///|
/// 畳んだノードを動かすと、マーカーが元の場所に置き去りになっていた。
test "a hidden node carries its markers when moved" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(toggle_hidden(3))
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n<!--\n### b\n-->\n")
  let s = init_doc(get_text())
  assert_eq(node_hidden(s, "b"), true)
}

///|
/// 子を作ると、見出しの `#` が 1 つ増える。
test "add child writes the next heading depth" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n### b\n"))
  ignore(add_child(3, ""))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n### b\n\n#### \n")
}

///|
/// rename は見出しの深さを保つ。
test "rename keeps the heading depth" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n### b\n"))
  ignore(rename_node(3, "B", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n### B\n")
}

///|
/// 畳んだノードに足すときは先に開く。畳んだままだと新しい見出しが
/// hide 領域の中に生まれ、マップに出ないまま空の見出しだけが増えていた。
test "adding to a folded node unfolds it first" {
  ignore(init_doc("# r\n\n## a\n"))
  ignore(toggle_hidden(2))
  ignore(add_child(2, ""))
  assert_eq(get_text(), "# r\n\n## a\n\n### \n")
}

///|
test "unfold-then-add is one undo step" {
  let folded = "# r\n\n<!--\n## a\n-->\n"
  ignore(init_doc("# r\n\n## a\n"))
  ignore(toggle_hidden(2))
  assert_eq(get_text(), folded)
  ignore(add_child(2, ""))
  ignore(undo())
  assert_eq(get_text(), folded)
}

///|
/// HTML コメントは最初の `-->` で必ず終わる。hide 領域の中に孤立した
/// フェンス行があっても、`-->` を食って以降を全部 hidden にしない。
test "a stray fence inside a hide region does not eat the close marker" {
  let s = init_doc("# r\n\n<!--\n\n## a\n\n```\n\n-->\n\n## b\n")
  assert_eq(node_hidden(s, "a"), true)
  assert_eq(node_hidden(s, "b"), false)
}

///|
/// 行き先が動かす範囲の中にある移動は、丸ごと何もしない。
test "a move into its own subtree changes nothing" {
  let before = "# r\n\n## a\n\n---\n\n## c\n\n### c1\n"
  ignore(init_doc(before))
  ignore(move_nodes([3], 4, 0))
  assert_eq(get_text(), before)
}

///|
/// 畳んだノードへドロップすると、そのまま呑まれてマップから消えていた
/// （足す側の unfold_before_add と同じ手当てが move には無かった）。
/// 先に開いてから子にする。
test "moving onto a folded node unfolds it first" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  let s = toggle_hidden(2)
  assert_eq(node_hidden(s, "a"), true)
  let after = move_nodes([3], 2, 0)
  assert_eq(node_hidden(after, "a"), false)
  assert_eq(node_hidden(after, "b"), false)
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n")
}

///|
/// 畳んだノードへの追加も、続く rename と 1 つの undo になる（tag を保つ）。
test "adding into a folded node stays one undo with the rename" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n"))
  ignore(toggle_hidden(2))
  let folded = get_text()
  ignore(add_child(2, "s9"))
  ignore(rename_node(4, "名前", "s9"))
  ignore(undo())
  assert_eq(get_text(), folded)
}

///|
/// フェンス区間はコアが唯一の答えを持つ。UI はここから受け取るだけなので、
/// 「どこからどこまでか」と「情報文字列」を固定する。情報文字列に語が
/// 2 つ並んでも開く（GitHub のコピー指定など）。
test "fence spans cover the whole block and carry the info string" {
  let s = init_doc("# r\n\n```js copy\nlet a = 1\n```\n")
  assert_eq(
    s.contains(
      "\"fences\":[{\"from\":5,\"to\":29,\"bodyFrom\":16,\"bodyTo\":25,\"info\":\"js copy\"}]",
    ),
    true,
  )
}

///|
/// 中身が空でも区間は成立する（body は body_start より手前で終わる）。
test "an empty fence has no body" {
  let s = init_doc("# r\n\n```\n```\n")
  assert_eq(
    s.contains("\"from\":5,\"to\":12,\"bodyFrom\":9,\"bodyTo\":8,\"info\":\"\""),
    true,
  )
}

///|
/// 閉じないフェンスは文書末まで。以降の `#` はどのみち見出しにならない。
test "an unclosed fence runs to the end of the document" {
  let s = init_doc("# r\n\n~~~\n# not a heading\n")
  assert_eq(
    s.contains("\"from\":5,\"to\":24,\"bodyFrom\":9,\"bodyTo\":24"),
    true,
  )
  // 見出しはルートだけ（フェンスの中の # は数えない）
  assert_eq(s.contains("\"label\":\"not a heading\""), false)
}

///|
/// hide 領域の中で開いたフェンスは、領域と一緒に `-->` で終わる。
test "a fence opened inside a hide region ends with the region" {
  let s = init_doc("# r\n\n<!--\n## a\n\n```\ncode\n-->\n\n## b\n")
  assert_eq(s.contains("\"from\":16,\"to\":24,\"bodyFrom\":20,\"bodyTo\":24"), true)
  // 領域が閉じているので b は隠れない
  assert_eq(node_hidden(s, "b"), false)
}

///|
/// 断片の読み替え。フェンスの中の `#` は動かさない。
test "relevel shifts real headings only" {
  assert_eq(
    relevel_text("## a\n\n```\n# fake\n```\n\n### b\n", 4),
    "#### a\n\n```\n# fake\n```\n\n##### b\n",
  )
  assert_eq(relevel_text("本文だけ\n", 3), "本文だけ\n")
  assert_eq(has_headings("```js copy\n# fake\n```\n"), false)
  assert_eq(has_headings("### real\n"), true)
}

///|
/// 深さは 1 を下回らない（浅くしすぎても壊れない）。
test "relevel never goes above depth one" {
  assert_eq(relevel_text("### a\n\n#### b\n", 1), "# a\n\n## b\n")
  assert_eq(relevel_text("# a\n\n## b\n", 1), "# a\n\n## b\n")
}

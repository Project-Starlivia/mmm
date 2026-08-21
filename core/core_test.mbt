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
test "typing coalesces by tag and abort reverts the session" {
  ignore(init_doc("# r\n"))
  ignore(replace_text(3, 3, "x", "s1"))
  ignore(replace_text(4, 4, "y", "s1"))
  assert_eq(get_text(), "# rxy\n")
  ignore(undo())
  assert_eq(get_text(), "# r\n")
  ignore(redo())
  assert_eq(get_text(), "# rxy\n")
  ignore(abort_session("s1"))
  assert_eq(get_text(), "# r\n")
}

///|
test "reorder swaps sibling blocks" {
  ignore(init_doc("# r\n\n## a\n\nbody a\n\n## b\n"))
  ignore(reorder_node(3, -1))
  assert_eq(get_text(), "# r\n\n## b\n\n## a\n\nbody a\n")
  ignore(reorder_node(3, 1))
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
test "separator splits groups and is fence-safe" {
  let s = init_doc(
    "# r\n\n## a\n\n---\n\n## b\n\n```\n---\n```\n\n## c\n",
  )
  // a は区間 0、b と c は区間 1（フェンス内の --- は数えない）。
  // 区切り行はどのノードにも属さないので、a の添付コンテンツにもならない
  assert_eq(
    s.contains("\"group\":0,\"hasContent\":false,\"hidden\":false,\"label\":\"a\""),
    true,
  )
  assert_eq(
    s.contains("\"group\":1,\"hasContent\":true,\"hidden\":false,\"label\":\"b\""),
    true,
  )
  assert_eq(
    s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"c\""),
    true,
  )
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
  // sibling of L inserts at L's sub_end — still before the root
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
/// group 番号は文書全体の通し番号なので、ルート直下の区間と、無関係な
/// 別ツリー（2 つ目の `#` 以降）が同じ番号を踏むことがある。区切りの
/// 生死判定がそれに引きずられると、ルート側は空になったのに `---` が
/// 消え残る（別ツリーがまだ同じ番号にいるように見えてしまうため）。
test "dangling separator cleanup ignores unrelated trees sharing its group number" {
  ignore(
    init_doc(
      "# Root\n\n## Child1\n\n---\n\n## Child2\n\n# SecondRoot\n\n---\n\n## Child3\n",
    ),
  )
  // Root(1) Child1(2) Child2(3) SecondRoot(4) Child3(5)
  ignore(delete_nodes([3]))
  assert_eq(
    get_text(),
    "# Root\n\n## Child1\n\n# SecondRoot\n\n---\n\n## Child3\n",
  )
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
test "a thematic break inside content does not split groups" {
  let s = init_doc("# r\n\n## a\n\ntext\n\n---\n\nmore\n\n## b\n")
  // the --- is followed by content, not a heading: a and b share group 0
  assert_eq(
    s.contains("\"group\":0,\"hasContent\":true,\"hidden\":false,\"label\":\"a\""),
    true,
  )
  assert_eq(
    s.contains("\"group\":0,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""),
    true,
  )
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
test "crlf newlines are preserved and matched on insert" {
  ignore(init_doc("# r\r\n\r\n## a\r\n"))
  ignore(add_sibling(2, ""))
  assert_eq(get_text(), "# r\r\n\r\n## a\r\n\r\n## \r\n")
}

///|
test "hide wraps the subtree in comment markers" {
  ignore(init_doc("# r\n\n## a\n\nbody\n\n### a1\n\n## b\n"))
  // a = id 2; hiding wraps [hs, sub_end)
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
  assert_eq(s.contains("\"hidden\":true,\"label\":\"a1\""), true)
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
  ignore(reorder_node(2, 1)) // swap with next sibling (b)
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
  // close one here too. Being stricter hid the rest of mmm.md.
  ignore(init_doc("# r\n\n<!--\n## a\n--->\n\n## b\n"))
  let s = init_doc("# r\n\n<!--\n## a\n--->\n\n## b\n")
  assert_eq(s.contains("\"hidden\":true,\"label\":\"a\""), true)
  assert_eq(s.contains("\"hidden\":false,\"label\":\"b\""), true)
}

///|
test "comment opener tolerates extra dashes" {
  let s = init_doc("# r\n\n<!---\n## a\n-->\n\n## b\n")
  assert_eq(s.contains("\"hidden\":true,\"label\":\"a\""), true)
  assert_eq(s.contains("\"hidden\":false,\"label\":\"b\""), true)
}

///|
test "a run of dashes without > is still a separator, not a comment close" {
  // `---` must keep splitting groups; only `-->`-shaped lines close comments
  let s = init_doc("# r\n\n## a\n\n---\n\n## b\n")
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
}

///|
test "unclosed comment hides everything after it" {
  let s = init_doc("# r\n\n<!--\n## a\n\n## b\n")
  assert_eq(s.contains("\"hidden\":true,\"label\":\"a\""), true)
  assert_eq(s.contains("\"hidden\":true,\"label\":\"b\""), true)
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
/// `---` の直後の見出しは、書かれた深さに関わらずルート直下として読む。
/// id: r=1 a=2 a1=3 b=4 b1=5
test "a separator lifts the next heading to a root child" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n---\n\n### b\n\n#### b1\n"))
  // b は ### だが区間の先頭なので a の部分木には入らない
  assert_eq(selection_text([2]).contains("### b"), false)
  // ルートの部分木には入る（別ツリーになっていない）
  assert_eq(selection_text([1]).contains("### b"), true)
  // b1 は b の子のまま
  assert_eq(selection_text([4]).contains("#### b1"), true)
  // テキストは書き換えない
  assert_eq(get_text(), "# r\n\n## a\n\n### a1\n\n---\n\n### b\n\n#### b1\n")
}

///|
/// 区間の中で先頭より浅い見出しが出たら、そこで基準を取り直す。
/// 取り直さないと、以降の深い見出しが元の基準でずれて親子関係が壊れる。
/// id: r=1 a=2 b=3 c=4 c1=5
test "a shallower heading re-anchors the run" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n### b\n\n## c\n\n### c1\n"))
  // c は b の子ではなく、ルート直下の兄弟
  assert_eq(selection_text([3]).contains("## c"), false)
  // c1 は c の子のまま
  assert_eq(selection_text([4]).contains("### c1"), true)
  assert_eq(selection_text([1]).contains("### b"), true)
}

///|
/// 直前が本文の行なら setext 見出しの下線なので、区切りにしない。
test "a separator right after a paragraph is not a separator" {
  let s = init_doc("# r\n\n## a\n\n本文\n---\n\n## b\n")
  assert_eq(s.contains("\"group\":0,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
}

///|
/// `***` `___` `- - -` も CommonMark では同じ thematic break。
test "other thematic break markers work the same" {
  let s = init_doc("# r\n\n## a\n\n***\n\n## b\n\n- - -\n\n## c\n")
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
  assert_eq(s.contains("\"group\":2,\"hasContent\":false,\"hidden\":false,\"label\":\"c\""), true)
}

///|
/// front matter の区切り線は、最初の `#` より前なので自動的に落ちる。
test "front matter delimiters are not separators" {
  let s = init_doc("---\ntitle: x\n---\n\n# r\n\n## a\n")
  assert_eq(s.contains("\"group\":0,\"hasContent\":false,\"hidden\":false,\"label\":\"a\""), true)
  assert_eq(get_text(), "---\ntitle: x\n---\n\n# r\n\n## a\n")
}

///|
/// 先頭に置いた区切りは区間 0 を空にする（= 全部が反対側に出る）。
test "a title separator sends everything left" {
  let s = init_doc("# r\n\n---\n\n## a\n\n## b\n")
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"a\""), true)
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
}

///|
/// 区切り行はどのノードの範囲にも入らない（コピーや削除に付いてこない）。
test "a separator line belongs to no node" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n---\n\n### b\n"))
  assert_eq(selection_text([2]).contains("---"), false)
  ignore(delete_nodes([2]))
  assert_eq(get_text().contains("---"), true)
}

///|
/// 2 連の区切りは、最後の 1 本だけが効く。
test "consecutive separators collapse to one" {
  let s = init_doc("# r\n\n## a\n\n---\n\n---\n\n## b\n")
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
}

///|
/// hide は見た目を畳む操作であって、区間の構造を変えるものではない。
/// 区間の先頭を畳んだだけで区切りが死に、以降の左右が全部入れ替わっていた。
test "hiding a run head keeps the separator alive" {
  let s = init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n")
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
  ignore(toggle_hidden(3))
  let after = init_doc(get_text())
  // b は区間 1、c は区間 2 のまま（畳んでも区間番号が動かない）
  assert_eq(after.contains("\"group\":1,\"hasContent\":false,\"hidden\":true,\"label\":\"b\""), true)
  assert_eq(after.contains("\"group\":2,\"hasContent\":false,\"hidden\":false,\"label\":\"c\""), true)
}

///|
/// 区間の中身を全部よそへ動かしたら、区切りは**両脇 2 本まとめて**消す。
/// 1 本だけ消すと、そこから下の左右が全部反転してしまう。
/// c は右（区切り 2 本）だった → 両脇が消えて 0 本 = 右のまま。
test "moving a run's only node cleans up both separators" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"))
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n\n## c\n")
}

///|
/// 削除でも同じ。
test "deleting a run's only node cleans up both separators" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"))
  ignore(delete_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n## c\n")
}

///|
/// 区間に他の中身が残るなら区切りは消さない。
test "a separator survives when the run still has members" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n## b2\n\n---\n\n## c\n"))
  ignore(delete_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## b2\n\n---\n\n## c\n")
}

///|
/// 畳んだノードを動かすと、マーカーが元の場所に置き去りになっていた。
test "a hidden node carries its markers when moved" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(toggle_hidden(3))
  ignore(move_nodes([3], 2, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n<!--\n### b\n-->\n")
  let s = init_doc(get_text())
  assert_eq(s.contains("\"hidden\":true,\"label\":\"b\""), true)
}

///|
/// 読み替えが起きた区間の中でも、子を作れば子になること（`#` の数）。
test "add child inside a re-leveled run writes the right depth" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n### b\n"))
  ignore(add_child(3, ""))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n### b\n\n#### \n")
}

///|
/// rename は書かれている深さを保つ（読み替えで浅く見えていても減らさない）。
test "rename keeps the written heading depth" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n### b\n"))
  ignore(rename_node(3, "B", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n### B\n")
}

///|
/// reorder は区間の壁を越えない。越えると区間の中身が入れ替わる。
test "reorder stays inside its bundle" {
  let before = "# r\n\n## a\n\n---\n\n## b\n\n## c\n"
  ignore(init_doc(before))
  ignore(reorder_node(3, -1))
  assert_eq(get_text(), before)
  ignore(reorder_node(4, -1))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n\n## b\n")
}

///|
/// indent も区間の壁を越えない。
test "indent stays inside its bundle" {
  let before = "# r\n\n## a\n\n---\n\n## b\n"
  ignore(init_doc(before))
  ignore(indent_nodes([3]))
  assert_eq(get_text(), before)
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
/// reorder は深さを変えない移動。構造上の深さを渡していたせいで、
/// 読み替えの起きた区間（先頭が ###）の中の #### が ### に化けていた。
test "reorder keeps raw depth inside a re-leveled run" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n### h\n\n#### x\n\n#### y\n"))
  ignore(reorder_node(5, -1))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n### h\n\n#### y\n\n#### x\n")
}

///|
/// setext の下線になりうるのは `-` だけの行のみ。`***` や `- - -` は
/// 本文の直後でも水平線（CommonMark どおり）なので、区切りとして効く。
test "only dash-only separators are suppressed after text" {
  let s = init_doc("# r\n\n## a\n\nbody\n***\n\n## b\n")
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
  let s2 = init_doc("# r\n\n## a\n\nbody\n---\n\n## b\n")
  assert_eq(s2.contains("\"group\":0,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
}

///|
/// HTML コメントは最初の `-->` で必ず終わる。hide 領域の中に孤立した
/// フェンス行があっても、`-->` を食って以降を全部 hidden にしない。
test "a stray fence inside a hide region does not eat the close marker" {
  let s = init_doc("# r\n\n<!--\n\n## a\n\n```\n\n-->\n\n## b\n")
  assert_eq(s.contains("\"hidden\":true,\"label\":\"a\""), true)
  assert_eq(s.contains("\"hidden\":false,\"label\":\"b\""), true)
}

///|
/// 行き先が動かす範囲の中にある移動は、丸ごと何もしない。
/// 以前は移動せずに区切りの掃除だけが走り、テキストが変わっていた。
test "a move into its own subtree changes nothing" {
  let before = "# r\n\n## a\n\n---\n\n## c\n\n### c1\n"
  ignore(init_doc(before))
  ignore(move_nodes([3], 4, 0))
  assert_eq(get_text(), before)
}

///|
/// 左の区間を全部同時に消しても、残った右の区間の左右は変わらない。
/// 対で消す規則の帰結: 生き残りが全部右なら、区切りは 1 本も残らない。
test "deleting every left run keeps all survivors on the right" {
  ignore(
    init_doc(
      "# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n\n---\n\n## d\n\n---\n\n## e\n\n---\n\n## f\n\n---\n\n## g\n\n---\n\n## h\n\n---\n\n## i\n\n---\n\n## j\n",
    ),
  )
  ignore(delete_nodes([3, 5, 7, 9, 11]))
  assert_eq(get_text(), "# r\n\n## a\n\n## c\n\n## e\n\n## g\n\n## i\n")
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
/// 掃除の偶数規則: 末尾の区間が空いたら、手前の区切りだけ消す（下が無いので
/// 偶奇は関係ない）。
test "emptying the last run removes its leading separator" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  ignore(delete_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n")
}

///|
/// 先頭の区間（右側の頭）が空いても、残った「タイトル直後の `---`」は
/// 消さない — それは「全部左」の正しい表現。
test "emptying the first run keeps the title separator" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  ignore(delete_nodes([2]))
  assert_eq(get_text(), "# r\n\n---\n\n## b\n")
  let s = init_doc(get_text())
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"b\""), true)
}

///|
/// 連続 2 区間が空いたら、3 本の候補から偶数の 2 本を消し、最後の 1 本を
/// 境目として残す。下（e）の左右は変わらない。
test "emptying two adjacent runs keeps one separator as the boundary" {
  // a(右) b(左) c(右) d(左) e(右)
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n\n---\n\n## d\n\n---\n\n## e\n"))
  // b と c を同時に消す → 区切り3本(手前・間・後ろ)のうち2本消して1本残す
  ignore(delete_nodes([3, 4]))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## d\n\n---\n\n## e\n")
  // d は左のまま、e は右のまま
  let s = init_doc(get_text())
  assert_eq(s.contains("\"group\":1,\"hasContent\":false,\"hidden\":false,\"label\":\"d\""), true)
  assert_eq(s.contains("\"group\":2,\"hasContent\":false,\"hidden\":false,\"label\":\"e\""), true)
}

///|
/// 側の末尾へ移動: 左が空なら文書末尾に `---` を 1 本書いて置く。
/// これがこの道具が区切りを増やす唯一の経路。
test "move to empty left side writes the only separator" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n## b\n"))
  ignore(move_side_end([4], true))
  assert_eq(get_text(), "# r\n\n## a\n\n### a1\n\n---\n\n## b\n")
}

///|
/// 左に既にノードがあれば、いちばん下の後ろへ動かすだけ（区切りは増えない）。
test "move to occupied left side appends after its last node" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  ignore(move_side_end([2], true))
  assert_eq(get_text(), "# r\n\n---\n\n## b\n\n## a\n")
}

///|
/// 右が空（タイトル直後 `---` = 全部左）なら、最初の区切りの手前へ。
test "move to empty right side inserts before the first separator" {
  ignore(init_doc("# r\n\n---\n\n## a\n\n## b\n"))
  ignore(move_side_end([3], false))
  assert_eq(get_text(), "# r\n\n## b\n\n---\n\n## a\n")
}

///|
/// 側の末尾に子を作る（ルートの左右 ＋ ボタン）。左が空なら `---` ごと書く。
test "add at empty left side writes separator and heading" {
  ignore(init_doc("# r\n\n## a\n"))
  ignore(add_side_end(true, ""))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## \n")
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  ignore(add_side_end(false, ""))
  assert_eq(get_text(), "# r\n\n## a\n\n## \n\n---\n\n## b\n")
}

///|
/// move_side_end は undo 1 回で戻る。
test "move side end is one undo step" {
  let before = "# r\n\n## a\n\n### a1\n\n## b\n"
  ignore(init_doc(before))
  ignore(move_side_end([4], true))
  ignore(undo())
  assert_eq(get_text(), before)
}

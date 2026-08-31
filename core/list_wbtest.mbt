// リストも構造として読む・モードに従って書く（list-form）の検証。
// st の中（depth / parent / list_from）を直接見たいので whitebox テスト。


///|
/// 深さ・ラベル・親を 1 本の文字列に畳む（形の違いを無視した木の指紋）
fn tree_sig() -> String {
  let sb = StringBuilder::new()
  for nd in st.nodes {
    sb.write_string(nd.depth.to_string())
    sb.write_string(":")
    sb.write_string(nd.label)
    sb.write_string(":")
    sb.write_string(nd.parent.to_string())
    sb.write_string("|")
  }
  sb.to_string()
}

///|
test "list items are structure" {
  ignore(
    init_doc("- root\n  - branch A\n    [a](https://a.example)\n    - leaf\n"),
  )
  assert_eq(st.nodes.length(), 3)
  assert_eq(st.nodes[0].depth, 1)
  assert_eq(st.nodes[1].depth, 2)
  assert_eq(st.nodes[2].depth, 3)
  assert_eq(st.nodes[1].label, "branch A")
  assert_eq(st.nodes[1].has_content, true) // [a](…) は branch A の中身
  assert_eq(st.nodes[2].parent, st.nodes[1].id)
}

///|
test "a heading resets list nesting (hybrid)" {
  ignore(init_doc("# r\n\n## a\n\n- x\n  - y\n\n## b\n\n- z\n"))
  // x は a の子（深さ 3）、y はその子、z は b の子で x と同じ深さ
  assert_eq(tree_sig(), "1:r:-1|2:a:1|3:x:2|4:y:3|2:b:1|3:z:5|")
}

///|
test "indent stack reads 4-space and tab nesting" {
  ignore(init_doc("- a\n    - b\n\t\t- c\n- d\n"))
  // 4 スペースもタブ 2 つ(=4 桁)も「前より深い」だけで読む。d は先頭へ戻る
  assert_eq(st.nodes[0].depth, 1)
  assert_eq(st.nodes[1].depth, 2)
  assert_eq(st.nodes[2].depth, 2) // タブ 2 桁 ×2 = 4 桁 = b と同じ段
  assert_eq(st.nodes[3].depth, 1)
}

///|
test "separator and bold lines are not list items" {
  ignore(init_doc("# r\n\n---\n\n**bold** text\n\n-\n"))
  // `---` と `**bold**` は印の直後が空白でない。`-` 単独は空ラベルの項目
  assert_eq(st.nodes.length(), 2)
  assert_eq(st.nodes[1].label, "")
  assert_eq(st.nodes[1].depth, 2)
}

///|
test "listFrom is detected only at init" {
  ignore(init_doc("# r\n\n- x\n"))
  assert_eq(st.list_from, 2) // リストの最浅は深さ 2
  ignore(init_doc("# r\n\n## a\n"))
  assert_eq(st.list_from, 0) // リストが無ければ全部見出し
  // 編集でリストを書き足してもモードは動かない
  ignore(replace_text(9, 9, "\n- hand\n", ""))
  assert_eq(st.list_from, 0)
}

///|
test "writes follow the mode: child of a list item is a list line" {
  ignore(init_doc("- root\n  - a\n"))
  assert_eq(st.list_from, 1)
  ignore(add_child(2, "")) // a の子
  assert_eq(get_text(), "- root\n  - a\n\n    - \n")
}

///|
test "rename keeps the list prefix canonical" {
  ignore(init_doc("- root\n  *   messy   \n"))
  ignore(rename_node(2, "clean", ""))
  assert_eq(get_text(), "- root\n  - clean\n")
}

///|
test "indent and outdent rewrite prefixes, crossing the form boundary" {
  ignore(init_doc("# r\n\n## a\n\n- x\n"))
  assert_eq(st.list_from, 3)
  // x(深さ3, リスト) を段上げ → 深さ 2 は見出し側なので ## になる
  ignore(outdent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n## x\n")
  // 戻す: a の下へ段下げ → 深さ 3 はリスト側なので - に戻る
  ignore(indent_nodes([3]))
  assert_eq(get_text(), "# r\n\n## a\n\n- x\n")
}

///|
test "reformat converts the whole document and round-trips" {
  let head_form = "# root\n\n## branch A\n\n[a](https://a.example)\n\n### leaf\n"
  ignore(init_doc(head_form))
  let sig = tree_sig()
  ignore(set_list_from(1))
  ignore(reformat(""))
  assert_eq(
    get_text(),
    "- root\n  - branch A\n\n    [a](https://a.example)\n\n    - leaf\n",
  )
  assert_eq(tree_sig(), sig) // モードを替えてもマップは 1 ピクセルも変わらない
  ignore(set_list_from(0))
  ignore(reformat(""))
  assert_eq(get_text(), head_form) // 往復でバイト一致
  assert_eq(tree_sig(), sig)
  // 変換は 1 回の undo で戻る
  ignore(undo())
  assert_eq(
    get_text(),
    "- root\n  - branch A\n\n    [a](https://a.example)\n\n    - leaf\n",
  )
}

///|
test "hybrid mode writes heads above the boundary and lists below" {
  ignore(init_doc("# r\n\n## a\n"))
  ignore(set_list_from(3))
  ignore(add_child(2, "")) // 深さ 3 → リスト
  assert_eq(get_text(), "# r\n\n## a\n\n- \n")
  ignore(add_sibling(1, "")) // ルートの兄弟は子になる → 深さ 2 → 見出し
  assert_eq(get_text(), "# r\n\n## a\n\n- \n\n## \n")
}

///|
test "move across the boundary rewrites the prefix" {
  ignore(init_doc("# r\n\n## a\n\n- x\n\n## b\n"))
  assert_eq(st.list_from, 3)
  // x(a の子, リスト) を b の子へ D&D
  ignore(move_nodes([3], 4, 0))
  assert_eq(get_text(), "# r\n\n## a\n\n## b\n\n- x\n")
  assert_eq(tree_sig(), "1:r:-1|2:a:1|2:b:1|3:x:4|")
}

///|
/// 整形した list 形が、**外の Markdown パーサでも同じ木に読める**こと。
///
/// 判定材料は 3 つ。中身の行が項目の中身の列（ラベルの始まる列）まで
/// 字下げされていること、ラベルと中身の間に空行があること、兄弟の間に
/// 空行が無いこと。1 つでも崩れると、外のパーサはそこでリストを閉じ、
/// 続く項目は別のリスト・深い字下げはコードブロックに化ける。
test "list form is readable by an outside Markdown parser" {
  ignore(init_doc("# root\n\n## a\n\ntext\n\n### leaf\n\n## b\n"))
  ignore(set_list_from(1))
  ignore(reformat(""))
  assert_eq(get_text(), "- root\n  - a\n\n    text\n\n    - leaf\n  - b\n")
}

///|
/// フェンスの中はコード。**空行を足したり詰めたりしない**（足していた頃、
/// `const x = 1;` の前後に空行が入ってコードが変わっていた）。
/// 字下げは塊ごと動くので、中の相対的な字下げは保たれる。
test "fences move as a block and keep their body untouched" {
  let head = "# r\n\n## a\n\n```ts\nif (x) {\n  y();\n}\n```\n"
  ignore(init_doc(head))
  ignore(set_list_from(1))
  ignore(reformat(""))
  assert_eq(
    get_text(),
    "- r\n  - a\n\n    ```ts\n    if (x) {\n      y();\n    }\n    ```\n",
  )
  // 字下げされたフェンスも、コアはフェンスとして読む（中の `- x` が
  // ノードに化けない）
  assert_eq(st.nodes.length(), 2)
  ignore(set_list_from(0))
  ignore(reformat(""))
  assert_eq(get_text(), head) // 往復でバイト一致
}

///|
/// 字下げされたフェンスの中の構造めいた行は、構造にならない。
test "structure lines inside an indented fence stay code" {
  ignore(init_doc("- r\n  - a\n\n    ```\n    - not a node\n    # nor this\n    ```\n"))
  assert_eq(st.nodes.length(), 2)
  assert_eq(st.nodes[1].label, "a")
}

///|
test "pasted list fragments relevel into the document form" {
  ignore(init_doc("# r\n\n## a\n")) // 見出しの文書（listFrom 0）
  // リストの断片を深さ 3 に合わせると、見出しに書き直される。
  // 見出しの形は「ブロックの間は空行 1 つ」なので、詰めて書かれていた
  // リストの断片も、書き直すときに空行が入る
  assert_eq(relevel_text("- p\n  - q\n", 3), "### p\n\n#### q\n")
}

///|
/// リストの文書へ、見出しで書かれた断片（本文つき）を貼ると、本文の
/// 字下げも新しい深さの列に合わせて書き直される。**接頭辞だけでは
/// 足りない** — 貼り付けでも reformat と同じ規則を通す。
test "pasted heading fragments with content indent into the list form" {
  ignore(init_doc("- root\n  - a\n"))
  assert_eq(st.list_from, 1)
  let pasted = relevel_text("## x\n\nhttps://e.example\n\n### z\n", 3)
  assert_eq(pasted, "    - x\n\n      https://e.example\n\n      - z\n")
}

///|
/// 2 行以上の中身（コードフェンスの開きと閉じ）を一度に足しても、
/// **全部の行**が項目の中身の列まで字下げされる。先頭だけ字下げしていた頃は
/// 2 行目から列 0 に落ち、外のパーサがそこでリストを閉じて続く兄弟が
/// 迷子になった（1 行の追記で踏んだ事故が、複数行で再演する）。
test "multi-line content is indented on every line" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(set_list_from(1))
  ignore(reformat(""))
  let a = st.nodes[1].id
  ignore(insert_content(a, "```\n\n```", ""))
  // 中の空行にも基準列ぶんの字下げが入る（フェンスの中では、それは余分な
  // 空白ではなく塊の基準列）。追記の後ろの空行は block_insert の既存の規則。
  assert_eq(get_text(), "- r\n  - a\n\n    ```\n    \n    ```\n\n  - b\n")
  // 足したフェンスは、コアからもフェンスとして読める（中身は木を割らない）
  assert_eq(st.nodes.length(), 3)
  assert_eq(st.fences.length(), 1)
}

///|
/// 見出しの形（列 0）では字下げしない。空行に空白を置き去りにもしない。
test "multi-line content in heading form stays at column 0" {
  ignore(init_doc("# r\n\n## a\n"))
  let a = st.nodes[1].id
  ignore(insert_content(a, "```\n\n```", ""))
  assert_eq(get_text(), "# r\n\n## a\n\n```\n\n```\n")
}

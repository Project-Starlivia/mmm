// 文書の頭（YAML frontmatter）は非構造区間、の検証。
// st.head / st.nodes を直接見たいので whitebox テスト。

///|
/// 頭の区間を 1 本の文字列に畳む（無ければ "none"）。
/// Head は Eq を持たないので、比べられる形に落とす。
fn head_sig() -> String {
  match st.head {
    Some(h) => {
      let sb = StringBuilder::new()
      sb.write_string(h.start.to_string())
      sb.write_string(":")
      sb.write_string(h.body_start.to_string())
      sb.write_string(":")
      sb.write_string(h.body_end.to_string())
      sb.write_string(":")
      sb.write_string(h.end.to_string())
      sb.to_string()
    }
    None => "none"
  }
}

///|
test "頭の中のリスト項目はノードにならない" {
  ignore(init_doc("---\ntags:\n  - 設計\n  - web\n---\n\n# r\n\n## a\n"))
  assert_eq(st.nodes.length(), 2)
  assert_eq(st.nodes[0].label, "r")
  assert_eq(st.nodes[1].label, "a")
}

///|
test "頭の中の見出し行もノードにならない" {
  ignore(init_doc("---\n# YAML のコメント\nimage-folder: ./img/\n---\n\n# r\n"))
  assert_eq(st.nodes.length(), 1)
  assert_eq(st.nodes[0].label, "r")
}

///|
test "頭の区間は開きの行頭から閉じの行末まで" {
  ignore(init_doc("---\nimage-folder: ./img/\n---\n\n# r\n"))
  // `---\n` = 0..3 (next 4) / `image-folder: ./img/\n` = 4..24 (next 25)
  // / `---\n` = 25..28
  assert_eq(head_sig(), "0:4:24:28")
}

///|
test "中身の無い頭も頭（body_end が body_start より手前）" {
  ignore(init_doc("---\n---\n\n# r\n"))
  assert_eq(head_sig(), "0:4:3:7")
  assert_eq(st.nodes.length(), 1)
}

///|
test "閉じない `---` は頭ではない" {
  ignore(init_doc("---\n- a\n\n# r\n"))
  assert_eq(head_sig(), "none")
  // 頭が成立しないので `- a` は今までどおりリスト項目
  assert_eq(st.nodes.length(), 2)
  assert_eq(st.nodes[0].label, "a")
  assert_eq(st.nodes[1].label, "r")
}

///|
test "先頭でない `---` は頭ではない" {
  ignore(init_doc("# r\n\n---\n\n## a\n"))
  assert_eq(head_sig(), "none")
  assert_eq(st.nodes.length(), 2)
}

///|
test "ダッシュ 4 本は頭を開かない" {
  ignore(init_doc("----\n- a\n----\n\n# r\n"))
  assert_eq(head_sig(), "none")
}

///|
test "頭を含む文書の往復がバイト同一" {
  let src = "---\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n\n![](./img/a.webp)\n"
  ignore(init_doc(src))
  assert_eq(get_text(), src)
}

///|
test "貼り付け断片の頭も構造に数えない" {
  assert_eq(has_headings("---\ntags:\n  - a\n---\n\ntext\n"), false)
  assert_eq(has_headings("---\ntags:\n  - a\n---\n\n# r\n"), true)
}

///|
/// 割り切りの固定: 閉じないまま本文まで走った頭は、本文の最初の `---` を
/// 道連れに閉じる（Jekyll / Obsidian と同じ）。ここでは 2 本目の `---` が
/// 「区切り線」のつもりでも頭として吸われ、その手前の `# r` ごと消える。
/// オフセットは手で数えて確かめた値（core/parser.mbt の scan_head 参照）。
test "先頭が --- で後ろにもう 1 本あれば、間の見出しごと頭に吸われる" {
  ignore(init_doc("---\n\n# r\n\n## a\n\n---\n\n## b\n"))
  assert_eq(head_sig(), "0:4:15:19")
  assert_eq(st.nodes.length(), 1)
  assert_eq(st.nodes[0].label, "b")
}

///|
/// Pandoc 形式の `...` は閉じ記号として見ない（is_head_marker はダッシュ
/// 3 本だけを見る）ので、閉じないまま本文の最初の `---` まで走り、`# r` を
/// 巻き込む。
test "Pandoc の `...` は頭を閉じず、本文の最初の --- まで走る" {
  ignore(init_doc("---\ntitle: x\n...\n\n# r\n\n---\n\n## a\n"))
  assert_eq(head_sig(), "0:4:22:26")
  assert_eq(st.nodes.length(), 1)
  assert_eq(st.nodes[0].label, "a")
}

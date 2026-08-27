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

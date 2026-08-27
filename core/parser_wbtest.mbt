// scan_doc / scan_lines は private（構造として効くかどうかを決める前の、
// 行の並びだけの結果）。それを直接見たいので whitebox テスト。

///|
/// 区切りのかたまりを数える（構造として効くかどうかは doc の仕事）。
fn sep_runs_of(md : String) -> Array[(Int, Int)] {
  let lines = scan_lines(md)
  let scan = scan_doc(md, lines)
  let out : Array[(Int, Int)] = []
  for r in scan.seps {
    out.push((r.start, r.lines))
  }
  out
}

///|
test "区切りは連続したかたまりで数える" {
  // `---` 1 本 → 1 本の境界、2 本続き → 2 本の境界
  let md = "# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"
  let runs = sep_runs_of(md)
  assert_eq(runs.length(), 2)
  assert_eq(runs[0].1, 1)
  assert_eq(runs[1].1, 2)
}

///|
test "空行と hide マーカーは、かたまりを切らない" {
  let md = "# r\n\n## a\n\n---\n\n---\n\n## b\n"
  assert_eq(sep_runs_of(md).length(), 1)
  assert_eq(sep_runs_of(md)[0].1, 2)
  let md2 = "# r\n\n## a\n\n---\n<!--\n---\n\n## b\n"
  assert_eq(sep_runs_of(md2).length(), 1)
  assert_eq(sep_runs_of(md2)[0].1, 2)
}

///|
test "本文の直後の `---` は setext の下線なので数えない" {
  // `***` にこの危険は無いので、こちらは数える
  assert_eq(sep_runs_of("# r\n\n## a\n\nbody\n---\n\n## b\n").length(), 0)
  assert_eq(sep_runs_of("# r\n\n## a\n\nbody\n***\n\n## b\n").length(), 1)
}

///|
test "フェンスの中の区切りは数えない" {
  assert_eq(sep_runs_of("# r\n\n```\n---\n---\n```\n\n## a\n").length(), 0)
}

///|
test "`- - -` は今までどおりリスト項目のまま" {
  // 間を空けた形は CommonMark では区切りだが、mmm の読みではリスト項目。
  // 読みを変えないため、ここでは拾わない
  assert_eq(sep_runs_of("# r\n\n- - -\n").length(), 0)
  let lines = scan_lines("# r\n\n- - -\n")
  let scan = scan_doc("# r\n\n- - -\n", lines)
  assert_eq(scan.heads.length(), 2)
}

///|
test "リストの形の文書では、項目の中身の列に書かれた区切りも読む" {
  let md = "- root\n\n  - a\n\n  ---\n\n  - b\n"
  assert_eq(sep_runs_of(md).length(), 1)
}

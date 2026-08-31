// md がどう読まれるかを、指紋（ブロックの種類と原文の範囲）で固定する。
// 読むのは mizchi/markdown。ここは mmm がその出力に何を期待しているかの記録で、
// 期待が崩れたら気づけるようにしてある。
//
// span は原文を隙間なく敷き詰める（前の to = 次の from）。すげ替えがこれに乗る。

///|
test "字下げの見出しはコードとして読まれる（F5）" {
  inspect(
    ast_sig("# a\n    # x\n"),
    content=(
      #|H1Atx[0,4] Indent[8,12]
    ),
  )
}

///|
test "項目だけの文書" {
  inspect(
    ast_sig("- x\n- y\n"),
    content=(
      #|ListDashtrue[0,8](2)
    ),
  )
}

///|
test "翼のトグルと飾りの水平線" {
  inspect(
    ast_sig("# r\n\n## a\n\n---\n\n### x\n\n***\n"),
    content=(
      #|H1Atx[0,4] Blank1[4,5] H2Atx[5,10] Blank1[10,11] Rule-3[11,15] Blank1[15,16] H3Atx[16,22] Blank1[22,23] Rule*3[23,27]
    ),
  )
}

///|
/// 7 個以上は CommonMark どおり段落。見出しは深さ 6 まで。
/// 深い階層は Item（リスト）で書く — 相対記法なので上限が無い。
/// 無限階層を通すかは #19 で保留。
test "7 個以上の # は段落になる（見出しは深さ 6 まで）" {
  inspect(
    ast_sig("###### f\n\n####### g\n\n######## h\n"),
    content=(
      #|H6Atx[0,9] Blank1[9,10] P[10,20] Blank1[20,21] P[21,32]
    ),
  )
}

///|
test "畳みと frontmatter" {
  inspect(
    ast_sig("---\nk: v\n---\n\n# r\n\n<details>\n\n## a\n\n</details>\n"),
    content=(
      #|Front[0,13] Blank1[13,14] H1Atx[14,18] Blank1[18,19] Html[19,29] Blank1[29,30] H2Atx[30,35] Blank1[35,36] Html[36,47]
    ),
  )
}

///|
/// 見出しの中身の span は **原文の絶対位置ではなく、中身に対する 0 始まりの相対**。
/// `text` を挟んで見出しが後ろにあっても `0,1` のまま。build.mbt の label_of は
/// この前提で中身の開始位置を自分で数えているので、崩れたらここが鳴る。
test "インラインの span は中身に対する相対" {
  let sb = StringBuilder::new()
  for
    md in [
      "# a\n", "#   a\n", "# a **b**\n", "text\n\n# a\n", "# a #\n", "a\n=\n",
    ] {
    sb.write_string("\{md.escape()} → ")
    for b in read(md).children {
      match b {
        Heading(children~, span~, level~, closing_hashes~, ..) => {
          sb.write_string(
            "H\{level} \{span.from},\{span.to} close=\{closing_hashes} :",
          )
          for c in children {
            let s = span_of(c)
            sb.write_string(" \{s.from},\{s.to}")
          }
        }
        _ => ()
      }
    }
    sb.write_string("\n")
  }
  inspect(
    sb.to_string(),
    content=(
      #|"# a\n" → H1 0,4 close=0 : 0,1
      #|"#   a\n" → H1 0,6 close=0 : 0,1
      #|"# a **b**\n" → H1 0,10 close=0 : 0,2 2,7
      #|"text\n\n# a\n" → H1 6,10 close=0 : 0,1
      #|"# a #\n" → H1 0,6 close=1 : 0,1
      #|"a\n=\n" → H1 0,4 close=0 : 0,1
      #|
    ),
  )
}

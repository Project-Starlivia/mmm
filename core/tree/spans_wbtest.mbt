// 「このノードは原文のここに書かれている」を指紋 `id[from,label,to]` で固定する。
//
// 範囲は骨格の行の頭から自分の最後の中身の尻まで。label はラベルの頭（マーカーの
// 後ろ）で、行を持たない Implicit と文書の散文（`1`）は `-`。空行と側の水平線は
// どのノードのものでもない（隙間）。

///|
test "見出し 1 つ" {
  inspect(spans_sig("# a\n"), content="1[0,-,0] 2[0,2,4]")
}

///|
test "親は子の尻まで、子は自分の中身の尻まで" {
  inspect(
    spans_sig("# r\n\n## a\n\nhello\n\n## b\n"),
    content=(
      #|1[0,-,0] 2[0,2,23] 3[5,8,17] 5[18,21,23]
    ),
  )
}

///|
test "末尾の空行はどのノードのものでもない" {
  inspect(spans_sig("# a\n\n\n"), content="1[0,-,0] 2[0,2,4]")
}

///|
test "Implicit は子の和。行が無いのでラベルの頭も無い" {
  inspect(
    spans_sig("# r\n\n### x\n"),
    content="1[0,-,0] 2[0,2,11] 3[5,-,11] 4[5,9,11]",
  )
}

///|
test "側の水平線は隙間" {
  inspect(
    spans_sig("# r\n\n## a\n\n---\n\n## b\n"),
    content="1[0,-,0] 2[0,2,21] 3[5,8,10] 4[16,19,21]",
  )
}

///|
test "飾りに落ちた水平線は中身なので範囲に入る" {
  inspect(
    spans_sig("# a\n\n---\n"),
    content=(
      #|1[0,-,0] 2[0,2,9]
    ),
  )
}

///|
test "CRLF は 2 文字" {
  inspect(
    spans_sig("# a\r\n"),
    content=(
      #|1[0,-,0] 2[0,2,5]
    ),
  )
}

///|
test "文書の散文は frontmatter の尻から最初の根の手前まで" {
  inspect(
    spans_sig("---\nk: v\n---\n\nhello\n\n# a\n"),
    content=(
      #|1[13,-,20] 3[21,23,25]
    ),
  )
}

///|
/// 項目の頭は行頭ではなくマーカー。容器の字下げは範囲の外に残る
test "項目は入れ子込み" {
  inspect(
    spans_sig("- a\n  - b\n- c\n"),
    content=(
      #|1[0,-,0] 2[0,2,10] 3[6,8,10] 4[10,12,14]
    ),
  )
}

///|
test "畳みは <details> から </details> まで" {
  inspect(
    spans_sig("# r\n\n<details>\n\n## a\n\nx\n\n</details>\n\n## b\n"),
    content=(
      #|1[0,-,0] 2[0,2,42] 3[5,19,36] 5[37,40,42]
    ),
  )
}

///|
test "定義行も中身（尻は改行込みで他の塊と揃う）" {
  inspect(
    spans_sig("# a\n\n[q]: /r\n"),
    content=(
      #|1[0,-,0] 2[0,2,13]
    ),
  )
}

///|
test "対にならない details は原文のまま中身" {
  inspect(
    spans_sig("# a\n\n<details>\nx\n\n# b\n"),
    content=(
      #|1[0,-,0] 2[0,2,17] 4[18,20,22]
    ),
  )
}

///|
/// 項目のラベルの頭はマーカーの後ろ。入れ子の項目は容器の字下げが範囲の外に残る
/// ので from はマーカーの位置
test "項目のラベルの頭はマーカーの後ろ" {
  inspect(
    spans_sig("- a\n  - b\n"),
    content=(
      #|1[0,-,0] 2[0,2,10] 3[6,8,10]
    ),
  )
}

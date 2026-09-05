// md がどう読まれるかを、指紋（ブロックの種類と原文の範囲）で固定する。
// 読むのは mizchi/markdown。ここは mmm がその出力に何を期待しているかの記録で、
// 期待が崩れたら気づけるようにしてある。
//
// span は原文を隙間なく敷き詰める（前の to = 次の from）。すげ替えがこれに乗る。

///|
test "字下げの見出しはコードとして読まれる（F5）" {
  inspect(
    md_ast_sig("# a\n    # x\n"),
    content=(
      #|H1Atx[0,4] Indent[8,12]
    ),
  )
}

///|
test "項目だけの文書" {
  inspect(
    md_ast_sig("- x\n- y\n"),
    content=(
      #|ListDashtrue[0,8](2)
    ),
  )
}

///|
test "境界の水平線と飾りの水平線" {
  inspect(
    md_ast_sig("# r\n\n## a\n\n---\n\n### x\n\n***\n"),
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
    md_ast_sig("###### f\n\n####### g\n\n######## h\n"),
    content=(
      #|H6Atx[0,9] Blank1[9,10] P[10,20] Blank1[20,21] P[21,32]
    ),
  )
}

///|
test "畳みと frontmatter" {
  inspect(
    md_ast_sig("---\nk: v\n---\n\n# r\n\n<details>\n\n## a\n\n</details>\n"),
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

///|
/// 方言 — ライブラリの生の指紋と、mmm が揃えた後の指紋を並べる。ライブラリの版が
/// 上がって生の指紋が変われば、ここで気付く。

///|
test "方言 — フェンス付きの塊の尻は閉じの行の改行まで（生は閉じの手前で止まる）" {
  let md = "# a\n\n```js\nx\n```\n\n$$\ny\n$$\n\n:::note\nz\n:::\n"
  inspect(
    raw_ast_sig(md),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Fence(js)[5,13] Blank1[13,18] Math[18,23] Blank1[23,27] Directive(note)[27,37]
    ),
  )
  inspect(
    md_ast_sig(md),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Fence(js)[5,17] Blank1[13,18] Math[18,26] Blank1[23,27] Directive(note)[27,41]
    ),
  )
}

///|
test "方言 — CRLF でも、項目の中でも、閉じが無ければそのまま" {
  inspect(
    raw_ast_sig("# a\r\n\r\n```\r\nx\r\n```\r\n"),
    content=(
      #|H1Atx[0,5] Blank1[5,7] Fence()[7,15]
    ),
  )
  inspect(
    md_ast_sig("# a\r\n\r\n```\r\nx\r\n```\r\n"),
    content=(
      #|H1Atx[0,5] Blank1[5,7] Fence()[7,20]
    ),
  )
  inspect(
    md_ast_sig("```\nx\n"),
    content=(
      #|Fence()[0,6]
    ),
  )
  // 項目の中のフェンスは項目の指紋に畳まれるので、地番で見る
  inspect(
    spans_sig("- a\n  ```js\n  1\n  ```\n"),
    content=(
      #|1[0,-,0] 2[0,2,22] 3[6,-,22]
    ),
  )
}

///|
test "方言 — 定義行の尻は改行込み（生は改行の手前で止まる）" {
  let md = "# a\n\n[q]: /r\n\n## b\n"
  inspect(
    raw_ast_sig(md),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Blank1[13,14] H2Atx[14,19] Def[5,12]
    ),
  )
  inspect(
    md_ast_sig(md),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Blank1[13,14] H2Atx[14,19] Def[5,13]
    ),
  )
}

///|
test "綴り — 区切り線は ---（ライブラリは *** と書く）。コードの中の *** は触らない" {
  let d = parse("# r\n\n## a\n\n***\n\n## b\n\n***\n\n```\n***\n```\n")
  inspect(
    serialize(d),
    content=(
      #|# r
      #|
      #|## a
      #|
      #|---
      #|
      #|## b
      #|
      #|---
      #|
      #|```
      #|***
      #|```
      #|
    ),
  )
  let l = parse("- a\n\n  ***\n\n  - b\n")
  inspect(
    serialize(l),
    content=(
      #|- a
      #|
      #|  ---
      #|
      #|  - b
      #|
    ),
  )
}

///|
test "綴り — frontmatter と本文の間は空行 1 つ" {
  inspect(
    serialize(parse("---\nk: v\n---\n# a\n")),
    content=(
      #|---
      #|k: v
      #|---
      #|
      #|# a
      #|
    ),
  )
}

///|
/// ライブラリが読んだままの mdAst の指紋。方言との差を並べるため（試験だけが使う）
fn raw_ast_sig(md : String) -> String {
  ast_sig(@markdown.parse(md).document)
}

///|
test "方言 — 定義行が続くと、生の span は改行込みになる。飲み込まない" {
  let two = "# a\n\n[q]: /r\n[s]: /t\n"
  inspect(
    raw_ast_sig(two),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Def[5,13] Def[13,20]
    ),
  )
  inspect(
    md_ast_sig(two),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Def[5,13] Def[13,21]
    ),
  )
  inspect(
    serialize(parse(two)),
    content=(
      #|# a
      #|
      #|[q]: /r
      #|
      #|[s]: /t
      #|
    ),
  )
}

///|
test "方言 — ::: の中身が 2 塊でも、入れ子でも、閉じまで" {
  inspect(
    md_ast_sig(":::note\n- a\n  ***\n:::\n"),
    content=(
      #|Directive(note)[0,22]
    ),
  )
  inspect(
    serialize(parse("# r\n\n:::note\n- a\n  ***\n:::\n")),
    content=(
      #|# r
      #|
      #|:::note
      #|- a
      #|  ***
      #|:::
      #|
    ),
  )
  // 入れ子の :::。ライブラリは外の閉じを段落と読む（生は Directive(a)[0,10] … P[16,20]）。
  // 方言は外の span を閉じまで伸ばし、飲まれた段落を落とす。閉じの行と同じ段落に字が続く形
  // （`:::\nmore`）はライブラリ自身が `:::` を増やすので、そこは同着のまま
  inspect(
    md_ast_sig(":::a\n:::b\nx\n:::\n:::\n"),
    content=(
      #|Directive(a)[0,20]
    ),
  )
  inspect(
    serialize(parse(":::a\n:::b\nx\n:::\n:::\n")),
    content=(
      #|:::a
      #|:::b
      #|x
      #|:::
      #|:::
      #|
    ),
  )
}

///|
test "方言 — 閉じの無いフェンスは空行の先のフェンスを掴まない（地番が重ならない）" {
  inspect(
    spans_sig("- ```\n  x\n\n```\nz\n```\n"),
    content=(
      #|1[0,-,0] 2[0,2,21] 3[2,-,11] 4[11,-,21]
    ),
  )
}

///|
test "綴り — 段落の直後の線は *** のまま（--- だと setext の下線になる）。冪等" {
  let quote = "# r\n\n> a\n>\n> ---\n"
  let once = serialize(parse(quote))
  inspect(
    once,
    content=(
      #|# r
      #|
      #|> a
      #|> ***
      #|
    ),
  )
  inspect(serialize(parse(once)) == once, content="true")
  let tight = "# r\n\n> - a\n>   ***\n"
  let again = serialize(parse(tight))
  inspect(
    again,
    content=(
      #|# r
      #|
      #|> - a
      #|>   ***
      #|
    ),
  )
  inspect(serialize(parse(again)) == again, content="true")
}

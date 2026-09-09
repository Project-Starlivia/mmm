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
  let sb = StringBuilder()
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
/// 境界の `***` は `Root.rules`、飾りの `***` は中身の原文（`Block.source`）、
/// コードの中の `***` はコードの中身。どれも読んだ字のまま返る。
test "綴り — 水平線は読んだ字のまま。境界も飾りもコードの中も" {
  let d = parse("# r\n\n## a\n\n***\n\n## b\n\n***\n\n```\n***\n```\n")
  inspect(
    serialize(d),
    content=(
      #|# r
      #|
      #|## a
      #|
      #|***
      #|
      #|## b
      #|
      #|***
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
      #|  ***
      #|
      #|  - b
      #|
    ),
  )
}

///|
/// 読みは CRLF を含む md も受けるが（`方言 — CRLF でも…`）、書きは LF だけ。
/// 塊の中身は読んだ原文なので、その中の CRLF だけが残る。
test "綴り — 書き戻しの改行は LF だけ" {
  inspect(serialize(parse("# a\r\n\r\n## b\r\n")), content="# a\n\n## b\n")
  inspect(
    serialize(parse("# a\r\n\r\n```\r\nx\r\n```\r\n")),
    content="# a\n\n```\r\nx\r\n```\n",
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
test "綴り — 引用の中の線は原文のまま。冪等" {
  let quote = "# r\n\n> a\n>\n> ---\n"
  let once = serialize(parse(quote))
  inspect(
    once,
    content=(
      #|# r
      #|
      #|> a
      #|>
      #|> ---
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

///|
/// #84 — 詰め（`loose`）は**項目と項目の間の空行**。ライブラリの `tight` は
/// 列のどこかに空行があれば偽なので、項目の中の空行でも偽になる。それで書き戻すと
/// 空行が項目の間へ移り、触っていない字が変わる（冪等でもなくなる）
test "綴り — 項目の中の空行は項目の間に移らない。冪等" {
  let inner = "# h\n\n- b\n\n  text\n- c\n"
  let once = serialize(parse(inner))
  inspect(
    once,
    content=(
      #|# h
      #|
      #|- b
      #|
      #|  text
      #|- c
      #|
    ),
  )
  inspect(once == inner, content="true")
  inspect(serialize(parse(once)) == once, content="true")
  let fenced = "# h\n\n- b\n\n  ```\n  x\n  ```\n- c\n"
  let again = serialize(parse(fenced))
  inspect(
    again,
    content=(
      #|# h
      #|
      #|- b
      #|
      #|  ```
      #|  x
      #|  ```
      #|- c
      #|
    ),
  )
  inspect(again == fenced, content="true")
  inspect(serialize(parse(again)) == again, content="true")
}

///|
/// #46 — ライブラリは**閉じたフェンスを含む引用**の span を空（`from == to`）で
/// 返し、その字を次の `BlankLines` に付ける。方言（`measured`）が原文から測り直す。
/// 直す前は木に引用が残らず、書き戻すと文書ごと消えていた
test "閉じたフェンスを含む引用の span は、原文から測り直す" {
  inspect(md_ast_sig("> ```\n> x\n> ```\n"), content="Quote[0,16]")
  inspect(
    md_ast_sig("# h\n\n> ```\n> x\n> ```\n\n# i\n"),
    content=(
      #|H1Atx[0,4] Blank1[4,5] Quote[5,21] Blank1[21,22] H1Atx[22,26]
    ),
  )
  // frontmatter の後ろでも、文書の尻でも同じ
  inspect(
    md_ast_sig("---\nk: v\n---\n\n> ```\n> x\n> ```\n"),
    content=(
      #|Front[0,13] Blank1[13,14] Quote[14,30]
    ),
  )
  // 閉じの無いフェンスなら span は元から在る（癖はこの形だけ）
  inspect(md_ast_sig("> ```\n> x\n"), content="Quote[0,10]")
}

///|
/// #46 — 測り直した span がそのまま原文になる。往復で字が 1 つも減らない
test "閉じたフェンスを含む引用は、書き戻しても字が減らない" {
  let cases = [
    "> ```\n> x\n> ```\n", "# h\n\n> ```\n> x\n> ```\n\n# i\n", "---\nk: v\n---\n\n> ```\n> x\n> ```\n",
    "> [!NOTE]\n> ```\n> x\n> ```\n",
  ]
  for md in cases {
    inspect(serialize(parse(md)) == md, content="true")
  }
}

///|
/// #178 — 水平線が続いても字は減らない。境界を取るのは最後の 1 本だけで、
/// 手前は書かれた場所（直前のノードの中身）に残る
test "水平線が続いても、書き戻せば本数はそのまま" {
  let cases = [
    "# a\n\n## b\n\n---\n\n---\n\n## c\n", "# a\n\n## b\n\n---\n\n---\n\n---\n\n## c\n",
    "# a\n\n## b\n\n---\n\n***\n\n## c\n", "# a\n\n## b\n\n---\n\n---\n", "# r\n\n## a\n\n---\n\n- i\n",
  ]
  for md in cases {
    inspect(serialize(parse(md)) == md, content="true")
    json_inspect(check(parse(md)), content=[])
  }
}

///|
/// #180 — GFM のタスクリスト（`- [ ] a`）は解釈しない。ライブラリは `[ ]` を
/// 食べて段落をその後ろから始めるので、ラベルはマーカーの後ろから測り直す。
/// **チェックは綴り**なので、名前の字にそのまま残る（地図にも `[ ] a` と出る）
test "タスクリストのチェックは名前の字" {
  json_inspect(parse("- [ ] a\n  - [x] b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "[ ] a",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "[x] b",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
/// #180 — 書き戻してもチェックの 4 文字は落ちない。字だけの項目（`- [ ]`）も、
/// 折り返した名前も、番号付きの列も同じ
test "タスクリストは、書き戻しても字が減らない" {
  let cases = [
    "- [ ] a\n  - [x] b\n", "* [X] a\n", "1. [ ] a\n", "- [ ] a\n  more\n", "- [ ]\n",
    "- [ ] a\n\n  text\n",
  ]
  for md in cases {
    inspect(serialize(parse(md)) == md, content="true")
  }
}

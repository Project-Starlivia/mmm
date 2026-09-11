// 項目（`- a`）が骨格として積まれることを固定する。
//
// 深さは**その列が座る枠の 1 つ下**。見出しは入れ子をリセットするので、同じ
// 字下げでも直前の見出し次第で深さが変わる。境界が引き出した先も同じ。
// 項目の中は文書（見出しは項目の子）と順序法則（兄弟は項目が先）もここ。

///|
test "項目だけの木" {
  json_inspect(parse("- root\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "root",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "入れ子は深くなる" {
  json_inspect(parse("- root\n  - a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "root",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
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
test "兄弟は並ぶ" {
  json_inspect(parse("- root\n  - a\n  - b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "root",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
            {
              "id": 4,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
test "見出しの下の項目は 1 つ深い" {
  json_inspect(parse("# r\n\n- a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
test "見出しは入れ子をリセットする" {
  json_inspect(parse("# r\n\n## s\n\n- a\n  - b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "s",
              "body": [],
              "children": [
                {
                  "id": 4,
                  "label": "a",
                  "body": [],
                  "children": [
                    {
                      "id": 5,
                      "label": "b",
                      "body": [],
                      "children": [],
                      "mark": [
                        "Item",
                        { "marker": "-", "offset": 2, "loose": false },
                      ],
                    },
                  ],
                  "mark": [
                    "Item",
                    { "marker": "-", "offset": 2, "loose": false },
                  ],
                },
              ],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
test "マーカーの銘柄は構造に影響しない" {
  json_inspect(parse("* a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "*", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
  json_inspect(parse("+ a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "+", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "順序リストも項目として読む" {
  json_inspect(parse("1. a\n2. b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "1.", "offset": 3, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 3,
          "label": "b",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "2.", "offset": 3, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "ラベルは原文のまま" {
  json_inspect(parse("- a **b**\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a **b**",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
/// **ラベルは 1 行目。** 途中の段落を引き上げると、その文字がラベルと
/// 中身の両方に出る（切り出しはブロックの範囲でやるので）。
test "1 行目が段落でなければラベルは無い" {
  json_inspect(parse("- ```\n  code\n  ```\n\n  x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "",
          "body": [
            {
              "id": 3,
              "content": ["Code", { "info": "", "text": "code\n" }],
              "source": "```\ncode\n```",
            },
            { "id": 4, "source": "x" },
          ],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "途中の段落はラベルにならない" {
  json_inspect(
    parse("- <details>\n  <summary>a</summary>\n\n  x\n\n  </details>\n"),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "a", "body": "x" },
                ],
                "source": "<details>\n<summary>a</summary>\n\nx\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// ラベルは項目の 1 行目の中身。**容器の字下げは剥がす** — 書き戻すとき
/// 行ごとの字下げと `\r` の総量ぶん手前で切れる。ラベルの末尾が消えていた。
test "続きの行があるラベルは末尾まで残る" {
  json_inspect(parse("- aaa\n  bbb\n  ccc\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "aaa\nbbb\nccc",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "CRLF でもラベルは末尾まで残る" {
  json_inspect(parse("- aaa\r\n  bbb\r\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "aaa\nbbb",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
/// **ラベルの端はインラインの並びからは導けない。** mdAst は 1 行目がリンクの
/// 定義行の形をしていると中身の一部を定義として引き取るので、インラインが
/// 行の全部を覆わないことがある。記法の側から引く。引き取られた行は
/// ラベルが抱えているので、中身として重ねて出さない。
test "定義行に見える 1 行目でもラベルは全部残る" {
  json_inspect(parse("- [q]: /r\n  ZZZ\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "[q]: /r\nZZZ",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
/// **項目の深さは、その列が座る枠の 1 つ下。** 入れ子の段数から数え直すと、
/// 境界が親の項目を深さ 2 へ引き出したときに元の位置から数えてしまい、
/// 間に綴られていない項目が生える（項目は相対記法なので飛びは存在しない）。
test "境界のあとの入れ子項目に空の項目が生えない" {
  json_inspect(parse("# r\n\n## h\n\n---\n\n- a\n  - b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "h",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 4,
              "label": "a",
              "body": [],
              "children": [
                {
                  "id": 5,
                  "label": "b",
                  "body": [],
                  "children": [],
                  "mark": [
                    "Item",
                    { "marker": "-", "offset": 2, "loose": false },
                  ],
                },
              ],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left"],
        "rules": ["", "---"],
      },
    ],
  })
}

///|
/// 同じ経路で、後ろの見出しが項目に化けていた。
test "境界のあとの入れ子項目の後ろでも見出しは見出し" {
  json_inspect(parse("# r\n\n## h\n\n### x\n\n---\n\n- a\n  - b\n\n### t\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "h",
              "body": [],
              "children": [
                {
                  "id": 4,
                  "label": "x",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 5,
              "label": "a",
              "body": [],
              "children": [
                {
                  "id": 6,
                  "label": "b",
                  "body": [],
                  "children": [],
                  "mark": [
                    "Item",
                    { "marker": "-", "offset": 2, "loose": false },
                  ],
                },
              ],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
            {
              "id": 7,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 8,
                  "label": "t",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left", "Left"],
        "rules": ["", "---", ""],
      },
    ],
  })
}

///|
/// **同じ列の項目は兄弟。** 境界は最初の項目を深さ 2 へ引き出すので、残りも
/// 引き出された先に並ぶ。見出し（`## b` `## c`）と同じ形になる。
test "境界のあとの兄弟項目は同じ深さに並ぶ" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n- b\n\n- c\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 4,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": true }],
            },
            {
              "id": 5,
              "label": "c",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": true }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left", "Left"],
        "rules": ["", "---", ""],
      },
    ],
  })
}

///|
/// **項目の深さは持ち主の 1 つ下。** 同じ項目の中身に列が 2 つあれば
/// （間に中身が挟まれば列は割れる）、2 つ目は前の列の子ではなく兄弟。
test "項目の中の 2 つ目の列は前の列の兄弟" {
  json_inspect(parse("- a\n\n  - b\n\n  text\n\n  - c\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "b",
              "body": [{ "id": 4, "source": "text" }],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
            {
              "id": 5,
              "label": "c",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

// ══════════════════════════════════════════════════════════════════
// 項目の中は文書 — `<li>` の中は、その項目の深さを 0 とした文書（docs/spec.md「項目の中」）
// ══════════════════════════════════════════════════════════════════

///|
/// 骨格だけを見る。深さぶん字下げして、綴りの印（`#` 見出し・`-` 項目・
/// `.` 飛び）とラベルを並べる。中身は枚数だけ。
fn skeleton(md : String) -> String {
  let out = []
  fn node(x : Node, depth : Int) -> Unit {
    let sign = match x.mark {
      Some(Heading(..)) => "#"
      Some(Item(..)) => "-"
      None => "."
    }
    let label = if x.label == "" { "" } else { " " + x.label }
    let body = if x.body.is_empty() {
      ""
    } else {
      " +" + x.body.length().to_string()
    }
    out.push("  ".repeat(depth - 1) + sign + label + body)
    for k in x.children {
      node(k, depth + 1)
    }
  }

  for r in parse(md).roots {
    node(r.node, 1)
  }
  out.join("\n")
}

///|
/// 顔（最初の塊）が見出しなら、項目のラベルは空でその見出しは子。
/// `<li>` は 1 つなので項目も 1 つ。
test "項目の中は文書 — 顔の見出しは子" {
  inspect(
    skeleton("- # head\n"),
    content=(
      #|-
      #|  # head
    ),
  )
}

///|
/// 2 塊目でも同じ。顔かどうかは関係ない（ラベルは顔が段落のときだけ）。
test "項目の中は文書 — 中の見出しは見出しのまま子になる" {
  json_inspect(parse("- a\n  # x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "x",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
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
/// `#` の本数は項目からの深さ。飛びは文書と同じく Implicit が埋める。
test "項目の中は文書 — 飛びは Implicit が埋める" {
  inspect(
    skeleton("- ## head\n"),
    content=(
      #|-
      #|  .
      #|    # head
    ),
  )
}

///|
/// 深い見出しは浅い見出しの子。
test "項目の中は文書 — 深い見出しは子" {
  inspect(
    skeleton("- # x\n  ## y\n"),
    content=(
      #|-
      #|  # x
      #|    # y
    ),
  )
}

///|
/// 浅く戻れば兄弟。飛びを埋めた Implicit の隣に並ぶ。
test "項目の中は文書 — 浅く戻れば兄弟" {
  inspect(
    skeleton("- ## x\n  # y\n"),
    content=(
      #|-
      #|  .
      #|    # x
      #|  # y
    ),
  )
}

///|
/// 順序法則も文書と同じ — 見出しの後ろの項目はその見出しの子。
test "項目の中は文書 — 見出しの後ろの項目は子" {
  inspect(
    skeleton("- # x\n  - y\n"),
    content=(
      #|-
      #|  # x
      #|    - y
    ),
  )
}

///|
/// 同じ深さの見出しは前の見出しを閉じるので、続く見出しは元の項目の子。
test "項目の中は文書 — 見出しを閉じれば元の項目の子" {
  inspect(
    skeleton("- x\n  # a\n  - k\n  # b\n"),
    content=(
      #|- x
      #|  # a
      #|    - k
      #|  # b
    ),
  )
}

///|
/// 積みは項目ごと。前の項目の見出しは次の項目に引きずられない。
test "項目の中は文書 — 積みは項目ごと" {
  inspect(
    skeleton("- ## a\n- # b\n"),
    content=(
      #|-
      #|  .
      #|    # a
      #|-
      #|  # b
    ),
  )
}

///|
/// 側は根の子だけの性質なので、項目の中の `---` は常に飾り（直前のノードの
/// 中身の尻）。境界にならないので、続く見出しは引き出されない。
test "項目の中は文書 — 中の水平線は飾り" {
  inspect(
    skeleton("- # x\n\n  ---\n\n  # y\n"),
    content=(
      #|-
      #|  # x +1
      #|  # y
    ),
  )
}

///|
/// 項目の中の見出しも `#` は 6 本まで。7 本目は段落なので中身に落ちる。
test "項目の中は文書 — 7 本目の # は中身" {
  inspect(
    skeleton("- ###### a\n  ####### b\n"),
    content=(
      #|-
      #|  .
      #|    .
      #|      .
      #|        .
      #|          .
      #|            # a +1
    ),
  )
}

///|
/// **項目の中の見出しも項目なので、畳みが立つ。** 覆う対象のノードが在る以上、
/// 綴り（`<details>` `<summary>`）は構造とフラグが引き受け、名前だけが木に残る。
test "項目の中は文書 — 中の見出しを包んだ畳みは、そのノードの畳み" {
  let with_fold = parse(
    "- item\n\n  <details>\n  <summary>h</summary>\n\n  ## h\n\n  </details>\n",
  )
  let without = parse("- item\n\n  ## h\n")
  // 畳みを書いた md と書いていない md が同じ木になってはいけない
  assert_not_eq(with_fold, without)
  // 残る字は項目の名前・見出しの名前・畳みの名前だけ（綴りは 1 つも残らない）
  assert_eq(written(with_fold), "item\nh\nh")
}

///|
/// 列 0 へ出れば項目が閉じるので、これは中身ではなく別の木（C17）。
test "項目の中は文書 — 列 0 の見出しは項目を閉じる" {
  json_inspect(parse("- a\n\n# x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 3,
          "label": "x",
          "body": [],
          "children": [],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
/// 列 0 の見出しは md でも項目を閉じる。深さの計算だけで項目の下へ潜ると
/// 単調性が破れるので、見出しを積む前に項目の枠を落とす。C17 を全部の
/// 深さへ広げたもの。
test "項目の中は文書 — 列 0 の深い見出しも項目の下へ潜らない" {
  json_inspect(parse("# r\n\n- b\n\n### x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
            {
              "id": 4,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 5,
                  "label": "x",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
test "項目の中は文書 — 列 0 の見出しは項目の根の下にも潜らない" {
  json_inspect(parse("- a\n\n### x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 3,
          "label": "",
          "body": [],
          "children": [
            {
              "id": 4,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 5,
                  "label": "x",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
test "項目の中は文書 — 列 0 の見出しは入れ子項目の後ろでも潜らない" {
  json_inspect(parse("# r\n\n- b\n\n  - c\n\n### x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "b",
              "body": [],
              "children": [
                {
                  "id": 4,
                  "label": "c",
                  "body": [],
                  "children": [],
                  "mark": [
                    "Item",
                    { "marker": "-", "offset": 2, "loose": false },
                  ],
                },
              ],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
            {
              "id": 5,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 6,
                  "label": "x",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
/// **意味は往復で失われない。** 項目の中の見出しは `#` のまま読み書きされ、
/// 書いた字を読み直しても同じ木になる（空行の数は正規形に落ちる）。
test "項目の中は文書 — 往復しても木は変わらず、書き方は落ち着く" {
  let corpus = [
    "- # head\n", "- a\n  # x\n", "- ## head\n", "- # x\n  ## y\n", "- ## x\n  # y\n",
    "- # x\n  - y\n", "- x\n  # a\n  - k\n  # b\n", "- ## a\n- # b\n", "- # x\n\n  ---\n\n  # y\n",
  ]
  let bad = []
  for md in corpus {
    let once = serialize(parse(md))
    if shape(parse(once)) != shape(parse(md)) {
      bad.push("木が変わる " + md.escape() + " -> " + once.escape())
    }
    if serialize(parse(once)) != once {
      bad.push("冪等でない " + once.escape())
    }
  }
  json_inspect(bad, content=[])
}

// ══════════════════════════════════════════════════════════════════
// 順序法則 — 兄弟は項目が先、見出しが後
// ══════════════════════════════════════════════════════════════════

///|
/// 兄弟に項目と見出しが並ぶのは、**項目が先のときだけ**。深さの規則から
/// 自動的にそうなるので、並べ替えは要らない。
test "順序法則 — 項目のあとの見出しは兄弟になる" {
  json_inspect(parse("# r\n\n- b\n\n## a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
            {
              "id": 4,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
/// 見出しのあとの項目は「直近の見出しの深さ + 1」なので、兄弟ではなく子。
/// だから [見出し, 項目] の並びは作られない。
test "順序法則 — 見出しのあとの項目は子になる" {
  json_inspect(parse("# r\n\n## a\n\n- b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [
                {
                  "id": 4,
                  "label": "b",
                  "body": [],
                  "children": [],
                  "mark": [
                    "Item",
                    { "marker": "-", "offset": 2, "loose": false },
                  ],
                },
              ],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

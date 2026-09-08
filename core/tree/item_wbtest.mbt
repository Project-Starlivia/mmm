// 項目（`- a`）が骨格として積まれることを固定する。
//
// 深さは**その列が座る枠の 1 つ下**。見出しは入れ子をリセットするので、同じ
// 字下げでも直前の見出し次第で深さが変わる。境界が引き出した先も同じ。

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
          "label": "aaa\r\nbbb",
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

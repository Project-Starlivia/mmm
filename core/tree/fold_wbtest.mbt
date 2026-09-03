// 畳み（`<details>`）を固定する。
//
// 領域が**ちょうど 1 つのノードの定義ごと**包んでいれば、そのノードの畳み
// （`details = true`、中身は普通に読む）。そうでなければ中身の 1 枚（`Details`）。

///|
test "定義ごと包んでいれば、そのノードの畳み" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n\nbody\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": true,
                  "body": [["Opaque", "body"]],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right"],
      },
    ],
  })
}

///|
/// `<summary>` はラベルと文字列が完全一致すれば畳み。
test "summary が一致すれば畳み" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n"),
    content={
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "HeadingNode",
            {
              "id": 2,
              "label": "r",
              "details": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h",
                    "details": true,
                    "body": [],
                    "children": [],
                  },
                ],
              ],
            },
          ],
          "sides": ["Right"],
        },
      ],
    },
  )
}

///|
/// 一致しなければ、領域は自分の名前を持つ別物なので中身に落ちる。
test "summary が一致しなければ中身" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>x</summary>\n\n## h\n\n</details>\n"),
    content={
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "HeadingNode",
            {
              "id": 2,
              "label": "r",
              "details": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>x</summary>\n\n## h\n\n</details>",
                  },
                ],
              ],
              "children": [],
            },
          ],
          "sides": [],
        },
      ],
    },
  )
}

///|
/// 見出しの行が領域の外にあるので、包んでいるのは中身だけ。
test "中身だけ包んでいれば中身の 1 枚" {
  json_inspect(parse("# r\n\n## h\n\n<details>\n\nbody\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": false,
                  "body": [
                    [
                      "Details",
                      { "id": 4, "text": "<details>\n\nbody\n\n</details>" },
                    ],
                  ],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right"],
      },
    ],
  })
}

///|
/// h の部分木より広いので、ちょうど覆っていない。
test "2 ノード分を包んでいれば中身" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n\n## h2\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [
              [
                "Details",
                { "id": 3, "text": "<details>\n\n## h\n\n## h2\n\n</details>" },
              ],
            ],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "最初が段落なら中身" {
  json_inspect(parse("# r\n\n<details>\n\nbodya\n\n# head\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [
              [
                "Details",
                {
                  "id": 3,
                  "text": "<details>\n\nbodya\n\n# head\n\n</details>",
                },
              ],
            ],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 空行を挟まないと md は 1 つの Html に潰すので、中の見出しが見出しにならない。
test "空行なしで 1 塊なら中身" {
  json_inspect(parse("# r\n\n<details>\n## h\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [["Opaque", "<details>\n## h\n</details>"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 打っている途中に文書の残りが吸い込まれないよう、片割れは畳まない。
test "閉じの無い開きはただの文字" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [["Opaque", "<details>"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right"],
      },
    ],
  })
}

///|
test "相手の居ない閉じもただの文字" {
  json_inspect(parse("# r\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [["Opaque", "</details>"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 畳みは見出しの階層に割り込まない。
test "畳みの後ろは元の深さに戻る" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n\n</details>\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": true,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "HeadingNode",
                {
                  "id": 4,
                  "label": "b",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Right"],
      },
    ],
  })
}

///|
test "項目も定義ごと包める" {
  json_inspect(parse("# r\n\n<details>\n\n- a\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [],
            "children": [
              [
                "ListNode",
                {
                  "id": 3,
                  "label": "a",
                  "details": true,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right"],
      },
    ],
  })
}

///|
/// 空行を挟まないと md は開きの塊に次の行を飲み込む。飲み込まれた行を
/// 捨てないよう、開きが `<details>` だけでなければ覆っていないものとして扱う。
/// **意味を 1 ビットも失わない**の帰結。
test "開きに飲み込まれた行があれば中身" {
  json_inspect(parse("# r\n\n<details>\n### x\n\n## y\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [
              [
                "Details",
                { "id": 3, "text": "<details>\n### x\n\n## y\n</details>" },
              ],
            ],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 同じ md でも空行 1 つで切れ方が変わる。どちらも中身に落ちるが、
/// 逐語の中身が違う。**md 自身の規則**なので mmm は従うだけ。
test "空行の有無で逐語が変わる" {
  let with_blank = parse("# r\n\n<details>\n\n### x\n\n## y\n</details>\n")
  let without = parse("# r\n\n<details>\n### x\n\n## y\n</details>\n")
  assert_not_eq(with_blank, without)
}

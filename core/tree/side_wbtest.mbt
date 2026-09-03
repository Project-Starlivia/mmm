// 水平線（thematic break）を固定する。
//
// 意味は常に「隣を区切る」。**直後のブロックが見出し・項目の行なら境界**で、
// それ以外は装飾。記法(`---` `***` `___`)も本数も判定に使わない。

///|
test "直後が見出しなら境界。側が裏返る" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n## b\n"), content={
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
                  "label": "a",
                  "details": false,
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
        "sides": ["Right", "Left"],
      },
    ],
  })
}

///|
test "先頭に置けば最初の子から左になる" {
  json_inspect(parse("# r\n\n---\n\n## a\n"), content={
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Left"],
      },
    ],
  })
}

///|
/// 境界は「直前のものの一部ではない」宣言なので、深さ 2 まで引き出す。
/// 見出しは絶対座標で動かせないので、足りない深さを Implicit が埋める。
test "深い見出しは Implicit を挟んで深さ 2 へ" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n### x\n"), content={
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "ImplicitNode",
                {
                  "id": 4,
                  "children": [
                    [
                      "HeadingNode",
                      {
                        "id": 5,
                        "label": "x",
                        "details": false,
                        "body": [],
                        "children": [],
                      },
                    ],
                  ],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Left"],
      },
    ],
  })
}

///|
/// 項目は相対記法で深さが導出値なので、深さ 2 に直接置き直せる。
test "項目は Implicit を挟まず深さ 2 へ" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n- b\n"), content={
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "ListNode",
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
        "sides": ["Right", "Left"],
      },
    ],
  })
}

///|
/// 深さ 2 では見出しと項目が交互に並ぶ。だから children は 1 本の列。
test "見出しと項目が交互に並ぶ" {
  json_inspect(
    parse("# root\n\n---\n\n## h1\n\n---\n\n* i1\n\n---\n\n## h2\n"),
    content={
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "HeadingNode",
            {
              "id": 2,
              "label": "root",
              "details": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h1",
                    "details": false,
                    "body": [],
                    "children": [],
                  },
                ],
                [
                  "ListNode",
                  {
                    "id": 4,
                    "label": "i1",
                    "details": false,
                    "body": [],
                    "children": [],
                  },
                ],
                [
                  "HeadingNode",
                  {
                    "id": 5,
                    "label": "h2",
                    "details": false,
                    "body": [],
                    "children": [],
                  },
                ],
              ],
            },
          ],
          "sides": ["Left", "Right", "Left"],
        },
      ],
    },
  )
}

///|
/// 兄弟の間でも同じ。y は x の一部ではないので引き出される。
test "兄弟の間の水平線も引き出す" {
  json_inspect(parse("# r\n\n## a\n\n### x\n\n---\n\n### y\n"), content={
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [
                    [
                      "HeadingNode",
                      {
                        "id": 4,
                        "label": "x",
                        "details": false,
                        "body": [],
                        "children": [],
                      },
                    ],
                  ],
                },
              ],
              [
                "ImplicitNode",
                {
                  "id": 5,
                  "children": [
                    [
                      "HeadingNode",
                      {
                        "id": 6,
                        "label": "y",
                        "details": false,
                        "body": [],
                        "children": [],
                      },
                    ],
                  ],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Left"],
      },
    ],
  })
}

///|
/// 直後が中身なら境界になれない。**書かれた場所にそのまま残る。**
test "中身に挟まれた水平線は装飾" {
  json_inspect(parse("# a\n\nbody\n\n---\n\nbody\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Opaque", "body"], "ThematicBreak", ["Opaque", "body"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "b",
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
/// 直前の中身を消すと、同じ線が境界に昇格する。md 自身の性質。
test "直前が中身でも、直後が見出しなら境界" {
  json_inspect(parse("# a\n\nbody\n\n---\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Opaque", "body"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Left"],
      },
    ],
  })
}

///|
/// 連続していても境界は 1 つ。最初の 1 本は直後が水平線なので装飾に落ちる。
test "本数に意味は無い" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n---\n\n## b\n"), content={
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
                  "label": "a",
                  "details": false,
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
        "sides": ["Right", "Left"],
      },
    ],
  })
}

///|
test "文末の水平線は装飾" {
  json_inspect(parse("# r\n\n## a\n\n---\n"), content={
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
                  "label": "a",
                  "details": false,
                  "body": ["ThematicBreak"],
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
/// 根は側を持たないので、引き出す先が無い。
test "根の直前の水平線は装飾" {
  json_inspect(parse("# r\n\n---\n\n# s\n"), content={
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
            "body": ["ThematicBreak"],
            "children": [],
          },
        ],
        "sides": [],
      },
      {
        "node": [
          "HeadingNode",
          {
            "id": 3,
            "label": "s",
            "details": false,
            "body": [],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "最初の見出しより前の水平線は文書の中身" {
  json_inspect(parse("body\n\n---\n\n# a\n"), content={
    "eol": "Lf",
    "body": [["Opaque", "body"], "ThematicBreak"],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// `***` も `___` も同じ意味。記法で差別しない。
test "記法は差別しない" {
  let dash = parse("# r\n\n---\n\n## a\n")
  assert_eq(dash, parse("# r\n\n***\n\n## a\n"))
  assert_eq(dash, parse("# r\n\n___\n\n## a\n"))
}

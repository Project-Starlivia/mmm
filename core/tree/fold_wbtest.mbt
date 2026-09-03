// 畳み（`<details>`）を固定する。
//
// **2 つ揃ったときだけ**そのノードの畳み（`details = true`、中身は普通に読む）:
// `<summary>` がラベルと一致し、領域がそのノードの body・children とその body を
// 過不足なく覆っている。欠ければ中身の 1 枚（`Details`）。

///|
test "名前と形が揃えば、そのノードの畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\nbody\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h",
                    "details": true,
                    "open": false,
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
    },
  )
}

///|
/// 名前が無ければ、領域が誰のものか言えていないので畳みではない。
test "summary が無ければ中身" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n\n</details>\n"), content={
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
            "open": false,
            "body": [
              [
                "Details",
                { "id": 3, "text": "<details>\n\n## h\n\n</details>" },
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
              "open": false,
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
            "open": false,
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": false,
                  "open": false,
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
            "open": false,
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
            "open": false,
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
            "open": false,
            "body": [
              ["Details", { "id": 3, "text": "<details>\n## h\n</details>" }],
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
            "open": false,
            "body": [["Opaque", "<details>"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": false,
                  "open": false,
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
            "open": false,
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
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n## b\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h",
                    "details": true,
                    "open": false,
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
                    "open": false,
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
    },
  )
}

///|
test "項目も定義ごと包める" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n"),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "ListNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
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
            "open": false,
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

///|
/// 入れ子も同じ規則で読む。外を解いたあと、中をまた同じ目で見る。
test "入れ子の畳みも畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details>\n<summary>a1</summary>\n\n### a1\n\n</details>\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [
                      [
                        "HeadingNode",
                        {
                          "id": 4,
                          "label": "a1",
                          "details": true,
                          "open": false,
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
          "sides": ["Right"],
        },
      ],
    },
  )
}

///|
/// 空行を挟まないと md は閉じを重ねて 1 つの塊にする。**何段ぶんかは数えれば
/// 分かる**ので、段ごとにほどいてから読む。外部レンダラが入れ子の畳みとして
/// 見せるものを、mmm も同じに読む。
test "重なった閉じはほどいて読む" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details>\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "x",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [
                      [
                        "HeadingNode",
                        {
                          "id": 4,
                          "label": "y",
                          "details": true,
                          "open": false,
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
          "sides": ["Right"],
        },
      ],
    },
  )
}

///|
/// `open` は畳みの姿の一部なので意味として持つ。捨てると外部レンダラでの
/// 見え方が変わってしまう。
test "open は畳みに持つ" {
  json_inspect(
    parse("# r\n\n<details open>\n<summary>h</summary>\n\n## h\n\n</details>\n"),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h",
                    "details": true,
                    "open": true,
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
/// 知らない属性は畳みの綴りではない。畳みにすると開きの塊ごと落ちて消えるので、
/// 領域まるごと逐語で持つ。
test "知らない属性が付いていれば中身" {
  json_inspect(
    parse(
      "# r\n\n<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>",
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
/// 開きが重なっていると、どの `<summary>` が誰のものか言えない。
/// ほどかず領域まるごと逐語で持つ。
test "重なった開きは中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>",
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
/// 項目も見出しと同じ道を通る。
test "項目の畳みにも open が付く" {
  json_inspect(
    parse("# r\n\n<details open>\n<summary>a</summary>\n\n- a\n\n</details>\n"),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "ListNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": true,
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
/// open は段ごとに別。外が閉じていて中が開いていてもよい。
test "内側だけ open" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details open>\n<summary>a1</summary>\n\n### a1\n\n</details>\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [
                      [
                        "HeadingNode",
                        {
                          "id": 4,
                          "label": "a1",
                          "details": true,
                          "open": true,
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
          "sides": ["Right"],
        },
      ],
    },
  )
}

///|
/// 行で分かれていなくても、`</details>` の並びなら数えられる。
test "同じ行に重なった閉じもほどく" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details></details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "x",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [
                      [
                        "HeadingNode",
                        {
                          "id": 4,
                          "label": "y",
                          "details": true,
                          "open": false,
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
          "sides": ["Right"],
        },
      ],
    },
  )
}

///|
test "3 段の重なりもほどく" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n\n<details>\n<summary>z</summary>\n\n#### z\n</details>\n</details>\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "x",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [
                      [
                        "HeadingNode",
                        {
                          "id": 4,
                          "label": "y",
                          "details": true,
                          "open": false,
                          "body": [],
                          "children": [
                            [
                              "HeadingNode",
                              {
                                "id": 5,
                                "label": "z",
                                "details": true,
                                "open": false,
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
/// 閉じが余ると、その塊は綴りとして落とせない（余った `</details>` が消える）。
/// 落とせない塊に頼る畳みも立たないので、領域は丸ごと逐語になる。
test "落とせない閉じに頼る畳みは立たない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>",
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
/// ラベルも `<summary>` の中身も原文の切り出しなので、記法ごと一致が要る。
test "summary は記法ごと一致する" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>**h**</summary>\n\n## **h**\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "**h**",
                    "details": true,
                    "open": false,
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
test "記法が違えば一致しない" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>h</summary>\n\n## **h**\n\n</details>\n"),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>h</summary>\n\n## **h**\n\n</details>",
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
/// 世間で一番普通の綴り。行で切ると落ちるので、綴りは字句で拾う。
test "1 行に書いた開きと名前も畳み" {
  json_inspect(
    parse("# r\n\n<details><summary>a</summary>\n\n## a\n\n</details>\n"),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
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
/// mmm が兄弟を 2 つ畳んだら書く形。**自分の書いたものを読み戻せること。**
test "兄弟の畳みは両方立つ" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [],
                  },
                ],
                [
                  "HeadingNode",
                  {
                    "id": 4,
                    "label": "b",
                    "details": true,
                    "open": false,
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
    },
  )
}

///|
/// `<details-x>` はカスタム要素で、畳みの開きではない。
/// 名前の直後が空白・`>`・`/` でなければタグとして読まない。
test "名前が違うタグは畳みの開きではない" {
  json_inspect(parse("# r\n\n<details-x>\n\n## a\n\n</details>\n"), content={
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
            "open": false,
            "body": [["Opaque", "<details-x>"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "a",
                  "details": false,
                  "open": false,
                  "body": [["Opaque", "</details>"]],
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
/// 開きの塊に名前が 2 枚あると、書き戻すとき 1 枚しか書けない。
/// 落とすと消えるので畳みにしない。
test "summary が 2 枚なら中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>",
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
/// 閉じの塊に地の文が続くと、塊ごと落とせないので畳みにしない。
test "閉じの塊に地の文が続けば中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\ntail\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>h</summary>\n\n## h\n\n</details>\ntail",
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
/// 項目も見出しと同じ検査を通る。領域の外の中身を畳みに取り込まない。
test "項目の畳みも領域の後ろを見る" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n\nx\n"),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>a</summary>\n\n- a\n\n</details>",
                  },
                ],
                ["Opaque", "x"],
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
/// **生テキストの中は跨ぐ。** `<script>` の中の文字列は閉じではない。
/// md が「ここは生の HTML」と言った範囲で HTML の字句規則に従うだけ。
test "script の中の閉じは綴りではない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<script>\nvar x = \"</details>\";\n</script>\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [
                      ["Opaque", "<script>\nvar x = \"</details>\";\n</script>"],
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
    },
  )
}

///|
/// コメントの中身はマップの意味論に一切参加しない。閉じにもならない。
test "コメントの中の閉じは綴りではない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<!-- </details> -->\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [["Opaque", "<!-- </details> -->"]],
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
/// **深さは md の `#` の数ではなく、build が実際に積んだ深さで測る。**
/// 境界の水平線は部分木を深さ 2 へ引き出すので、`### x` は `a` の子ではなく
/// 兄弟になる。領域は 2 つの部分木に跨っていて、1 ノードを覆っていない。
test "境界の水平線が領域の中にあれば中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n---\n\n### x\n\n</details>\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>a</summary>\n\n## a\n\n---\n\n### x\n\n</details>",
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
/// 飾りの水平線は中身なので、部分木の中に居る。畳みは立つ。
test "飾りの水平線が領域の中なら畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\nbody\n\n---\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [["Opaque", "body"], "ThematicBreak"],
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
/// 閉じの直後の境界は、部分木の外（兄弟との区切り）なので跨ぐ。
test "境界の水平線が閉じの直後なら畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n## b\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
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
                    "open": false,
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
    },
  )
}

///|
/// 飾りの水平線とその後ろの中身は `a` の body なので、領域が狭い。
test "飾りの水平線が閉じの直後なら中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\nsome text\n",
    ),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>a</summary>\n\n## a\n\n</details>",
                  },
                ],
                "ThematicBreak",
                ["Opaque", "some text"],
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
/// 飛びは部分木の中で埋まるので、領域は 1 ノードを覆っている。
test "飛びが領域の中でも畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n#### deep\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": true,
                    "open": false,
                    "body": [],
                    "children": [
                      [
                        "ImplicitNode",
                        {
                          "id": 4,
                          "children": [
                            [
                              "HeadingNode",
                              {
                                "id": 5,
                                "label": "deep",
                                "details": false,
                                "open": false,
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
/// **跨いでよいのは、実際に落ちる綴りの塊だけ。** 立たない畳みの綴りは中身
/// （逐語・ただの文字）になるので、跨ぐと領域の外の中身を畳みの内側へ引き込む。
test "後ろの領域が立たなければ跨がない" {
  json_inspect(
    parse(
      "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details>\n<summary>zz</summary>\n\n## c\n\n</details>\n",
    ),
    content={
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>b</summary>\n\n## b\n\n</details>",
                  },
                ],
                [
                  "Details",
                  {
                    "id": 4,
                    "text": "<details>\n<summary>zz</summary>\n\n## c\n\n</details>",
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
test "後ろの迷子のタグは跨がない" {
  json_inspect(
    parse(
      "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details>\n\n## c\n",
    ),
    content={
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>b</summary>\n\n## b\n\n</details>",
                  },
                ],
                ["Opaque", "<details>"],
              ],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 4,
                    "label": "c",
                    "details": false,
                    "open": false,
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
/// 文書の末尾の水平線は、その先に骨格が無いので飾り＝このノードの中身。
/// 領域はそれを覆っていないので畳みは立たない。
test "末尾の飾りの水平線は跨がない" {
  json_inspect(
    parse(
      "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n---\n",
    ),
    content={
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details>\n<summary>b</summary>\n\n## b\n\n</details>",
                  },
                ],
                "ThematicBreak",
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
/// **空打ちも畳みの綴りを跨ぐ。** 中身として数えると、保留中の水平線が
/// そこで装飾に落ちて、本番の木と深さがずれる。
test "畳みの前の境界は空打ちでも境界のまま" {
  json_inspect(
    parse(
      "# r\n\n## a\n\n---\n\n<details>\n<summary>c</summary>\n\n- c\n\n</details>\n\n- e\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": false,
                    "open": false,
                    "body": [
                      "ThematicBreak",
                      [
                        "Details",
                        {
                          "id": 4,
                          "text": "<details>\n<summary>c</summary>\n\n- c\n\n</details>",
                        },
                      ],
                    ],
                    "children": [
                      [
                        "ListNode",
                        {
                          "id": 5,
                          "label": "e",
                          "details": false,
                          "open": false,
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
          "sides": ["Right"],
        },
      ],
    },
  )
}

///|
/// **svg は foreign content。** 中の `details` は SVG の要素であって畳みでは
/// ないので数えない（数えると SVG のカードが畳みの逐語に化ける）。
test "svg の中のタグは綴りではない" {
  json_inspect(parse("# r\n\n## h\n\n<svg><details>a</details></svg>\n"), content={
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
            "open": false,
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "details": false,
                  "open": false,
                  "body": [["Svg", "<svg><details>a</details></svg>\n"]],
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
/// `<!` に `--` が続かない形と `<?` は擬似コメントで、最初の `>` までが中身。
test "擬似コメントの中の閉じは綴りではない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<?x </details> ?>\n\n</details>\n",
    ),
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
              "open": false,
              "body": [],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h",
                    "details": true,
                    "open": false,
                    "body": [["Opaque", "<?x </details> ?>"]],
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
/// 生テキストの名前は前方一致では見ない（`<pre` で `<presentation>` を
/// 拾わない）。`pre` はそもそも生テキストではないので一覧に無い。
test "pre は生テキストではない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<pre><details></pre>\n\n</details>\n\n## h2\n",
    ),
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
              "open": false,
              "body": [["Opaque", "<details>\n<summary>h</summary>"]],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "h",
                    "details": false,
                    "open": false,
                    "body": [
                      [
                        "Details",
                        {
                          "id": 4,
                          "text": "<pre><details></pre>\n\n</details>",
                        },
                      ],
                    ],
                    "children": [],
                  },
                ],
                [
                  "HeadingNode",
                  {
                    "id": 5,
                    "label": "h2",
                    "details": false,
                    "open": false,
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
    },
  )
}

///|
/// HTML で引用符が値を囲むのは `=` の直後だけ。それ以外の `\"` は属性名の
/// ただの文字なので、そこで囲みが始まったことにしない。
test "= の後ろでない引用符は囲みを始めない" {
  json_inspect(
    parse("# r\n\n<details \"x>\n<summary>h</summary>\n\n## h\n\n</details>\n"),
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
              "open": false,
              "body": [
                [
                  "Details",
                  {
                    "id": 3,
                    "text": "<details \"x>\n<summary>h</summary>\n\n## h\n\n</details>",
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

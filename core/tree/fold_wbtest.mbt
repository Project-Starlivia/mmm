// 畳み（`<details>`）を固定する。
//
// **形が揃ったときだけ**そのノードの畳み（`fold` が在る、中身は普通に読む）:
// 領域がそのノードの body・children とその body を過不足なく覆っている。
// 名前は持ち主を決めていないので、`<summary>` は書かれたまま持つだけ。

///|
test "形が揃えば、そのノードの畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\nbody\n\n</details>\n",
    ),
    content={
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
                "fold": { "open": false, "summary": "h" },
                "body": [{ "id": 4, "source": "body" }],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// 名前は持ち主を決めていない。決めているのは範囲のほう。
test "summary が無くても畳み" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n\n</details>\n"), content={
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
              "fold": { "open": false },
              "body": [],
              "children": [],
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
/// 名前はそのまま持つ。ラベルと一致していなくても畳みは立つ。
test "summary はラベルと違ってもよい" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>x</summary>\n\n## h\n\n</details>\n"),
    content={
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
                "fold": { "open": false, "summary": "x" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// 見出しの行が領域の外にあるので、包んでいるのは中身だけ。
test "中身だけ包んでいれば中身の 1 枚" {
  json_inspect(parse("# r\n\n## h\n\n<details>\n\nbody\n\n</details>\n"), content={
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
              "body": [
                {
                  "id": 4,
                  "content": ["Details", { "open": false, "body": "body" }],
                  "source": "<details>\n\nbody\n\n</details>",
                },
              ],
              "children": [],
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
/// h の部分木より広いので、ちょうど覆っていない。
test "2 ノード分を包んでいれば中身" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n\n## h2\n\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": ["Details", { "open": false, "body": "## h\n\n## h2" }],
              "source": "<details>\n\n## h\n\n## h2\n\n</details>",
            },
          ],
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
test "最初が段落なら中身" {
  json_inspect(parse("# r\n\n<details>\n\nbodya\n\n# head\n\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": [
                "Details",
                { "open": false, "body": "bodya\n\n# head" },
              ],
              "source": "<details>\n\nbodya\n\n# head\n\n</details>",
            },
          ],
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
/// 空行を挟まないと md は 1 つの Html に潰すので、中の見出しが見出しにならない。
test "空行なしで 1 塊なら中身" {
  json_inspect(parse("# r\n\n<details>\n## h\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": ["Details", { "open": false, "body": "## h" }],
              "source": "<details>\n## h\n</details>",
            },
          ],
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
/// 打っている途中に文書の残りが吸い込まれないよう、片割れは畳まない。
test "閉じの無い開きはただの文字" {
  json_inspect(parse("# r\n\n<details>\n\n## h\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [{ "id": 3, "source": "<details>" }],
          "children": [
            {
              "id": 4,
              "label": "h",
              "body": [],
              "children": [],
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
test "相手の居ない閉じもただの文字" {
  json_inspect(parse("# r\n\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [{ "id": 3, "source": "</details>" }],
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
/// 畳みは見出しの階層に割り込まない。
test "畳みの後ろは元の深さに戻る" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n## b\n",
    ),
    content={
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
                "fold": { "open": false, "summary": "h" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 4,
                "label": "b",
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
    },
  )
}

///|
test "項目も定義ごと包める" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>a</summary>\n\n- a\n\n</details>\n"),
    content={
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
                "fold": { "open": false, "summary": "a" },
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
    },
  )
}

///|
/// 空行を挟まないと md は開きの塊に次の行を飲み込む。飲み込まれた行を
/// 捨てないよう、開きが `<details>` だけでなければ覆っていないものとして扱う。
/// **意味を 1 ビットも失わない**の帰結。
test "開きに飲み込まれた行があれば中身" {
  json_inspect(parse("# r\n\n<details>\n### x\n\n## y\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": ["Details", { "open": false, "body": "### x\n\n## y" }],
              "source": "<details>\n### x\n\n## y\n</details>",
            },
          ],
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
/// 同じ md でも空行 1 つで切れ方が変わる。どちらも中身に落ちるが、
/// 切り出しの中身が違う。**md 自身の規則**なので mmm は従うだけ。
test "空行の有無で切り出しが変わる" {
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
                "fold": { "open": false, "summary": "a" },
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "a1",
                    "fold": { "open": false, "summary": "a1" },
                    "body": [],
                    "children": [],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
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
                "label": "x",
                "fold": { "open": false, "summary": "x" },
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "y",
                    "fold": { "open": false, "summary": "y" },
                    "body": [],
                    "children": [],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
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
                "fold": { "open": true, "summary": "h" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// 知らない属性は畳みの綴りではない。畳みにすると開きの塊ごと落ちて消えるので、
/// 領域まるごと原文のまま持つ。
test "知らない属性が付いていれば中身" {
  json_inspect(
    parse(
      "# r\n\n<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "h", "body": "## h" },
                ],
                "source": "<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// 開きが重なっていると、どの `<summary>` が誰のものか言えない。
/// ほどかず領域まるごと原文のまま持つ。
test "重なった開きは中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  {
                    "open": false,
                    "body": "<details>\n<summary>h</summary>\n\n## h\n\n</details>",
                  },
                ],
                "source": "<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
                "fold": { "open": true, "summary": "a" },
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
                "fold": { "open": false, "summary": "a" },
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "a1",
                    "fold": { "open": true, "summary": "a1" },
                    "body": [],
                    "children": [],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
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
                "label": "x",
                "fold": { "open": false, "summary": "x" },
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "y",
                    "fold": { "open": false, "summary": "y" },
                    "body": [],
                    "children": [],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
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
                "label": "x",
                "fold": { "open": false, "summary": "x" },
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "y",
                    "fold": { "open": false, "summary": "y" },
                    "body": [],
                    "children": [
                      {
                        "id": 5,
                        "label": "z",
                        "fold": { "open": false, "summary": "z" },
                        "body": [],
                        "children": [],
                        "mark": ["Heading", { "setext": false, "closing": 0 }],
                      },
                    ],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
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
    },
  )
}

///|
/// 閉じが余ると、その塊は綴りとして落とせない（余った `</details>` が消える）。
/// 落とせない塊に頼る畳みも立たないので、領域は丸ごと原文のまま残る。
test "落とせない閉じに頼る畳みは立たない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "y", "body": "## y" },
                ],
                "source": "<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// `<summary>` の中身は原文の切り出しで、記法ごとそのまま持つ。
test "summary は原文のまま持つ" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>**h**</summary>\n\n## **h**\n\n</details>\n",
    ),
    content={
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
                "label": "**h**",
                "fold": { "open": false, "summary": "**h**" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
test "記法つきのラベルと違う summary も持つ" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>h</summary>\n\n## **h**\n\n</details>\n"),
    content={
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
                "label": "**h**",
                "fold": { "open": false, "summary": "h" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
                "fold": { "open": false, "summary": "a" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
                "fold": { "open": false, "summary": "a" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 4,
                "label": "b",
                "fold": { "open": false, "summary": "b" },
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
    },
  )
}

///|
/// `<details-x>` はカスタム要素で、畳みの開きではない。
/// 名前の直後が空白・`>`・`/` でなければタグとして読まない。
test "名前が違うタグは畳みの開きではない" {
  json_inspect(parse("# r\n\n<details-x>\n\n## a\n\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [{ "id": 3, "source": "<details-x>" }],
          "children": [
            {
              "id": 4,
              "label": "a",
              "body": [{ "id": 5, "source": "</details>" }],
              "children": [],
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
/// 開きの塊に名前が 2 枚あると、書き戻すとき 1 枚しか書けない。
/// 落とすと消えるので畳みにしない。
test "summary が 2 枚なら中身" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  {
                    "open": false,
                    "summary": "h",
                    "body": "<summary>ZZZ</summary>\n\n## h",
                  },
                ],
                "source": "<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "h", "body": "## h" },
                ],
                "source": "<details>\n<summary>h</summary>\n\n## h\n\n</details>\ntail",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "a", "body": "- a" },
                ],
                "source": "<details>\n<summary>a</summary>\n\n- a\n\n</details>",
              },
              { "id": 4, "source": "x" },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
                "fold": { "open": false, "summary": "a" },
                "body": [
                  {
                    "id": 4,
                    "source": "<script>\nvar x = \"</details>\";\n</script>",
                  },
                ],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
                "fold": { "open": false, "summary": "a" },
                "body": [{ "id": 4, "source": "<!-- </details> -->" }],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  {
                    "open": false,
                    "summary": "a",
                    "body": "## a\n\n---\n\n### x",
                  },
                ],
                "source": "<details>\n<summary>a</summary>\n\n## a\n\n---\n\n### x\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
                "fold": { "open": false, "summary": "a" },
                "body": [
                  { "id": 4, "source": "body" },
                  { "id": 5, "content": "ThematicBreak", "source": "---" },
                ],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
                "fold": { "open": false, "summary": "a" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 4,
                "label": "b",
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right", "Left"],
          "rules": ["", "---"],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "a", "body": "## a" },
                ],
                "source": "<details>\n<summary>a</summary>\n\n## a\n\n</details>",
              },
              { "id": 4, "content": "ThematicBreak", "source": "---" },
              { "id": 5, "source": "some text" },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
                "fold": { "open": false, "summary": "a" },
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "",
                    "body": [],
                    "children": [
                      {
                        "id": 5,
                        "label": "deep",
                        "body": [],
                        "children": [],
                        "mark": ["Heading", { "setext": false, "closing": 0 }],
                      },
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
    },
  )
}

///|
/// **跨いでよいのは、実際に落ちる綴りの塊だけ。** 立たない畳みの綴りは中身
/// （Details・ただの文字）になるので、跨ぐと領域の外の中身を畳みの内側へ引き込む。
test "後ろの領域が立たなければ跨がない" {
  json_inspect(
    parse(
      "# a\n\n<details>\n<summary>b</summary>\n\n## b\n\n</details>\n\n<details class=\"z\">\n<summary>c</summary>\n\n## c\n\n</details>\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "b", "body": "## b" },
                ],
                "source": "<details>\n<summary>b</summary>\n\n## b\n\n</details>",
              },
              {
                "id": 4,
                "content": [
                  "Details",
                  { "open": false, "summary": "c", "body": "## c" },
                ],
                "source": "<details class=\"z\">\n<summary>c</summary>\n\n## c\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "b", "body": "## b" },
                ],
                "source": "<details>\n<summary>b</summary>\n\n## b\n\n</details>",
              },
              { "id": 4, "source": "<details>" },
            ],
            "children": [
              {
                "id": 5,
                "label": "c",
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "b", "body": "## b" },
                ],
                "source": "<details>\n<summary>b</summary>\n\n## b\n\n</details>",
              },
              { "id": 4, "content": "ThematicBreak", "source": "---" },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
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
                "label": "c",
                "fold": { "open": false, "summary": "c" },
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
              {
                "id": 5,
                "label": "e",
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right", "Left", "Left"],
          "rules": ["", "---", ""],
        },
      ],
    },
  )
}

///|
/// **svg は foreign content。** 中の `details` は SVG の要素であって畳みでは
/// ないので数えない（数えると SVG のカードが畳みの中身に化ける）。
test "svg の中のタグは綴りではない" {
  json_inspect(parse("# r\n\n## h\n\n<svg><details>a</details></svg>\n"), content={
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
              "body": [
                {
                  "id": 4,
                  "content": ["Svg", "<svg><details>a</details></svg>\n"],
                  "source": "<svg><details>a</details></svg>",
                },
              ],
              "children": [],
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
/// `<!` に `--` が続かない形と `<?` は擬似コメントで、最初の `>` までが中身。
test "擬似コメントの中の閉じは綴りではない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n<?x </details> ?>\n\n</details>\n",
    ),
    content={
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
                "fold": { "open": false, "summary": "h" },
                "body": [{ "id": 4, "source": "<?x </details> ?>" }],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [{ "id": 3, "source": "<details>\n<summary>h</summary>" }],
            "children": [
              {
                "id": 4,
                "label": "h",
                "body": [
                  {
                    "id": 5,
                    "content": ["Details", { "open": false, "body": "</pre>" }],
                    "source": "<pre><details></pre>\n\n</details>",
                  },
                ],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 6,
                "label": "h2",
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
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "h", "body": "## h" },
                ],
                "source": "<details \"x>\n<summary>h</summary>\n\n## h\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// **深さも「実際に落ちる塊」を跨いで測る。** 綴りに見えても落ちない塊
/// （対にならない `<summary>` など）は本番では中身になり、そこで保留中の
/// 水平線が装飾に落ちる。跨いでしまうと水平線が保留のまま次の骨格を引き出し、
/// 領域の外に書かれた見出しが畳みの中へ入る。
test "落ちない綴りの塊は深さでも跨がない" {
  json_inspect(
    parse(
      "# r\n\n<details>\n\n## s\n\n---\n\n<summary>z</summary>\n\n</details>\n\n### a\n\n### b\n\n## t\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "z", "body": "" },
                ],
                "source": "<details>\n\n## s\n\n---\n\n<summary>z</summary>\n\n</details>",
              },
            ],
            "children": [
              {
                "id": 4,
                "label": "",
                "body": [],
                "children": [
                  {
                    "id": 5,
                    "label": "a",
                    "body": [],
                    "children": [],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
                  },
                  {
                    "id": 6,
                    "label": "b",
                    "body": [],
                    "children": [],
                    "mark": ["Heading", { "setext": false, "closing": 0 }],
                  },
                ],
              },
              {
                "id": 7,
                "label": "t",
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
    },
  )
}

///|
/// **そのブロック自身のノードは、最初に座る綴られた枠。** 1 つの塊が項目を
/// 何段も積むので、最後に座った枠を「持ち主の深さ」にすると、領域の外に
/// 書かれた項目まで畳みの中に入る。
test "入れ子項目を含む塊でも、持ち主の深さで測る" {
  json_inspect(
    parse(
      "# r\n\n## h\n\n---\n\n<details>\n\n- a\n  - b\n\n</details>\n\n- c\n",
    ),
    content={
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
                "fold": { "open": false },
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
              {
                "id": 6,
                "label": "c",
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right", "Left", "Left"],
          "rules": ["", "---", ""],
        },
      ],
    },
  )
}

///|
/// **領域の中に書いた水平線は、領域の中の骨格にしか効かない。** 行き先が
/// 領域の外なら、その水平線は部分木のものではない（畳みが立つと綴りは木から
/// 消えるので、書き戻したとき領域の外へ出てしまう）。
test "領域の中の境界が外の骨格を引き出せば中身" {
  json_inspect(
    parse("# r\n\n<details>\n\n## a\n\n---\n\n</details>\n\n## b\n"),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": ["Details", { "open": false, "body": "## a\n\n---" }],
                "source": "<details>\n\n## a\n\n---\n\n</details>",
              },
            ],
            "children": [
              {
                "id": 4,
                "label": "b",
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// **水平線の本数に意味は無い。** 続けて書いても境界は 1 つで、最後の 1 本が取る。
/// 手前の 1 本は装飾なので、その場のノード（畳まれた `a`）の中身に落ちる —
/// 書き戻すと `</details>` の内側に移る。兄弟の間に置かれた塊の居場所が
/// 木に無いのは #181 と同じ形（字は減らないが位置が動く）。
test "閉じの直後の水平線が続いても境界" {
  json_inspect(
    parse(
      "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n---\n\n## b\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "a", "body": "## a" },
                ],
                "source": "<details>\n<summary>a</summary>\n\n## a\n\n</details>",
              },
              { "id": 4, "content": "ThematicBreak", "source": "---" },
            ],
            "children": [
              {
                "id": 5,
                "label": "b",
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Left"],
          "rules": ["---"],
        },
      ],
    },
  )
}

///|
/// **タグの間の空白は綴りではない。** 1 行に並べても行で分けても言っている
/// ことは同じで、書き戻すときは mmm の並べ方になる。
test "タブで繋いだ開きと名前も畳み" {
  json_inspect(
    parse("# r\n\n<details>	<summary>s</summary>\n\n## a\n\n</details>\n"),
    content={
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
                "fold": { "open": false, "summary": "s" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// 中身の Details は GitHub が描くのと同じものを読む — `open`、直後の `<summary>`、
/// 閉じまでの間の原文。導出はしない（名前が無ければ無いまま）。
test "中身の Details は open と summary と中身を読む" {
  json_inspect(
    parse(
      "# r\n\n## h\n\n<details open>\n<summary>s</summary>\n\nbody\n\nmore\n\n</details>\n",
    ),
    content={
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
                "body": [
                  {
                    "id": 4,
                    "content": [
                      "Details",
                      { "open": true, "summary": "s", "body": "body\n\nmore" },
                    ],
                    "source": "<details open>\n<summary>s</summary>\n\nbody\n\nmore\n\n</details>",
                  },
                ],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// 項目の中の畳みの後ろに兄弟の項目が続いても、兄弟は部分木の外なので畳みは立つ
/// （見出しの下の「項目の畳みも領域の後ろを見る」と同じ理屈）。
test "項目の中の畳みは、兄弟の項目が続いても立つ" {
  json_inspect(
    parse(
      "- a\n\n  <details>\n  <summary>b</summary>\n\n  - b\n\n  </details>\n\n  - c\n",
    ),
    content={
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
                "fold": { "open": false, "summary": "b" },
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
              {
                "id": 4,
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
    },
  )
}

///|
/// #181 — **閉じは境界と同じ。** 領域は部分木を過不足なく覆うので、`</details>` の
/// 後ろに書かれたものはその部分木の外。畳んだノードの枠を降ろすので、続く項目は
/// 子ではなく兄弟になる（GitHub が縦に 3 つ並べて描くのと同じ）。
/// 側は裏返らない — 裏返すのは `---` だけ
test "閉じの後ろの項目は、畳んだノードの兄弟" {
  json_inspect(
    parse(
      "# root\n\n- head\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\n- y\n",
    ),
    content={
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
                "label": "head",
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
              {
                "id": 4,
                "label": "head",
                "fold": { "open": false, "summary": "head" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 5,
                "label": "y",
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Right", "Right", "Right"],
          "rules": ["", "", ""],
        },
      ],
    },
  )
}

///|
/// #181 — 閉じの後ろが深い見出しなら、畳んだノードの子にはなれない（領域の外）。
/// 間を Implicit が埋める
test "閉じの後ろの深い見出しは、Implicit を挟んで兄弟の下へ" {
  json_inspect(
    parse(
      "# root\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\n### z\n",
    ),
    content={
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
                "label": "head",
                "fold": { "open": false, "summary": "head" },
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 4,
                "label": "",
                "body": [],
                "children": [
                  {
                    "id": 5,
                    "label": "z",
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
    },
  )
}

///|
/// #181 — 閉じの後ろが骨格でなければ、その中身は畳むノードの body。
/// 領域が部分木より狭いので畳みは立たない（今までどおり Details カード）
test "閉じの後ろが中身なら畳みは立たない" {
  json_inspect(
    parse(
      "# root\n\n<details>\n<summary>head</summary>\n\n## head\n\n</details>\n\ntext\n",
    ),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "root",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "summary": "head", "body": "## head" },
                ],
                "source": "<details>\n<summary>head</summary>\n\n## head\n\n</details>",
              },
              { "id": 4, "source": "text" },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// #181 — 閉じを境界と同じに見ても、字は 1 つも動かない
test "閉じの後ろに何が来ても、書き戻せば同じ字" {
  let d = "<details>\n<summary>head</summary>\n\n## head\n\n</details>"
  let cases = [
    "# root\n\n- head\n\n" + d + "\n\n- y\n",
    "# root\n\n- head\n\n" + d + "\n\n## y\n",
    "# root\n\n- head\n\n" + d + "\n\n### z\n",
    "# root\n\n- head\n\n" + d + "\n\n# w\n",
    "# root\n\n- head\n\n" + d + "\n\n---\n\n- y\n",
    "# root\n\n- head\n\n" + d + "\n\n- y\n  - z\n",
  ]
  for md in cases {
    inspect(serialize(parse(md)) == md, content="true")
    json_inspect(check(parse(md)), content=[])
  }
}

///|
/// #178 #181 — 閉じの後ろの水平線は、**直後が骨格なら**境界。続けて書けば手前の
/// 1 本は飾りなので、領域は部分木より狭い ＝ 畳みは立たない。どちらも字は動かない
test "閉じの後ろの水平線は、直後が骨格なら境界" {
  // 1 本なら境界。畳みは立つ
  let one = "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n## b\n"
  inspect(serialize(parse(one)) == one, content="true")
  inspect(parse(one).to_json().stringify().contains("fold"), content="true")
  // 2 本なら手前は飾り。畳みは立たず、領域ごと中身になる
  let two = "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n</details>\n\n---\n\n---\n\n## b\n"
  inspect(serialize(parse(two)) == two, content="true")
  inspect(parse(two).to_json().stringify().contains("fold"), content="false")
  json_inspect(check(parse(two)), content=[])
}

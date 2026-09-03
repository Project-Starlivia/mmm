// 骨格でないものが、いま積んでいるノードの中身になることを固定する。
//
// 絵になるのは 4 つだけで、疑わしきは Opaque（逐語）。

///|
test "散文はノードの中身になる" {
  json_inspect(parse("# a\n\nhello\n"), content={
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
            "body": [["Opaque", "hello"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "中身は文書順に並ぶ" {
  json_inspect(parse("# a\n\nhello\n\nworld\n"), content={
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
            "body": [["Opaque", "hello"], ["Opaque", "world"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "中身は深さで振り分けられる" {
  json_inspect(parse("# a\n\nx\n\n## b\n\ny\n"), content={
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
            "body": [["Opaque", "x"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
                  "open": false,
                  "body": [["Opaque", "y"]],
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
test "最初の骨格より前の散文は文書のもの" {
  json_inspect(parse("intro\n\n# a\n"), content={
    "eol": "Lf",
    "body": [["Opaque", "intro"]],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "open": false,
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
test "画像" {
  json_inspect(parse("# a\n\n![alt](x.png)\n"), content={
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
            "body": [["Image", { "alt": "alt", "src": "x.png", "title": "" }]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "リンク" {
  json_inspect(parse("# a\n\n[text](https://e.com)\n"), content={
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
              ["Link", { "text": "text", "href": "https://e.com", "title": "" }],
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
test "混ざった段落は切り分けない" {
  json_inspect(parse("# a\n\nsee ![alt](x.png)\n"), content={
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
            "body": [["Opaque", "see ![alt](x.png)"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "フェンスのコード" {
  json_inspect(parse("# a\n\n```js\nlet x = 1\n```\n"), content={
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
            "body": [["Code", { "info": "js", "text": "let x = 1\n" }]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "インデントコードも読む（書くのはフェンス）" {
  json_inspect(parse("# a\n\n    code\n"), content={
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
            "body": [["Code", { "info": "", "text": "code\n" }]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "SVG" {
  json_inspect(parse("# a\n\n<svg><rect/></svg>\n"), content={
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
            "body": [["Svg", "<svg><rect/></svg>\n"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "飾りの水平線は Rule" {
  json_inspect(parse("# a\n\n***\n"), content={
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
            "body": ["ThematicBreak"],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "引用と表は逐語のまま" {
  json_inspect(parse("# a\n\n> quote\n"), content={
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
            "body": [["Opaque", "> quote"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "項目にも中身が付く" {
  json_inspect(parse("- a\n\n  hello\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "open": false,
            "body": [["Opaque", "hello"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// **容器の字下げは剥がす。** 項目の中の行頭の空白はその項目の記法であって
/// 中身ではない。剥がさないと逐語の列がずれ、深い入れ子では読み直したときに
/// 字下げコードへ化ける。
test "項目の中の逐語は列 0 に揃う" {
  json_inspect(parse("- a\n\n  <details>\n\n  ## h\n\n  </details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
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
/// 2 段でも同じ。剥がす幅は容器の字下げそのもの。
test "入れ子の項目でも列 0 に揃う" {
  json_inspect(
    parse("- a\n  - b\n\n    <details>\n\n    ## h\n\n    </details>\n"),
    content={
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "ListNode",
            {
              "id": 2,
              "label": "a",
              "details": false,
              "open": false,
              "body": [],
              "children": [
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
                  "open": false,
                  "body": [
                    [
                      "Details",
                      { "id": 4, "text": "<details>\n\n## h\n\n</details>" },
                    ],
                  ],
                  "children": [],
                },
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
/// Opaque も同じ規則で切る。
test "項目の中の Opaque も列 0 に揃う" {
  json_inspect(parse("- a\n\n  <!-- x\n  y -->\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "open": false,
            "body": [["Opaque", "<!-- x\ny -->"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 改行の流儀は逐語の中でも保つ（`Doc.eol` は書き戻すときの流儀）。
test "CRLF は逐語の中でも保たれる" {
  json_inspect(
    parse("# r\r\n\r\n<details>\r\n\r\n## h\r\n\r\n</details>\r\n"),
    content={
      "eol": "Crlf",
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
                  { "id": 3, "text": "<details>\r\n\r\n## h\r\n\r\n</details>" },
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
/// **リンクの定義行は書いてあった位置に戻す。** mdAst はこれをブロックとして
/// 返さず `Document.definitions` に分けて持つので、読まないと行ごと消える。
/// 文書のどこに書いてもよい記法なので、まとめて 1 か所へ動かすと
/// 触っていない場所が動く。
test "リンクの定義行は位置ごと残る" {
  json_inspect(parse("# r\n\n[a]: b \"c\"\n\n## h\n"), content={
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
            "body": [["Opaque", "[a]: b \"c\""]],
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
test "定義行が文末にあっても残る" {
  json_inspect(parse("# r\n\n## h\n\n[a]: b\n"), content={
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
                  "body": [["Opaque", "[a]: b"]],
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
/// タイトルは中身なので落とさない。木の形と renderer の props は別でよい。
test "画像とリンクのタイトルは残る" {
  json_inspect(parse("# r\n\n![a](b.png \"t1\")\n\n[c](d \"t2\")\n"), content={
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
              ["Image", { "alt": "a", "src": "b.png", "title": "t1" }],
              ["Link", { "text": "c", "href": "d", "title": "t2" }],
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
/// `$$` と `:::` の span は閉じの行を含まないので、原文のまま持つと閉じが落ちる。
/// フェンスのコードは `Block::Code` として綴りごと持つので、こちらは要らない。
test "数式とディレクティブの閉じは残る" {
  json_inspect(parse("# r\n\n$$\nx\n$$\n\n:::note\ny\n:::\n"), content={
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
            "body": [["Opaque", "$$\nx\n$$"], ["Opaque", ":::note\ny\n:::"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

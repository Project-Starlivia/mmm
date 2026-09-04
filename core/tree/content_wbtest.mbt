// 骨格でないものが、いま積んでいるノードの中身になることを固定する。
//
// 絵になるのは 4 つだけで、疑わしきは Opaque（原文のまま）。

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
            "body": [{ "id": 3, "content": ["Opaque", "hello"] }],
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
            "body": [
              { "id": 3, "content": ["Opaque", "hello"] },
              { "id": 4, "content": ["Opaque", "world"] },
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
            "body": [{ "id": 3, "content": ["Opaque", "x"] }],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 4,
                  "label": "b",
                  "body": [{ "id": 5, "content": ["Opaque", "y"] }],
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
    "body": [{ "id": 2, "content": ["Opaque", "intro"] }],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 3, "label": "a", "body": [], "children": [] },
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
            "body": [
              {
                "id": 3,
                "content": [
                  "Image",
                  { "alt": "alt", "src": "x.png", "title": "" },
                ],
              },
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
            "body": [
              {
                "id": 3,
                "content": [
                  "Link",
                  { "text": "text", "href": "https://e.com", "title": "" },
                ],
              },
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
            "body": [{ "id": 3, "content": ["Opaque", "see ![alt](x.png)"] }],
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
            "body": [
              {
                "id": 3,
                "content": ["Code", { "info": "js", "text": "let x = 1\n" }],
              },
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
            "body": [
              { "id": 3, "content": ["Code", { "info": "", "text": "code\n" }] },
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
            "body": [{ "id": 3, "content": ["Svg", "<svg><rect/></svg>\n"] }],
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
            "body": [{ "id": 3, "content": "ThematicBreak" }],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "引用と表は原文のまま" {
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
            "body": [{ "id": 3, "content": ["Opaque", "> quote"] }],
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
            "body": [{ "id": 3, "content": ["Opaque", "hello"] }],
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
/// 中身ではない。剥がさないと切り出しの列がずれ、深い入れ子では読み直したときに
/// 字下げコードへ化ける。
test "項目の中の切り出しは列 0 に揃う" {
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
            "body": [
              {
                "id": 3,
                "content": ["Details", "<details>\n\n## h\n\n</details>"],
              },
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
              "body": [],
              "children": [
                {
                  "id": 3,
                  "label": "b",
                  "body": [
                    {
                      "id": 4,
                      "content": ["Details", "<details>\n\n## h\n\n</details>"],
                    },
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
            "body": [{ "id": 3, "content": ["Opaque", "<!-- x\ny -->"] }],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 改行の流儀は切り出しの中でも保つ（`Doc.eol` は書き戻すときの流儀）。
test "CRLF は切り出しの中でも保たれる" {
  json_inspect(
    parse("# r\r\n\r\n<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>\r\n"),
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
              "body": [
                {
                  "id": 3,
                  "content": [
                    "Details", "<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>",
                  ],
                },
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
            "body": [{ "id": 3, "content": ["Opaque", "[a]: b \"c\""] }],
            "children": [
              [
                "HeadingNode",
                { "id": 4, "label": "h", "body": [], "children": [] },
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
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "h",
                  "body": [{ "id": 4, "content": ["Opaque", "[a]: b"] }],
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
            "body": [
              {
                "id": 3,
                "content": [
                  "Image",
                  { "alt": "a", "src": "b.png", "title": "t1" },
                ],
              },
              {
                "id": 4,
                "content": ["Link", { "text": "c", "href": "d", "title": "t2" }],
              },
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
            "body": [
              { "id": 3, "content": ["Opaque", "$$\nx\n$$"] },
              { "id": 4, "content": ["Opaque", ":::note\ny\n:::"] },
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
/// **定義行は項目の中にも書ける。** 定義は文書ぜんぶで 1 列なので、項目を
/// 読み解くときはその項目のぶんだけ切り出して渡す。まとめて外へ出すと、
/// 触っていない場所が動く。
test "項目の中の定義行は項目の中に残る" {
  json_inspect(parse("- a\n  - b\n\n    [q]: /r\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "body": [],
            "children": [
              {
                "id": 3,
                "label": "b",
                "body": [{ "id": 4, "content": ["Opaque", "[q]: /r"] }],
                "children": [],
              },
            ],
          },
        ],
        "sides": ["Right"],
      },
    ],
  })
}

///|
/// **同じ行を 2 度は出さない。** 原文のまま持つ領域は定義行ごと抱えるので、
/// そこに重ねて出すと、書き戻したとき定義行が増える。
test "原文のまま持つ領域の中の定義行は重ねない" {
  json_inspect(
    parse("# r\n\n<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>\n"),
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
              "body": [
                {
                  "id": 3,
                  "content": [
                    "Details", "<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>",
                  ],
                },
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
/// **定義行は畳みの領域に入れない。** 開きとノードの間に書いてあれば、それは
/// そのノードのものではない要素なので①が欠ける（畳みが立つと綴りは木から
/// 消えるので、書き戻したとき定義行が領域の外へ出る）。
test "開きとノードの間の定義行があれば中身" {
  json_inspect(parse("# r\n\n<details>\n\n[q]: /r\n\n## a\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details", "<details>\n\n[q]: /r\n\n## a\n\n</details>",
                ],
              },
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
/// **定義行は塊にならないが中身。** 保留中の水平線はそこで飾りに落ちるので、
/// 後ろの見出しは境界の先ではなく普通の子になる。
test "定義行は保留中の水平線を飾りに落とす" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n[q]: /r\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "a",
                  "body": [
                    { "id": 4, "content": "ThematicBreak" },
                    { "id": 5, "content": ["Opaque", "[q]: /r"] },
                  ],
                  "children": [],
                },
              ],
              [
                "HeadingNode",
                { "id": 6, "label": "b", "body": [], "children": [] },
              ],
            ],
          },
        ],
        "sides": ["Right", "Right"],
      },
    ],
  })
}

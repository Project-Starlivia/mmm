// 骨格でないものが、いま積んでいるノードの中身になることを固定する。
//
// 絵になるのは 4 つだけで、疑わしきは Raw（原文のまま）。

///|
test "散文はノードの中身になる" {
  json_inspect(parse("# a\n\nhello\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": ["Raw", "hello"], "source": "hello" }],
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
test "中身は文書順に並ぶ" {
  json_inspect(parse("# a\n\nhello\n\nworld\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            { "id": 3, "content": ["Raw", "hello"], "source": "hello" },
            { "id": 4, "content": ["Raw", "world"], "source": "world" },
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
test "中身は深さで振り分けられる" {
  json_inspect(parse("# a\n\nx\n\n## b\n\ny\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": ["Raw", "x"], "source": "x" }],
          "children": [
            {
              "id": 4,
              "label": "b",
              "body": [{ "id": 5, "content": ["Raw", "y"], "source": "y" }],
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
test "最初の骨格より前の散文は文書のもの" {
  json_inspect(parse("intro\n\n# a\n"), content={
    "body": [{ "id": 2, "content": ["Raw", "intro"], "source": "intro" }],
    "roots": [
      {
        "node": {
          "id": 3,
          "label": "a",
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
test "画像" {
  json_inspect(parse("# a\n\n![alt](x.png)\n"), content={
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
                "Image",
                { "alt": "alt", "src": "x.png", "title": "" },
              ],
              "source": "![alt](x.png)",
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
test "リンク" {
  json_inspect(parse("# a\n\n[text](https://e.com)\n"), content={
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
                "Link",
                { "text": "text", "href": "https://e.com", "title": "" },
              ],
              "source": "[text](https://e.com)",
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
test "混ざった段落は切り分けない" {
  json_inspect(parse("# a\n\nsee ![alt](x.png)\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Raw", "see ![alt](x.png)"],
              "source": "see ![alt](x.png)",
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
test "フェンスのコード" {
  json_inspect(parse("# a\n\n```js\nlet x = 1\n```\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Code", { "info": "js", "text": "let x = 1\n" }],
              "source": "```js\nlet x = 1\n```",
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
test "インデントコードも読む（書くのはフェンス）" {
  json_inspect(parse("# a\n\n    code\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Code", { "info": "", "text": "code\n" }],
              "source": "code",
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
test "SVG" {
  json_inspect(parse("# a\n\n<svg><rect/></svg>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Svg", "<svg><rect/></svg>\n"],
              "source": "<svg><rect/></svg>",
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
test "飾りの水平線は Rule" {
  json_inspect(parse("# a\n\n***\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": "ThematicBreak", "source": "***" }],
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
test "引用と表は原文のまま" {
  json_inspect(parse("# a\n\n> quote\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            { "id": 3, "content": ["Raw", "> quote"], "source": "> quote" },
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
test "項目にも中身が付く" {
  json_inspect(parse("- a\n\n  hello\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": ["Raw", "hello"], "source": "hello" }],
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
/// **容器の字下げを剥がすから、項目の中の `<details>` も畳みとして読める。**
/// 剥がさないと切り出しの列がずれ、深い入れ子では字下げコードへ化ける。
/// 包まれた `## h` は項目の子になり、畳みはその見出しに乗る。
test "項目の中の畳みは、包んだ見出しに乗る" {
  json_inspect(parse("- a\n\n  <details>\n\n  ## h\n\n  </details>\n"), content={
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
              "label": "h",
              "fold": { "open": false },
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
/// 2 段でも同じ。剥がす幅は容器の字下げそのものなので、深い項目でも畳みは乗る。
test "入れ子の項目でも、畳みは包んだ見出しに乗る" {
  json_inspect(
    parse("- a\n  - b\n\n    <details>\n\n    ## h\n\n    </details>\n"),
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
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "h",
                    "fold": { "open": false },
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
            "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// Raw も同じ規則で切る。
test "項目の中の Raw も列 0 に揃う" {
  json_inspect(parse("- a\n\n  <!-- x\n  y -->\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Raw", "<!-- x\ny -->"],
              "source": "<!-- x\ny -->",
            },
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
/// 読んだ原文は切り出しの中でも字のまま（書き足す改行は LF だけ）。
test "CRLF は切り出しの中でも保たれる" {
  json_inspect(
    parse("# r\r\n\r\n<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>\r\n"),
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
                    "text": "<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>",
                    "open": false,
                    "body": "## h",
                  },
                ],
                "source": "<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>",
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
/// **リンクの定義行は書いてあった位置に戻す。** mdAst はこれをブロックとして
/// 返さず `Document.definitions` に分けて持つので、読まないと行ごと消える。
/// 文書のどこに書いてもよい記法なので、まとめて 1 か所へ動かすと
/// 触っていない場所が動く。
test "リンクの定義行は位置ごと残る" {
  json_inspect(parse("# r\n\n[a]: b \"c\"\n\n## h\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": ["Raw", "[a]: b \"c\""],
              "source": "[a]: b \"c\"",
            },
          ],
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
test "定義行が文末にあっても残る" {
  json_inspect(parse("# r\n\n## h\n\n[a]: b\n"), content={
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
                { "id": 4, "content": ["Raw", "[a]: b"], "source": "[a]: b" },
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
/// タイトルは中身なので落とさない。木の形と renderer の props は別でよい。
test "画像とリンクのタイトルは残る" {
  json_inspect(parse("# r\n\n![a](b.png \"t1\")\n\n[c](d \"t2\")\n"), content={
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
                "Image",
                { "alt": "a", "src": "b.png", "title": "t1" },
              ],
              "source": "![a](b.png \"t1\")",
            },
            {
              "id": 4,
              "content": ["Link", { "text": "c", "href": "d", "title": "t2" }],
              "source": "[c](d \"t2\")",
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
/// `$$` と `:::` の span は閉じの行を含まないので、原文のまま持つと閉じが落ちる。
/// フェンスのコードは `Block::Code` として綴りごと持つので、こちらは要らない。
test "数式とディレクティブの閉じは残る" {
  json_inspect(parse("# r\n\n$$\nx\n$$\n\n:::note\ny\n:::\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            { "id": 3, "content": ["Raw", "$$\nx\n$$"], "source": "$$\nx\n$$" },
            {
              "id": 4,
              "content": ["Raw", ":::note\ny\n:::"],
              "source": ":::note\ny\n:::",
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
/// **定義行は項目の中にも書ける。** 定義は文書ぜんぶで 1 列なので、項目を
/// 読み解くときはその項目のぶんだけ切り出して渡す。まとめて外へ出すと、
/// 触っていない場所が動く。
test "項目の中の定義行は項目の中に残る" {
  json_inspect(parse("- a\n  - b\n\n    [q]: /r\n"), content={
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
              "body": [
                { "id": 4, "content": ["Raw", "[q]: /r"], "source": "[q]: /r" },
              ],
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
/// **同じ行を 2 度は出さない。** 原文のまま持つ領域は定義行ごと抱えるので、
/// そこに重ねて出すと、書き戻したとき定義行が増える。
test "原文のまま持つ領域の中の定義行は重ねない" {
  json_inspect(
    parse("# r\n\n<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>\n"),
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
                    "text": "<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>",
                    "open": false,
                    "body": "junk\n\n[q]: /r\n\n## a",
                  },
                ],
                "source": "<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>",
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
/// **定義行は畳みの領域に入れない。** 開きとノードの間に書いてあれば、それは
/// そのノードのものではない要素なので①が欠ける（畳みが立つと綴りは木から
/// 消えるので、書き戻したとき定義行が領域の外へ出る）。
test "開きとノードの間の定義行があれば中身" {
  json_inspect(parse("# r\n\n<details>\n\n[q]: /r\n\n## a\n\n</details>\n"), content={
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
                  "text": "<details>\n\n[q]: /r\n\n## a\n\n</details>",
                  "open": false,
                  "body": "[q]: /r\n\n## a",
                },
              ],
              "source": "<details>\n\n[q]: /r\n\n## a\n\n</details>",
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
/// **定義行は塊にならないが中身。** 保留中の水平線はそこで飾りに落ちるので、
/// 後ろの見出しは境界の先ではなく普通の子になる。
test "定義行は保留中の水平線を飾りに落とす" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n[q]: /r\n\n## b\n"), content={
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
              "body": [
                { "id": 4, "content": "ThematicBreak", "source": "---" },
                { "id": 5, "content": ["Raw", "[q]: /r"], "source": "[q]: /r" },
              ],
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
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
/// 素の URL の行と `<URL>` は、書き方が違うだけの同じリンク。
/// **見える字が URL そのもの**なので `text` は URL になる。
/// 開ける先だけ（`http(s)`）で、字が混ざれば Raw。
test "素の URL とオートリンク" {
  fn body(md : String) -> Json {
    parse("# a\n\n" + md + "\n").roots[0].node.body
    .map(b => b.content)
    .to_json()
  }

  json_inspect(
    [
      body("https://e.com/x"),
      body("<https://e.com/x>"),
      body("http://e.com"),
      body("see https://e.com/x"),
      body("https://e.com/x y"),
      body("ftp://e.com/x"),
      body("<mailto:a@e.com>"),
    ],
    content=[
      [
        [
          "Link",
          { "text": "https://e.com/x", "href": "https://e.com/x", "title": "" },
        ],
      ],
      [
        [
          "Link",
          { "text": "https://e.com/x", "href": "https://e.com/x", "title": "" },
        ],
      ],
      [
        [
          "Link",
          { "text": "http://e.com", "href": "http://e.com", "title": "" },
        ],
      ],
      [["Raw", "see https://e.com/x"]],
      [["Raw", "https://e.com/x y"]],
      [["Raw", "ftp://e.com/x"]],
      [["Raw", "<mailto:a@e.com>"]],
    ],
  )
}

///|
/// 貼り付けは一番外の段落だけを行ごとにノードにする。段落かどうかは mdAst が言う。
test "lines — 段落なら行の列、それ以外の中身は None" {
  assert_eq(lines("a\nb\n"), Some(["a", "b"]))
  assert_eq(lines("  a  \r\n\r\n"), Some(["a"]))
  assert_eq(lines("**a** and [b](c)\n"), Some(["**a** and [b](c)"]))
  assert_eq(lines("| a | b |\n|---|---|\n| 1 | 2 |\n"), None)
  assert_eq(lines("> q\n"), None)
  assert_eq(lines("<div>x</div>\n"), None)
  assert_eq(lines("```\nx\n```\n"), None)
  assert_eq(lines(""), None)
}

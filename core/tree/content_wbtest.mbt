// 骨格でないものが、いま積んでいるノードの中身になることを固定する。
//
// 絵になるのは 4 つだけで、疑わしきは Opaque（逐語）。

///|
test "散文はノードの中身になる" {
  json_inspect(parse("# a\n\nhello\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Opaque", "hello"]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "中身は文書順に並ぶ" {
  json_inspect(parse("# a\n\nhello\n\nworld\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Opaque", "hello"], ["Opaque", "world"]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "中身は深さで振り分けられる" {
  json_inspect(parse("# a\n\nx\n\n## b\n\ny\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Opaque", "x"]],
          },
          "items": [],
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Explicit",
                {
                  "node": {
                    "id": 3,
                    "label": "b",
                    "folded": false,
                    "body": [["Opaque", "y"]],
                  },
                  "items": [],
                  "headings": [],
                },
              ],
            },
          ],
        },
      ],
    ],
  })
}

///|
test "最初の骨格より前の散文は文書のもの" {
  json_inspect(parse("intro\n\n# a\n"), content={
    "eol": "Lf",
    "body": [["Opaque", "intro"]],
    "roots": [
      [
        "Explicit",
        {
          "node": { "id": 2, "label": "a", "folded": false, "body": [] },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "画像" {
  json_inspect(parse("# a\n\n![alt](x.png)\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Content", ["Image", { "alt": "alt", "src": "x.png" }]]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "リンク" {
  json_inspect(parse("# a\n\n[text](https://e.com)\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [
              ["Content", ["Link", { "text": "text", "href": "https://e.com" }]],
            ],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "混ざった段落は切り分けない" {
  json_inspect(parse("# a\n\nsee ![alt](x.png)\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Opaque", "see ![alt](x.png)"]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "フェンスのコード" {
  json_inspect(parse("# a\n\n```js\nlet x = 1\n```\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [
              ["Content", ["Code", { "info": "js", "text": "let x = 1\n" }]],
            ],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "インデントコードも読む（書くのはフェンス）" {
  json_inspect(parse("# a\n\n    code\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Content", ["Code", { "info": "", "text": "code\n" }]]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "SVG" {
  json_inspect(parse("# a\n\n<svg><rect/></svg>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Content", ["Svg", "<svg><rect/></svg>\n"]]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "飾りの水平線は Rule" {
  json_inspect(parse("# a\n\n***\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": { "id": 2, "label": "a", "folded": false, "body": ["Rule"] },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "引用と表は逐語のまま" {
  json_inspect(parse("# a\n\n> quote\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Opaque", "> quote"]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "項目にも中身が付く" {
  json_inspect(parse("- a\n\n  hello\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": {
            "id": 2,
            "label": "a",
            "folded": false,
            "body": [["Opaque", "hello"]],
          },
          "items": [],
        },
      ],
    ],
  })
}

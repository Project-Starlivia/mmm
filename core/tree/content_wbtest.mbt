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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "hello"]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "hello"], ["Opaque", "world"]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "x"]],
          },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                {
                  "sign": "Heading",
                  "label": "b",
                  "folded": false,
                  "body": [["Opaque", "y"]],
                },
              ],
              "children": [],
            },
          },
        ],
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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "a", "folded": false, "body": [] },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Content", ["Image", { "alt": "alt", "src": "x.png" }]]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [
              ["Content", ["Link", { "text": "text", "href": "https://e.com" }]],
            ],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "see ![alt](x.png)"]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [
              ["Content", ["Code", { "info": "js", "text": "let x = 1\n" }]],
            ],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Content", ["Code", { "info": "", "text": "code\n" }]]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Content", ["Svg", "<svg><rect/></svg>\n"]]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "a", "folded": false, "body": ["Rule"] },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "> quote"]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Item",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "hello"]],
          },
        ],
        "wings": [],
      },
    ],
  })
}

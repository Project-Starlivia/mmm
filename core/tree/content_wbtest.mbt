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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Opaque", "x"]],
            "children": [
              [
                "Head",
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
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
          "Head",
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
test "画像" {
  json_inspect(parse("# a\n\n![alt](x.png)\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Image", { "alt": "alt", "src": "x.png" }]],
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Link", { "text": "text", "href": "https://e.com" }]],
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": ["Rule"],
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
          "Head",
          {
            "id": 2,
            "label": "a",
            "details": false,
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
          "List",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Opaque", "hello"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

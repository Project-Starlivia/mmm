// 「この md はこの mmmTree になる」を固定する。
//
// 期待値は `json_inspect` が `moon test -u` で埋める。JSON への変換は
// derive(ToJson) の導出なので、**テストの土台に手書きのコードが無い**
// （手書きだと、その変換自身が間違っていてもテストは緑になる）。

///|
test "見出し 1 つが木 1 本になる" {
  json_inspect(parse("# a\n"), content={
    "eol": "Lf",
    "body": [],
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
test "深さ 1 が 2 つなら木も 2 本" {
  json_inspect(parse("# a\n\n# b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "a", "folded": false, "body": [] },
        ],
        "wings": [],
      },
      {
        "id": 3,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "b", "folded": false, "body": [] },
        ],
        "wings": [],
      },
    ],
  })
}

///|
test "深さ 2 は根の翼になる" {
  json_inspect(parse("# r\n\n## a\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "r", "folded": false, "body": [] },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "a", "folded": false, "body": [] },
              ],
              "children": [],
            },
          },
          {
            "side": "Right",
            "branch": {
              "id": 4,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "b", "folded": false, "body": [] },
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
test "深さ 3 は翼の下の枝" {
  json_inspect(parse("# r\n\n## a\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "r", "folded": false, "body": [] },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "a", "folded": false, "body": [] },
              ],
              "children": [
                {
                  "id": 4,
                  "node": [
                    "Explicit",
                    {
                      "sign": "Heading",
                      "label": "x",
                      "folded": false,
                      "body": [],
                    },
                  ],
                  "children": [],
                },
              ],
            },
          },
        ],
      },
    ],
  })
}

///|
test "浅く戻る" {
  json_inspect(parse("# r\n\n## a\n\n### x\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "r", "folded": false, "body": [] },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "a", "folded": false, "body": [] },
              ],
              "children": [
                {
                  "id": 4,
                  "node": [
                    "Explicit",
                    {
                      "sign": "Heading",
                      "label": "x",
                      "folded": false,
                      "body": [],
                    },
                  ],
                  "children": [],
                },
              ],
            },
          },
          {
            "side": "Right",
            "branch": {
              "id": 5,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "b", "folded": false, "body": [] },
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
test "飛びは Implicit が埋める" {
  json_inspect(parse("# r\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "r", "folded": false, "body": [] },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": "Implicit",
              "children": [
                {
                  "id": 4,
                  "node": [
                    "Explicit",
                    {
                      "sign": "Heading",
                      "label": "x",
                      "folded": false,
                      "body": [],
                    },
                  ],
                  "children": [],
                },
              ],
            },
          },
        ],
      },
    ],
  })
}

///|
test "深さ 1 が無ければ根が Implicit になる" {
  json_inspect(parse("## a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": "Implicit",
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "a", "folded": false, "body": [] },
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
test "ラベルは原文の逐語（インラインを解釈しない）" {
  json_inspect(parse("# a **b** `c`\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "a **b** `c`",
            "folded": false,
            "body": [],
          },
        ],
        "wings": [],
      },
    ],
  })
}

///|
test "中身の無い見出しは空ラベル" {
  json_inspect(parse("# \n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "", "folded": false, "body": [] },
        ],
        "wings": [],
      },
    ],
  })
}

///|
test "封筒" {
  json_inspect(parse("---\nk: v\n---\n\n# a\n"), content={
    "frontmatter": "k: v\n",
    "eol": "Lf",
    "body": [],
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
test "改行の流儀は保存する" {
  json_inspect(parse("# a\r\n"), content={
    "eol": "Crlf",
    "body": [],
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

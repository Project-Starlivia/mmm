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
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
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
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
      {
        "node": [
          "HeadingNode",
          { "id": 3, "label": "b", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "深さ 2 は根の子になる" {
  json_inspect(parse("# r\n\n## a\n\n## b\n"), content={
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
                { "id": 3, "label": "a", "body": [], "children": [] },
              ],
              [
                "HeadingNode",
                { "id": 4, "label": "b", "body": [], "children": [] },
              ],
            ],
          },
        ],
        "sides": ["Right", "Right"],
      },
    ],
  })
}

///|
test "深さ 3 は根の子の下" {
  json_inspect(parse("# r\n\n## a\n\n### x\n"), content={
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
                  "body": [],
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 4, "label": "x", "body": [], "children": [] },
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
  })
}

///|
test "浅く戻る" {
  json_inspect(parse("# r\n\n## a\n\n### x\n\n## b\n"), content={
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
                  "body": [],
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 4, "label": "x", "body": [], "children": [] },
                    ],
                  ],
                },
              ],
              [
                "HeadingNode",
                { "id": 5, "label": "b", "body": [], "children": [] },
              ],
            ],
          },
        ],
        "sides": ["Right", "Right"],
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
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "ImplicitNode",
                {
                  "id": 3,
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 4, "label": "x", "body": [], "children": [] },
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
  })
}

///|
test "深さ 1 が無ければ根が Implicit になる" {
  json_inspect(parse("## a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ImplicitNode",
          {
            "id": 2,
            "children": [
              [
                "HeadingNode",
                { "id": 3, "label": "a", "body": [], "children": [] },
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
test "ラベルは原文のまま（インラインを解釈しない）" {
  json_inspect(parse("# a **b** `c`\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a **b** `c`", "body": [], "children": [] },
        ],
        "sides": [],
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
        "node": [
          "HeadingNode",
          { "id": 2, "label": "", "body": [], "children": [] },
        ],
        "sides": [],
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
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
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
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// **インラインの span は中身に対する相対。** 原文の絶対位置に足すと、
/// 行ごとの字下げと `\r` の総量ぶん手前で切れてラベルの末尾が消える。
test "setext のラベルも末尾まで残る" {
  json_inspect(parse("aaa\r\nbbb\r\n===\r\n"), content={
    "eol": "Crlf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "aaa\r\nbbb", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

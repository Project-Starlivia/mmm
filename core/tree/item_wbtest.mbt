// 項目（`- a`）が骨格として積まれることを固定する。
//
// 深さは「直近の見出しの深さ + 1 + 入れ子段数」。**見出しは入れ子をリセットする**
// ので、同じ字下げでも直前の見出し次第で深さが変わる。

///|
test "項目だけの木" {
  json_inspect(parse("- root\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "List",
          {
            "id": 2,
            "label": "root",
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
test "入れ子は深くなる" {
  json_inspect(parse("- root\n  - a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "List",
          {
            "id": 2,
            "label": "root",
            "details": false,
            "body": [],
            "children": [
              {
                "id": 3,
                "label": "a",
                "details": false,
                "body": [],
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
test "兄弟は並ぶ" {
  json_inspect(parse("- root\n  - a\n  - b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "List",
          {
            "id": 2,
            "label": "root",
            "details": false,
            "body": [],
            "children": [
              {
                "id": 3,
                "label": "a",
                "details": false,
                "body": [],
                "children": [],
              },
              {
                "id": 4,
                "label": "b",
                "details": false,
                "body": [],
                "children": [],
              },
            ],
          },
        ],
        "sides": ["Right", "Right"],
      },
    ],
  })
}

///|
test "見出しの下の項目は 1 つ深い" {
  json_inspect(parse("# r\n\n- a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "Head",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [],
            "children": [
              [
                "List",
                {
                  "id": 3,
                  "label": "a",
                  "details": false,
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
test "見出しは入れ子をリセットする" {
  json_inspect(parse("# r\n\n## s\n\n- a\n  - b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "Head",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [],
            "children": [
              [
                "Head",
                {
                  "id": 3,
                  "label": "s",
                  "details": false,
                  "body": [],
                  "children": [
                    [
                      "List",
                      {
                        "id": 4,
                        "label": "a",
                        "details": false,
                        "body": [],
                        "children": [
                          {
                            "id": 5,
                            "label": "b",
                            "details": false,
                            "body": [],
                            "children": [],
                          },
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
  })
}

///|
test "マーカーの銘柄は構造に影響しない" {
  json_inspect(parse("* a\n"), content={
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
            "body": [],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
  json_inspect(parse("+ a\n"), content={
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
test "順序リストも項目として読む" {
  json_inspect(parse("1. a\n2. b\n"), content={
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
            "body": [],
            "children": [],
          },
        ],
        "sides": [],
      },
      {
        "node": [
          "List",
          {
            "id": 3,
            "label": "b",
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
test "ラベルは原文の逐語" {
  json_inspect(parse("- a **b**\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "List",
          {
            "id": 2,
            "label": "a **b**",
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

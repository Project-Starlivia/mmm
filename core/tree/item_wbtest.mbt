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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "root", "folded": false, "body": [] },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "root", "folded": false, "body": [] },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                { "sign": "Item", "label": "a", "folded": false, "body": [] },
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
test "兄弟は並ぶ" {
  json_inspect(parse("- root\n  - a\n  - b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "root", "folded": false, "body": [] },
        ],
        "wings": [
          {
            "side": "Right",
            "branch": {
              "id": 3,
              "node": [
                "Explicit",
                { "sign": "Item", "label": "a", "folded": false, "body": [] },
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
                { "sign": "Item", "label": "b", "folded": false, "body": [] },
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
test "見出しの下の項目は 1 つ深い" {
  json_inspect(parse("# r\n\n- a\n"), content={
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
                { "sign": "Item", "label": "a", "folded": false, "body": [] },
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
test "見出しは入れ子をリセットする" {
  json_inspect(parse("# r\n\n## s\n\n- a\n  - b\n"), content={
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
                { "sign": "Heading", "label": "s", "folded": false, "body": [] },
              ],
              "children": [
                {
                  "id": 4,
                  "node": [
                    "Explicit",
                    {
                      "sign": "Item",
                      "label": "a",
                      "folded": false,
                      "body": [],
                    },
                  ],
                  "children": [
                    {
                      "id": 5,
                      "node": [
                        "Explicit",
                        {
                          "sign": "Item",
                          "label": "b",
                          "folded": false,
                          "body": [],
                        },
                      ],
                      "children": [],
                    },
                  ],
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
test "マーカーの銘柄は構造に影響しない" {
  json_inspect(parse("* a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "a", "folded": false, "body": [] },
        ],
        "wings": [],
      },
    ],
  })
  json_inspect(parse("+ a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "a", "folded": false, "body": [] },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "a", "folded": false, "body": [] },
        ],
        "wings": [],
      },
      {
        "id": 3,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "b", "folded": false, "body": [] },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "a **b**", "folded": false, "body": [] },
        ],
        "wings": [],
      },
    ],
  })
}

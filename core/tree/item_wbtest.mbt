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
      [
        "Item",
        {
          "node": { "id": 2, "label": "root", "folded": false, "body": [] },
          "items": [],
        },
      ],
    ],
  })
}

///|
test "入れ子は深くなる" {
  json_inspect(parse("- root\n  - a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "root", "folded": false, "body": [] },
          "items": [
            {
              "side": "Right",
              "branch": {
                "node": { "id": 3, "label": "a", "folded": false, "body": [] },
                "children": [],
              },
            },
          ],
        },
      ],
    ],
  })
}

///|
test "兄弟は並ぶ" {
  json_inspect(parse("- root\n  - a\n  - b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "root", "folded": false, "body": [] },
          "items": [
            {
              "side": "Right",
              "branch": {
                "node": { "id": 3, "label": "a", "folded": false, "body": [] },
                "children": [],
              },
            },
            {
              "side": "Right",
              "branch": {
                "node": { "id": 4, "label": "b", "folded": false, "body": [] },
                "children": [],
              },
            },
          ],
        },
      ],
    ],
  })
}

///|
test "見出しの下の項目は 1 つ深い" {
  json_inspect(parse("# r\n\n- a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": { "id": 2, "label": "r", "folded": false, "body": [] },
          "items": [
            {
              "side": "Right",
              "branch": {
                "node": { "id": 3, "label": "a", "folded": false, "body": [] },
                "children": [],
              },
            },
          ],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "見出しは入れ子をリセットする" {
  json_inspect(parse("# r\n\n## s\n\n- a\n  - b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": { "id": 2, "label": "r", "folded": false, "body": [] },
          "items": [],
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 3, "label": "s", "folded": false, "body": [] },
                  "items": [
                    {
                      "node": {
                        "id": 4,
                        "label": "a",
                        "folded": false,
                        "body": [],
                      },
                      "children": [
                        {
                          "node": {
                            "id": 5,
                            "label": "b",
                            "folded": false,
                            "body": [],
                          },
                          "children": [],
                        },
                      ],
                    },
                  ],
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
test "マーカーの銘柄は構造に影響しない" {
  json_inspect(parse("* a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "a", "folded": false, "body": [] },
          "items": [],
        },
      ],
    ],
  })
  json_inspect(parse("+ a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "a", "folded": false, "body": [] },
          "items": [],
        },
      ],
    ],
  })
}

///|
test "順序リストも項目として読む" {
  json_inspect(parse("1. a\n2. b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "a", "folded": false, "body": [] },
          "items": [],
        },
      ],
      [
        "Item",
        {
          "node": { "id": 3, "label": "b", "folded": false, "body": [] },
          "items": [],
        },
      ],
    ],
  })
}

///|
test "ラベルは原文の逐語" {
  json_inspect(parse("- a **b**\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "a **b**", "folded": false, "body": [] },
          "items": [],
        },
      ],
    ],
  })
}

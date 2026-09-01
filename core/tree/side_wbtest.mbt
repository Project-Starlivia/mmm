// 側（`---` のトグル）を固定する。
//
// `---` はトグル専用で、翼の境目を作る。**本数によらず 1 回**。
// 飾りの水平線は `***` の側（チャンネルが違う）。

///|
test "区切りで側が裏返る" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n## b\n"), content={
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
            "side": "Left",
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
test "本数によらずトグル 1 回" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n---\n\n## b\n"), content={
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
            "side": "Left",
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
test "先頭の区切りは左開始" {
  json_inspect(parse("# r\n\n---\n\n## a\n"), content={
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
            "side": "Left",
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
test "何度でも裏返る" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"), content={
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
            "side": "Left",
            "branch": {
              "id": 4,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "b", "folded": false, "body": [] },
              ],
              "children": [],
            },
          },
          {
            "side": "Right",
            "branch": {
              "id": 5,
              "node": [
                "Explicit",
                { "sign": "Heading", "label": "c", "folded": false, "body": [] },
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
test "C18 — 深いノードは親に飲まれず反対側の翼になる" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n### x\n"), content={
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
            "side": "Left",
            "branch": {
              "id": 4,
              "node": "Implicit",
              "children": [
                {
                  "id": 5,
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
test "行き先の翼が無い区切りは飾りに落ちる" {
  json_inspect(parse("# r\n\n## a\n\n---\n"), content={
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
                {
                  "sign": "Heading",
                  "label": "a",
                  "folded": false,
                  "body": ["Rule"],
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
test "木をまたぐ区切りも飾り" {
  json_inspect(parse("# r\n\n---\n\n# s\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "r", "folded": false, "body": ["Rule"] },
        ],
        "wings": [],
      },
      {
        "id": 3,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "s", "folded": false, "body": [] },
        ],
        "wings": [],
      },
    ],
  })
}

///|
test "木が変わると側は右へ戻る" {
  json_inspect(parse("# r\n\n---\n\n## a\n\n# s\n\n## b\n"), content={
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
            "side": "Left",
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
      {
        "id": 4,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "s", "folded": false, "body": [] },
        ],
        "wings": [
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
test "項目の中の区切りは飾り" {
  json_inspect(parse("- a\n\n  ---\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "a", "folded": false, "body": ["Rule"] },
        ],
        "wings": [],
      },
    ],
  })
}

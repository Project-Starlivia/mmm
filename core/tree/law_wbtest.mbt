// 構造の規則を固定する。
//
//   単調性 — 項目の子孫は項目。項目の領土の見出しは骨格にならない
//   順序法則 — 兄弟は項目が先、見出しが後

///|
test "単調性 — 項目の中の見出しは逐語のまま中身になる" {
  json_inspect(parse("- a\n  # x\n"), content={
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
            "body": [["Opaque", "# x"]],
          },
          "items": [],
        },
      ],
    ],
  })
}

///|
/// 列 0 へ出れば項目が閉じるので、これは中身ではなく別の木（C17）。
test "単調性 — 列 0 の見出しは項目を閉じる" {
  json_inspect(parse("- a\n\n# x\n"), content={
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
        "Explicit",
        {
          "node": { "id": 3, "label": "x", "folded": false, "body": [] },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
/// 兄弟に項目と見出しが並ぶのは、**項目が先のときだけ**。深さの規則から
/// 自動的にそうなるので、並べ替えは要らない。
test "順序法則 — 項目のあとの見出しは兄弟になる" {
  json_inspect(parse("# r\n\n- b\n\n## a\n"), content={
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
                "node": { "id": 3, "label": "b", "folded": false, "body": [] },
                "children": [],
              },
            },
          ],
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 4, "label": "a", "folded": false, "body": [] },
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
/// 見出しのあとの項目は「直近の見出しの深さ + 1」なので、兄弟ではなく子。
/// だから [見出し, 項目] の並びは作られない。
test "順序法則 — 見出しのあとの項目は子になる" {
  json_inspect(parse("# r\n\n## a\n\n- b\n"), content={
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
                  "node": { "id": 3, "label": "a", "folded": false, "body": [] },
                  "items": [
                    {
                      "node": {
                        "id": 4,
                        "label": "b",
                        "folded": false,
                        "body": [],
                      },
                      "children": [],
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
/// 列 0 の見出しは md でも項目を閉じる。深さの計算だけで項目の下へ潜ると
/// 単調性が破れるので、見出しを積む前に項目の枠を落とす。C17 を全部の
/// 深さへ広げたもの。
test "単調性 — 深い見出しも項目の下へ潜らない" {
  json_inspect(parse("# r\n\n- b\n\n### x\n"), content={
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
                "node": { "id": 3, "label": "b", "folded": false, "body": [] },
                "children": [],
              },
            },
          ],
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Implicit",
                {
                  "id": 4,
                  "headings": [
                    [
                      "Explicit",
                      {
                        "node": {
                          "id": 5,
                          "label": "x",
                          "folded": false,
                          "body": [],
                        },
                        "items": [],
                        "headings": [],
                      },
                    ],
                  ],
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
test "単調性 — 項目の根の下にも潜らない" {
  json_inspect(parse("- a\n\n### x\n"), content={
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
        "Implicit",
        {
          "id": 3,
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Implicit",
                {
                  "id": 4,
                  "headings": [
                    [
                      "Explicit",
                      {
                        "node": {
                          "id": 5,
                          "label": "x",
                          "folded": false,
                          "body": [],
                        },
                        "items": [],
                        "headings": [],
                      },
                    ],
                  ],
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
test "単調性 — 入れ子項目の後ろでも潜らない" {
  json_inspect(parse("# r\n\n- b\n\n  - c\n\n### x\n"), content={
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
                "node": { "id": 3, "label": "b", "folded": false, "body": [] },
                "children": [
                  {
                    "node": {
                      "id": 4,
                      "label": "c",
                      "folded": false,
                      "body": [],
                    },
                    "children": [],
                  },
                ],
              },
            },
          ],
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Implicit",
                {
                  "id": 5,
                  "headings": [
                    [
                      "Explicit",
                      {
                        "node": {
                          "id": 6,
                          "label": "x",
                          "folded": false,
                          "body": [],
                        },
                        "items": [],
                        "headings": [],
                      },
                    ],
                  ],
                },
              ],
            },
          ],
        },
      ],
    ],
  })
}

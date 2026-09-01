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
      {
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Item",
            "label": "a",
            "folded": false,
            "body": [["Opaque", "# x"]],
          },
        ],
        "wings": [],
      },
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
          { "sign": "Heading", "label": "x", "folded": false, "body": [] },
        ],
        "wings": [],
      },
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
                { "sign": "Item", "label": "b", "folded": false, "body": [] },
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
/// 見出しのあとの項目は「直近の見出しの深さ + 1」なので、兄弟ではなく子。
/// だから [見出し, 項目] の並びは作られない。
test "順序法則 — 見出しのあとの項目は子になる" {
  json_inspect(parse("# r\n\n## a\n\n- b\n"), content={
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
          },
        ],
      },
    ],
  })
}

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
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "open": false,
            "body": [["Opaque", "# x"]],
            "children": [],
          },
        ],
        "sides": [],
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
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "open": false,
            "body": [],
            "children": [],
          },
        ],
        "sides": [],
      },
      {
        "node": [
          "HeadingNode",
          {
            "id": 3,
            "label": "x",
            "details": false,
            "open": false,
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
/// 兄弟に項目と見出しが並ぶのは、**項目が先のときだけ**。深さの規則から
/// 自動的にそうなるので、並べ替えは要らない。
test "順序法則 — 項目のあとの見出しは兄弟になる" {
  json_inspect(parse("# r\n\n- b\n\n## a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "open": false,
            "body": [],
            "children": [
              [
                "ListNode",
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
                  "open": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "HeadingNode",
                {
                  "id": 4,
                  "label": "a",
                  "details": false,
                  "open": false,
                  "body": [],
                  "children": [],
                },
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
/// 見出しのあとの項目は「直近の見出しの深さ + 1」なので、兄弟ではなく子。
/// だから [見出し, 項目] の並びは作られない。
test "順序法則 — 見出しのあとの項目は子になる" {
  json_inspect(parse("# r\n\n## a\n\n- b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "open": false,
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "a",
                  "details": false,
                  "open": false,
                  "body": [],
                  "children": [
                    [
                      "ListNode",
                      {
                        "id": 4,
                        "label": "b",
                        "details": false,
                        "open": false,
                        "body": [],
                        "children": [],
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
/// 列 0 の見出しは md でも項目を閉じる。深さの計算だけで項目の下へ潜ると
/// 単調性が破れるので、見出しを積む前に項目の枠を落とす。C17 を全部の
/// 深さへ広げたもの。
test "単調性 — 深い見出しも項目の下へ潜らない" {
  json_inspect(parse("# r\n\n- b\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "open": false,
            "body": [],
            "children": [
              [
                "ListNode",
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
                  "open": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "ImplicitNode",
                {
                  "id": 4,
                  "children": [
                    [
                      "HeadingNode",
                      {
                        "id": 5,
                        "label": "x",
                        "details": false,
                        "open": false,
                        "body": [],
                        "children": [],
                      },
                    ],
                  ],
                },
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
test "単調性 — 項目の根の下にも潜らない" {
  json_inspect(parse("- a\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "open": false,
            "body": [],
            "children": [],
          },
        ],
        "sides": [],
      },
      {
        "node": [
          "ImplicitNode",
          {
            "id": 3,
            "children": [
              [
                "ImplicitNode",
                {
                  "id": 4,
                  "children": [
                    [
                      "HeadingNode",
                      {
                        "id": 5,
                        "label": "x",
                        "details": false,
                        "open": false,
                        "body": [],
                        "children": [],
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
test "単調性 — 入れ子項目の後ろでも潜らない" {
  json_inspect(parse("# r\n\n- b\n\n  - c\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "open": false,
            "body": [],
            "children": [
              [
                "ListNode",
                {
                  "id": 3,
                  "label": "b",
                  "details": false,
                  "open": false,
                  "body": [],
                  "children": [
                    {
                      "id": 4,
                      "label": "c",
                      "details": false,
                      "open": false,
                      "body": [],
                      "children": [],
                    },
                  ],
                },
              ],
              [
                "ImplicitNode",
                {
                  "id": 5,
                  "children": [
                    [
                      "HeadingNode",
                      {
                        "id": 6,
                        "label": "x",
                        "details": false,
                        "open": false,
                        "body": [],
                        "children": [],
                      },
                    ],
                  ],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Right"],
      },
    ],
  })
}

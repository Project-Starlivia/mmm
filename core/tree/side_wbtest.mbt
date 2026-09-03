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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "Head",
                {
                  "id": 4,
                  "label": "b",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Left"],
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "Head",
                {
                  "id": 4,
                  "label": "b",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Left"],
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Left"],
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "Head",
                {
                  "id": 4,
                  "label": "b",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "Head",
                {
                  "id": 5,
                  "label": "c",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Right", "Left", "Right"],
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "Implicit",
                {
                  "id": 4,
                  "children": [
                    [
                      "Head",
                      {
                        "id": 5,
                        "label": "x",
                        "details": false,
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
        "sides": ["Right", "Left"],
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
                  "label": "a",
                  "details": false,
                  "body": ["Rule"],
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
test "木をまたぐ区切りも飾り" {
  json_inspect(parse("# r\n\n---\n\n# s\n"), content={
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
            "body": ["Rule"],
            "children": [],
          },
        ],
        "sides": [],
      },
      {
        "node": [
          "Head",
          {
            "id": 3,
            "label": "s",
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
test "木が変わると側は右へ戻る" {
  json_inspect(parse("# r\n\n---\n\n## a\n\n# s\n\n## b\n"), content={
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
                  "label": "a",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
            ],
          },
        ],
        "sides": ["Left"],
      },
      {
        "node": [
          "Head",
          {
            "id": 4,
            "label": "s",
            "details": false,
            "body": [],
            "children": [
              [
                "Head",
                {
                  "id": 5,
                  "label": "b",
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
/// 側は根の持ち物なので、根がまだ無い場所の区切りは裏返す相手が居ない。
/// ここを分けないと、後ろが `#` か `##` かで同じ `---` の意味が変わる。
test "根より前の区切りは側になれない" {
  json_inspect(parse("aaa\n\n---\n\n## root\n\n## a\n"), content={
    "eol": "Lf",
    "body": [["Opaque", "aaa"], "Rule"],
    "roots": [
      {
        "node": [
          "Implicit",
          {
            "id": 2,
            "children": [
              [
                "Head",
                {
                  "id": 3,
                  "label": "root",
                  "details": false,
                  "body": [],
                  "children": [],
                },
              ],
              [
                "Head",
                {
                  "id": 4,
                  "label": "a",
                  "details": false,
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
test "根より前の区切りは、後ろが # でも ## でも同じ" {
  // 木の形は違う（`##` は Implicit の根を要る）が、**区切りの行き先は同じ**。
  // 飾りとして文書に落ち、側は裏返らない
  let two = parse("aaa\n\n---\n\n## root\n")
  let one = parse("aaa\n\n---\n\n# root\n")
  assert_eq(two.body, one.body)
  assert_eq(two.body, [Opaque("aaa"), Rule])
  assert_eq(two.roots[0].sides[0], Right)
  assert_eq(two.roots[0].node is Implicit(_), true)
}

///|
test "項目の中の区切りは飾り" {
  json_inspect(parse("- a\n\n  ---\n"), content={
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
            "body": ["Rule"],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

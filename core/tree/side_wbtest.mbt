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
                  "items": [],
                  "headings": [],
                },
              ],
            },
            {
              "side": "Left",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 4, "label": "b", "folded": false, "body": [] },
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
test "本数によらずトグル 1 回" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n---\n\n## b\n"), content={
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
                  "items": [],
                  "headings": [],
                },
              ],
            },
            {
              "side": "Left",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 4, "label": "b", "folded": false, "body": [] },
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
test "先頭の区切りは左開始" {
  json_inspect(parse("# r\n\n---\n\n## a\n"), content={
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
              "side": "Left",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 3, "label": "a", "folded": false, "body": [] },
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
test "何度でも裏返る" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"), content={
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
                  "items": [],
                  "headings": [],
                },
              ],
            },
            {
              "side": "Left",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 4, "label": "b", "folded": false, "body": [] },
                  "items": [],
                  "headings": [],
                },
              ],
            },
            {
              "side": "Right",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 5, "label": "c", "folded": false, "body": [] },
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
test "C18 — 深いノードは親に飲まれず反対側の翼になる" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n### x\n"), content={
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
                  "items": [],
                  "headings": [],
                },
              ],
            },
            {
              "side": "Left",
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
test "行き先の翼が無い区切りは飾りに落ちる" {
  json_inspect(parse("# r\n\n## a\n\n---\n"), content={
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
                  "node": {
                    "id": 3,
                    "label": "a",
                    "folded": false,
                    "body": ["Rule"],
                  },
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
test "木をまたぐ区切りも飾り" {
  json_inspect(parse("# r\n\n---\n\n# s\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": { "id": 2, "label": "r", "folded": false, "body": ["Rule"] },
          "items": [],
          "headings": [],
        },
      ],
      [
        "Explicit",
        {
          "node": { "id": 3, "label": "s", "folded": false, "body": [] },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "木が変わると側は右へ戻る" {
  json_inspect(parse("# r\n\n---\n\n## a\n\n# s\n\n## b\n"), content={
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
              "side": "Left",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 3, "label": "a", "folded": false, "body": [] },
                  "items": [],
                  "headings": [],
                },
              ],
            },
          ],
        },
      ],
      [
        "Explicit",
        {
          "node": { "id": 4, "label": "s", "folded": false, "body": [] },
          "items": [],
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Explicit",
                {
                  "node": { "id": 5, "label": "b", "folded": false, "body": [] },
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
/// 側は根の持ち物なので、根がまだ無い場所の区切りは裏返す相手が居ない。
/// ここを分けないと、後ろが `#` か `##` かで同じ `---` の意味が変わる。
test "根より前の区切りは側になれない" {
  json_inspect(parse("aaa\n\n---\n\n## root\n\n## a\n"), content={
    "eol": "Lf",
    "body": [["Opaque", "aaa"], "Rule"],
    "roots": [
      [
        "Implicit",
        {
          "id": 2,
          "headings": [
            {
              "side": "Right",
              "branch": [
                "Explicit",
                {
                  "node": {
                    "id": 3,
                    "label": "root",
                    "folded": false,
                    "body": [],
                  },
                  "items": [],
                  "headings": [],
                },
              ],
            },
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
test "根より前の区切りは、後ろが # でも ## でも同じ" {
  // 木の形は違う（`##` は Implicit の根を要る）が、**区切りの行き先は同じ**。
  // 飾りとして文書に落ち、側は裏返らない
  let two = parse("aaa\n\n---\n\n## root\n")
  let one = parse("aaa\n\n---\n\n# root\n")
  assert_eq(two.body, one.body)
  assert_eq(two.body, [Opaque("aaa"), Rule])
  match two.roots[0] {
    Implicit(headings~, ..) => assert_eq(headings[0].side, Right)
    _ => fail("深さ 2 から始まるので根は Implicit のはず")
  }
}

///|
test "項目の中の区切りは飾り" {
  json_inspect(parse("- a\n\n  ---\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "a", "folded": false, "body": ["Rule"] },
          "items": [],
        },
      ],
    ],
  })
}

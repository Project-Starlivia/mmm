// 畳み（`<details>`）を固定する。
//
// 骨格行は畳みの外。**中身と子だけを包む**ので、畳まれるのは開きの直前に
// 積まれていたノード。

///|
test "details は直前のノードを畳む" {
  json_inspect(parse("# r\n\n<details>\n\n## a\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": { "id": 2, "label": "r", "folded": true, "body": [] },
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
          ],
        },
      ],
    ],
  })
}

///|
test "summary は開きと同じ塊なので落ちる" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>r</summary>\n\n## a\n\n</details>\n"),
    content={
      "eol": "Lf",
      "body": [],
      "roots": [
        [
          "Explicit",
          {
            "node": { "id": 2, "label": "r", "folded": true, "body": [] },
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
                      "body": [],
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
    },
  )
}

///|
test "入れ子の畳み" {
  json_inspect(
    parse(
      "# r\n\n<details>\n\n## a\n\n<details>\n\n### x\n\n</details>\n\n</details>\n",
    ),
    content={
      "eol": "Lf",
      "body": [],
      "roots": [
        [
          "Explicit",
          {
            "node": { "id": 2, "label": "r", "folded": true, "body": [] },
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
                      "folded": true,
                      "body": [],
                    },
                    "items": [],
                    "headings": [
                      [
                        "Explicit",
                        {
                          "node": {
                            "id": 4,
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
    },
  )
}

///|
test "畳んだノードの中身は残る" {
  json_inspect(parse("# r\n\n<details>\n\ntext\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "r",
            "folded": true,
            "body": [["Opaque", "text"]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
test "相手の居ない閉じは逐語のまま残る" {
  json_inspect(parse("# r\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Explicit",
        {
          "node": {
            "id": 2,
            "label": "r",
            "folded": false,
            "body": [["Opaque", "</details>"]],
          },
          "items": [],
          "headings": [],
        },
      ],
    ],
  })
}

///|
/// 木が 2 本になるのは畳みのせいではない。列 0 の `<details>` がリストを
/// 閉じるという md の規則で、`- b` は別のリストとして読まれる。
test "項目も畳める" {
  json_inspect(parse("- a\n\n<details>\n\n  - b\n\n</details>\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      [
        "Item",
        {
          "node": { "id": 2, "label": "a", "folded": true, "body": [] },
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

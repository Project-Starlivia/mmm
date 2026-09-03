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
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "details": false,
            "body": [["Opaque", "<details>"]],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "a",
                  "details": false,
                  "body": [["Opaque", "</details>"]],
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
test "summary は開きと同じ塊なので落ちる" {
  json_inspect(
    parse("# r\n\n<details>\n<summary>r</summary>\n\n## a\n\n</details>\n"),
    content={
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
              "body": [["Opaque", "<details>\n<summary>r</summary>"]],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": false,
                    "body": [["Opaque", "</details>"]],
                    "children": [],
                  },
                ],
              ],
            },
          ],
          "sides": ["Right"],
        },
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
        {
          "node": [
            "HeadingNode",
            {
              "id": 2,
              "label": "r",
              "details": false,
              "body": [["Opaque", "<details>"]],
              "children": [
                [
                  "HeadingNode",
                  {
                    "id": 3,
                    "label": "a",
                    "details": false,
                    "body": [["Opaque", "<details>"]],
                    "children": [
                      [
                        "HeadingNode",
                        {
                          "id": 4,
                          "label": "x",
                          "details": false,
                          "body": [
                            ["Opaque", "</details>"],
                            ["Opaque", "</details>"],
                          ],
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
    },
  )
}

///|
test "畳んだノードの中身は残る" {
  json_inspect(parse("# r\n\n<details>\n\ntext\n\n</details>\n"), content={
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
            "body": [
              ["Opaque", "<details>"],
              ["Opaque", "text"],
              ["Opaque", "</details>"],
            ],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "相手の居ない閉じは逐語のまま残る" {
  json_inspect(parse("# r\n\n</details>\n"), content={
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
            "body": [["Opaque", "</details>"]],
            "children": [],
          },
        ],
        "sides": [],
      },
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
      {
        "node": [
          "ListNode",
          {
            "id": 2,
            "label": "a",
            "details": false,
            "body": [["Opaque", "<details>"]],
            "children": [],
          },
        ],
        "sides": [],
      },
      {
        "node": [
          "ListNode",
          {
            "id": 3,
            "label": "b",
            "details": false,
            "body": [["Opaque", "</details>"]],
            "children": [],
          },
        ],
        "sides": [],
      },
    ],
  })
}

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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Heading", "label": "r", "folded": true, "body": [] },
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
        ],
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
          "id": 2,
          "node": [
            "Explicit",
            { "sign": "Heading", "label": "r", "folded": true, "body": [] },
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
                    "body": [],
                  },
                ],
                "children": [],
              },
            },
          ],
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
          "id": 2,
          "node": [
            "Explicit",
            { "sign": "Heading", "label": "r", "folded": true, "body": [] },
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
                    "folded": true,
                    "body": [],
                  },
                ],
                "children": [
                  {
                    "id": 4,
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "r",
            "folded": true,
            "body": [["Opaque", "text"]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          {
            "sign": "Heading",
            "label": "r",
            "folded": false,
            "body": [["Opaque", "</details>"]],
          },
        ],
        "wings": [],
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
        "id": 2,
        "node": [
          "Explicit",
          { "sign": "Item", "label": "a", "folded": true, "body": [] },
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

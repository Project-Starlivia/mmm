// 水平線（thematic break）を固定する。
//
// 意味は常に「隣を区切る」。**直後のブロックが見出し・項目の行なら境界**で、
// それ以外は装飾。記法(`---` `***` `___`)も本数も判定に使わない。

///|
test "直後が見出しなら境界。側が裏返る" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n## b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 4,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left"],
        "rules": ["", "---"],
      },
    ],
  })
}

///|
test "先頭に置けば最初の子から左になる" {
  json_inspect(parse("# r\n\n---\n\n## a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Left"],
        "rules": ["---"],
      },
    ],
  })
}

///|
/// 境界は「直前のものの一部ではない」宣言なので、深さ 2 まで引き出す。
/// 見出しは絶対座標で動かせないので、足りない深さを Implicit が埋める。
test "深い見出しは Implicit を挟んで深さ 2 へ" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n### x\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 4,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 5,
                  "label": "x",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left"],
        "rules": ["", "---"],
      },
    ],
  })
}

///|
/// 項目は相対記法で深さが導出値なので、深さ 2 に直接置き直せる。
test "項目は Implicit を挟まず深さ 2 へ" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n- b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 4,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left"],
        "rules": ["", "---"],
      },
    ],
  })
}

///|
/// 深さ 2 では見出しと項目が交互に並ぶ。だから children は 1 本の列。
test "見出しと項目が交互に並ぶ" {
  json_inspect(
    parse("# root\n\n---\n\n## h1\n\n---\n\n* i1\n\n---\n\n## h2\n"),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "root",
            "body": [],
            "children": [
              {
                "id": 3,
                "label": "h1",
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
              {
                "id": 4,
                "label": "i1",
                "body": [],
                "children": [],
                "mark": ["Item", { "marker": "*", "offset": 2, "loose": false }],
              },
              {
                "id": 5,
                "label": "h2",
                "body": [],
                "children": [],
                "mark": ["Heading", { "setext": false, "closing": 0 }],
              },
            ],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": ["Left", "Right", "Left"],
          "rules": ["---", "---", "---"],
        },
      ],
    },
  )
}

///|
/// 兄弟の間でも同じ。y は x の一部ではないので引き出される。
test "兄弟の間の水平線も引き出す" {
  json_inspect(parse("# r\n\n## a\n\n### x\n\n---\n\n### y\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [
                {
                  "id": 4,
                  "label": "x",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 5,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 6,
                  "label": "y",
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left"],
        "rules": ["", "---"],
      },
    ],
  })
}

///|
/// 直後が中身なら境界になれない。**書かれた場所にそのまま残る。**
test "中身に挟まれた水平線は装飾" {
  json_inspect(parse("# a\n\nbody\n\n---\n\nbody\n\n## b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            { "id": 3, "content": ["Raw", "body"], "source": "body" },
            { "id": 4, "content": "ThematicBreak", "source": "---" },
            { "id": 5, "content": ["Raw", "body"], "source": "body" },
          ],
          "children": [
            {
              "id": 6,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
/// 直前の中身を消すと、同じ線が境界に昇格する。md 自身の性質。
test "直前が中身でも、直後が見出しなら境界" {
  json_inspect(parse("# a\n\nbody\n\n---\n\n## b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": ["Raw", "body"], "source": "body" }],
          "children": [
            {
              "id": 4,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Left"],
        "rules": ["---"],
      },
    ],
  })
}

///|
/// 連続していても境界は 1 つ。最初の 1 本は直後が水平線なので装飾に落ちる。
test "本数に意味は無い" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n---\n\n## b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
            {
              "id": 4,
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Left"],
        "rules": ["", "---"],
      },
    ],
  })
}

///|
test "文末の水平線は装飾" {
  json_inspect(parse("# r\n\n## a\n\n---\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "a",
              "body": [{ "id": 4, "content": "ThematicBreak", "source": "---" }],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
/// 根は側を持たないので、引き出す先が無い。
test "根の直前の水平線は装飾" {
  json_inspect(parse("# r\n\n---\n\n# s\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [{ "id": 3, "content": "ThematicBreak", "source": "---" }],
          "children": [],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 4,
          "label": "s",
          "body": [],
          "children": [],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "最初の見出しより前の水平線は文書の中身" {
  json_inspect(parse("body\n\n---\n\n# a\n"), content={
    "body": [
      { "id": 2, "content": ["Raw", "body"], "source": "body" },
      { "id": 3, "content": "ThematicBreak", "source": "---" },
    ],
    "roots": [
      {
        "node": {
          "id": 4,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
/// `***` も `___` も同じ意味。記法で差別しないが、**読んだ綴りは残る**（`rules`）。
test "記法は差別しない — 形は同じで、綴りだけ残る" {
  let dash = parse("# r\n\n---\n\n## a\n")
  let star = parse("# r\n\n***\n\n## a\n")
  let under = parse("# r\n\n___\n\n## a\n")
  assert_eq(shape(dash), shape(star))
  assert_eq(shape(dash), shape(under))
  json_inspect(
    [dash.roots[0].rules, star.roots[0].rules, under.roots[0].rules],
    content=[["---"], ["***"], ["___"]],
  )
}

///|
/// **項目の中の水平線は中身。** 境界になれるのは根の領土の隙間だけなので、
/// 保留せずその場に置く。保留すると、置く前に項目の枠が閉じられたとき
/// 帰る場所が無くなって文書へ落ちる。
test "項目の中の水平線は、後ろが見出しでも項目の中身" {
  json_inspect(parse("- a\n\n  ---\n\n# h\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": "ThematicBreak", "source": "---" }],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 4,
          "label": "h",
          "body": [],
          "children": [],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

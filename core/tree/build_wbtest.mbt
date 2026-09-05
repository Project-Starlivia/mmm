// 「この md はこの mmmTree になる」を固定する。
//
// 期待値は `json_inspect` が `moon test -u` で埋める。JSON への変換は
// derive(ToJson) の導出なので、**テストの土台に手書きのコードが無い**
// （手書きだと、その変換自身が間違っていてもテストは緑になる）。

///|
test "見出し 1 つが木 1 本になる" {
  json_inspect(parse("# a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "深さ 1 が 2 つなら木も 2 本" {
  json_inspect(parse("# a\n\n# b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
      {
        "node": [
          "HeadingNode",
          { "id": 3, "label": "b", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "深さ 2 は根の子になる" {
  json_inspect(parse("# r\n\n## a\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "HeadingNode",
                { "id": 3, "label": "a", "body": [], "children": [] },
              ],
              [
                "HeadingNode",
                { "id": 4, "label": "b", "body": [], "children": [] },
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
test "深さ 3 は根の子の下" {
  json_inspect(parse("# r\n\n## a\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "a",
                  "body": [],
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 4, "label": "x", "body": [], "children": [] },
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
test "浅く戻る" {
  json_inspect(parse("# r\n\n## a\n\n### x\n\n## b\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "HeadingNode",
                {
                  "id": 3,
                  "label": "a",
                  "body": [],
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 4, "label": "x", "body": [], "children": [] },
                    ],
                  ],
                },
              ],
              [
                "HeadingNode",
                { "id": 5, "label": "b", "body": [], "children": [] },
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
test "飛びは Implicit が埋める" {
  json_inspect(parse("# r\n\n### x\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "ImplicitNode",
                {
                  "id": 3,
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 4, "label": "x", "body": [], "children": [] },
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
test "深さ 1 が無ければ根が Implicit になる" {
  json_inspect(parse("## a\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ImplicitNode",
          {
            "id": 2,
            "children": [
              [
                "HeadingNode",
                { "id": 3, "label": "a", "body": [], "children": [] },
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
test "ラベルは原文のまま（インラインを解釈しない）" {
  json_inspect(parse("# a **b** `c`\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a **b** `c`", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "中身の無い見出しは空ラベル" {
  json_inspect(parse("# \n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "frontmatter" {
  json_inspect(parse("---\nk: v\n---\n\n# a\n"), content={
    "frontmatter": "k: v\n",
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
test "改行の流儀は保存する" {
  json_inspect(parse("# a\r\n"), content={
    "eol": "Crlf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// **インラインの span は中身に対する相対。** 原文の絶対位置に足すと、
/// 行ごとの字下げと `\r` の総量ぶん手前で切れてラベルの末尾が消える。
test "setext のラベルも末尾まで残る" {
  json_inspect(parse("aaa\r\nbbb\r\n===\r\n"), content={
    "eol": "Crlf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          { "id": 2, "label": "aaa\r\nbbb", "body": [], "children": [] },
        ],
        "sides": [],
      },
    ],
  })
}

///|
/// 見出しも同じ。`[q]: /r` が定義として引き取られても、2 行目が消えず、
/// 引き取られた行が中身として重ねて出ることもない。
test "定義行に見える setext でもラベルは全部残る" {
  json_inspect(parse("[q]: /r\nZZZ\n---\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "ImplicitNode",
          {
            "id": 2,
            "children": [
              [
                "HeadingNode",
                { "id": 3, "label": "[q]: /r\nZZZ", "body": [], "children": [] },
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
/// 閉じの `#` は飾りなので落ちるが、空白が無ければ中身。
test "ATX の閉じの # は飾り、空白が無ければ中身" {
  json_inspect([parse("# a ###\n"), parse("# a#\n"), parse("# a #b\n")], content=[
    {
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "HeadingNode",
            { "id": 2, "label": "a", "body": [], "children": [] },
          ],
          "sides": [],
        },
      ],
    },
    {
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "HeadingNode",
            { "id": 2, "label": "a#", "body": [], "children": [] },
          ],
          "sides": [],
        },
      ],
    },
    {
      "eol": "Lf",
      "body": [],
      "roots": [
        {
          "node": [
            "HeadingNode",
            { "id": 2, "label": "a #b", "body": [], "children": [] },
          ],
          "sides": [],
        },
      ],
    },
  ])
}

///|
/// **改行の入ったラベルは setext でしか書けない。** 書く側はラベルに改行が
/// 在るかで綴りを選ぶので、木は ATX か setext かを持たない。それが成り立つのは
/// setext の見出しが深さ 1〜2 にしか座らないから — 境界が引き出す先も深さ 2。
test "setext の見出しは境界の先でも深さ 2" {
  json_inspect(parse("# r\n\n## a\n\n---\n\nZZZ\nWWW\n---\n"), content={
    "eol": "Lf",
    "body": [],
    "roots": [
      {
        "node": [
          "HeadingNode",
          {
            "id": 2,
            "label": "r",
            "body": [],
            "children": [
              [
                "HeadingNode",
                { "id": 3, "label": "a", "body": [], "children": [] },
              ],
              [
                "HeadingNode",
                { "id": 4, "label": "ZZZ\nWWW", "body": [], "children": [] },
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
/// 手で組んだ木の id は文書順でないことがある（操作が足したノードは max+1）。
/// 読み直せば文書順に振り直されるので、その番号を先に言えるようにする。
test "number — 文書順に振り直したときの番号。中身も同じ列、先頭に足せば後ろがずれる" {
  fn leaf(id : Int, label : String) -> Node {
    HeadingNode({ id, label, fold: None, body: [], children: [] })
  }

  let d : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [{ id: 2, content: ThematicBreak }],
    roots: [
      { node: leaf(999, "n"), sides: [] },
      {
        node: HeadingNode({
          id: 3,
          label: "r",
          fold: None,
          body: [{ id: 4, content: ThematicBreak }],
          children: [leaf(5, "a"), leaf(998, "m")],
        }),
        sides: [Right, Right],
      },
    ],
  }
  assert_eq(number(d, doc_id), Some(doc_id))
  assert_eq(number(d, 2), Some(2))
  assert_eq(number(d, 999), Some(3))
  assert_eq(number(d, 3), Some(4))
  assert_eq(number(d, 4), Some(5))
  assert_eq(number(d, 5), Some(6))
  assert_eq(number(d, 998), Some(7))
  assert_eq(number(d, 8), None)
}

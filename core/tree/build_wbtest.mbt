// 「この md はこの mmmTree になる」を固定する。
//
// 期待値は `json_inspect` が `moon test -u` で埋める。JSON への変換は
// derive(ToJson) の導出なので、**テストの土台に手書きのコードが無い**
// （手書きだと、その変換自身が間違っていてもテストは緑になる）。

///|
test "見出し 1 つが木 1 本になる" {
  json_inspect(parse("# a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
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
test "深さ 1 が 2 つなら木も 2 本" {
  json_inspect(parse("# a\n\n# b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 3,
          "label": "b",
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
test "深さ 2 は根の子になる" {
  json_inspect(parse("# r\n\n## a\n\n## b\n"), content={
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
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
test "深さ 3 は根の子の下" {
  json_inspect(parse("# r\n\n## a\n\n### x\n"), content={
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
test "浅く戻る" {
  json_inspect(parse("# r\n\n## a\n\n### x\n\n## b\n"), content={
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
              "label": "b",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
          ],
          "mark": ["Heading", { "setext": false, "closing": 0 }],
        },
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
test "飛びは Implicit が埋める" {
  json_inspect(parse("# r\n\n### x\n"), content={
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
              "label": "",
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
/// #203 — 桁 0 に並ぶ項目は木が本ごとに分かれる。詰めは木ごとの `loose` にしか
/// 残らないので、書きはそれを見て列に戻す（unbuild_wbtest）
test "桁 0 の項目は 1 本ずつ別の木。詰めは木ごとに持つ" {
  json_inspect(parse("- a\n- b\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
      {
        "node": {
          "id": 3,
          "label": "b",
          "body": [],
          "children": [],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
test "深さ 1 が無ければ根が Implicit になる" {
  json_inspect(parse("## a\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "",
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
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
test "ラベルは原文のまま（インラインを解釈しない）" {
  json_inspect(parse("# a **b** `c`\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a **b** `c`",
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
test "中身の無い見出しは空ラベル" {
  json_inspect(parse("# \n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "",
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
test "frontmatter" {
  json_inspect(parse("---\nk: v\n---\n\n# a\n"), content={
    "frontmatter": "k: v\n",
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
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
test "CRLF の md も読める（改行の流儀は持たない）" {
  json_inspect(parse("# a\r\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
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
/// **インラインの span は中身に対する相対。** 原文の絶対位置に足すと、
/// 行ごとの字下げと `\r` の総量ぶん手前で切れてラベルの末尾が消える。
test "setext のラベルも末尾まで残る" {
  json_inspect(parse("aaa\r\nbbb\r\n===\r\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "aaa\nbbb",
          "body": [],
          "children": [],
          "mark": ["Heading", { "setext": true, "closing": 0 }],
        },
        "sides": [],
        "rules": [],
      },
    ],
  })
}

///|
/// 見出しも同じ。`[q]: /r` が定義として引き取られても、2 行目が消えず、
/// 引き取られた行が中身として重ねて出ることもない。
test "定義行に見える setext でもラベルは全部残る" {
  json_inspect(parse("[q]: /r\nZZZ\n---\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "[q]: /r\nZZZ",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": true, "closing": 0 }],
            },
          ],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
/// 閉じの `#` は飾りなので名前から落ち、本数だけ `closing` に残る。
/// 空白が無ければ飾りではなく中身。
test "ATX の閉じの # は飾り、空白が無ければ中身" {
  json_inspect([parse("# a ###\n"), parse("# a#\n"), parse("# a #b\n")], content=[
    {
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a",
            "body": [],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 3 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
    {
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a#",
            "body": [],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
    {
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a #b",
            "body": [],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  ])
}

///|
/// **読んだ書き方（`setext`）は木が持ち、書き戻しもその綴り。**
/// setext の見出しが深さ 1〜2 にしか座らないから書き戻せる — 境界が引き出す先も深さ 2。
test "setext の見出しは境界の先でも深さ 2" {
  json_inspect(parse("# r\n\n## a\n\n---\n\nZZZ\nWWW\n---\n"), content={
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
              "label": "ZZZ\nWWW",
              "body": [],
              "children": [],
              "mark": ["Heading", { "setext": true, "closing": 0 }],
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
/// 手で組んだ木の id は文書順でないことがある（操作が足したノードは max+1）。
/// 読み直せば文書順に振り直されるので、その番号を先に言えるようにする。
test "number — 文書順に振り直したときの番号。中身も同じ列、先頭に足せば後ろがずれる" {
  fn leaf(id : Int, label : String) -> Node {
    { id, label, fold: None, body: [], children: [], mark: Some(atx), }
  }

  let d : Doc = {
    frontmatter: None,
    body: [{ id: 2, source: None, content: Some(ThematicBreak), }],
    roots: [
      { node: leaf(999, "n"), sides: [], rules: [], },
      {
        node: {
          id: 3,
          label: "r",
          fold: None,
          body: [{ id: 4, source: None, content: Some(ThematicBreak), }],
          children: [leaf(5, "a"), leaf(998, "m")],
          mark: Some(atx),
        },
        sides: [Right, Right],
        rules: ["", ""],
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

// ══════════════════════════════════════════════════════════════════
// 項目の中身は文書と同じ規則で読む — 見出しは項目の子
// ══════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════
// 項目の中は、その項目の深さを 0 とした文書（docs/spec.md「項目の中」）
// ══════════════════════════════════════════════════════════════════

///|
/// 骨格だけを見る。深さぶん字下げして、綴りの印（`#` 見出し・`-` 項目・
/// `.` 飛び）とラベルを並べる。中身は枚数だけ。
fn skeleton(md : String) -> String {
  let out = []
  fn node(x : Node, depth : Int) -> Unit {
    let sign = match x.mark {
      Some(Heading(..)) => "#"
      Some(Item(..)) => "-"
      None => "."
    }
    let label = if x.label == "" { "" } else { " " + x.label }
    let body = if x.body.is_empty() {
      ""
    } else {
      " +" + x.body.length().to_string()
    }
    out.push("  ".repeat(depth - 1) + sign + label + body)
    for k in x.children {
      node(k, depth + 1)
    }
  }

  for r in parse(md).roots {
    node(r.node, 1)
  }
  out.join("\n")
}

///|
/// 顔（最初の塊）が見出しなら、項目のラベルは空でその見出しは子。
/// `<li>` は 1 つなので項目も 1 つ。
test "項目の中は文書 — 顔の見出しは子" {
  inspect(
    skeleton("- # head\n"),
    content=(
      #|-
      #|  # head
    ),
  )
}

///|
/// 2 塊目でも同じ。顔かどうかは関係ない（ラベルは顔が段落のときだけ）。
test "項目の中は文書 — 2 塊目の見出しも子" {
  inspect(
    skeleton("- a\n  # x\n"),
    content=(
      #|- a
      #|  # x
    ),
  )
}

///|
/// `#` の本数は項目からの深さ。飛びは文書と同じく Implicit が埋める。
test "項目の中は文書 — 飛びは Implicit が埋める" {
  inspect(
    skeleton("- ## head\n"),
    content=(
      #|-
      #|  .
      #|    # head
    ),
  )
}

///|
/// 深い見出しは浅い見出しの子。
test "項目の中は文書 — 深い見出しは子" {
  inspect(
    skeleton("- # x\n  ## y\n"),
    content=(
      #|-
      #|  # x
      #|    # y
    ),
  )
}

///|
/// 浅く戻れば兄弟。飛びを埋めた Implicit の隣に並ぶ。
test "項目の中は文書 — 浅く戻れば兄弟" {
  inspect(
    skeleton("- ## x\n  # y\n"),
    content=(
      #|-
      #|  .
      #|    # x
      #|  # y
    ),
  )
}

///|
/// 順序法則も文書と同じ — 見出しの後ろの項目はその見出しの子。
test "項目の中は文書 — 見出しの後ろの項目は子" {
  inspect(
    skeleton("- # x\n  - y\n"),
    content=(
      #|-
      #|  # x
      #|    - y
    ),
  )
}

///|
/// 同じ深さの見出しは前の見出しを閉じるので、続く見出しは元の項目の子。
test "項目の中は文書 — 見出しを閉じれば元の項目の子" {
  inspect(
    skeleton("- x\n  # a\n  - k\n  # b\n"),
    content=(
      #|- x
      #|  # a
      #|    - k
      #|  # b
    ),
  )
}

///|
/// 積みは項目ごと。前の項目の見出しは次の項目に引きずられない。
test "項目の中は文書 — 積みは項目ごと" {
  inspect(
    skeleton("- ## a\n- # b\n"),
    content=(
      #|-
      #|  .
      #|    # a
      #|-
      #|  # b
    ),
  )
}

///|
/// 側は根の子だけの性質なので、項目の中の `---` は常に飾り（直前のノードの
/// 中身の尻）。境界にならないので、続く見出しは引き出されない。
test "項目の中は文書 — 中の水平線は飾り" {
  inspect(
    skeleton("- # x\n\n  ---\n\n  # y\n"),
    content=(
      #|-
      #|  # x +1
      #|  # y
    ),
  )
}

///|
/// 項目の中の見出しも `#` は 6 本まで。7 本目は段落なので中身に落ちる。
test "項目の中は文書 — 7 本目の # は中身" {
  inspect(
    skeleton("- ###### a\n  ####### b\n"),
    content=(
      #|-
      #|  .
      #|    .
      #|      .
      #|        .
      #|          .
      #|            # a +1
    ),
  )
}

///|
/// **意味は往復で失われない。** 項目の中の見出しは `#` のまま読み書きされ、
/// 書いた字を読み直しても同じ木になる（空行の数は正規形に落ちる）。
test "項目の中は文書 — 往復しても木は変わらず、書き方は落ち着く" {
  let corpus = [
    "- # head\n", "- a\n  # x\n", "- ## head\n", "- # x\n  ## y\n", "- ## x\n  # y\n",
    "- # x\n  - y\n", "- x\n  # a\n  - k\n  # b\n", "- ## a\n- # b\n", "- # x\n\n  ---\n\n  # y\n",
  ]
  let bad = []
  for md in corpus {
    let once = serialize(parse(md))
    if shape(parse(once)) != shape(parse(md)) {
      bad.push("木が変わる " + md.escape() + " -> " + once.escape())
    }
    if serialize(parse(once)) != once {
      bad.push("冪等でない " + once.escape())
    }
  }
  json_inspect(bad, content=[])
}

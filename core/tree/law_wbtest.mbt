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

///|
/// 木に書かれている文字ぜんぶ。**綴り**（`#` や `<details>`）は構造とフラグが
/// 引き受けるので出てこない。綴りとして読めなかったものはここに残るはず。
fn written(doc : Doc) -> String {
  let bag = []
  fn blocks(bs : Array[Block]) -> Unit {
    for b in bs {
      match b {
        Image(alt~, src~) => {
          bag.push(alt)
          bag.push(src)
        }
        Link(text~, href~) => {
          bag.push(text)
          bag.push(href)
        }
        Code(info~, text~) => {
          bag.push(info)
          bag.push(text)
        }
        Svg(s) => bag.push(s)
        ThematicBreak => ()
        Details(text~, ..) => bag.push(text)
        Opaque(s) => bag.push(s)
      }
    }
  }

  fn items(xs : Array[ListNode]) -> Unit {
    for x in xs {
      bag.push(x.label)
      blocks(x.body)
      items(x.children)
    }
  }

  fn nodes(xs : Array[Node]) -> Unit {
    for x in xs {
      match x {
        HeadingNode(h) => {
          bag.push(h.label)
          blocks(h.body)
          nodes(h.children)
        }
        ListNode(l) => {
          bag.push(l.label)
          blocks(l.body)
          items(l.children)
        }
        ImplicitNode(g) => nodes(g.children)
      }
    }
  }

  if doc.frontmatter is Some(f) {
    bag.push(f)
  }
  blocks(doc.body)
  for r in doc.roots {
    nodes([r.node])
  }
  bag.join("\n")
}

///|
/// s に pat が何回出るか。
fn tally(s : String, pat : String) -> Int {
  let mut n = 0
  let mut i = 0
  while i + pat.length() <= s.length() {
    let mut k = 0
    while k < pat.length() && s[i + k] == pat[k] {
      k = k + 1
    }
    if k == pat.length() {
      n = n + 1
      i = i + pat.length()
    } else {
      i = i + 1
    }
  }
  n
}

///|
/// **意味を 1 ビットも失わない。** 綴りとして読めなかった文字は逐語のまま木に残る。
/// serialize が無いうちは往復では言えないので、実際に一度ずつ落とした形を名指しで
/// 見張る。ここが落ちたら、綴りの判定が「読めないものを捨てる」側に倒れている。
test "意味 — 綴りにならなかった文字は消えない" {
  let gone = []
  fn keep(md : String, pat : String, want : Int) -> Unit {
    let got = tally(written(parse(md)), pat)
    if got != want {
      gone.push("\{pat.escape()} × \{got} ≠ \{want} : \{md.escape()}")
    }
  }

  // 開きに飲み込まれた骨格の行
  keep("# r\n\n<details>\n### x\n\n## y\n</details>\n", "### x", 1)
  // ほどいて余った閉じ
  keep(
    "# r\n\n<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>\n", "</details>",
    2,
  )
  // 知らない属性
  keep(
    "# r\n\n<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>\n",
    "class=\"x\"", 1,
  )
  // 重なった開き
  keep(
    "# r\n\n<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>\n",
    "<details>", 2,
  )
  // 名前が合わない畳み
  keep(
    "# r\n\n<details>\n<summary>x</summary>\n\n## h\n\n</details>\n", "<summary>x</summary>",
    1,
  )
  json_inspect(gone, content=[])
}

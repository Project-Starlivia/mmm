// 構造の規則を固定する。
//
//   単調性 — 項目の子孫は項目。項目の領土の見出しは骨格にならない
//   順序法則 — 兄弟は項目が先、見出しが後

///|
test "単調性 — 項目の中の見出しは原文のまま中身になる" {
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
            "body": [{ "id": 3, "content": ["Opaque", "# x"] }],
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
          { "id": 2, "label": "a", "body": [], "children": [] },
        ],
        "sides": [],
      },
      {
        "node": [
          "HeadingNode",
          { "id": 3, "label": "x", "body": [], "children": [] },
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
            "body": [],
            "children": [
              [
                "ListNode",
                { "id": 3, "label": "b", "body": [], "children": [] },
              ],
              [
                "HeadingNode",
                { "id": 4, "label": "a", "body": [], "children": [] },
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
                      "ListNode",
                      { "id": 4, "label": "b", "body": [], "children": [] },
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
            "body": [],
            "children": [
              [
                "ListNode",
                { "id": 3, "label": "b", "body": [], "children": [] },
              ],
              [
                "ImplicitNode",
                {
                  "id": 4,
                  "children": [
                    [
                      "HeadingNode",
                      { "id": 5, "label": "x", "body": [], "children": [] },
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
          { "id": 2, "label": "a", "body": [], "children": [] },
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
                      { "id": 5, "label": "x", "body": [], "children": [] },
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
            "body": [],
            "children": [
              [
                "ListNode",
                {
                  "id": 3,
                  "label": "b",
                  "body": [],
                  "children": [
                    { "id": 4, "label": "c", "body": [], "children": [] },
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
                      { "id": 6, "label": "x", "body": [], "children": [] },
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
      match b.content {
        Image(alt~, src~, title~) => {
          bag.push(alt)
          bag.push(src)
          bag.push(title)
        }
        Link(text~, href~, title~) => {
          bag.push(text)
          bag.push(href)
          bag.push(title)
        }
        Code(info~, text~) => {
          bag.push(info)
          bag.push(text)
        }
        Svg(s) => bag.push(s)
        ThematicBreak => ()
        Details(text=s, ..) => bag.push(s)
        Opaque(s) => bag.push(s)
      }
    }
  }

  /// 畳みの名前も中身。綴りとして落ちるのは `<summary>` のタグのほうだけ。
  fn named(f : Fold?) -> Unit {
    if f is Some({ summary: Some(s), .. }) {
      bag.push(s)
    }
  }

  fn items(xs : Array[ListNode]) -> Unit {
    for x in xs {
      bag.push(x.label)
      named(x.fold)
      blocks(x.body)
      items(x.children)
    }
  }

  fn nodes(xs : Array[Node]) -> Unit {
    for x in xs {
      match x {
        HeadingNode(h) => {
          bag.push(h.label)
          named(h.fold)
          blocks(h.body)
          nodes(h.children)
        }
        ListNode(l) => {
          bag.push(l.label)
          named(l.fold)
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
/// **意味を 1 ビットも失わない。** 綴りとして読めなかった文字は原文のまま木に残る。
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
  // 畳みの名前。タグは綴り（`summary` から書き戻せる）だが、中の文字は中身
  keep(
    "# r\n\n<details>\n<summary>Zqname</summary>\n\n## h\n\n</details>\n", "Zqname",
    1,
  )
  // 綴りでないタグ
  keep("# r\n\n<details-x>\n\n## a\n\n</details>\n", "<details-x>", 1)
  // 閉じの塊に続いた地の文（`<details>` が "tail" を含むので別の語で見る）
  keep(
    "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\nxyzzy\n", "xyzzy",
    1,
  )
  // 2 枚目の名前
  keep(
    "# r\n\n<details>\n<summary>h</summary>\n<summary>ZZZ</summary>\n\n## h\n\n</details>\n",
    "ZZZ", 1,
  )
  // 生テキストの中の閉じは綴りではないので、文字のまま残る
  keep(
    "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<script>\nvar x = \"</details>\";\n</script>\n\n</details>\n",
    "</details>", 1,
  )
  // 閉じのフェンス — 目印を置ける場所が無いので、フェンスそのものを見る
  keep("# r\n\n$$\nx\n$$\n", "$$", 2)
  keep("# r\n\n:::note\nx\n:::\n", ":::", 2)
  json_inspect(gone, content=[])
}

///|
/// **単調性の下では畳みが立たない。** 項目の領土の見出しは骨格にならないので、
/// ノードでない以上「そのノードを覆う」対象が無い。綴りを落とすと書き戻せない
/// 木になるので、領域まるごと原文のまま持つ。
test "単調性 — 項目の中の見出しを包んだ畳みは原文のまま" {
  let with_fold = parse(
    "- item\n\n  <details>\n  <summary>h</summary>\n\n  ## h\n\n  </details>\n",
  )
  let without = parse("- item\n\n  ## h\n")
  // 畳みを書いた md と書いていない md が同じ木になってはいけない
  assert_not_eq(with_fold, without)
  assert_eq(tally(written(with_fold), "<summary>h</summary>"), 1)
}

///|
/// 中身を置ける場所ごとに 1 形。目印（`Zq…`）を 1 つ埋めてある。
/// **法則はどれもこの 1 列を通す** — 形を足せば見張りが全部同時に効く。
fn forms() -> Array[(String, String)] {
  [
    ("見出しのラベル", "# Zq1\n"),
    ("setext のラベル", "Zq2\n===\n"),
    ("setext の 2 行目", "Zq3a\nZq3\n===\n"),
    ("項目のラベル", "- Zq4\n"),
    ("項目のラベルの続き", "- Zq5a\n  Zq5\n"),
    ("段落", "# r\n\nZq6\n"),
    ("コードの中身", "# r\n\n```\nZq7\n```\n"),
    ("コードの info", "# r\n\n```Zq8\nx\n```\n"),
    ("字下げコード", "# r\n\n    Zq9\n"),
    ("画像の alt", "# r\n\n![Zq10](b.png)\n"),
    ("画像の src", "# r\n\n![a](Zq11.png)\n"),
    ("画像のタイトル", "# r\n\n![a](b.png \"Zq12\")\n"),
    ("リンクの text", "# r\n\n[Zq13](b)\n"),
    ("リンクの href", "# r\n\n[a](Zq14)\n"),
    ("リンクのタイトル", "# r\n\n[a](b \"Zq15\")\n"),
    ("リンクの定義行", "# r\n\n[a]: b \"Zq16\"\n"),
    ("定義行が骨格より前", "[a]: b \"Zq17\"\n\n# r\n"),
    ("表", "# r\n\n| Zq18 | b |\n| - | - |\n| 1 | 2 |\n"),
    ("引用", "# r\n\n> Zq19\n"),
    ("コメント", "# r\n\n<!-- Zq20 -->\n"),
    ("html の塊", "# r\n\n<div>Zq21</div>\n"),
    ("svg", "# r\n\n<svg>Zq22</svg>\n"),
    ("数式の中身", "# r\n\n$$\nZq23\n$$\n"),
    ("ディレクティブ", "# r\n\n:::Zq25\nx\n:::\n"),
    ("脚注定義", "# r\n\n[^1]: Zq27\n"),
    ("frontmatter", "---\nk: Zq28\n---\n\n# a\n"),
    (
      "畳みの中身", "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\nZq29\n\n</details>\n",
    ),
    (
      "畳みの名前", "# r\n\n<details>\n<summary>Zq30</summary>\n\n## Zq30\n\n</details>\n",
    ),
    (
      "畳めない領域", "# r\n\n<details class=\"Zq31\">\n<summary>h</summary>\n\n## h\n\n</details>\n",
    ),
    ("迷子の開き", "# r\n\n<details Zq32>\n"),
    (
      "項目の中の畳み", "- item\n\n  <details>\n  <summary>Zq33</summary>\n\n  ## h\n\n  </details>\n",
    ),
    ("項目の中の見出し", "- item\n\n  ## Zq34\n"),
    ("深い項目の中身", "- a\n  - b\n\n    Zq35\n"),
    ("項目の中の線の後ろ", "- a\n\n  ---\n\n  Zq36\n"),
    ("線の後ろの中身", "# r\n\n---\n\nZq37\n"),
    ("CRLF の段落", "# r\r\n\r\nZq38\r\n"),
    (
      "畳みの入れ子", "# r\n\n<details>\n<summary>a</summary>\n\n## a\n\n<details>\n<summary>Zq39</summary>\n\n### Zq39\n\n</details>\n\n</details>\n",
    ),
    ("余った閉じの後ろ", "# r\n\n</details>\n\nZq40\n"),
    ("定義行に食われた行", "[a]: b\nZq41\n"),
    ("項目の中の定義行", "- a\n\n  [x]: b \"Zq42\"\n"),
    (
      "畳めない領域の中の定義行", "# r\n\n<details class=\"z\">\n\n[a]: b \"Zq43\"\n\n## h\n\n</details>\n",
    ),
    (
      "畳みの中の定義行", "# r\n\n<details>\n\n## h\n\n[a]: b \"Zq44\"\n\n</details>\n",
    ),
  ]
}

///|
/// **中身は原文と同じ数だけ木に在る。** 綴り（`#` や `<details>`）は構造と
/// フラグが引き受けるので消えてよいが、それ以外の文字は 1 つも落ちてはいけないし、
/// 増えてもいけない（書き戻すと触っていない場所に行が生える）。
///
/// 中身を置ける場所ごとに 1 形つくり、目印（`Zq…`）の数を総当たりで見る。
/// 名指しの見張りは「一度落とした形」しか守らないので、**まだ落としていない形**は
/// ここが守る。落ちたら、その場所の読みがどこかで綴り扱いになっている。
test "意味 — 中身を置ける場所すべてで文字が同じ数だけ残る" {
  let forms = forms()
  let gone = []
  for form in forms {
    let (name, md) = form
    let mark = mark_of(md)
    let want = tally(md, mark)
    let got = tally(written(parse(md)), mark)
    if got != want {
      gone.push("\{name} : \{mark} が \{want} → \{got} : \{md.escape()}")
    }
  }
  json_inspect(gone, content=[])
}

///|
/// md に埋めた目印（`Zq` に続く英数字）を取り出す。
fn mark_of(md : String) -> String {
  let mut at = 0
  while at + 1 < md.length() && !(md[at] == 'Z' && md[at + 1] == 'q') {
    at = at + 1
  }
  guard at + 1 < md.length() else { return "Zq" }
  let mut z = at + 2
  while z < md.length() &&
        ((md[z] >= '0' && md[z] <= '9') || (md[z] >= 'a' && md[z] <= 'z')) {
    z = z + 1
  }
  String::unsafe_substring(md, start=at, end=z)
}

// 骨格でないものが、いま積んでいるノードの中身になることを固定する。
//
// 絵になるのは 4 つだけで、疑わしきは Raw（原文のまま）。

///|
test "散文はノードの中身になる" {
  json_inspect(parse("# a\n\nhello\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "source": "hello" }],
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
test "中身は文書順に並ぶ" {
  json_inspect(parse("# a\n\nhello\n\nworld\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            { "id": 3, "source": "hello" },
            { "id": 4, "source": "world" },
          ],
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
test "中身は深さで振り分けられる" {
  json_inspect(parse("# a\n\nx\n\n## b\n\ny\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "source": "x" }],
          "children": [
            {
              "id": 4,
              "label": "b",
              "body": [{ "id": 5, "source": "y" }],
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
test "最初の骨格より前の散文は文書のもの" {
  json_inspect(parse("intro\n\n# a\n"), content={
    "body": [{ "id": 2, "source": "intro" }],
    "roots": [
      {
        "node": {
          "id": 3,
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
test "画像" {
  json_inspect(parse("# a\n\n![alt](x.png)\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": [
                "Image",
                { "alt": "alt", "src": "x.png", "title": "" },
              ],
              "source": "![alt](x.png)",
            },
          ],
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
test "リンク" {
  json_inspect(parse("# a\n\n[text](https://e.com)\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": [
                "Link",
                { "text": "text", "href": "https://e.com", "title": "" },
              ],
              "source": "[text](https://e.com)",
            },
          ],
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
test "混ざった段落は切り分けない" {
  json_inspect(parse("# a\n\nsee ![alt](x.png)\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "source": "see ![alt](x.png)" }],
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
test "フェンスのコード" {
  json_inspect(parse("# a\n\n```js\nlet x = 1\n```\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Code", { "info": "js", "text": "let x = 1\n" }],
              "source": "```js\nlet x = 1\n```",
            },
          ],
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
/// 意味は Code。**記法（字下げ 4 桁）は `source` に残る**ので、書き戻せば字下げのまま
/// （#206。前は剥いだ字が返って段落に化けていた）
test "インデントコードも読む — 記法は source に残る" {
  json_inspect(parse("# a\n\n    code\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Code", { "info": "", "text": "code\n" }],
              "source": "    code",
            },
          ],
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
test "SVG" {
  json_inspect(parse("# a\n\n<svg><rect/></svg>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [
            {
              "id": 3,
              "content": ["Svg", "<svg><rect/></svg>\n"],
              "source": "<svg><rect/></svg>",
            },
          ],
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
test "飾りの水平線は Rule" {
  json_inspect(parse("# a\n\n***\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "content": "ThematicBreak", "source": "***" }],
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
test "引用と表は原文のまま" {
  json_inspect(parse("# a\n\n> quote\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "source": "> quote" }],
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
test "項目にも中身が付く" {
  json_inspect(parse("- a\n\n  hello\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "source": "hello" }],
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
/// **容器の字下げを剥がすから、項目の中の `<details>` も畳みとして読める。**
/// 剥がさないと切り出しの列がずれ、深い入れ子では字下げコードへ化ける。
/// 包まれた `## h` は項目の子になり、畳みはその見出しに乗る。
test "項目の中の畳みは、包んだ見出しに乗る" {
  json_inspect(parse("- a\n\n  <details>\n\n  ## h\n\n  </details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "",
              "body": [],
              "children": [
                {
                  "id": 4,
                  "label": "h",
                  "fold": { "open": false },
                  "body": [],
                  "children": [],
                  "mark": ["Heading", { "setext": false, "closing": 0 }],
                },
              ],
            },
          ],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
/// 2 段でも同じ。剥がす幅は容器の字下げそのものなので、深い項目でも畳みは乗る。
test "入れ子の項目でも、畳みは包んだ見出しに乗る" {
  json_inspect(
    parse("- a\n  - b\n\n    <details>\n\n    ## h\n\n    </details>\n"),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "a",
            "body": [],
            "children": [
              {
                "id": 3,
                "label": "b",
                "body": [],
                "children": [
                  {
                    "id": 4,
                    "label": "",
                    "body": [],
                    "children": [
                      {
                        "id": 5,
                        "label": "h",
                        "fold": { "open": false },
                        "body": [],
                        "children": [],
                        "mark": ["Heading", { "setext": false, "closing": 0 }],
                      },
                    ],
                  },
                ],
                "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
              },
            ],
            "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
          },
          "sides": ["Right"],
          "rules": [""],
        },
      ],
    },
  )
}

///|
/// Raw も同じ規則で切る。
test "項目の中の Raw も列 0 に揃う" {
  json_inspect(parse("- a\n\n  <!-- x\n  y -->\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [{ "id": 3, "source": "<!-- x\ny -->" }],
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
/// **切り出しは改行を LF に揃える**（#207）。読んだ字をそのまま持つのが原則だが、
/// 改行だけは例外 — 木が抱える字は LF だけという不変量で、これが無いと CRLF の
/// 文書を書き戻したとき 1 つの文書の中で改行が混ざる。原文そのもの（地番と
/// 記法構造の書き戻し）は `slice` を使うので、1 バイトも変わらない。
test "切り出しの中の CRLF は LF に揃う" {
  json_inspect(
    parse("# r\r\n\r\n<details class=\"x\">\r\n\r\n## h\r\n\r\n</details>\r\n"),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": ["Details", { "open": false, "body": "## h" }],
                "source": "<details class=\"x\">\n\n## h\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// **リンクの定義行は書いてあった位置に戻す。** mdAst はこれをブロックとして
/// 返さず `Document.definitions` に分けて持つので、読まないと行ごと消える。
/// 文書のどこに書いてもよい記法なので、まとめて 1 か所へ動かすと
/// 触っていない場所が動く。
test "リンクの定義行は位置ごと残る" {
  json_inspect(parse("# r\n\n[a]: b \"c\"\n\n## h\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [{ "id": 3, "source": "[a]: b \"c\"" }],
          "children": [
            {
              "id": 4,
              "label": "h",
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
test "定義行が文末にあっても残る" {
  json_inspect(parse("# r\n\n## h\n\n[a]: b\n"), content={
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
              "label": "h",
              "body": [{ "id": 4, "source": "[a]: b" }],
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
/// タイトルは中身なので落とさない。木の形と renderer の props は別でよい。
test "画像とリンクのタイトルは残る" {
  json_inspect(parse("# r\n\n![a](b.png \"t1\")\n\n[c](d \"t2\")\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": [
                "Image",
                { "alt": "a", "src": "b.png", "title": "t1" },
              ],
              "source": "![a](b.png \"t1\")",
            },
            {
              "id": 4,
              "content": ["Link", { "text": "c", "href": "d", "title": "t2" }],
              "source": "[c](d \"t2\")",
            },
          ],
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
/// `$$` と `:::` の span は閉じの行を含まないので、原文のまま持つと閉じが落ちる。
/// フェンスのコードは `Block::Code` として綴りごと持つので、こちらは要らない。
test "数式とディレクティブの閉じは残る" {
  json_inspect(parse("# r\n\n$$\nx\n$$\n\n:::note\ny\n:::\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            { "id": 3, "source": "$$\nx\n$$" },
            { "id": 4, "source": ":::note\ny\n:::" },
          ],
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
/// **定義行は項目の中にも書ける。** 定義は文書ぜんぶで 1 列なので、項目を
/// 読み解くときはその項目のぶんだけ切り出して渡す。まとめて外へ出すと、
/// 触っていない場所が動く。
test "項目の中の定義行は項目の中に残る" {
  json_inspect(parse("- a\n  - b\n\n    [q]: /r\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "a",
          "body": [],
          "children": [
            {
              "id": 3,
              "label": "b",
              "body": [{ "id": 4, "source": "[q]: /r" }],
              "children": [],
              "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
            },
          ],
          "mark": ["Item", { "marker": "-", "offset": 2, "loose": false }],
        },
        "sides": ["Right"],
        "rules": [""],
      },
    ],
  })
}

///|
/// **同じ行を 2 度は出さない。** 原文のまま持つ領域は定義行ごと抱えるので、
/// そこに重ねて出すと、書き戻したとき定義行が増える。
test "原文のまま持つ領域の中の定義行は重ねない" {
  json_inspect(
    parse("# r\n\n<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>\n"),
    content={
      "body": [],
      "roots": [
        {
          "node": {
            "id": 2,
            "label": "r",
            "body": [
              {
                "id": 3,
                "content": [
                  "Details",
                  { "open": false, "body": "junk\n\n[q]: /r\n\n## a" },
                ],
                "source": "<details>\njunk\n\n[q]: /r\n\n## a\n\n</details>",
              },
            ],
            "children": [],
            "mark": ["Heading", { "setext": false, "closing": 0 }],
          },
          "sides": [],
          "rules": [],
        },
      ],
    },
  )
}

///|
/// **定義行は畳みの領域に入れない。** 開きとノードの間に書いてあれば、それは
/// そのノードのものではない要素なので①が欠ける（畳みが立つと綴りは木から
/// 消えるので、書き戻したとき定義行が領域の外へ出る）。
test "開きとノードの間の定義行があれば中身" {
  json_inspect(parse("# r\n\n<details>\n\n[q]: /r\n\n## a\n\n</details>\n"), content={
    "body": [],
    "roots": [
      {
        "node": {
          "id": 2,
          "label": "r",
          "body": [
            {
              "id": 3,
              "content": [
                "Details",
                { "open": false, "body": "[q]: /r\n\n## a" },
              ],
              "source": "<details>\n\n[q]: /r\n\n## a\n\n</details>",
            },
          ],
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
/// **定義行は塊にならないが中身。** 保留中の水平線はそこで飾りに落ちるので、
/// 後ろの見出しは境界の先ではなく普通の子になる。
test "定義行は保留中の水平線を飾りに落とす" {
  json_inspect(parse("# r\n\n## a\n\n---\n\n[q]: /r\n\n## b\n"), content={
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
              "body": [
                { "id": 4, "content": "ThematicBreak", "source": "---" },
                { "id": 5, "source": "[q]: /r" },
              ],
              "children": [],
              "mark": ["Heading", { "setext": false, "closing": 0 }],
            },
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
        "sides": ["Right", "Right"],
        "rules": ["", ""],
      },
    ],
  })
}

///|
/// 素の URL の行と `<URL>` は、書き方が違うだけの同じリンク。
/// **見える字が URL そのもの**なので `text` は URL になる。
/// 開ける先だけ（`http(s)`）で、字が混ざれば Raw。
test "素の URL とオートリンク" {
  fn body(md : String) -> Json {
    parse("# a\n\n" + md + "\n").roots[0].node.body
    .map(b => b.content)
    .to_json()
  }

  json_inspect(
    [
      body("https://e.com/x"),
      body("<https://e.com/x>"),
      body("http://e.com"),
      body("see https://e.com/x"),
      body("https://e.com/x y"),
      body("ftp://e.com/x"),
      body("<mailto:a@e.com>"),
    ],
    content=[
      [
        [
          [
            "Link",
            {
              "text": "https://e.com/x",
              "href": "https://e.com/x",
              "title": "",
            },
          ],
        ],
      ],
      [
        [
          [
            "Link",
            {
              "text": "https://e.com/x",
              "href": "https://e.com/x",
              "title": "",
            },
          ],
        ],
      ],
      [
        [
          [
            "Link",
            { "text": "http://e.com", "href": "http://e.com", "title": "" },
          ],
        ],
      ],
      [null],
      [null],
      [null],
      [null],
    ],
  )
}

///|
/// 塊 1 つの md を、貼る側と同じ道（地番を通して）で段に割る
fn rung_list(md : String) -> Array[Rung]? {
  let (doc, spots) = build(md)
  guard doc.body.get(0) is Some(b) && spots.get(b.id) is Some(spot) else {
    return None
  }
  rungs(md, spot)
}

///|
/// 貼り付けは一番外の段落だけを行ごとにノードにする。段落かどうかは mdAst が言う。
test "行に割れるのは段落だけ — それ以外の中身は行を持たない" {
  assert_eq(
    rung_list("a\nb\n"),
    Some([{ col: 0, label: "a", }, { col: 0, label: "b", }]),
  )
  assert_eq(rung_list("  a  \r\n\r\n"), Some([{ col: 2, label: "a", }]))
  assert_eq(
    rung_list("**a** and [b](c)\n"),
    Some([{ col: 0, label: "**a** and [b](c)", }]),
  )
  assert_eq(rung_list("| a | b |\n|---|---|\n| 1 | 2 |\n"), None)
  assert_eq(rung_list("> q\n"), None)
  assert_eq(rung_list("<div>x</div>\n"), None)
  assert_eq(rung_list("```\nx\n```\n"), None)
  assert_eq(rung_list(""), None)
}

///|
/// **桁は原文から測る。** 塊の原文（`carve` 済み）では測れないものを押さえる —
/// 1 行目より浅い行、タブ、空行の後ろの塊（#118）
test "rungs: 桁は原文から測る — タブは 4 桁、空行の後ろも失わない" {
  // タブ 1 つと空白 4 つは同じ深さ
  assert_eq(
    rung_list("a\n\tb\n"),
    Some([{ col: 0, label: "a", }, { col: 4, label: "b", }]),
  )
  assert_eq(
    rung_list("a\n    b\n"),
    Some([{ col: 0, label: "a", }, { col: 4, label: "b", }]),
  )
  // 1 行目より浅い行。塊の原文では 1 行目と同じ桁に見える
  assert_eq(
    rung_list("  a\nb\n"),
    Some([{ col: 2, label: "a", }, { col: 0, label: "b", }]),
  )
  // 空行で塊が割れても、2 つ目の塊は左余白を持ったまま測れる
  let md = "a\n  b\n\n  c\n"
  let (doc, spots) = build(md)
  assert_eq(doc.body.map(b => rungs(md, spots.get(b.id).unwrap())), [
    Some([{ col: 0, label: "a", }, { col: 2, label: "b", }]),
    Some([{ col: 2, label: "c", }]),
  ])
}

// ══════════════════════════════════════════════════════════════════
// 読んだ字は source だけ — content は意味だけを持ち、無ければ読み解いていない
// ══════════════════════════════════════════════════════════════════

///|
/// **同じ字を 2 か所に持たない。** 読み解かなかった中身は `content` を持たず、
/// 原文は `source` 1 か所。書き戻しもそこから。
test "読み解かない中身は content を持たず、原文は source だけ" {
  let body = (md : String) => parse("# a\n\n" + md + "\n").roots[0].node.body
  json_inspect(body("hello"), content=[{ "id": 3, "source": "hello" }])
  json_inspect(body("| x |\n| - |"), content=[
    { "id": 3, "source": "| x |\n| - |" },
  ])
  json_inspect(body("<!-- c -->"), content=[{ "id": 3, "source": "<!-- c -->" }])
}

///|
/// 畳みにならなかった領域も原文は `source` 1 か所。`open` / `summary` / `body` は
/// GitHub が描くのと同じ読み取りなので残る。
test "Details も原文は source だけ" {
  json_inspect(
    parse("# a\n\n<details>\n\nx\n\n</details>\n\n## b\n").roots[0].node.body,
    content=[
      {
        "id": 3,
        "content": ["Details", { "open": false, "body": "x" }],
        "source": "<details>\n\nx\n\n</details>",
      },
    ],
  )
}

///|
/// 意味の在る中身は、読んだ原文と両方を持つ — 綴りが違えば触った所だけ正規形に落ちる。
test "読み解いた中身は意味と原文の両方を持つ" {
  json_inspect(parse("# a\n\n![alt](x.png)\n").roots[0].node.body, content=[
    {
      "id": 3,
      "content": ["Image", { "alt": "alt", "src": "x.png", "title": "" }],
      "source": "![alt](x.png)",
    },
  ])
}

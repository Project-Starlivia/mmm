// check を固定する。
//
// **parse の出力は必ず通る**（通らなければ読みのバグ）。
// 破れを見つけられることは、手で組んだ壊れた木で確かめる。

///|
/// 今日までに集めた綴りと、中身を置ける場所の総当たり（`forms`）を通す。
/// 1 つでも破れたら読みがおかしい。
test "parse の出力は必ず通る" {
  let sources = [
    "# a\n", "# a\n\n## b\n\n### c\n", "## a\n", "# r\n\n#### z\n", "- a\n  - b\n",
    "# r\n\n- b\n\n## a\n", "# r\n\n## a\n\n- b\n", "# r\n\n## a\n\n---\n\n## b\n",
    "# r\n\n---\n\n### x\n", "# root\n\n---\n\n## h1\n\n---\n\n* i1\n\n---\n\n## h2\n",
    "# a\n\nbody\n\n---\n\nbody\n\n## b\n", "# r\n\n## a\n\n---\n\n---\n\n## b\n",
    "# r\n\n<details>\n\n## h\n\nbody\n\n</details>\n", "# r\n\n## h\n\n<details>\n\nbody\n\n</details>\n",
    "# r\n\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n", "# r\n\n</details>\n",
    "# r\n\n<!-- x -->\n", "---\nk: v\n---\n\n# a\n", "text\n\n![a](b.png)\n\n# a\n",
    "# a\n\n```js\nx\n```\n", "- a\n  # x\n", "# r\n\n- b\n\n### x\n", "###### f\n\n####### g\n",
    "# a\r\n\r\n## b\r\n", "",
    // 畳み — 綴りになる形と、ならずに原文のまま残る形の両方
     "# r\n\n<details open>\n<summary>h</summary>\n\n## h\n\n</details>\n", "# r\n\n<details class=\"x\">\n<summary>h</summary>\n\n## h\n\n</details>\n",
    "# r\n\n<details>\n<summary>x</summary>\n\n## x\n\n<details>\n<summary>y</summary>\n\n### y\n</details>\n</details>\n",
    "# r\n\n<details>\n<summary>y</summary>\n\n## y\n</details>\n</details>\n", "# r\n\n<details>\n<details>\n<summary>h</summary>\n\n## h\n\n</details>\n\n</details>\n",
    "# r\n\n<details>\n### x\n\n## y\n</details>\n",
  ]
  let bad = []
  for md in sources {
    if check(parse(md)).length() > 0 {
      bad.push(md.escape())
    }
  }
  for form in forms() {
    let (name, md) = form
    if check(parse(md)).length() > 0 {
      bad.push(name)
    }
  }
  json_inspect(bad, content=[])
}

///|
test "同じ id が 2 度出たら見つける" {
  let n : Node = {
    id: 7,
    label: "a",
    fold: None,
    body: [],
    children: [],
    mark: Some(atx),
  }
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: { ..n, children: [n], mark: Some(atx), },
        sides: [Right],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["DupeId", 7]])
}

///|
/// 飛びを埋める理由が無く、書き出す文字も無いので居てはいけない。
test "子を持たない Implicit を見つける" {
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: {
          id: 2,
          label: "",
          fold: None,
          body: [],
          children: [],
          mark: None,
        },
        sides: [],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["BarrenImplicit", 2]])
}

///|
test "側の本数が子と合わなければ見つける" {
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: {
          id: 2,
          label: "r",
          fold: None,
          body: [],
          children: [
            {
              id: 3,
              label: "a",
              fold: None,
              body: [],
              children: [],
              mark: Some(atx),
            },
          ],
          mark: Some(atx),
        },
        sides: [],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[
    ["SideCount", { "root": 2, "sides": 0, "children": 1 }],
  ])
}

///|
/// 中身もノードと同じ id 空間に居る。
test "中身の id も一意さを見る" {
  let doc : Doc = {
    frontmatter: None,
    body: [{ id: 5, source: None, content: Raw("a"), }],
    roots: [
      {
        node: {
          id: 5,
          label: "r",
          fold: None,
          body: [],
          children: [],
          mark: Some(atx),
        },
        sides: [],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["DupeId", 5]])
}

///|
/// 名前の字で畳みを断る規則は無い。`</summary>` も、生の HTML の塊を
/// 終わらせる空行も、md が言うとおりに読まれるだけで破れではない。
test "畳みの名前は何でも書ける — `</summary>` も空行も破れではない" {
  let named = (s : String) => {
    let doc : Doc = {
      frontmatter: None,
      body: [],
      roots: [
        {
          node: {
            id: 2,
            label: "x",
            fold: Some({ open: false, summary: Some(s), }),
            body: [],
            children: [],
            mark: Some(atx),
          },
          sides: [],
          rules: [],
        },
      ],
    }
    check(doc)
  }
  json_inspect(named("a</summary>b"), content=[])
  json_inspect(named("a\n  \nb"), content=[])
}

///|
/// **1 行の改行は塊を割らない。** `<summary>a\nb</summary>` はそのまま読み戻せる
/// ので、名前に改行が在るだけでは書けないことにならない。
test "改行だけの名前は書ける" {
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: {
          id: 2,
          label: "x",
          fold: Some({ open: false, summary: Some("a\nb\n"), }),
          body: [],
          children: [],
          mark: Some(atx),
        },
        sides: [],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[])
}

///|
fn tb(id : Int) -> Block {
  { id, source: None, content: ThematicBreak, }
}

///|
fn leaf(id : Int, label : String, body? : Array[Block] = []) -> Node {
  { id, label, fold: None, body, children: [], mark: Some(atx), }
}

///|
/// 骨格の直前の水平線は境界（側の変わり目）に読まれるので、中身としては書けない。
/// 文書の中身の尻に根が続く・見出しの中身の尻に子が続く・兄弟が続く、の 3 つ。
/// 最後のノードの尻と、項目の中は飾りのまま。
test "中身の尻の水平線に骨格が続けば見つける" {
  let doc : Doc = {
    frontmatter: None,
    body: [tb(2)],
    roots: [
      {
        node: {
          id: 3,
          label: "r",
          fold: None,
          body: [tb(4)],
          children: [
            leaf(5, "a", body=[tb(6)]),
            {
              id: 7,
              label: "i",
              fold: None,
              body: [tb(8)],
              children: [],
              mark: Some(bullet),
            },
            leaf(9, "b", body=[
              tb(10),
              { id: 11, source: None, content: Raw("x"), },
            ]),
            leaf(12, "c", body=[tb(13)]),
          ],
          mark: Some(atx),
        },
        // 項目 i は見出し a の直後なので、境界（側の変わり目）が要る
        sides: [Right, Left, Left, Left],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[
    ["BorderBreak", 2],
    ["BorderBreak", 4],
    ["BorderBreak", 6],
  ])
}

///|
/// 見出し（Implicit も）の直後の項目はその見出しの子に読まれ、Implicit は飛びを
/// その見出しから測られる。間に境界（側の変わり目）があれば別 — 深さ 2 へ引き出される。
/// 項目の後ろなら何でも置ける（項目の枠は見出しの親になれず、落ちる）。
test "見出しに境界なしで続く項目・Implicit を見つける" {
  let item = (id : Int, label : String) => {
    (
      { id, label, fold: None, body: [], children: [], mark: Some(bullet), } :
      Node)
  }
  let gap = (id : Int, kid : Node) => {
    (
      { id, label: "", fold: None, body: [], children: [kid], mark: None, } :
      Node)
  }
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      { node: gap(2, leaf(3, "x")), sides: [Right], rules: [], },
      { node: item(4, "i"), sides: [], rules: [], },
      { node: gap(5, leaf(6, "y")), sides: [Right], rules: [], },
      { node: item(7, "j"), sides: [], rules: [], },
      { node: leaf(8, "a"), sides: [], rules: [], },
      { node: item(9, "k"), sides: [], rules: [], },
      { node: gap(10, leaf(11, "z")), sides: [Right], rules: [], },
      {
        node: {
          id: 12,
          label: "r",
          fold: None,
          body: [],
          children: [
            leaf(13, "b"),
            item(14, "l"),
            gap(15, leaf(16, "w")),
            leaf(17, "c"),
            item(18, "m"),
            leaf(19, "d"),
            gap(20, leaf(21, "v")),
          ],
          mark: Some(atx),
        },
        sides: [Right, Right, Left, Left, Right, Right, Right],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[
    ["Swallowed", 4],
    ["Swallowed", 7],
    ["Swallowed", 9],
    ["Swallowed", 14],
    ["Swallowed", 20],
  ])
}

///|
/// 項目の中の `---` は中身なので、項目の根の子は側を持てない。
test "項目の根の子の Left を見つける" {
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: {
          id: 2,
          label: "a",
          fold: None,
          body: [],
          children: [
            {
              id: 3,
              label: "b",
              fold: None,
              body: [],
              children: [],
              mark: Some(bullet),
            },
            {
              id: 4,
              label: "c",
              fold: None,
              body: [],
              children: [],
              mark: Some(bullet),
            },
          ],
          mark: Some(bullet),
        },
        sides: [Right, Left],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["ListSide", 2]])
}

///|
/// 項目は相対記法で深さが飛ばないので、飛び（Implicit）の直下には居られない。
/// 書くと Implicit が消え、項目は 1 つ浅く読まれる。
test "Implicit の直下の項目を見つける" {
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: {
          id: 2,
          label: "r",
          fold: None,
          body: [],
          children: [
            {
              id: 3,
              label: "",
              fold: None,
              body: [],
              children: [
                {
                  id: 4,
                  label: "i",
                  fold: None,
                  body: [],
                  children: [],
                  mark: Some(bullet),
                },
              ],
              mark: None,
            },
          ],
          mark: Some(atx),
        },
        sides: [Right],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["GappedItem", 4]])
}

///|
/// `#` は 6 本まで。7 段目の見出しは書くと段落になる。項目は相対記法なので、
/// 見出しの下で何段深くても書ける。
test "深さ 7 以上の見出しを見つける" {
  fn chain(depth : Int, tip : Node) -> Node {
    let mut n = tip
    for i in 0..<depth {
      n = {
        id: depth - i,
        label: "h",
        fold: None,
        body: [],
        children: [n],
        mark: Some(atx),
      }
    }
    n
  }

  let seven : Doc = {
    frontmatter: None,
    body: [],
    roots: [{ node: chain(6, leaf(10, "g")), sides: [Right], rules: [], }],
  }
  json_inspect(check(seven), content=[["TooDeep", 10]])
  // 6 段目の下の項目と、6 段目までの飛び（Implicit）は書ける
  let deep_item : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: chain(6, {
          id: 10,
          label: "i",
          fold: None,
          body: [],
          children: [
            {
              id: 11,
              label: "j",
              fold: None,
              body: [],
              children: [],
              mark: Some(bullet),
            },
          ],
          mark: Some(bullet),
        }),
        sides: [Right],
        rules: [],
      },
    ],
  }
  json_inspect(check(deep_item), content=[])
  let gapped : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: chain(4, {
          id: 9,
          label: "",
          fold: None,
          body: [],
          children: [leaf(10, "f")],
          mark: None,
        }),
        sides: [Right],
        rules: [],
      },
    ],
  }
  json_inspect(check(gapped), content=[])
}

///|
/// 深さ 3 には setext が無い。改行を含む名前は ATX に落とせない（2 行目が段落になる）
test "深さ 3 以上の改行を含む名前は書けない" {
  let doc : Doc = {
    frontmatter: None,
    body: [],
    roots: [
      {
        node: {
          id: 2,
          label: "a",
          fold: None,
          body: [],
          children: [
            {
              id: 3,
              label: "b",
              fold: None,
              body: [],
              children: [
                {
                  id: 4,
                  label: "c\nd",
                  fold: None,
                  body: [],
                  children: [],
                  mark: Some(Heading(setext=true, closing=0)),
                },
              ],
              mark: Some(atx),
            },
          ],
          mark: Some(atx),
        },
        sides: [Right],
        rules: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["DeepSetext", 4]])
}

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
  let n : HeadingNode = {
    id: 7,
    label: "a",
    fold: None,
    body: [],
    children: [],
  }
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      { node: HeadingNode({ ..n, children: [HeadingNode(n)] }), sides: [Right] },
    ],
  }
  json_inspect(check(doc), content=[["DupeId", 7]])
}

///|
/// 飛びを埋める理由が無く、書き出す文字も無いので居てはいけない。
test "子を持たない Implicit を見つける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [{ node: ImplicitNode({ id: 2, children: [] }), sides: [] }],
  }
  json_inspect(check(doc), content=[["BarrenImplicit", 2]])
}

///|
test "側の本数が子と合わなければ見つける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      {
        node: HeadingNode({
          id: 2,
          label: "r",
          fold: None,
          body: [],
          children: [
            HeadingNode({
              id: 3,
              label: "a",
              fold: None,
              body: [],
              children: [],
            }),
          ],
        }),
        sides: [],
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
    eol: Lf,
    body: [{ id: 5, content: Opaque("a") }],
    roots: [
      {
        node: HeadingNode({
          id: 5,
          label: "r",
          fold: None,
          body: [],
          children: [],
        }),
        sides: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["DupeId", 5]])
}

///|
/// `<summary>` の中身は最初の `</summary>` までなので、名前にそれが入って
/// いると読み戻したとき別の名前になる。
test "畳みの名前が summary に書けなければ見つける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      {
        node: HeadingNode({
          id: 2,
          label: "x",
          fold: Some({ open: false, summary: Some("a</summary>b") }),
          body: [],
          children: [],
        }),
        sides: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["UnwritableName", 2]])
}

///|
/// 生の HTML の塊は空行で終わるので、名前に空行が入っていると `</summary>`
/// が次の塊へ落ちて、読み戻したとき畳みごと消える。名前が変わるだけの
/// `</summary>` より損が大きい。
test "畳みの名前に空行が入っていれば見つける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      {
        node: HeadingNode({
          id: 2,
          label: "x",
          fold: Some({ open: false, summary: Some("a\n  \nb") }),
          body: [],
          children: [],
        }),
        sides: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["UnwritableName", 2]])
}

///|
/// **1 行の改行は塊を割らない。** `<summary>a\nb</summary>` はそのまま読み戻せる
/// ので、名前に改行が在るだけでは書けないことにならない。
test "改行だけの名前は書ける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      {
        node: HeadingNode({
          id: 2,
          label: "x",
          fold: Some({ open: false, summary: Some("a\nb\n") }),
          body: [],
          children: [],
        }),
        sides: [],
      },
    ],
  }
  json_inspect(check(doc), content=[])
}

///|
fn tb(id : Int) -> Block {
  { id, content: ThematicBreak }
}

///|
fn leaf(id : Int, label : String, body? : Array[Block] = []) -> Node {
  HeadingNode({ id, label, fold: None, body, children: [] })
}

///|
/// 骨格の直前の水平線は境界（側の変わり目）に読まれるので、中身としては書けない。
/// 文書の中身の尻に根が続く・見出しの中身の尻に子が続く・兄弟が続く、の 3 つ。
/// 最後のノードの尻と、項目の中は飾りのまま。
test "中身の尻の水平線に骨格が続けば見つける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [tb(2)],
    roots: [
      {
        node: HeadingNode({
          id: 3,
          label: "r",
          fold: None,
          body: [tb(4)],
          children: [
            leaf(5, "a", body=[tb(6)]),
            ListNode({
              id: 7,
              label: "i",
              fold: None,
              body: [tb(8)],
              children: [],
            }),
            leaf(9, "b", body=[tb(10), { id: 11, content: Opaque("x") }]),
            leaf(12, "c", body=[tb(13)]),
          ],
        }),
        // 項目 i は見出し a の直後なので、境界（側の変わり目）が要る
        sides: [Right, Left, Left, Left],
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
  let li = (id : Int, label : String) => {
    ListNode({ id, label, fold: None, body: [], children: [] })
  }
  let gap = (id : Int, kid : Node) => ImplicitNode({ id, children: [kid] })
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      { node: gap(2, leaf(3, "x")), sides: [Right] },
      { node: li(4, "i"), sides: [] },
      { node: gap(5, leaf(6, "y")), sides: [Right] },
      { node: li(7, "j"), sides: [] },
      { node: leaf(8, "a"), sides: [] },
      { node: li(9, "k"), sides: [] },
      { node: gap(10, leaf(11, "z")), sides: [Right] },
      {
        node: HeadingNode({
          id: 12,
          label: "r",
          fold: None,
          body: [],
          children: [
            leaf(13, "b"),
            li(14, "l"),
            gap(15, leaf(16, "w")),
            leaf(17, "c"),
            li(18, "m"),
            leaf(19, "d"),
            gap(20, leaf(21, "v")),
          ],
        }),
        sides: [Right, Right, Left, Left, Right, Right, Right],
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
    eol: Lf,
    body: [],
    roots: [
      {
        node: ListNode({
          id: 2,
          label: "a",
          fold: None,
          body: [],
          children: [
            { id: 3, label: "b", fold: None, body: [], children: [] },
            { id: 4, label: "c", fold: None, body: [], children: [] },
          ],
        }),
        sides: [Right, Left],
      },
    ],
  }
  json_inspect(check(doc), content=[["ListSide", 2]])
}

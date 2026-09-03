// check を固定する。
//
// **parse の出力は必ず通る**（通らなければ読みのバグ）。
// 破れを見つけられることは、手で組んだ壊れた木で確かめる。

///|
/// 今日までに集めた綴りを一通り通す。1 つでも破れたら読みがおかしい。
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
    // 畳み — 綴りになる形と、ならずに逐語へ落ちる形の両方
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
  json_inspect(bad, content=[])
}

///|
test "同じ id が 2 度出たら見つける" {
  let n : HeadingNode = {
    id: 7,
    label: "a",
    details: false,
    open: false,
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
          details: false,
          open: false,
          body: [],
          children: [
            HeadingNode({
              id: 3,
              label: "a",
              details: false,
              open: false,
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
/// 中身の畳みも同じ id 空間に居る。
test "Details の id も一意さを見る" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [Details(id=5, text="a")],
    roots: [
      {
        node: HeadingNode({
          id: 5,
          label: "r",
          details: false,
          open: false,
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
/// `open` は畳みの綴りの一部なので、畳んでいないノードには立たない。
/// 立っていると書き出す `<details>` が無く、綴れない木になる。
test "畳んでいないのに open が立っていたら見つける" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [],
    roots: [
      {
        node: HeadingNode({
          id: 2,
          label: "a",
          details: false,
          open: true,
          body: [],
          children: [],
        }),
        sides: [],
      },
    ],
  }
  json_inspect(check(doc), content=[["OpenWithoutDetails", 2]])
}

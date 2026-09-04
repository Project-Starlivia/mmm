// 「前後の木がこう違えば、md はここだけ変わる」を固定する。
//
// 前の木は原文から読む（地番がそこから出るので、ここだけは読みに依る）。
// 後の木はその写しを手で変えたもの — 誰が変えたか（操作）は反映の外。

///|
/// 根 root の、path を辿った先のノードを f で置き換えた Doc。
fn change(doc : Doc, root : Int, path : Array[Int], f : (Node) -> Node) -> Doc {
  let roots = doc.roots.copy()
  let r = roots[root]
  roots[root] = { node: rewrite(r.node, path, 0, f), sides: r.sides }
  { ..doc, roots, }
}

///|
fn rewrite(x : Node, path : Array[Int], k : Int, f : (Node) -> Node) -> Node {
  if k == path.length() {
    return f(x)
  }
  let i = path[k]
  match x {
    HeadingNode(h) => {
      let kids = h.children.copy()
      kids[i] = rewrite(kids[i], path, k + 1, f)
      HeadingNode({ ..h, children: kids })
    }
    ImplicitNode(g) => {
      let kids = g.children.copy()
      kids[i] = rewrite(kids[i], path, k + 1, f)
      ImplicitNode({ ..g, children: kids })
    }
    ListNode(l) => {
      let kids = l.children.copy()
      kids[i] = match rewrite(ListNode(kids[i]), path, k + 1, f) {
        ListNode(c) => c
        _ => abort("項目の子は項目")
      }
      ListNode({ ..l, children: kids })
    }
  }
}

///|
fn relabel(label : String) -> (Node) -> Node {
  x => {
    match x {
      HeadingNode(h) => HeadingNode({ ..h, label, })
      ListNode(l) => ListNode({ ..l, label, })
      other => other
    }
  }
}

///|
fn adopt(kid : Node) -> (Node) -> Node {
  x => {
    match x {
      HeadingNode(h) => HeadingNode({ ..h, children: h.children + [kid] })
      ListNode(l) =>
        match kid {
          ListNode(c) => ListNode({ ..l, children: l.children + [c] })
          _ => abort("項目の子は項目")
        }
      ImplicitNode(g) => ImplicitNode({ ..g, children: g.children + [kid] })
    }
  }
}

///|
fn orphan(x : Node) -> Node {
  match x {
    HeadingNode(h) => HeadingNode({ ..h, children: [] })
    ListNode(l) => ListNode({ ..l, children: [] })
    ImplicitNode(g) => ImplicitNode({ ..g, children: [] })
  }
}

///|
fn fresh(label : String) -> Node {
  HeadingNode({ id: 99, label, fold: None, body: [], children: [] })
}

///|
test "変わっていなければ編集は無い" {
  let md = "# r\n\n## a\n"
  let (before, spans) = survey(md)
  json_inspect(reflect(md, before, spans, before), content=[])
}

///|
test "ラベルだけ変えれば、その地番だけ" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], relabel("A"))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 5, "to": 10, "insert": "## A\n" },
  ])
}

///|
test "中身を足せば、そのノードの地番" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], x => {
    match x {
      HeadingNode(h) => HeadingNode({ ..h, body: [Opaque("x")] })
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 5, "to": 10, "insert": "## a\n\nx\n" },
  ])
}

///|
test "深い所の変化は上を触らない" {
  let md = "# r\n\n## a\n\n### x\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0, 0], relabel("X"))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 11, "to": 17, "insert": "### X\n" },
  ])
}

///|
/// 段 5（子列の差分）までは、子が増えれば親が丸ごと
test "子を増やせば親の地番" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("c")))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 5, "to": 10, "insert": "## a\n\n### c\n" },
  ])
}

///|
test "側が変われば根が丸ごと" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let roots = before.roots.copy()
  roots[0] = { node: roots[0].node, sides: [Right, Left] }
  let after : Doc = { ..before, roots, }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 16, "insert": "# r\n\n## a\n\n***\n\n## b\n" },
  ])
}

///|
test "枝の移動は元と先の 2 箇所" {
  let md = "# r\n\n## a\n\n### x\n\n## b\n"
  let (before, spans) = survey(md)
  let x = match before.roots[0].node {
    HeadingNode(r) => children_of(r.children[0])[0]
    _ => abort("見出し")
  }
  let after = change(change(before, 0, [0], orphan), 0, [1], adopt(x))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 5, "to": 17, "insert": "## a\n" },
    { "from": 18, "to": 23, "insert": "## b\n\n### x\n" },
  ])
}

///|
test "入れ子の項目は容器の桁に揃える" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let d : Node = ListNode({
    id: 99,
    label: "d",
    fold: None,
    body: [],
    children: [],
  })
  let after = change(before, 0, [0], adopt(d))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 6, "to": 10, "insert": "- b\n    - d\n" },
  ])
  inspect(
    apply(md, reflect(md, before, spans, after)),
    content=(
      #|- a
      #|  - b
      #|    - d
      #|- c
      #|
    ),
  )
}

///|
test "散文" {
  let md = "hello\n\n# a\n"
  let (before, spans) = survey(md)
  let after : Doc = { ..before, body: [Opaque("bye")] }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 6, "insert": "bye\n" },
  ])
}

///|
/// 段 5 までは、根の増減は全文
test "根が増えれば全文" {
  let md = "# a\n"
  let (before, spans) = survey(md)
  let after : Doc = {
    ..before,
    roots: before.roots + [{ node: fresh("b"), sides: [] }],
  }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "# a\n\n# b\n" },
  ])
}

///|
/// 改行を含むラベルはライブラリが ATX で書き、2 行目が段落に落ちる。
/// 読み直すと形が違うので全文へ落ちる（全文も同じ形になるが、それが正規形）
test "読み直して形が違えば全文へ落ちる" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], relabel("a\nb"))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 16, "insert": "# r\n\n## a\nb\n\n## b\n" },
  ])
}

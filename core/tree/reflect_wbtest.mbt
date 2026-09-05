// 「前後の木がこう違えば、md はここだけ変わる」を固定する。
//
// 前の木は原文から読む（地番がそこから出るので、ここだけは読みに依る）。
// 後の木はその写しを手で変えたもの — 誰が変えたか（操作）は反映の外。

///|
/// 根 root の、path を辿った先のノードを f で置き換えた Doc。
fn change(doc : Doc, root : Int, path : Array[Int], f : (Node) -> Node) -> Doc {
  let roots = doc.roots.copy()
  let r = roots[root]
  let node = rewrite(r.node, path, 0, f)
  // 側は根の子と並走する。増えたぶんは Right
  let sides = Array::makei(children_of(node).length(), i => {
    if i < r.sides.length() {
      r.sides[i]
    } else {
      Right
    }
  })
  roots[root] = { node, sides }
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
      HeadingNode(h) => HeadingNode({ ..h, body: blocks([Opaque("x")]) })
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 10, "to": 10, "insert": "\nx\n" },
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
test "最初の子は親の尻に差す" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("c")))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 10, "to": 10, "insert": "\n### c\n" },
  ])
}

///|
test "増えた子は最後に残る子の後ろ" {
  let md = "# r\n\n## a\n\n### x\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("y")))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 17, "to": 17, "insert": "\n### y\n" },
  ])
}

///|
test "頭に差せば次に残る子の手前" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => {
    match x {
      HeadingNode(h) =>
        HeadingNode({ ..h, children: [fresh("c")] + h.children })
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 5, "to": 5, "insert": "## c\n\n" },
  ])
}

///|
test "消えた子は範囲ごと消える" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => {
    match x {
      HeadingNode(h) => HeadingNode({ ..h, children: [h.children[0]] })
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 10, "to": 16, "insert": "" },
  ])
}

///|
test "並べ替えは容器ごと" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => {
    match x {
      HeadingNode(h) => HeadingNode({ ..h, children: h.children.rev() })
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 16, "insert": "# r\n\n## b\n\n## a\n" },
  ])
}

///|
test "子を総取り替えすれば、消して同じ桁に差す" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let z : Node = ListNode({
    id: 99,
    label: "z",
    fold: None,
    body: [],
    children: [],
  })
  let after = change(change(before, 0, [], orphan), 0, [], adopt(z))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 4, "to": 4, "insert": "  - z\n" },
    { "from": 4, "to": 10, "insert": "" },
  ])
  inspect(
    apply(md, reflect(md, before, spans, after)),
    content=(
      #|- a
      #|  - z
      #|- c
      #|
    ),
  )
}

///|
test "入れ子の項目の手前に差せば、後ろに字下げを戻す" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let z : Node = ListNode({
    id: 99,
    label: "z",
    fold: None,
    body: [],
    children: [],
  })
  let after = change(before, 0, [], x => {
    match x {
      ListNode(l) =>
        match z {
          ListNode(c) => ListNode({ ..l, children: [c] + l.children })
          _ => abort("項目")
        }
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 6, "to": 6, "insert": "- z\n  " },
  ])
  inspect(
    apply(md, reflect(md, before, spans, after)),
    content=(
      #|- a
      #|  - z
      #|  - b
      #|- c
      #|
    ),
  )
}

///|
test "入れ子の項目が消えれば字下げも道連れ" {
  let md = "- a\n  - b\n  - d\n- c\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => {
    match x {
      ListNode(l) => ListNode({ ..l, children: [l.children[1]] })
      other => other
    }
  })
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 4, "to": 10, "insert": "" },
  ])
}

///|
test "側の在る根に子を足せば根が丸ごと" {
  let md = "# r\n\n## a\n\n---\n\n## b\n"
  let (before, spans) = survey(md)
  let roots = before.roots.copy()
  let r = roots[0]
  roots[0] = { node: adopt(fresh("c"))(r.node), sides: r.sides + [Right] }
  let after : Doc = { ..before, roots, }
  json_inspect(reflect(md, before, spans, after), content=[
    {
      "from": 0,
      "to": 21,
      "insert": "# r\n\n## a\n\n***\n\n## b\n\n***\n\n## c\n",
    },
  ])
}

///|
test "畳みの中の子の出し入れは容器ごと" {
  let md = "# r\n\n<details>\n\n## a\n\n</details>\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("c")))
  json_inspect(reflect(md, before, spans, after), content=[
    {
      "from": 5,
      "to": 33,
      "insert": "<details>\n\n## a\n\n### c\n\n</details>\n",
    },
  ])
}

///|
test "改行の無い末尾に差すときは改行してから" {
  let md = "# a"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], adopt(fresh("b")))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 3, "to": 3, "insert": "\n\n## b\n" },
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
    { "from": 10, "to": 17, "insert": "" },
    { "from": 23, "to": 23, "insert": "\n### x\n" },
  ])
}

///|
test "入れ子の項目の子は、容器の中身の桁に差す" {
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
    { "from": 10, "to": 10, "insert": "    - d\n" },
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
  let after : Doc = { ..before, body: blocks([Opaque("bye")]) }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 0, "insert": "bye\n\n" },
    { "from": 0, "to": 7, "insert": "" },
  ])
}

///|
test "根も同じ — 増えれば隣に差す" {
  let md = "# a\n"
  let (before, spans) = survey(md)
  let after : Doc = {
    ..before,
    roots: before.roots + [{ node: fresh("b"), sides: [] }],
  }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 4, "to": 4, "insert": "\n# b\n" },
  ])
}

///|
test "根が消えれば範囲ごと消える" {
  let md = "# a\n\n# b\n"
  let (before, spans) = survey(md)
  let after : Doc = { ..before, roots: [before.roots[0]] }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 4, "to": 9, "insert": "" },
  ])
}

///|
test "根が無い文書に最初の根を差す" {
  let md = "hello\n"
  let (before, spans) = survey(md)
  let after : Doc = { ..before, roots: [{ node: fresh("b"), sides: [] }] }
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 6, "to": 6, "insert": "\n# b\n" },
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

///|
test "ラベルだけなら自分の行だけ。子は触らない" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], relabel("R"))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "# R\n" },
  ])
}

///|
test "項目のラベルだけなら、子の字下げは残る" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], relabel("A"))
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "- A\n" },
  ])
  inspect(
    apply(md, reflect(md, before, spans, after)),
    content=(
      #|- A
      #|  - b
      #|- c
      #|
    ),
  )
}

///|
test "自分も子も変われば、自分の行と子列の差分" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(
    change(before, 0, [], relabel("R")),
    0,
    [],
    adopt(fresh("c")),
  )
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "# R\n" },
    { "from": 16, "to": 16, "insert": "\n## c\n" },
  ])
}

///|
/// 中身の列も子の列と同じ差分。行（ラベル）には触らない — そこに目印が在る。
fn rebody(body : Array[Block]) -> (Node) -> Node {
  x => {
    match x {
      HeadingNode(h) => HeadingNode({ ..h, body, })
      ListNode(l) => ListNode({ ..l, body, })
      other => other
    }
  }
}

///|
test "中身を 1 枚足せば、行は触らず行の尻へ隙間を挟んで差す" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], rebody(blocks([Opaque("x")])))
  let edits = reflect(md, before, spans, after)
  json_inspect(edits, content=[{ "from": 10, "to": 10, "insert": "\nx\n" }])
  inspect(apply(md, edits), content="# r\n\n## a\n\nx\n\n## b\n")
}

///|
test "中身を 1 枚消せば、その範囲と隙間だけ" {
  let md = "# r\n\n## a\n\nhello\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], rebody([]))
  let edits = reflect(md, before, spans, after)
  json_inspect(edits, content=[{ "from": 10, "to": 17, "insert": "" }])
  inspect(apply(md, edits), content="# r\n\n## a\n\n## b\n")
}

///|
test "中身を置き換えれば、その範囲だけ" {
  let md = "# r\n\n## a\n\nhello\n\n## b\n"
  let (before, spans) = survey(md)
  let a = children_of(before.roots[0].node)[0]
  let after = change(
    before,
    0,
    [0],
    rebody([{ id: body_of(a)[0].id, content: Opaque("bye") }]),
  )
  json_inspect(reflect(md, before, spans, after), content=[
    { "from": 11, "to": 17, "insert": "bye\n" },
  ])
}

///|
test "消える子は後ろの隙間を道連れ。最後なら前の隙間" {
  let md = "# r\n\n## a\n\n## b\n\n## c\n"
  let (before, spans) = survey(md)
  let drop = (i : Int) => {
    change(before, 0, [], x => {
      match x {
        HeadingNode(h) => {
          let kids = h.children.copy()
          let _ = kids.remove(i)
          HeadingNode({ ..h, children: kids })
        }
        other => other
      }
    })
  }
  let mid = reflect(md, before, spans, drop(1))
  json_inspect(mid, content=[{ "from": 11, "to": 17, "insert": "" }])
  inspect(apply(md, mid), content="# r\n\n## a\n\n## c\n")
  let last = reflect(md, before, spans, drop(2))
  json_inspect(last, content=[{ "from": 16, "to": 22, "insert": "" }])
  inspect(apply(md, last), content="# r\n\n## a\n\n## b\n")
}

///|
test "増える子は隙間を挟む — 兄弟の後ろにも、空の親にも" {
  let md = "# r\n\n## a\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], adopt(fresh("c")))
  let edits = reflect(md, before, spans, after)
  json_inspect(edits, content=[{ "from": 10, "to": 10, "insert": "\n## c\n" }])
  inspect(apply(md, edits), content="# r\n\n## a\n\n## c\n")
  let solo = "# r\n"
  let (b2, s2) = survey(solo)
  let e2 = reflect(solo, b2, s2, change(b2, 0, [], adopt(fresh("c"))))
  json_inspect(e2, content=[{ "from": 4, "to": 4, "insert": "\n## c\n" }])
}

///|
test "詰まった項目の列は詰まったまま" {
  let md = "- a\n- b\n"
  let (before, spans) = survey(md)
  let kid = ListNode({ id: 99, label: "c", fold: None, body: [], children: [] })
  let grown = reflect(md, before, spans, change(before, 0, [], adopt(kid)))
  json_inspect(grown, content=[{ "from": 4, "to": 4, "insert": "  - c\n" }])
  inspect(apply(md, grown), content="- a\n  - c\n- b\n")
  let after : Doc = { ..before, roots: [before.roots[0]] }
  let cut = reflect(md, before, spans, after)
  json_inspect(cut, content=[{ "from": 4, "to": 8, "insert": "" }])
}

///|
test "枝の移動は隙間ごと — 元は消え、先には隙間を挟んで差す" {
  let md = "# r\n\n## a\n\nhello\n\n## b\n\n## c\n"
  let (before, spans) = survey(md)
  let r = before.roots[0].node
  let kids = children_of(r)
  let after = change(before, 0, [], x => {
    with_children(x, [with_children(kids[0], [kids[1], kids[2]])])
  })
  let edits = reflect(md, before, spans, after)
  json_inspect(edits, content=[
    { "from": 17, "to": 17, "insert": "\n### b\n\n### c\n" },
    { "from": 17, "to": 29, "insert": "" },
  ])
  inspect(apply(md, edits), content="# r\n\n## a\n\nhello\n\n### b\n\n### c\n")
}

///|
test "文書の頭の散文 — 隙間は後ろに付く" {
  let md = "hello\n\n# a\n"
  let (before, spans) = survey(md)
  let swapped = reflect(md, before, spans, {
    ..before,
    body: blocks([Opaque("bye")]),
  })
  inspect(apply(md, swapped), content="bye\n\n# a\n")
  let gone = reflect(md, before, spans, { ..before, body: [] })
  inspect(apply(md, gone), content="# a\n")
  let bare = "# a\n"
  let (b2, s2) = survey(bare)
  let born = reflect(bare, b2, s2, { ..b2, body: blocks([Opaque("bye")]) })
  inspect(apply(bare, born), content="bye\n\n# a\n")
  let (b3, s3) = survey("")
  let first = reflect("", b3, s3, { ..b3, body: blocks([Opaque("bye")]) })
  inspect(apply("", first), content="bye\n")
}

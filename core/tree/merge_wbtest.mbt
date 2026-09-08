// 「前後の木がこう違えば、md はここだけ変わる」を固定する。
//
// 前の木は原文から読む（地番がそこから出るので、ここだけは読みに依る）。
// 後の木はその写しを手で変えたもの — 誰が変えたか（操作）は合流の外。

///|
/// 合流の編集列。検証の答え（`same`）は focus の可否に使うもので、edit の試験が見る。
fn changes(
  md : String,
  before : Doc,
  spans : Map[Int, Spot],
  after : Doc,
) -> Array[Edit] {
  merge(md, before, spans, after).edits
}

///|
/// 根 root の、path を辿った先のノードを f で置き換えた Doc。
fn change(doc : Doc, root : Int, path : Array[Int], f : (Node) -> Node) -> Doc {
  let roots = doc.roots.copy()
  let r = roots[root]
  let node = rewrite(r.node, path, 0, f)
  // 側と境界の綴りは根の子と並走する。増えたぶんは Right で、綴りは無い
  let n = node.children.length()
  let sides = Array::makei(n, i => {
    if i < r.sides.length() {
      r.sides[i]
    } else {
      Right
    }
  })
  let rules = Array::makei(n, i => {
    if i < r.rules.length() {
      r.rules[i]
    } else {
      ""
    }
  })
  roots[root] = { node, sides, rules, }
  { ..doc, roots, }
}

///|
fn rewrite(x : Node, path : Array[Int], k : Int, f : (Node) -> Node) -> Node {
  if k == path.length() {
    return f(x)
  }
  let i = path[k]
  let kids = x.children.copy()
  kids[i] = rewrite(kids[i], path, k + 1, f)
  { ..x, children: kids, }
}

///|
fn relabel(label : String) -> (Node) -> Node {
  // Implicit は行が無いので名前を持たない（綴るのは操作の仕事）
  x => if x.mark is Some(_) { { ..x, label, } } else { x }
}

///|
fn adopt(kid : Node) -> (Node) -> Node {
  x => { ..x, children: x.children + [kid], }
}

///|
fn orphan(x : Node) -> Node {
  { ..x, children: [], }
}

///|
fn fresh(label : String) -> Node {
  { id: 99, label, fold: None, body: [], children: [], mark: Some(atx), }
}

///|
test "変わっていなければ編集は無い" {
  let md = "# r\n\n## a\n"
  let (before, spans) = survey(md)
  json_inspect(changes(md, before, spans, before), content=[])
}

///|
test "ラベルだけ変えれば、その地番だけ" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], relabel("A"))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 5, "to": 10, "insert": "## A\n" },
  ])
}

///|
test "中身を足せば、そのノードの地番" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], x => { ..x, body: [raw("x")], })
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 10, "to": 10, "insert": "\nx\n" },
  ])
}

///|
test "深い所の変化は上を触らない" {
  let md = "# r\n\n## a\n\n### x\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0, 0], relabel("X"))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 11, "to": 17, "insert": "### X\n" },
  ])
}

///|
test "最初の子は親の尻に差す" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("c")))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 10, "to": 10, "insert": "\n### c\n" },
  ])
}

///|
test "増えた子は最後に残る子の後ろ" {
  let md = "# r\n\n## a\n\n### x\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("y")))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 17, "to": 17, "insert": "\n### y\n" },
  ])
}

///|
test "頭に差せば次に残る子の手前" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => {
    ..x,
    children: [fresh("c")] + x.children,
  })
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 5, "to": 5, "insert": "## c\n\n" },
  ])
}

///|
test "消えた子は範囲ごと消える" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => { ..x, children: [x.children[0]], })
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 10, "to": 16, "insert": "" },
  ])
}

///|
test "並べ替えは容器ごと" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], x => { ..x, children: x.children.rev(), })
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 16, "insert": "# r\n\n## b\n\n## a\n" },
  ])
}

///|
test "子を総取り替えすれば、消して同じ桁に差す" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let z : Node = {
    id: 99,
    label: "z",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  let after = change(change(before, 0, [], orphan), 0, [], adopt(z))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 4, "to": 10, "insert": "  - z\n" },
  ])
  inspect(
    apply(md, changes(md, before, spans, after)),
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
  let z : Node = {
    id: 99,
    label: "z",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  let after = change(before, 0, [], x => {
    match x {
      l => { ..l, children: [z] + l.children, }
    }
  })
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 4, "to": 4, "insert": "  - z\n" },
  ])
  inspect(
    apply(md, changes(md, before, spans, after)),
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
  let after = change(before, 0, [], x => { ..x, children: [x.children[1]], })
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 4, "to": 10, "insert": "" },
  ])
}

///|
test "側の在る根に子を足せば根が丸ごと" {
  let md = "# r\n\n## a\n\n---\n\n## b\n"
  let (before, spans) = survey(md)
  let roots = before.roots.copy()
  let r = roots[0]
  roots[0] = {
    node: adopt(fresh("c"))(r.node),
    sides: r.sides + [Right],
    rules: r.rules + [""],
  }
  let after : Doc = { ..before, roots, }
  json_inspect(changes(md, before, spans, after), content=[
    {
      "from": 0,
      "to": 21,
      "insert": "# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n",
    },
  ])
}

///|
test "畳みの中の子の出し入れは容器ごと" {
  let md = "# r\n\n<details>\n\n## a\n\n</details>\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], adopt(fresh("c")))
  json_inspect(changes(md, before, spans, after), content=[
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
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 3, "to": 3, "insert": "\n\n## b\n" },
  ])
}

///|
test "側が変われば根が丸ごと" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let roots = before.roots.copy()
  roots[0] = { node: roots[0].node, sides: [Right, Left], rules: ["", ""], }
  let after : Doc = { ..before, roots, }
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 16, "insert": "# r\n\n## a\n\n---\n\n## b\n" },
  ])
}

///|
test "枝の移動は元と先の 2 箇所" {
  let md = "# r\n\n## a\n\n### x\n\n## b\n"
  let (before, spans) = survey(md)
  let x = before.roots[0].node.children[0].children[0]
  let after = change(change(before, 0, [0], orphan), 0, [1], adopt(x))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 10, "to": 17, "insert": "" },
    { "from": 23, "to": 23, "insert": "\n### x\n" },
  ])
}

///|
test "入れ子の項目の子は、容器の中身の桁に差す" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let d : Node = {
    id: 99,
    label: "d",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  let after = change(before, 0, [0], adopt(d))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 10, "to": 10, "insert": "    - d\n" },
  ])
  inspect(
    apply(md, changes(md, before, spans, after)),
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
  let after : Doc = { ..before, body: [raw("bye")], }
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 6, "insert": "bye\n" },
  ])
}

///|
test "根も同じ — 増えれば隣に差す" {
  let md = "# a\n"
  let (before, spans) = survey(md)
  let after : Doc = {
    ..before,
    roots: before.roots + [{ node: fresh("b"), sides: [], rules: [], }],
  }
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 4, "to": 4, "insert": "\n# b\n" },
  ])
}

///|
test "根が消えれば範囲ごと消える" {
  let md = "# a\n\n# b\n"
  let (before, spans) = survey(md)
  let after : Doc = { ..before, roots: [before.roots[0]], }
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 4, "to": 9, "insert": "" },
  ])
}

///|
test "根が無い文書に最初の根を差す" {
  let md = "hello\n"
  let (before, spans) = survey(md)
  let after : Doc = {
    ..before,
    roots: [{ node: fresh("b"), sides: [], rules: [], }],
  }
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 6, "to": 6, "insert": "\n# b\n" },
  ])
}

///|
/// 深さ 3 に setext は無いので、改行を含むラベルは ATX で書くしかなく、
/// 2 行目が段落に落ちる。読み直すと形が違うので全文へ落ちる
/// （全文も同じ形になるが、それが正規形）
test "読み直して形が違えば全文へ落ちる" {
  let md = "# r\n\n## a\n\n### c\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0, 0], relabel("a\nb"))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 17, "insert": "# r\n\n## a\n\n### a\nb\n" },
  ])
}

///|
test "ラベルだけなら自分の行だけ。子は触らない" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], relabel("R"))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "# R\n" },
  ])
}

///|
test "項目のラベルだけなら、子の字下げは残る" {
  let md = "- a\n  - b\n- c\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], relabel("A"))
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "- A\n" },
  ])
  inspect(
    apply(md, changes(md, before, spans, after)),
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
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 0, "to": 4, "insert": "# R\n" },
    { "from": 16, "to": 16, "insert": "\n## c\n" },
  ])
}

///|
/// 中身の列も子の列と同じ差分。行（ラベル）には触らない — そこに目印が在る。
fn rebody(body : Array[Block]) -> (Node) -> Node {
  x => { ..x, body, }
}

///|
test "中身を 1 枚足せば、行は触らず行の尻へ隙間を挟んで差す" {
  let md = "# r\n\n## a\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], rebody([raw("x")]))
  let edits = changes(md, before, spans, after)
  json_inspect(edits, content=[{ "from": 10, "to": 10, "insert": "\nx\n" }])
  inspect(apply(md, edits), content="# r\n\n## a\n\nx\n\n## b\n")
}

///|
test "中身を 1 枚消せば、その範囲と隙間だけ" {
  let md = "# r\n\n## a\n\nhello\n\n## b\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [0], rebody([]))
  let edits = changes(md, before, spans, after)
  json_inspect(edits, content=[{ "from": 10, "to": 17, "insert": "" }])
  inspect(apply(md, edits), content="# r\n\n## a\n\n## b\n")
}

///|
test "中身を置き換えれば、その範囲だけ" {
  let md = "# r\n\n## a\n\nhello\n\n## b\n"
  let (before, spans) = survey(md)
  let a = before.roots[0].node.children[0]
  let after = change(
    before,
    0,
    [0],
    rebody([{ id: a.body[0].id, content: None, source: Some("bye"), }]),
  )
  json_inspect(changes(md, before, spans, after), content=[
    { "from": 11, "to": 17, "insert": "bye\n" },
  ])
}

///|
test "消える子は手前の隙間を道連れ" {
  let md = "# r\n\n## a\n\n## b\n\n## c\n"
  let (before, spans) = survey(md)
  let drop = (i : Int) => {
    change(before, 0, [], x => {
      match x {
        h => {
          let kids = h.children.copy()
          let _ = kids.remove(i)
          { ..h, children: kids, }
        }
      }
    })
  }
  let mid = changes(md, before, spans, drop(1))
  json_inspect(mid, content=[{ "from": 10, "to": 16, "insert": "" }])
  inspect(apply(md, mid), content="# r\n\n## a\n\n## c\n")
  let last = changes(md, before, spans, drop(2))
  json_inspect(last, content=[{ "from": 16, "to": 22, "insert": "" }])
  inspect(apply(md, last), content="# r\n\n## a\n\n## b\n")
}

///|
test "増える子は正規形の隙間を連れてくる — 兄弟の後ろにも、空の親にも" {
  let md = "# r\n\n## a\n"
  let (before, spans) = survey(md)
  let after = change(before, 0, [], adopt(fresh("c")))
  let edits = changes(md, before, spans, after)
  json_inspect(edits, content=[{ "from": 10, "to": 10, "insert": "\n## c\n" }])
  inspect(apply(md, edits), content="# r\n\n## a\n\n## c\n")
  let solo = "# r\n"
  let (b2, s2) = survey(solo)
  let e2 = changes(solo, b2, s2, change(b2, 0, [], adopt(fresh("c"))))
  json_inspect(e2, content=[{ "from": 4, "to": 4, "insert": "\n## c\n" }])
}

///|
test "詰まった項目の列は詰まったまま" {
  let md = "- a\n- b\n"
  let (before, spans) = survey(md)
  let kid = {
    id: 99,
    label: "c",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  let grown = changes(md, before, spans, change(before, 0, [], adopt(kid)))
  json_inspect(grown, content=[{ "from": 4, "to": 4, "insert": "  - c\n" }])
  inspect(apply(md, grown), content="- a\n  - c\n- b\n")
  let after : Doc = { ..before, roots: [before.roots[0]], }
  let cut = changes(md, before, spans, after)
  json_inspect(cut, content=[{ "from": 4, "to": 8, "insert": "" }])
}

///|
test "枝の移動は隙間ごと — 元は消え、先には隙間を挟んで差す" {
  let md = "# r\n\n## a\n\nhello\n\n## b\n\n## c\n"
  let (before, spans) = survey(md)
  let r = before.roots[0].node
  let kids = r.children
  let after = change(before, 0, [], x => {
    ..x,
    children: [{ ..kids[0], children: [kids[1], kids[2]], }],
  })
  let edits = changes(md, before, spans, after)
  json_inspect(edits, content=[
    { "from": 17, "to": 29, "insert": "\n### b\n\n### c\n" },
  ])
  inspect(apply(md, edits), content="# r\n\n## a\n\nhello\n\n### b\n\n### c\n")
}

///|
test "文書の頭の散文 — 隙間は後ろに付く" {
  let md = "hello\n\n# a\n"
  let (before, spans) = survey(md)
  let swapped = changes(md, before, spans, { ..before, body: [raw("bye")], })
  inspect(apply(md, swapped), content="bye\n\n# a\n")
  let gone = changes(md, before, spans, { ..before, body: [], })
  inspect(apply(md, gone), content="# a\n")
  let bare = "# a\n"
  let (b2, s2) = survey(bare)
  let born = changes(bare, b2, s2, { ..b2, body: [raw("bye")], })
  inspect(apply(bare, born), content="bye\n\n# a\n")
  let (b3, s3) = survey("")
  let first = changes("", b3, s3, { ..b3, body: [raw("bye")], })
  inspect(apply("", first), content="bye\n")
}

///|
test "文書の頭の中身を並べ替えても、頭に空行は生まれない" {
  let md = "aaa\n\nbbb\n\n# h\n"
  let (before, spans) = survey(md)
  let bs = before.body
  let edits = changes(md, before, spans, { ..before, body: [bs[1], bs[0]], })
  inspect(apply(md, edits), content="bbb\n\naaa\n\n# h\n")
  let solo = "p1\n\np2\n"
  let (b2, s2) = survey(solo)
  let e2 = changes(solo, b2, s2, { ..b2, body: [b2.body[1], b2.body[0]], })
  inspect(apply(solo, e2), content="p2\n\np1\n")
}

///|
/// 読みは CRLF も受けるが、**書き足す改行は LF だけ**（spec「文字コードと改行」）。
/// 触っていない行のバイト列はそのまま残るので、原文の CRLF は動かない。
test "改行の無い末尾に差すとき、書き足す改行は LF" {
  let md = "# r\r\n\r\n## a"
  let (before, spans) = survey(md)
  let edits = changes(
    md,
    before,
    spans,
    change(before, 0, [], adopt(fresh("c"))),
  )
  inspect(apply(md, edits), content="# r\r\n\r\n## a\n\n## c\n")
}

///|
test "Implicit の子を入れ替えても、その手前の隙間は 1 つのまま" {
  let md = "# a\n\n#### deep\n\n## b\n"
  let (before, spans) = survey(md)
  // 深さ 3 の Implicit の中身（deep）を、新しい見出しに差し替える
  let after = change(before, 0, [0], x => { ..x, children: [fresh("w")], })
  let edits = changes(md, before, spans, after)
  inspect(apply(md, edits), content="# a\n\n### w\n\n## b\n")
}

///|
test "改行の無い末尾のノードを外へ出しても、空行は 1 つ" {
  let md = "# r\n\n## a\n\nhello"
  let (before, spans) = survey(md)
  let r = before.roots[0].node
  let a = r.children[0]
  let after : Doc = {
    ..before,
    roots: [
      { node: { ..r, children: [], }, sides: [], rules: [], },
      { node: a, sides: [], rules: [], },
    ],
  }
  let edits = changes(md, before, spans, after)
  inspect(apply(md, edits), content="# r\n\n# a\n\nhello\n")
}

///|
test "Implicit の手前の隙間 — CRLF でも、空白だけの空行でも 1 つのまま" {
  let crlf = "# a\r\n\r\n#### deep\r\n\r\n## b\r\n"
  let (b1, s1) = survey(crlf)
  let e1 = changes(
    crlf,
    b1,
    s1,
    change(b1, 0, [0], x => { ..x, children: [fresh("w")], }),
  )
  // 差した断片の改行は LF。触っていない行の CRLF はそのまま
  inspect(apply(crlf, e1), content="# a\r\n\r\n### w\n\r\n## b\r\n")
  let spaced = "# a\n  \n#### deep\n\n## b\n"
  let (b2, s2) = survey(spaced)
  let e2 = changes(
    spaced,
    b2,
    s2,
    change(b2, 0, [0], x => { ..x, children: [fresh("w")], }),
  )
  // 列の頭の境目は原文のまま（空白だけの行も 1 つの空行として残る）
  inspect(apply(spaced, e2), content="# a\n  \n### w\n\n## b\n")
}

///|
test "列の頭の境目は列のもの — 頭を消しても差しても、境目の字は残る" {
  let tight = "# r\n- a\n- b\n"
  let (b1, s1) = survey(tight)
  let kids1 = b1.roots[0].node.children
  let cut = changes(
    tight,
    b1,
    s1,
    change(b1, 0, [], x => { ..x, children: [kids1[1]], }),
  )
  inspect(apply(tight, cut), content="# r\n- b\n")
  let item = {
    id: 99,
    label: "z",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  let born = changes(
    tight,
    b1,
    s1,
    change(b1, 0, [], x => { ..x, children: [item] + kids1, }),
  )
  inspect(apply(tight, born), content="# r\n- z\n- a\n- b\n")
  let loose = "# r\n\n- a\n- b\n- c\n"
  let (b2, s2) = survey(loose)
  let kids2 = b2.roots[0].node.children
  let e2 = changes(
    loose,
    b2,
    s2,
    change(b2, 0, [], x => { ..x, children: kids2[1:].to_owned(), }),
  )
  inspect(apply(loose, e2), content="# r\n\n- b\n- c\n")
}

///|
test "frontmatter の直後の空行は、頭の要素を触っても消えない" {
  let md = "---\nk: v\n---\n\n# a\n\n# b\n"
  let (before, spans) = survey(md)
  let less : Doc = { ..before, roots: [before.roots[1]], }
  inspect(
    apply(md, changes(md, before, spans, less)),
    content="---\nk: v\n---\n\n# b\n",
  )
  let prose : Doc = { ..before, body: [raw("x")], }
  inspect(
    apply(md, changes(md, before, spans, prose)),
    content="---\nk: v\n---\n\nx\n\n# a\n\n# b\n",
  )
  let said = "---\nk: v\n---\n\nhello\n\n# a\n"
  let (b2, s2) = survey(said)
  inspect(
    apply(said, changes(said, b2, s2, { ..b2, body: [], })),
    content="---\nk: v\n---\n\n# a\n",
  )
}

///|
test "setext の見出しに子を足しても、下線の中に差さない" {
  let md = "a\n===\n"
  let (before, spans) = survey(md)
  let edits = changes(
    md,
    before,
    spans,
    change(before, 0, [], adopt(fresh("c"))),
  )
  json_inspect(edits, content=[{ "from": 6, "to": 6, "insert": "\n## c\n" }])
}

///|
test "空行の後に詰めて書いた列の頭を包んでも、その空行は残る" {
  let md = "# r\n\n- a\n- b\n"
  let (before, spans) = survey(md)
  let kids = before.roots[0].node.children
  let w = {
    id: 99,
    label: "w",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  let wrapped = {
    ..{
      id: 99,
      label: "w",
      fold: None,
      body: [],
      children: [],
      mark: Some(bullet),
    },
    children: [kids[0]],
  }
  ignore(w)
  let after = change(before, 0, [], x => { ..x, children: [wrapped, kids[1]], })
  inspect(
    apply(md, changes(md, before, spans, after)),
    content="# r\n\n- w\n  - a\n- b\n",
  )
  let loose = "# r\n\n- a\n\n- b\n"
  let (b2, s2) = survey(loose)
  let k2 = b2.roots[0].node.children
  let z = {
    id: 98,
    label: "z",
    fold: None,
    body: [],
    children: [],
    mark: Some(bullet),
  }
  inspect(
    apply(
      loose,
      changes(
        loose,
        b2,
        s2,
        change(b2, 0, [], x => { ..x, children: [z, k2[1]], }),
      ),
    ),
    content="# r\n\n- z\n\n- b\n",
  )
}

///|
test "散文を消しながら根の頭に差しても、文書の頭に空行は生まれない" {
  let md = "hello\n\n# a\n"
  let (before, spans) = survey(md)
  let after : Doc = {
    ..before,
    body: [],
    roots: [{ node: fresh("z"), sides: [], rules: [], }] + before.roots,
  }
  inspect(apply(md, changes(md, before, spans, after)), content="# z\n\n# a\n")
}

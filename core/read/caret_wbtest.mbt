// md のカーソルと地図の位置が、どのノード（またはカード）に掛かっているか。
// 区間の重なりだけの層。木と地番は手で組む（読みは tree の wbtest が固定済み）。

///|
/// 綴りは既定で `#`。`mark=None` で Implicit（綴りの無いノード）
fn node(
  id : Int,
  label : String,
  children? : Array[@tree.Node] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
  mark? : @tree.Mark? = Some(@tree.atx),
) -> @tree.Node {
  { id, label, fold, body, children, mark, }
}

///|
fn tree(roots : Array[@tree.Node]) -> @tree.Doc {
  {
    frontmatter: None,
    body: [],
    roots: roots.map(n => {
      ({ node: n, sides: n.children.map(_ => Right), rules: [], } : @tree.Root)
    }),
  }
}

///|
/// (id, from, label, to) の並びから地番の表
fn spots(rows : Array[(Int, Int, Int?, Int)]) -> Map[Int, @tree.Spot] {
  let out : Map[Int, @tree.Spot] = Map([])
  for r in rows {
    let (id, from, label, to) = r
    out[id] = { from, label, to, }
  }
  out
}

///|
fn reading(doc : @tree.Doc, spots : Map[Int, @tree.Spot]) -> Survey {
  { md: "", doc, spots, }
}

///|
/// "# r\n\n## a\n\nhello\n\n## b\n"
fn sample() -> Survey {
  reading(
    tree([node(2, "r", children=[node(3, "a"), node(5, "b")])]),
    spots([
      (1, 0, None, 0),
      (2, 0, Some(2), 23),
      (3, 5, Some(8), 17),
      (5, 18, Some(21), 23),
    ]),
  )
}

///|
fn point(p : Int) -> Array[Range] {
  [{ from: p, to: p, }]
}

///|
fn caret(p : Int, to? : Int = p) -> Caret {
  { ranges: [{ from: p, to, }], head: to, }
}

///|
fn nodes(ids : Array[Int], anchor : Int?) -> Choice {
  Nodes(sel={ ids, anchor, })
}

///|
test "最も深いノードだけ。自身の文は地番の頭から最初の子の頭まで" {
  let d = sample()
  assert_eq(ids_at(owns(d), point(1)), [2])
  assert_eq(ids_at(owns(d), point(7)), [3])
  assert_eq(ids_at(owns(d), point(12)), [3]) // hello の中
  assert_eq(ids_at(owns(d), point(20)), [5])
}

///|
test "閉じ際は中と見なす。点が継ぎ目ちょうどなら始まる側 1 つ" {
  let d = sample()
  assert_eq(ids_at(owns(d), point(5)), [3]) // r の文が閉じ、a が始まる → a
  assert_eq(ids_at(owns(d), point(17)), [3]) // a の文の閉じ際。b は 18 から
  assert_eq(ids_at(owns(d), point(23)), [5]) // 文書の末尾で追記中も出る
}

///|
test "範囲と複数カーソルは掛かるもの全部。無ければ空" {
  let d = sample()
  assert_eq(ids_at(owns(d), [{ from: 1, to: 20, }]), [2, 3, 5])
  assert_eq(ids_at(owns(d), [{ from: 1, to: 1, }, { from: 20, to: 20, }]), [
    2, 5,
  ])
  assert_eq(ids_at(owns(d), [{ from: 5, to: 6, }]), [2, 3]) // 範囲なら継ぎ目の両側
  assert_eq(ids_at(owns(d), []), [])
}

///|
test "Implicit は行が無く自身の文が空なので掛からない" {
  // "# r\n\n### x\n": r=2, Implicit=3, x=4
  let gap = reading(
    tree([
      node(2, "r", children=[node(3, "", mark=None, children=[node(4, "x")])]),
    ]),
    spots([
      (1, 0, None, 0),
      (2, 0, Some(2), 11),
      (3, 5, None, 11),
      (4, 5, Some(9), 11),
    ]),
  )
  assert_eq(ids_at(owns(gap), point(7)), [4])
  assert_eq(ids_at(owns(gap), point(5)), [4])
}

///|
/// "# r\n\n## a\n\n### x\n\n## b\n" で a が畳まれている: r=2, a=3, x=4, b=5
fn hidden() -> Survey {
  reading(
    tree([
      node(2, "r", children=[
        node(
          3,
          "a",
          children=[node(4, "x")],
          fold=Some({ open: false, summary: Some("a"), }),
        ),
        node(5, "b"),
      ]),
    ]),
    spots([
      (1, 0, None, 0),
      (2, 0, Some(2), 23),
      (3, 5, Some(8), 17),
      (4, 11, Some(15), 17),
      (5, 18, Some(21), 23),
    ]),
  )
}

///|
test "buried — 畳まれたノードの子孫。畳まれたノード自身は入らない" {
  assert_eq(buried(hidden().doc).iter().collect(), [4])
  assert_eq(buried(sample().doc).length(), 0)
}

///|
test "md が持つ間は選択はカーソルから。anchor は主カーソルの頭のノード" {
  let d = sample()
  assert_eq(chosen(d, Md, caret(12), None), nodes([3], Some(3)))
  assert_eq(chosen(d, Md, caret(1, to=20), None), nodes([2, 3, 5], Some(5)))
  // anchors が在っても見ない
  assert_eq(
    chosen(d, Md, caret(12), Some(NodeAt(at=[21], anchor=Some(21)))),
    nodes([3], Some(3)),
  )
  // 埋もれたノードは選択に居ない
  assert_eq(chosen(hidden(), Md, caret(13), None), nodes([], None))
}

///|
test "地図が持つ間は選択は位置から。点はラベルの頭、カードは中身の頭" {
  let d = sample()
  assert_eq(
    chosen(d, Map, caret(1), Some(NodeAt(at=[8, 21], anchor=Some(21)))),
    nodes([3, 5], Some(5)),
  )
  // 潰れて同じノードに落ちた点は 1 つに
  assert_eq(
    chosen(d, Map, caret(1), Some(NodeAt(at=[8, 9], anchor=Some(9)))),
    nodes([3], Some(3)),
  )
  // 無ければ何も選んでいない
  assert_eq(chosen(d, Map, caret(1), None), nothing)
  // カード: a(3) の中身 code(4) が [10, 18) に書かれている（地番は手で組む）
  let card : @tree.Block = {
    id: 4,
    source: None,
    content: Some(Code(info="", text="x")),
  }
  let card_at = spots([
    (1, 0, None, 0),
    (2, 0, Some(2), 18),
    (3, 5, Some(8), 18),
    (4, 10, None, 18),
  ])
  let carded = reading(
    tree([node(2, "r", children=[node(3, "a", body=[card])])]),
    card_at,
  )
  assert_eq(chosen(carded, Map, caret(1), Some(CardAt(at=10))), Card(id=4))
  assert_eq(chosen(carded, Map, caret(1), Some(CardAt(at=3))), nothing)
  // 埋もれたノードに掛かる位置は落とす
  assert_eq(
    chosen(hidden(), Map, caret(1), Some(NodeAt(at=[15, 21], anchor=Some(15)))),
    nodes([5], Some(5)),
  )
  // 畳まれたノードのカードは選べない。開けば選べる
  let shut = reading(
    tree([
      node(2, "r", children=[
        node(
          3,
          "a",
          body=[card],
          fold=Some({ open: false, summary: Some("a"), }),
        ),
      ]),
    ]),
    card_at,
  )
  assert_eq(chosen(shut, Map, caret(1), Some(CardAt(at=10))), nothing)
}

///|
test "anchors_of / anchors_for / ranges — id と位置の往復。カードは中身の頭" {
  // "# r\n\n## a\n\n```\nx\n```\n": r=2 [0,2,21] a=3 [5,8,21] code=4 [11,-,21]
  let s = survey("# r\n\n## a\n\n```\nx\n```\n")
  assert_eq(anchors_of(s, Some(3)), Some(NodeAt(at=[8], anchor=Some(8))))
  assert_eq(anchors_of(s, Some(4)), Some(CardAt(at=11)))
  assert_eq(anchors_of(s, None), None)
  assert_eq(anchors_of(s, Some(99)), None)
  assert_eq(
    anchors_for(s, nodes([2, 3], Some(3))),
    Some(NodeAt(at=[2, 8], anchor=Some(8))),
  )
  assert_eq(anchors_for(s, Card(id=4)), Some(CardAt(at=11)))
  assert_eq(anchors_for(s, nothing), Some(NodeAt(at=[], anchor=None)))
  assert_eq(ranges(s, nodes([3], Some(3))), [{ from: 5, to: 21, }])
  assert_eq(ranges(s, nodes([2], Some(2))), [{ from: 0, to: 21, }])
  assert_eq(ranges(s, Card(id=4)), [{ from: 11, to: 21, }])
}

///|
test "carry — 位置を写す。点も並びも基点も同じ写像で" {
  let shift = (p : Int) => p + 3
  assert_eq(
    carry(NodeAt(at=[8, 14], anchor=Some(14)), shift),
    NodeAt(at=[11, 17], anchor=Some(17)),
  )
  assert_eq(
    carry(NodeAt(at=[], anchor=None), shift),
    NodeAt(at=[], anchor=None),
  )
  assert_eq(carry(CardAt(at=11), shift), CardAt(at=14))
}

// ---- 二分探索の前提（#55） ----

///|
/// 位置の試験に使う見本。入れ子・項目・中身・畳み・頭を混ぜる
let placed : Array[String] = [
  "# r\n", "# r\n\nhello\n", "# r\n\n## a\n\n## b\n", "# r\n\n## a\n\n### x\n\n## b\n",
  "- a\n- b\n", "- a\n  - b\n    - c\n", "# r\n\n```\nx\n```\n\n## a\n", "---\nk: v\n---\n\n# r\n\n## a\n",
  "intro\n\n# a\n\n## b\n", "# r\n\n![](./x.webp)\n\n## a\n", "- # head\n\n  body\n",
  "# r\n\n<details>\n<summary>s</summary>\n\n## a\n\n</details>\n",
  // #204 — 列 0 の塊は項目を閉じるので、中身が子より後ろに書かれる
   "# r\n\n- head\n\ntext\n", "# r\n\n- a\n\ntext\n\n- b\n",
]

///|
/// **昇順で、重なりが無い。** `hit_at` の二分探索はこれに乗っている。
/// 親の文は最初の子の手前で終わり、次の兄弟はその子孫の後ろから始まるので
/// 成り立つ。子の後ろに書かれた中身は区間を割るが、子の領分は跨がない（#204）
/// — 崩れたら位置がどのノードに掛かるかが狂う
test "owns: from の昇順で、重なりが無い" {
  let bad : Array[String] = []
  for md in placed {
    let all = owns(survey(md))
    for i in 1..<all.length() {
      let a = all[i - 1]
      let b = all[i]
      if b.from < a.from {
        bad.push("\{md.escape()}: from が戻る \{a.from} → \{b.from}")
      }
      if b.from < a.to {
        bad.push(
          "\{md.escape()}: 重なる [\{a.from},\{a.to}) と [\{b.from},\{b.to})",
        )
      }
    }
  }
  json_inspect(bad, content=[])
}

///|
/// **二分探索は、全部を走った答えと一致する。** 走る版（`hit_at` を入れる前の
/// 形）を試験の中に残しておき、見本の全位置で突き合わせる
test "hit_at: 全部を走った答えと一致する" {
  let scanned = (all : Array[Own], p : Int) => {
    let on = all.filter(o => o.from <= p && o.to >= p)
    let starting = on.filter(o => o.from == p)
    if starting.length() > 0 {
      starting.get(0)
    } else {
      on.get(0)
    }
  }
  let bad : Array[String] = []
  for md in placed {
    let all = owns(survey(md))
    for p in 0..<=md.length() {
      // 無いときは -1（並べて読めるように）
      let fast = hit_at(all, p).map(o => o.id).unwrap_or(-1)
      let slow = scanned(all, p).map(o => o.id).unwrap_or(-1)
      if fast != slow {
        bad.push("\{md.escape()} の \{p}: 二分 \{fast} / 走査 \{slow}")
      }
    }
  }
  json_inspect(bad, content=[])
}

///|
/// **子の後ろに書かれた中身も、その持ち主の文。** 列 0 の塊は開いている項目を
/// 閉じるので、見出しの中身が子より後ろに書かれる（#204）。1 本の区間で
/// 「頭から最初の子まで」と読むと、そこに立てたカーソルが何にも掛からない
test "子の後ろに書かれた中身に立てたカーソルは、その持ち主に掛かる" {
  // "# r\n\n- head\n\ntext\n" — r=2, text=3, head=4
  let d = survey("# r\n\n- head\n\ntext\n")
  assert_eq(ids_at(owns(d), point(1)), [2]) // 見出しの行
  assert_eq(ids_at(owns(d), point(7)), [4]) // 項目の行
  assert_eq(ids_at(owns(d), point(14)), [2]) // 子の後ろの text は r のもの
  // 兄弟と兄弟の間に書かれていても同じ
  let mid = survey("# r\n\n- a\n\ntext\n\n- b\n")
  assert_eq(ids_at(owns(mid), point(12)), [2])
  assert_eq(ids_at(owns(mid), point(19)), [5])
}

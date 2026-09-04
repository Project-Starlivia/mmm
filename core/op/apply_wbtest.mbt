// Op ごとに「この木にこの操作でこの木」を固定する。木は手で組む。
// 最後に「apply の結果は check を通る」を法則として回す。

///|
fn run(d : @tree.Doc, op : Op) -> Done? {
  apply(d, op)
}

///|
test "Rename はラベルを替える。Implicit は見出しになる" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(
    run(d, Rename(id=4, label="y")),
    Some({
      doc: doc([root(h(2, "r", children=[gap(3, [h(4, "y")])]), sides=[Right])]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, Rename(id=3, label="a")),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(3),
    }),
  )
  let e = doc([root(item(2, "a"))])
  assert_eq(
    run(e, Rename(id=2, label="b")),
    Some({ doc: doc([root(item(2, "b"))]), focus: Some(2) }),
  )
}

///|
test "Rename は中身と知らない id に None" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(run(d, Rename(id=3, label="y")), None)
  assert_eq(run(d, Rename(id=9, label="y")), None)
}

///|
test "Fold は定義ごと畳み、名前はラベル。畳み済みなら open だけ替わる" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[Right]),
  ])
  let folded : @tree.Fold = { open: false, summary: Some("a") }
  assert_eq(
    run(d, Fold(id=3, open=false)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", fold=Some(folded), children=[h(4, "x")]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(3),
    }),
  )
  let custom : @tree.Fold = { open: false, summary: Some("custom") }
  let f = doc([
    root(h(2, "r", children=[h(3, "a", fold=Some(custom))]), sides=[Right]),
  ])
  assert_eq(
    run(f, Fold(id=3, open=true)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", fold=Some({ open: true, summary: Some("custom") })),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(3),
    }),
  )
}

///|
test "Fold は書けない名前なら名無しで畳む" {
  let d = doc([root(h(2, "a</summary>b"))])
  assert_eq(
    run(d, Fold(id=2, open=false)),
    Some({
      doc: doc([
        root(h(2, "a</summary>b", fold=Some({ open: false, summary: None }))),
      ]),
      focus: Some(2),
    }),
  )
}

///|
test "Fold は Implicit と中身に None。Unfold は畳んでいなければ None" {
  let d = doc([
    root(h(2, "r", body=[pic(3)], children=[gap(4, [h(5, "x")])]), sides=[Right]),
  ])
  assert_eq(run(d, Fold(id=4, open=false)), None)
  assert_eq(run(d, Fold(id=3, open=false)), None)
  assert_eq(run(d, Unfold(id=2)), None)
}

///|
test "Unfold は畳みを外す" {
  let folded : @tree.Fold = { open: false, summary: Some("a") }
  let d = doc([root(item(2, "a", fold=Some(folded)))])
  assert_eq(
    run(d, Unfold(id=2)),
    Some({ doc: doc([root(item(2, "a"))]), focus: Some(2) }),
  )
}

///|
test "Delete は部分木ごと。根の子なら side も、Implicit の掃除も" {
  let d = doc([
    root(
      h(2, "r", children=[h(3, "a", children=[h(4, "x")]), gap(5, [h(6, "y")])]),
      sides=[Right, Left],
    ),
  ])
  assert_eq(
    run(d, Delete(ids=[4, 6, 3])),
    Some({ doc: doc([root(h(2, "r"), sides=[])]), focus: None }),
  )
}

///|
test "Delete は中身も 1 枚ずつ（持ち主が focus）。根も Root ごと" {
  let d = doc([root(h(2, "r", body=[pic(3), code(4)])), root(h(5, "s"))])
  assert_eq(
    run(d, Delete(ids=[3])),
    Some({
      doc: doc([root(h(2, "r", body=[code(4)])), root(h(5, "s"))]),
      focus: Some(2),
    }),
  )
  // 持ち主ごと消せば focus は無い
  assert_eq(
    run(d, Delete(ids=[2, 3])),
    Some({ doc: doc([root(h(5, "s"))]), focus: None }),
  )
  assert_eq(
    run(d, Delete(ids=[5])),
    Some({ doc: doc([root(h(2, "r", body=[pic(3), code(4)]))]), focus: None }),
  )
}

///|
test "Delete は空と知らない id に None" {
  let d = doc([root(h(2, "r"))])
  assert_eq(run(d, Delete(ids=[])), None)
  assert_eq(run(d, Delete(ids=[2, 9])), None)
}

///|
test "AddNode は隣の前後と子の末尾。綴りは隣に従う" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    run(d, AddNode(at=NodePlace::After(node=3), labels=["b"])),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Left, Left]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, AddNode(at=NodePlace::Before(node=3), labels=["b", "c"])),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(4, "b"), h(5, "c"), h(3, "a")]), sides=[
          Left,
          Left,
          Left,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, AddNode(at=NodePlace::In(node=3, side=None), labels=[""])),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "")])]), sides=[Left]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, AddNode(at=NodePlace::In(node=2, side=Some(Right)), labels=["b"])),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Left, Right]),
      ]),
      focus: Some(4),
    }),
  )
}

///|
test "AddNode の綴り: 項目の隣は項目、項目の下は項目、見出しの下で子が無ければ見出し" {
  let d = doc([root(h(2, "r", children=[item(3, "a")]), sides=[Right])])
  assert_eq(
    run(d, AddNode(at=NodePlace::After(node=3), labels=["b"])),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(3, "a"), item(4, "b")]), sides=[
          Right,
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, AddNode(at=NodePlace::In(node=3, side=None), labels=["b"])),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(3, "a", children=[li(4, "b")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, AddNode(at=NodePlace::In(node=2, side=None), labels=["b"])),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(3, "a"), item(4, "b")]), sides=[
          Right,
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  let e = doc([root(h(2, "r"))])
  assert_eq(
    run(e, AddNode(at=NodePlace::In(node=2, side=None), labels=["b"])),
    Some({
      doc: doc([root(h(2, "r", children=[h(3, "b")]), sides=[Right])]),
      focus: Some(3),
    }),
  )
}

///|
test "AddNode を doc_id にすれば新しい根。空の文書にも" {
  assert_eq(
    run(
      doc([]),
      AddNode(at=NodePlace::In(node=@tree.doc_id, side=None), labels=["r"]),
    ),
    Some({ doc: doc([root(h(2, "r"))]), focus: Some(2) }),
  )
}

///|
test "AddNode を doc_id にすれば最後の根の綴りに従う" {
  let d = doc([root(item(2, "a"))])
  assert_eq(
    run(
      d,
      AddNode(at=NodePlace::In(node=@tree.doc_id, side=None), labels=["b"]),
    ),
    Some({ doc: doc([root(item(2, "a")), root(item(3, "b"))]), focus: Some(3) }),
  )
}

///|
test "AddNode は空のラベル列と知らない id に None" {
  let d = doc([root(h(2, "r"))])
  assert_eq(run(d, AddNode(at=NodePlace::After(node=2), labels=[])), None)
  assert_eq(run(d, AddNode(at=NodePlace::After(node=9), labels=["a"])), None)
}

///|
test "Wrap は席に座って id を唯一の子にする。根なら sides は [Right]" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[Left]),
  ])
  assert_eq(
    run(d, Wrap(id=3, label="p")),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(5, "p", children=[h(3, "a", children=[h(4, "x")])]),
          ]),
          sides=[Left],
        ),
      ]),
      focus: Some(5),
    }),
  )
  assert_eq(
    run(d, Wrap(id=2, label="top")),
    Some({
      doc: doc([
        root(
          h(5, "top", children=[
            h(2, "r", children=[h(3, "a", children=[h(4, "x")])]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(5),
    }),
  )
  let e = doc([root(item(2, "a", children=[li(3, "b")]), sides=[Right])])
  assert_eq(
    run(e, Wrap(id=3, label="p")),
    Some({
      doc: doc([
        root(item(2, "a", children=[li(4, "p", children=[li(3, "b")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
}

///|
test "Wrap は中身に None" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(run(d, Wrap(id=3, label="p")), None)
}

///|
test "MoveNode は文書順を保って抜き、隣の前後に差す" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), h(4, "b"), h(5, "c")]), sides=[
      Right,
      Right,
      Left,
    ]),
  ])
  assert_eq(
    run(d, MoveNode(ids=[5, 3], at=NodePlace::After(node=4))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(4, "b"), h(3, "a"), h(5, "c")]), sides=[
          Right,
          Right,
          Right,
        ]),
      ]),
      focus: Some(3),
    }),
  )
  assert_eq(
    run(d, MoveNode(ids=[5], at=NodePlace::Before(node=3))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(5, "c"), h(3, "a"), h(4, "b")]), sides=[
          Right,
          Right,
          Right,
        ]),
      ]),
      focus: Some(5),
    }),
  )
}

///|
test "MoveNode で子の下へ（indent）と親の後ろへ（outdent）" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Right, Right]),
  ])
  let indented = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "b")])]), sides=[Right]),
  ])
  assert_eq(
    run(d, MoveNode(ids=[4], at=NodePlace::In(node=3, side=None))),
    Some({ doc: indented, focus: Some(4) }),
  )
  assert_eq(
    run(indented, MoveNode(ids=[4], at=NodePlace::After(node=3))),
    Some({ doc: d, focus: Some(4) }),
  )
}

///|
test "MoveNode は側を運ばず、行き先が決める。根の脇は side で言う" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Right, Right]),
  ])
  assert_eq(
    run(d, MoveNode(ids=[3], at=NodePlace::In(node=2, side=Some(Left)))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(4, "b"), h(3, "a")]), sides=[Right, Left]),
      ]),
      focus: Some(3),
    }),
  )
}

///|
test "MoveNode で根の間へ行けば新しい根、根を子にすれば側は消える" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a")]), sides=[Left]),
    root(h(4, "s")),
  ])
  assert_eq(
    run(d, MoveNode(ids=[3], at=NodePlace::Before(node=4))),
    Some({
      doc: doc([root(h(2, "r"), sides=[]), root(h(3, "a")), root(h(4, "s"))]),
      focus: Some(3),
    }),
  )
  assert_eq(
    run(d, MoveNode(ids=[4], at=NodePlace::In(node=3, side=None))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "s")])]), sides=[Left]),
      ]),
      focus: Some(4),
    }),
  )
}

///|
test "MoveNode は綴りを保つ。項目は見出しの下に置け、見出しは項目の下に置けない" {
  // 見出しの直後の項目は境界（側の変わり目）が無いと飲み込まれる
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), item(4, "b")]), sides=[Right, Left]),
  ])
  assert_eq(
    run(d, MoveNode(ids=[4], at=NodePlace::In(node=3, side=None))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[item(4, "b")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    run(d, MoveNode(ids=[3], at=NodePlace::In(node=4, side=None))),
    None,
  )
  // 見出しは項目の後ろに置ける（項目の枠は見出しの親になれず、落ちる）。側は隣のもの
  assert_eq(
    run(d, MoveNode(ids=[3], at=NodePlace::After(node=4))),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(4, "b"), h(3, "a")]), sides=[Left, Left]),
      ]),
      focus: Some(3),
    }),
  )
}

///|
test "MoveNode は空・中身・知らない id・動かすものの中へ、に None" {
  let d = doc([
    root(
      h(2, "r", body=[pic(3)], children=[
        h(4, "a", children=[h(5, "x")]),
        h(6, "b"),
      ]),
      sides=[Right, Right],
    ),
  ])
  assert_eq(run(d, MoveNode(ids=[], at=NodePlace::After(node=6))), None)
  assert_eq(run(d, MoveNode(ids=[3], at=NodePlace::After(node=6))), None)
  assert_eq(run(d, MoveNode(ids=[9], at=NodePlace::After(node=6))), None)
  assert_eq(
    run(d, MoveNode(ids=[4], at=NodePlace::In(node=5, side=None))),
    None,
  )
  assert_eq(run(d, MoveNode(ids=[4], at=NodePlace::After(node=4))), None)
}

///|
test "FlipSide の 3 段: 根は鏡像、根の子は 1 つ、深いものは反対側へ引き出す" {
  let d = doc([
    root(
      h(2, "r", children=[
        h(3, "a", children=[h(4, "x", children=[h(5, "y")])]),
        h(6, "b"),
      ]),
      sides=[Right, Right],
    ),
  ])
  assert_eq(
    run(d, FlipSide(id=2)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[h(4, "x", children=[h(5, "y")])]),
            h(6, "b"),
          ]),
          sides=[Left, Left],
        ),
      ]),
      focus: Some(2),
    }),
  )
  assert_eq(
    run(d, FlipSide(id=6)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[h(4, "x", children=[h(5, "y")])]),
            h(6, "b"),
          ]),
          sides=[Right, Left],
        ),
      ]),
      focus: Some(6),
    }),
  )
  // y は深さ 4。反対側（Left）の末尾へ、Implicit 2 枚で深さを保つ。
  // 直前の b と側が変わるので境界が書かれ、Implicit は b に飲み込まれない
  assert_eq(
    run(d, FlipSide(id=5)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[h(4, "x")]),
            h(6, "b"),
            gap(8, [gap(7, [h(5, "y")])]),
          ]),
          sides=[Right, Right, Left],
        ),
      ]),
      focus: Some(5),
    }),
  )
}

///|
/// 項目は相対記法で深さを持たないので、Implicit で包まず直に深さ 2 へ。
test "FlipSide の深い項目は Implicit で包まず引き出す" {
  let d = doc([
    root(h(2, "r", children=[item(3, "i", children=[li(4, "j")])]), sides=[
      Right,
    ]),
  ])
  assert_eq(
    run(d, FlipSide(id=4)),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(3, "i"), item(4, "j")]), sides=[
          Right,
          Left,
        ]),
      ]),
      focus: Some(4),
    }),
  )
}

///|
/// 深いノードを引き出した先が、直前の兄弟と同じ側なら境界が無く、
/// Implicit はその兄弟に飲み込まれる（check が言う）。
test "FlipSide の深いノードは、引き出す先に境界が無ければ None" {
  let d = doc([
    root(
      h(2, "r", children=[
        h(3, "a", children=[h(4, "x", children=[h(5, "y")])]),
        h(6, "b"),
      ]),
      sides=[Right, Left],
    ),
  ])
  assert_eq(run(d, FlipSide(id=5)), None)
}

///|
test "FlipSide の深いノード: 根の Implicit が丸ごと抜ければ、引き出したものを子に置き直す" {
  let d = doc([root(gap(2, [gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(
    run(d, FlipSide(id=4)),
    Some({
      doc: doc([root(gap(2, [gap(5, [h(4, "x")])]), sides=[Left])]),
      focus: Some(4),
    }),
  )
}

///|
test "FlipSide は中身と知らない id に None" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(run(d, FlipSide(id=3)), None)
  assert_eq(run(d, FlipSide(id=9)), None)
}

///|
test "AddBlock は隣の前後と body の末尾" {
  let d = doc([
    root(h(2, "r", body=[pic(3)], children=[h(4, "a")]), sides=[Right]),
  ])
  let c : @tree.Content = Code(info="", text="x")
  assert_eq(
    run(d, AddBlock(at=BlockPlace::After(block=3), content=c)),
    Some({
      doc: doc([
        root(h(2, "r", body=[pic(3), code(5)], children=[h(4, "a")]), sides=[
          Right,
        ]),
      ]),
      focus: Some(5),
    }),
  )
  assert_eq(
    run(d, AddBlock(at=BlockPlace::Before(block=3), content=c)),
    Some({
      doc: doc([
        root(h(2, "r", body=[code(5), pic(3)], children=[h(4, "a")]), sides=[
          Right,
        ]),
      ]),
      focus: Some(5),
    }),
  )
  assert_eq(
    run(d, AddBlock(at=BlockPlace::In(node=4), content=c)),
    Some({
      doc: doc([
        root(h(2, "r", body=[pic(3)], children=[h(4, "a", body=[code(5)])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(5),
    }),
  )
  assert_eq(
    run(d, AddBlock(at=BlockPlace::In(node=@tree.doc_id), content=c)),
    Some({
      doc: doc(
        [root(h(2, "r", body=[pic(3)], children=[h(4, "a")]), sides=[Right])],
        body=[code(5)],
      ),
      focus: Some(5),
    }),
  )
}

///|
test "AddBlock は Implicit・ノードの id・知らない id に None" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "x")])]), sides=[Right])])
  let c : @tree.Content = Code(info="", text="x")
  assert_eq(run(d, AddBlock(at=BlockPlace::In(node=3), content=c)), None)
  assert_eq(run(d, AddBlock(at=BlockPlace::After(block=4), content=c)), None)
  assert_eq(run(d, AddBlock(at=BlockPlace::After(block=9), content=c)), None)
}

///|
test "SetBlock は中身を替え、id は保つ" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(
    run(d, SetBlock(id=3, content=Code(info="", text="x"))),
    Some({ doc: doc([root(h(2, "r", body=[code(3)]))]), focus: Some(3) }),
  )
  assert_eq(run(d, SetBlock(id=2, content=Code(info="", text="x"))), None)
}

///|
test "MoveBlock は文書順を保って抜き、隣の前後や別のノードの末尾に差す" {
  let d = doc([
    root(h(2, "r", body=[pic(3), code(4), pic(5)], children=[h(6, "a")]), sides=[
      Right,
    ]),
  ])
  assert_eq(
    run(d, MoveBlock(ids=[5, 3], at=BlockPlace::After(block=4))),
    Some({
      doc: doc([
        root(h(2, "r", body=[code(4), pic(3), pic(5)], children=[h(6, "a")]), sides=[
          Right,
        ]),
      ]),
      focus: Some(3),
    }),
  )
  assert_eq(
    run(d, MoveBlock(ids=[4], at=BlockPlace::In(node=6))),
    Some({
      doc: doc([
        root(
          h(2, "r", body=[pic(3), pic(5)], children=[h(6, "a", body=[code(4)])]),
          sides=[Right],
        ),
      ]),
      focus: Some(4),
    }),
  )
}

///|
test "MoveBlock は空・ノード混じり・知らない id・自分の隣へ、に None" {
  let d = doc([root(h(2, "r", body=[pic(3), code(4)]))])
  assert_eq(run(d, MoveBlock(ids=[], at=BlockPlace::After(block=4))), None)
  assert_eq(run(d, MoveBlock(ids=[2], at=BlockPlace::After(block=4))), None)
  assert_eq(run(d, MoveBlock(ids=[9], at=BlockPlace::After(block=4))), None)
  assert_eq(run(d, MoveBlock(ids=[3], at=BlockPlace::Before(block=3))), None)
}

///|
test "Graft は parse した根たちを差す。側は捨て、id は鋳直す" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    run(
      d,
      Graft(
        at=NodePlace::In(node=3, side=None),
        md="# p\n\n## q\n\n---\n\n## s\n\n# t\n",
      ),
    ),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[
              h(4, "p", children=[h(5, "q"), h(6, "s")]),
              h(7, "t"),
            ]),
          ]),
          sides=[Left],
        ),
      ]),
      focus: Some(4),
    }),
  )
}

///|
test "Graft は根の間にも差せる。先頭の散文は行き先の親の body 末尾へ" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(
    run(
      d,
      Graft(
        at=NodePlace::In(node=@tree.doc_id, side=None),
        md="![](q.png)\n\n# s\n",
      ),
    ),
    Some({
      doc: doc([root(h(2, "r", body=[pic(3)])), root(h(5, "s"))], body=[
        { id: 4, content: Image(alt="", src="q.png", title="") },
      ]),
      focus: Some(5),
    }),
  )
  assert_eq(
    run(d, Graft(at=NodePlace::After(node=2), md="text\n")),
    Some({
      doc: doc([root(h(2, "r", body=[pic(3)]))], body=[
        { id: 4, content: Opaque("text") },
      ]),
      focus: None,
    }),
  )
}

///|
test "Graft は空・知らない id・項目の下に見出し、に None" {
  let d = doc([root(h(2, "r", children=[item(3, "a")]), sides=[Right])])
  assert_eq(run(d, Graft(at=NodePlace::In(node=2, side=None), md="")), None)
  assert_eq(
    run(d, Graft(at=NodePlace::In(node=9, side=None), md="# p\n")),
    None,
  )
  assert_eq(
    run(d, Graft(at=NodePlace::In(node=3, side=None), md="# p\n")),
    None,
  )
}

///|
/// 代表的な木に、代表的な Op を総当たりで当て、Some ならその結果が
/// check を通ることを見る。落ちた Op と破れを並べる。
test "apply の結果は check を通る" {
  // 見出しの直後の項目・Implicit は飲み込まれるので、項目を先に置く（check が言う）
  let base = doc([
    root(item(11, "e"), sides=[]),
    root(
      h(2, "r", body=[pic(3)], children=[
        h(4, "a", children=[
          item(7, "b", children=[li(8, "c")]),
          gap(5, [h(6, "x")]),
        ]),
        h(9, "d", body=[code(10)]),
      ]),
      sides=[Right, Left],
    ),
  ])
  json_inspect(@tree.check(base), content=[])
  let ids = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  let ops : Array[Op] = []
  for id in ids {
    ops.push(Rename(id~, label="z"))
    ops.push(Fold(id~, open=false))
    ops.push(Unfold(id~))
    ops.push(Delete(ids=[id]))
    ops.push(Wrap(id~, label="w"))
    ops.push(FlipSide(id~))
    ops.push(SetBlock(id~, content=ThematicBreak))
    for to in ids {
      ops.push(MoveNode(ids=[id], at=NodePlace::Before(node=to)))
      ops.push(MoveNode(ids=[id], at=NodePlace::After(node=to)))
      ops.push(MoveNode(ids=[id], at=NodePlace::In(node=to, side=Some(Left))))
      ops.push(MoveBlock(ids=[id], at=BlockPlace::Before(block=to)))
      ops.push(MoveBlock(ids=[id], at=BlockPlace::In(node=to)))
      ops.push(AddNode(at=NodePlace::After(node=to), labels=["n"]))
      ops.push(AddBlock(at=BlockPlace::In(node=to), content=ThematicBreak))
      ops.push(Graft(at=NodePlace::In(node=to, side=None), md="# g\n\n- i\n"))
    }
  }
  let bad = []
  let mut some = 0
  for op in ops {
    match apply(base, op) {
      Some(done) => {
        some = some + 1
        let flaws = @tree.check(done.doc)
        if !flaws.is_empty() {
          bad.push((op, flaws))
        }
      }
      None => ()
    }
  }
  // 全部 None に潰れる退化を落とすための下限チェック。
  inspect(some, content="293")
  json_inspect(bad, content=[])
}

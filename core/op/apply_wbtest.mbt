// Op ごとに「この木にこの操作でこの木」を固定する。木は手で組む。
// 最後に「apply の結果は check を通る」を法則として回す。

///|
test "Rename はラベルを替える。Implicit は見出しになる" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(
    apply(d, Rename(id=4, label="y")),
    Some({
      doc: doc([root(h(2, "r", children=[gap(3, [h(4, "y")])]), sides=[Right])]),
      focus: Some(4),
    }),
  )
  assert_eq(
    apply(d, Rename(id=3, label="a")),
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
    apply(e, Rename(id=2, label="b")),
    Some({ doc: doc([root(item(2, "b"))]), focus: Some(2), }),
  )
}

///|
/// 畳まれたノードの名前は summary（地図が出す字）。名を付け直せばラベルも summary も同じ字に
test "Rename は畳まれたノードの summary も同じ字にする" {
  let d = doc([
    root(h(2, "a", fold=Some({ open: true, summary: Some("old"), }))),
  ])
  assert_eq(
    apply(d, Rename(id=2, label="b")),
    Some({
      doc: doc([root(h(2, "b", fold=Some({ open: true, summary: Some("b"), })))]),
      focus: Some(2),
    }),
  )
}

///|
test "Rename は中身と知らない id に None" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(apply(d, Rename(id=3, label="y")), None)
  assert_eq(apply(d, Rename(id=9, label="y")), None)
}

///|
test "Fold は定義ごと畳み、名前はラベル。畳み済みなら open だけ替わる" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[Right]),
  ])
  let folded : @tree.Fold = { open: false, summary: Some("a"), }
  assert_eq(
    apply(d, Fold(id=3, open=false)),
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
  let custom : @tree.Fold = { open: false, summary: Some("custom"), }
  let f = doc([
    root(h(2, "r", children=[h(3, "a", fold=Some(custom))]), sides=[Right]),
  ])
  assert_eq(
    apply(f, Fold(id=3, open=true)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", fold=Some({ open: true, summary: Some("custom"), })),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(3),
    }),
  )
}

///|
test "Fold の名前はラベルそのもの — `</summary>` が入っていても" {
  let d = doc([root(h(2, "a</summary>b"))])
  assert_eq(
    apply(d, Fold(id=2, open=false)),
    Some({
      doc: doc([
        root(
          h(
            2,
            "a</summary>b",
            fold=Some({ open: false, summary: Some("a</summary>b"), }),
          ),
        ),
      ]),
      focus: Some(2),
    }),
  )
}

///|
test "Fold は Implicit を綴ってから畳む。中身に None。Unfold は畳んでいなければ None" {
  let d = doc([
    root(h(2, "r", body=[pic(3)], children=[gap(4, [h(5, "x")])]), sides=[Right]),
  ])
  let folded : @tree.Fold = { open: false, summary: Some(""), }
  assert_eq(
    apply(d, Fold(id=4, open=false)),
    Some({
      doc: doc([
        root(
          h(2, "r", body=[pic(3)], children=[
            h(4, "", fold=Some(folded), children=[h(5, "x")]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(apply(d, Fold(id=3, open=false)), None)
  assert_eq(apply(d, Unfold(id=2)), None)
}

///|
test "Unfold は畳みを外す" {
  let folded : @tree.Fold = { open: false, summary: Some("a"), }
  let d = doc([root(item(2, "a", fold=Some(folded)))])
  assert_eq(
    apply(d, Unfold(id=2)),
    Some({ doc: doc([root(item(2, "a"))]), focus: Some(2), }),
  )
}

///|
test "Delete は部分木ごと。根の子なら side も、Implicit の掃除も。focus は残った親" {
  let d = doc([
    root(
      h(2, "r", children=[h(3, "a", children=[h(4, "x")]), gap(5, [h(6, "y")])]),
      sides=[Right, Left],
    ),
  ])
  // a の次の兄弟は Implicit 5 だが y ごと消えるので、親 r
  assert_eq(
    apply(d, Delete(ids=[4, 6, 3])),
    Some({ doc: doc([root(h(2, "r"), sides=[])]), focus: Some(2), }),
  )
}

///|
test "Delete は中身も 1 枚ずつ（持ち主が focus）。根も Root ごと（隣の根が focus）" {
  let d = doc([root(h(2, "r", body=[pic(3), code(4)])), root(h(5, "s"))])
  assert_eq(
    apply(d, Delete(ids=[3])),
    Some({
      doc: doc([root(h(2, "r", body=[code(4)])), root(h(5, "s"))]),
      focus: Some(2),
    }),
  )
  // 持ち主ごと消せば、先頭は文書順で r（ノード）なので、次の根 s
  assert_eq(
    apply(d, Delete(ids=[2, 3])),
    Some({ doc: doc([root(h(5, "s"))]), focus: Some(5), }),
  )
  // 末尾の根を消せば前の根
  assert_eq(
    apply(d, Delete(ids=[5])),
    Some({
      doc: doc([root(h(2, "r", body=[pic(3), code(4)]))]),
      focus: Some(2),
    }),
  )
}

///|
test "Delete は空と知らない id に None" {
  let d = doc([root(h(2, "r"))])
  assert_eq(apply(d, Delete(ids=[])), None)
  assert_eq(apply(d, Delete(ids=[2, 9])), None)
}

///|
test "Delete したノードの focus は次の兄弟 → 前の兄弟 → 親。消えるものは飛ばし、畳まれた兄弟はそれ自身" {
  let d = doc([
    root(
      h(2, "r", children=[h(3, "a"), h(4, "b", children=[h(5, "x")]), h(6, "c")]),
      sides=[Right, Right, Right],
    ),
  ])
  let focus = (op : Op) => apply(d, op).map(x => x.focus)
  // 次の兄弟
  assert_eq(focus(Delete(ids=[3])), Some(Some(4)))
  // 末尾なら前の兄弟。その子孫（x）ではない
  assert_eq(focus(Delete(ids=[6])), Some(Some(4)))
  // 次が一緒に消えるなら飛ばす
  assert_eq(focus(Delete(ids=[3, 4])), Some(Some(6)))
  // 兄弟が尽きれば親
  assert_eq(focus(Delete(ids=[3, 4, 6])), Some(Some(2)))
  // 子孫も選んでいても、基準は文書順の先頭（a）
  assert_eq(focus(Delete(ids=[5, 3])), Some(Some(4)))
  // 最後の根なら何も無い
  assert_eq(
    apply(doc([root(h(2, "r"))]), Delete(ids=[2])).map(x => x.focus),
    Some(None),
  )
  // 前の兄弟が畳まれていれば、その兄弟そのもの（埋もれた子孫には落ちない）
  let folded : @tree.Fold = { open: false, summary: Some("b"), }
  let f = doc([
    root(
      h(2, "r", children=[
        h(3, "b", fold=Some(folded), children=[h(4, "y")]),
        h(5, "c"),
      ]),
      sides=[Right, Right],
    ),
  ])
  assert_eq(apply(f, Delete(ids=[5])).map(x => x.focus), Some(Some(3)))
}

///|
test "AddNode は隣の前後と子の末尾。綴りは隣に従う" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    apply(d, AddNode(at=NodePlace::After(node=3), label="b")),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Left, Left]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    apply(d, AddNode(at=NodePlace::Before(node=3), label="b")),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(4, "b"), h(3, "a")]), sides=[Left, Left]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    apply(d, AddNode(at=NodePlace::In(node=3, side=None), label="")),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "")])]), sides=[Left]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    apply(d, AddNode(at=NodePlace::In(node=2, side=Some(Right)), label="b")),
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
    apply(d, AddNode(at=NodePlace::After(node=3), label="b")),
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
    apply(d, AddNode(at=NodePlace::In(node=3, side=None), label="b")),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(3, "a", children=[item(4, "b")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    apply(d, AddNode(at=NodePlace::In(node=2, side=None), label="b")),
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
    apply(e, AddNode(at=NodePlace::In(node=2, side=None), label="b")),
    Some({
      doc: doc([root(h(2, "r", children=[h(3, "b")]), sides=[Right])]),
      focus: Some(3),
    }),
  )
}

///|
test "AddNode を doc_id にすれば新しい根。空の文書にも" {
  assert_eq(
    apply(
      doc([]),
      AddNode(at=NodePlace::In(node=@tree.doc_id, side=None), label="r"),
    ),
    Some({ doc: doc([root(h(2, "r"))]), focus: Some(2), }),
  )
}

///|
test "AddNode を doc_id にすれば最後の根の綴りに従う" {
  let d = doc([root(item(2, "a"))])
  assert_eq(
    apply(d, AddNode(at=NodePlace::In(node=@tree.doc_id, side=None), label="b")),
    Some({ doc: doc([root(item(2, "a")), root(item(3, "b"))]), focus: Some(3), }),
  )
}

///|
test "AddNode は知らない id に None" {
  let d = doc([root(h(2, "r"))])
  assert_eq(apply(d, AddNode(at=NodePlace::After(node=9), label="a")), None)
}

///|
test "Wrap は席に座って id を唯一の子にする。根なら sides は [Right]" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a", children=[h(4, "x")])]), sides=[Left]),
  ])
  assert_eq(
    apply(d, Wrap(id=3, label="p")),
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
    apply(d, Wrap(id=2, label="top")),
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
  let e = doc([root(item(2, "a", children=[item(3, "b")]), sides=[Right])])
  assert_eq(
    apply(e, Wrap(id=3, label="p")),
    Some({
      doc: doc([
        root(item(2, "a", children=[item(4, "p", children=[item(3, "b")])]), sides=[
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
  assert_eq(apply(d, Wrap(id=3, label="p")), None)
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
    apply(d, MoveNode(ids=[5, 3], at=NodePlace::After(node=4))),
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
    apply(d, MoveNode(ids=[5], at=NodePlace::Before(node=3))),
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
    apply(d, MoveNode(ids=[4], at=NodePlace::In(node=3, side=None))),
    Some({ doc: indented, focus: Some(4), }),
  )
  assert_eq(
    apply(indented, MoveNode(ids=[4], at=NodePlace::After(node=3))),
    Some({ doc: d, focus: Some(4), }),
  )
}

///|
test "MoveNode は側を運ばず、行き先が決める。根の脇は side で言う" {
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Right, Right]),
  ])
  assert_eq(
    apply(d, MoveNode(ids=[3], at=NodePlace::In(node=2, side=Some(Left)))),
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
    apply(d, MoveNode(ids=[3], at=NodePlace::Before(node=4))),
    Some({
      doc: doc([root(h(2, "r"), sides=[]), root(h(3, "a")), root(h(4, "s"))]),
      focus: Some(3),
    }),
  )
  assert_eq(
    apply(d, MoveNode(ids=[4], at=NodePlace::In(node=3, side=None))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "s")])]), sides=[Left]),
      ]),
      focus: Some(4),
    }),
  )
}

///|
test "MoveNode は形だけ運び、綴りは席が決める" {
  // 見出しの直後の項目は境界（側の変わり目）が無いと飲み込まれる
  let d = doc([
    root(h(2, "r", children=[h(3, "a"), item(4, "b")]), sides=[Right, Left]),
  ])
  // 子の無い見出しの下へ項目 — 親に従って見出し
  assert_eq(
    apply(d, MoveNode(ids=[4], at=NodePlace::In(node=3, side=None))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a", children=[h(4, "b")])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  // 項目の下へ見出し — 項目
  assert_eq(
    apply(d, MoveNode(ids=[3], at=NodePlace::In(node=4, side=None))),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(4, "b", children=[item(3, "a")])]), sides=[
          Left,
        ]),
      ]),
      focus: Some(3),
    }),
  )
  // 見出しの後ろへ項目 — 隣に従って見出し（今まで Swallowed で断られていた席）
  assert_eq(
    apply(d, MoveNode(ids=[4], at=NodePlace::After(node=3))),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a"), h(4, "b")]), sides=[Right, Right]),
      ]),
      focus: Some(4),
    }),
  )
  // 項目の後ろへ見出し — 隣に従って項目。側は隣のもの
  assert_eq(
    apply(d, MoveNode(ids=[3], at=NodePlace::After(node=4))),
    Some({
      doc: doc([
        root(h(2, "r", children=[item(4, "b"), item(3, "a")]), sides=[
          Left,
          Left,
        ]),
      ]),
      focus: Some(3),
    }),
  )
}

///|
/// Implicit は行を省いた空の見出し。省いたままでは読めない席に来れば綴られ
/// （label `""`）、id は変わらない。
test "Implicit は見出しの直後に来れば綴られる" {
  // a → [Implicit → x, b]。b を上へも Implicit を下へも、同じ形
  let d = doc([
    root(
      h(2, "r", children=[h(3, "a", children=[gap(4, [h(5, "x")]), h(6, "b")])]),
      sides=[Right],
    ),
  ])
  let spelled = doc([
    root(
      h(2, "r", children=[
        h(3, "a", children=[h(6, "b"), h(4, "", children=[h(5, "x")])]),
      ]),
      sides=[Right],
    ),
  ])
  assert_eq(
    apply(d, MoveNode(ids=[6], at=Before(node=4))),
    Some({ doc: spelled, focus: Some(6), }),
  )
  assert_eq(
    apply(d, MoveNode(ids=[4], at=After(node=6))),
    Some({ doc: spelled, focus: Some(4), }),
  )
  // 新しい隣も同じ
  assert_eq(
    apply(d, AddNode(at=Before(node=4), label="n")),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[
              h(7, "n"),
              h(4, "", children=[h(5, "x")]),
              h(6, "b"),
            ]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(7),
    }),
  )
  // 根の子は、直前と側が変わらなければ境界が無い
  let e = doc([
    root(h(2, "r", children=[h(3, "a"), gap(4, [h(5, "x")]), h(6, "b")]), sides=[
      Right,
      Left,
      Right,
    ]),
  ])
  assert_eq(
    apply(e, MoveNode(ids=[6], at=Before(node=4))),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a"),
            h(6, "b"),
            h(4, "", children=[h(5, "x")]),
          ]),
          sides=[Right, Left, Left],
        ),
      ]),
      focus: Some(6),
    }),
  )
}

///|
/// 抜き取りで子が尽きた Implicit は操作の後で消える（掃除は門の仕事）ので、
/// その隣を席にできる。根まで登れば Root ごと消える
test "Implicit の唯一の子を、その Implicit の隣へ動かせる" {
  let d = doc([root(h(2, "r", children=[gap(3, [h(4, "a")])]), sides=[Right])])
  let out = Some({
    doc: doc([root(h(2, "r", children=[h(4, "a")]), sides=[Right])]),
    focus: Some(4),
  })
  assert_eq(apply(d, MoveNode(ids=[4], at=Before(node=3))), out)
  assert_eq(apply(d, MoveNode(ids=[4], at=After(node=3))), out)
  let e = doc([root(gap(2, [h(3, "a")]), sides=[Right]), root(h(4, "b"))])
  assert_eq(
    apply(e, MoveNode(ids=[3], at=After(node=2))),
    Some({ doc: doc([root(h(3, "a")), root(h(4, "b"))]), focus: Some(3), }),
  )
}

///|
test "Implicit は項目を子に持てば綴られる" {
  // 見出しの列に来た項目は見出しになる（隣に従う）ので、項目が Implicit の子に
  // なるのは天井だけ — 6 段目の隣へ飛びを動かすと、子は 7 段目で項目になる（cap）。
  // 項目は飛びを綴れないので、Implicit が綴られる
  let d = six([])
  let g = root(gap(8, [h(9, "z")]), sides=[Right])
  let f : @tree.Doc = { ..d, roots: [..d.roots, g], }
  assert_eq(
    apply(f, MoveNode(ids=[8], at=NodePlace::After(node=7))),
    Some({
      doc: doc([
        root(
          h(2, "a", children=[
            h(3, "b", children=[
              h(4, "c", children=[
                h(5, "d", children=[
                  h(6, "e", children=[
                    h(7, "f"),
                    h(8, "", children=[item(9, "z")]),
                  ]),
                ]),
              ]),
            ]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(8),
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
  assert_eq(apply(d, MoveNode(ids=[], at=NodePlace::After(node=6))), None)
  assert_eq(apply(d, MoveNode(ids=[3], at=NodePlace::After(node=6))), None)
  assert_eq(apply(d, MoveNode(ids=[9], at=NodePlace::After(node=6))), None)
  assert_eq(
    apply(d, MoveNode(ids=[4], at=NodePlace::In(node=5, side=None))),
    None,
  )
  assert_eq(apply(d, MoveNode(ids=[4], at=NodePlace::After(node=4))), None)
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
    apply(d, FlipSide(id=2)),
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
    apply(d, FlipSide(id=6)),
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
    apply(d, FlipSide(id=5)),
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
    root(h(2, "r", children=[item(3, "i", children=[item(4, "j")])]), sides=[
      Right,
    ]),
  ])
  assert_eq(
    apply(d, FlipSide(id=4)),
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
/// Implicit はその兄弟に飲み込まれる（check が言う）ので、外の 1 枚が綴られる。
test "FlipSide の深いノードは、引き出す先に境界が無ければ Implicit が綴られる" {
  let d = doc([
    root(
      h(2, "r", children=[
        h(3, "a", children=[h(4, "x", children=[h(5, "y")])]),
        h(6, "b"),
      ]),
      sides=[Right, Left],
    ),
  ])
  assert_eq(
    apply(d, FlipSide(id=5)),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[h(4, "x")]),
            h(6, "b"),
            h(8, "", children=[gap(7, [h(5, "y")])]),
          ]),
          sides=[Right, Left, Left],
        ),
      ]),
      focus: Some(5),
    }),
  )
}

///|
test "FlipSide の深いノード: 根の Implicit が丸ごと抜ければ、引き出したものを子に置き直す" {
  let d = doc([root(gap(2, [gap(3, [h(4, "x")])]), sides=[Right])])
  assert_eq(
    apply(d, FlipSide(id=4)),
    Some({
      doc: doc([root(gap(2, [gap(5, [h(4, "x")])]), sides=[Left])]),
      focus: Some(4),
    }),
  )
}

///|
test "FlipSide は中身と知らない id に None" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(apply(d, FlipSide(id=3)), None)
  assert_eq(apply(d, FlipSide(id=9)), None)
}

///|
test "AddBlock は隣の前後と body の末尾" {
  let d = doc([
    root(h(2, "r", body=[pic(3)], children=[h(4, "a")]), sides=[Right]),
  ])
  let c : @tree.Content = Code(info="", text="x")
  assert_eq(
    apply(d, AddBlock(at=BlockPlace::After(block=3), content=Some(c))),
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
    apply(d, AddBlock(at=BlockPlace::Before(block=3), content=Some(c))),
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
    apply(d, AddBlock(at=BlockPlace::In(node=4), content=Some(c))),
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
    apply(d, AddBlock(at=BlockPlace::In(node=@tree.doc_id), content=Some(c))),
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
  assert_eq(
    apply(d, AddBlock(at=BlockPlace::In(node=3), content=Some(c))),
    None,
  )
  assert_eq(
    apply(d, AddBlock(at=BlockPlace::After(block=4), content=Some(c))),
    None,
  )
  assert_eq(
    apply(d, AddBlock(at=BlockPlace::After(block=9), content=Some(c))),
    None,
  )
}

///|
test "SetBlock は中身を替え、id は保つ" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  assert_eq(
    apply(d, SetBlock(id=3, content=Some(Code(info="", text="x")), source=None)),
    Some({ doc: doc([root(h(2, "r", body=[code(3)]))]), focus: Some(3), }),
  )
  assert_eq(
    apply(d, SetBlock(id=2, content=Some(Code(info="", text="x")), source=None)),
    None,
  )
}

///|
test "MoveBlock は文書順を保って抜き、隣の前後や別のノードの末尾に差す" {
  let d = doc([
    root(h(2, "r", body=[pic(3), code(4), pic(5)], children=[h(6, "a")]), sides=[
      Right,
    ]),
  ])
  assert_eq(
    apply(d, MoveBlock(ids=[5, 3], at=BlockPlace::After(block=4))),
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
    apply(d, MoveBlock(ids=[4], at=BlockPlace::In(node=6))),
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
  assert_eq(apply(d, MoveBlock(ids=[], at=BlockPlace::After(block=4))), None)
  assert_eq(apply(d, MoveBlock(ids=[2], at=BlockPlace::After(block=4))), None)
  assert_eq(apply(d, MoveBlock(ids=[9], at=BlockPlace::After(block=4))), None)
  assert_eq(apply(d, MoveBlock(ids=[3], at=BlockPlace::Before(block=3))), None)
}

///|
/// 側は根のものなので、席へ差せば消える。捨てずに境界の字（読んだ `---` そのまま）
/// へ戻し、境界の直前に書かれていた行の中身の尻に置く — 書き戻せば md が境界と読む
test "Graft は parse した根たちを差す。側は境界の字に戻し、id は鋳直す" {
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Left])])
  assert_eq(
    apply(
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
              h(4, "p", children=[
                h(5, "q", body=[
                  { id: 8, content: Some(ThematicBreak), source: Some("---"), },
                ]),
                h(6, "s"),
              ]),
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
/// Mod+C は選んだ深さのまま写すので、断片は `##` から始まり得る。parse が
/// 先頭に埋める Implicit は切り出した場所の名残でしかなく、差すときは剥がす
/// （相対の形で入る）。断片の途中の飛びは綴りなので残す。
test "Graft は断片の先頭の Implicit を剥がして差す。途中の飛びは残す" {
  let d = doc([root(h(2, "r"))])
  assert_eq(
    apply(
      d,
      Graft(at=NodePlace::In(node=2, side=None), md="## a\n\n###\n\n## b\n"),
    ),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(4, "a", children=[h(5, "")]), h(6, "b")]), sides=[
          Right,
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  assert_eq(
    apply(
      d,
      Graft(at=NodePlace::In(node=2, side=None), md="### a\n\n##### b\n"),
    ),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(5, "a", children=[gap(6, [h(7, "b")])])]), sides=[
          Right,
        ]),
      ]),
      focus: Some(5),
    }),
  )
}

///|
/// 断片の一番外の段落は行ごとにノード、それ以外の中身は直前に生えたノードの中身
/// （無ければ行き先の親の body の末尾）。文書（anchor 無し）へ入れば文書の散文。
test "Graft の一番外 — 段落は行ごとにノード、中身は直前のノード、文書へ中身は散文" {
  let d = doc([root(h(2, "r", body=[pic(3)]))])
  // 根の隣に段落 2 行 → 最後の根に従って見出しの根 2 つ
  assert_eq(
    apply(d, Graft(at=NodePlace::After(node=2), md="text\nmore\n")),
    Some({
      doc: doc([
        root(h(2, "r", body=[pic(3)])),
        root(h(4, "text")),
        root(h(5, "more")),
      ]),
      focus: Some(4),
    }),
  )
  // 中身 1 枚は親の body の末尾。focus はその中身
  assert_eq(
    apply(d, Graft(at=NodePlace::In(node=2, side=None), md="![](q.png)\n")),
    Some({
      doc: doc([
        root(
          h(2, "r", body=[
            pic(3),
            {
              id: 4,
              source: Some("![](q.png)"),
              content: Some(Image(alt="", src="q.png", title="")),
            },
          ]),
        ),
      ]),
      focus: Some(4),
    }),
  )
  // URL 1 行は読みがリンクと読むので中身（特別扱いは無い）
  assert_eq(
    apply(d, Graft(at=NodePlace::In(node=2, side=None), md="https://x\n")),
    Some({
      doc: doc([
        root(
          h(2, "r", body=[
            pic(3),
            {
              id: 4,
              source: Some("https://x"),
              content: Some(Link(text="https://x", href="https://x", title="")),
            },
          ]),
        ),
      ]),
      focus: Some(4),
    }),
  )
  // 文書へ中身は文書の散文（最初の骨格より前）へ。マップには出ないが、手で頭に
  // 書いたのと同じ形 — 見えないことは地図の都合で、断る理由にしない
  assert_eq(
    apply(
      d,
      Graft(
        at=NodePlace::In(node=@tree.doc_id, side=None),
        md="![](q.png)\n\n# s\n",
      ),
    ),
    Some({
      doc: doc([root(h(2, "r", body=[pic(3)])), root(h(5, "s"))], body=[
        {
          id: 4,
          content: Some(Image(alt="", src="q.png", title="")),
          source: Some("![](q.png)"),
        },
      ]),
      focus: Some(5),
    }),
  )
  // 混ざった断片 — 一番外の段落はノード、見出しの下の中身はその見出しのまま
  assert_eq(
    apply(
      d,
      Graft(
        at=NodePlace::In(node=2, side=None),
        md="intro\n\n# a\n\n![](p.png)\n\n- b\n",
      ),
    ),
    Some({
      doc: doc([
        root(
          h(2, "r", body=[pic(3)], children=[
            h(4, "intro"),
            h(6, "a", body=[pic(7, source=Some("![](p.png)"))], children=[
              h(8, "b"),
            ]),
          ]),
          sides=[Right, Right],
        ),
      ]),
      focus: Some(4),
    }),
  )
}

///|
/// 貼った字下げは階層になる。**桁が深ければ手前の行の子、同じか浅ければ一番近い
/// 手前の段の隣**（#118）。タブは 4 桁で、空白 4 つと同じ深さ
test "Graft は貼った字下げを階層に読む — 桁の梯子" {
  let d = doc([root(h(2, "r"))])
  let grown = (md : String) => {
    match apply(d, Graft(at=NodePlace::In(node=2, side=None), md~)) {
      Some({ doc: got, .. }) => got.roots[0].node.children
      None => []
    }
  }
  // 2 桁ずつ深く
  assert_eq(grown("a\n  b\n    c\n"), [
    h(3, "a", children=[h(4, "b", children=[h(5, "c")])]),
  ])
  // タブ 1 つは空白 4 つと同じ深さ
  assert_eq(grown("a\n\tb\n"), [h(3, "a", children=[h(4, "b")])])
  assert_eq(grown("a\n    b\n"), [h(3, "a", children=[h(4, "b")])])
  // 一度も見ていない桁へ浅くなったら、一番近い手前の段の隣
  assert_eq(grown("a\n    b\n  c\n"), [
    h(3, "a", children=[h(4, "b"), h(5, "c")]),
  ])
  // 桁 0 へ戻れば兄弟。根の隣ではなく、貼り先の子として並ぶ
  assert_eq(grown("a\n  b\nc\n"), [h(3, "a", children=[h(4, "b")]), h(5, "c")])
}

///|
/// **空行は段を作らず、開いている段も閉じない。** 梯子は空行をまたいで立つので、
/// 空行の有無で木が変わらない（#118 の決め「コピペの空行は単に空行」）
test "Graft は空行をまたいでも同じ木 — 空行は桁に効かない" {
  let d = doc([root(h(2, "r"))])
  let grown = (md : String) => {
    match apply(d, Graft(at=NodePlace::In(node=2, side=None), md~)) {
      Some({ doc: got, .. }) => got.roots[0].node.children
      None => []
    }
  }
  let want = [h(3, "a", children=[h(4, "b"), h(5, "c")])]
  assert_eq(grown("a\n  b\n  c\n"), want)
  assert_eq(grown("a\n  b\n\n  c\n"), want)
  assert_eq(grown("a\n  b\n  \n  c\n"), want)
}

///|
/// **断片の左余白は切り出した先の容器。** 落とさないと 4 桁以上入った枝の写しが
/// 字下げコードとして読まれ、ノードが 1 つも生えない（#118）
test "Graft は断片の左余白を落とす — 枝の途中から写しても木になる" {
  let d = doc([root(h(2, "r"))])
  let grown = (md : String) => {
    match apply(d, Graft(at=NodePlace::In(node=2, side=None), md~)) {
      Some({ doc: got, .. }) => got.roots[0].node.children
      None => []
    }
  }
  // outline の枝を 4 桁目から写した形。続きが桁 0 へ戻っても、余白は断片ぜんぶで
  // 揃って落ちるので相対の深さが残る
  assert_eq(grown("    Child A\n        grandchild\nNext top branch\n"), [
    h(3, "Child A", children=[h(4, "grandchild")]),
    h(5, "Next top branch"),
  ])
  // タブで写した枝も同じ
  assert_eq(grown("\ta\n\t\tb\n"), [h(3, "a", children=[h(4, "b")])])
}

///|
/// 中身は**一番深い開いている段**のものになる。「直前に生えたノードのもの」を
/// 木にした形（#118）
test "Graft の中身は、一番深い開いている段の中身" {
  let d = doc([root(h(2, "r"))])
  assert_eq(
    apply(
      d,
      Graft(at=NodePlace::In(node=2, side=None), md="a\n  b\n\n![](p.png)\n"),
    ),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            h(3, "a", children=[
              h(4, "b", body=[pic(6, source=Some("![](p.png)"))]),
            ]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(3),
    }),
  )
}

///|
/// 断片が持ち込むのは形だけ。綴りは席が決める（`sign_at`）。
test "Graft は席の綴りで差す — 見出しの列では見出し、項目の列では項目" {
  // 子が見出しの見出しへ項目 — 見出しの直後の項目は飲み込まれるので、綴り替えないと書けない
  let d = doc([root(h(2, "r", children=[h(3, "a")]), sides=[Right])])
  assert_eq(
    apply(d, Graft(at=NodePlace::In(node=2, side=None), md="- b\n  - c\n")),
    Some({
      doc: doc([
        root(h(2, "r", children=[h(3, "a"), h(4, "b", children=[h(5, "c")])]), sides=[
          Right,
          Right,
        ]),
      ]),
      focus: Some(4),
    }),
  )
  // 子が項目の見出しへ見出し（`##` 始まりの飛びは剥がす。Implicit の id 1 つが飛ぶ）
  let e = doc([root(h(2, "r", children=[item(3, "a")]), sides=[Right])])
  assert_eq(
    apply(e, Graft(at=NodePlace::In(node=2, side=None), md="## b\n\n- c\n")),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            item(3, "a"),
            item(5, "b", children=[item(6, "c")]),
          ]),
          sides=[Right, Right],
        ),
      ]),
      focus: Some(5),
    }),
  )
  // 子の無い見出しへ項目 — 隣がいないので親に従い見出し（Tab と同じ答え）
  let f = doc([root(h(2, "r"))])
  assert_eq(
    apply(f, Graft(at=NodePlace::In(node=2, side=None), md="- b\n")),
    Some({
      doc: doc([root(h(2, "r", children=[h(3, "b")]), sides=[Right])]),
      focus: Some(3),
    }),
  )
  // 根が見出しの文書へ項目 — 最後の根に従って見出しの根
  assert_eq(
    apply(f, Graft(at=NodePlace::In(node=@tree.doc_id, side=None), md="- b\n")),
    Some({ doc: doc([root(h(2, "r")), root(h(3, "b"))]), focus: Some(3), }),
  )
}

///|
test "Graft は空・知らない id に None。項目の下の見出しは項目になる" {
  let d = doc([root(h(2, "r", children=[item(3, "a")]), sides=[Right])])
  assert_eq(apply(d, Graft(at=NodePlace::In(node=2, side=None), md="")), None)
  assert_eq(
    apply(d, Graft(at=NodePlace::In(node=2, side=None), md="  \n\n")),
    None,
  )
  assert_eq(
    apply(d, Graft(at=NodePlace::In(node=9, side=None), md="# p\n")),
    None,
  )
  assert_eq(
    apply(d, Graft(at=NodePlace::In(node=3, side=None), md="# p\n\n## q\n")),
    Some({
      doc: doc([
        root(
          h(2, "r", children=[
            item(3, "a", children=[item(4, "p", children=[item(5, "q")])]),
          ]),
          sides=[Right],
        ),
      ]),
      focus: Some(4),
    }),
  )
}

///|
/// 見出しは 6 段まで（`@tree.deepest`）。7 段目に着地する見出しは項目に綴り替わる —
/// 手で書くときも `######` の下は `- ` でしか続けられない。上の段には触らない。
fn six(tail : Array[@tree.Node]) -> @tree.Doc {
  doc([
    root(
      h(2, "a", children=[
        h(3, "b", children=[
          h(4, "c", children=[
            h(5, "d", children=[h(6, "e", children=[h(7, "f", children=tail)])]),
          ]),
        ]),
      ]),
      sides=[Right],
    ),
  ])
}

///|
test "AddNode は 6 段目の下なら項目で足す" {
  assert_eq(
    apply(six([]), AddNode(at=NodePlace::In(node=7, side=None), label="g")),
    Some({ doc: six([item(8, "g")]), focus: Some(8), }),
  )
}

///|
test "Graft は 6 段目の下なら部分木ごと項目にする。途中の飛びは空の項目" {
  assert_eq(
    apply(
      six([]),
      Graft(at=NodePlace::In(node=7, side=None), md="# p\n\n## q\n\n- i\n"),
    ),
    Some({
      doc: six([item(8, "p", children=[item(9, "q", children=[item(10, "i")])])]),
      focus: Some(8),
    }),
  )
  // `#` → `###` の飛びは Implicit。項目は行を省けないので、空の項目として綴る（形は保つ）
  assert_eq(
    apply(
      six([]),
      Graft(at=NodePlace::In(node=7, side=None), md="# p\n\n### q\n"),
    ),
    Some({
      doc: six([item(8, "p", children=[item(9, "", children=[item(10, "q")])])]),
      focus: Some(8),
    }),
  )
}

///|
test "MoveNode は 6 段目の下へ落とせば見出しを項目にする。Implicit は空の項目になり、focus は残る" {
  let d = six([])
  let x = root(h(8, "x", body=[pic(9)], children=[h(10, "y")]), sides=[Right])
  let e : @tree.Doc = { ..d, roots: [..d.roots, x], }
  assert_eq(
    apply(e, MoveNode(ids=[8], at=NodePlace::In(node=7, side=None))),
    Some({
      doc: six([item(8, "x", body=[pic(9)], children=[item(10, "y")])]),
      focus: Some(8),
    }),
  )
  let g = root(gap(8, [h(9, "z")]), sides=[Right])
  let f : @tree.Doc = { ..d, roots: [..d.roots, g], }
  assert_eq(
    apply(f, MoveNode(ids=[8], at=NodePlace::In(node=7, side=None))),
    Some({ doc: six([item(8, "", children=[item(9, "z")])]), focus: Some(8), }),
  )
}

///|
test "Wrap は 6 段目を包めば、包まれたほうが項目になる" {
  let d = doc([
    root(
      h(2, "a", children=[
        h(3, "b", children=[
          h(4, "c", children=[
            h(5, "d", children=[
              h(6, "e", children=[h(8, "w", children=[item(7, "f")])]),
            ]),
          ]),
        ]),
      ]),
      sides=[Right],
    ),
  ])
  assert_eq(
    apply(six([]), Wrap(id=7, label="w")),
    Some({ doc: d, focus: Some(8), }),
  )
}

///|
/// 代表的な木に、代表的な Op を総当たりで当て、Some ならその結果が
/// check を通ることを見る。落ちた Op と破れを並べる。
/// 境界（`BorderBreak`）だけは通す — 書けば md が境界と読むので、形は読み直しが決める。
test "apply の結果は check を通る（境界は md が決めるので除く）" {
  // 見出しの直後の項目・Implicit は飲み込まれるので、項目を先に置く（check が言う）
  let base = doc([
    root(item(11, "e"), sides=[]),
    root(
      h(2, "r", body=[pic(3)], children=[
        h(4, "a", children=[
          item(7, "b", children=[item(8, "c")]),
          gap(5, [h(6, "x")]),
        ]),
        h(9, "d", body=[code(10)]),
      ]),
      sides=[Right, Left],
    ),
  ])
  json_inspect(@tree.check(base), content=[])
  let bad = []
  let mut some = 0
  for op in ops_for(ids(base)) {
    match apply(base, op) {
      Some(done) => {
        some = some + 1
        let flaws = @tree.check(done.doc).filter(f => !(f is BorderBreak(_)))
        if !flaws.is_empty() {
          bad.push((op, flaws))
        }
      }
      None => ()
    }
  }
  // 全部 None に潰れる退化を落とすための下限チェック。
  inspect(some, content="502")
  json_inspect(bad, content=[])
}

// ══════════════════════════════════════════════════════════════════
// 項目の中は文書 — 綴りは席が決め、深さはその項目から測る
// ══════════════════════════════════════════════════════════════════

///|
/// **mmm は見出しの無い項目に見出しを持ち込まない。** 席の綴りは隣に従い、
/// 隣が居なければ親に従う（項目の下は項目）。md が項目の中に見出しを
/// 書いていれば、その隣だけがそれに従う。
test "項目の中の席の綴りは隣に従う" {
  // 子の無い項目の下は項目
  let lone = doc([root(item(2, "i"))])
  assert_eq(
    apply(lone, AddNode(at=In(node=2, side=None), label="n")),
    Some({
      doc: doc([root(item(2, "i", children=[item(3, "n")]), sides=[Right])]),
      focus: Some(3),
    }),
  )
  // 中に見出しが書かれていれば、その隣も見出し
  let inner = doc([root(item(2, "i", children=[h(3, "x")]), sides=[Right])])
  assert_eq(
    apply(inner, AddNode(at=After(node=3), label="n")),
    Some({
      doc: doc([
        root(item(2, "i", children=[h(3, "x"), h(4, "n")]), sides=[Right, Right]),
      ]),
      focus: Some(4),
    }),
  )
  // 見出しを見出しの無い項目の下へ落とせば項目になる
  let into = doc([root(item(2, "i")), root(h(3, "x"))])
  assert_eq(
    apply(into, MoveNode(ids=[3], at=In(node=2, side=None))),
    Some({
      doc: doc([root(item(2, "i", children=[item(3, "x")]), sides=[Right])]),
      focus: Some(3),
    }),
  )
}

///|
/// 隣が居なければ**種類**は親に従う（項目の下は項目）が、**マーカーと桁**は親を見ず既定 —
/// `sign_at` は親に落ち、`spell_at` は落ちない。`* a` の下に足せば `- n`。
/// 揃えるかは別の問い（issue にする）。ここは今の答えを固定するだけ
test "子の無い項目の下に足せば項目だが、マーカーは親のものでなく既定" {
  let d = doc([root(item(2, "a", marker="*"))])
  assert_eq(
    apply(d, AddNode(at=In(node=2, side=None), label="n")),
    Some({
      doc: doc([
        root(item(2, "a", marker="*", children=[item(3, "n")]), sides=[Right]),
      ]),
      focus: Some(3),
    }),
  )
}

///|
/// **天井も項目から測る。** 項目の中の見出しは `#` 1 本から始まるので、
/// 7 本目に着地する部分木だけが項目に綴り替わる。
test "項目の中の見出しの天井は、その項目から測る" {
  fn chain(depth : Int, tip : @tree.Node) -> @tree.Node {
    let mut n = tip
    for i in 0..<depth {
      n = h(20 + depth - i, "h", children=[n])
    }
    n
  }

  // 項目 > 見出し 6 段まではそのまま
  let under = doc([
    root(item(2, "i", children=[chain(5, h(3, "z"))]), sides=[Right]),
  ])
  assert_eq(apply(under, Rename(id=3, label="z")).map(d => d.doc), Some(under))
  // 7 段目に着けば、その部分木は項目になる
  let seven = doc([
    root(item(2, "i", children=[chain(6, h(3, "z"))]), sides=[Right]),
  ])
  let capped = apply(seven, Rename(id=3, label="z")).unwrap().doc
  // 書いた字を読み直しても同じ木（`- z` は `###### h` の子のまま）
  assert_eq(
    @tree.shape(@tree.parse(@tree.serialize(capped))),
    @tree.shape(capped),
  )
  inspect(
    @tree.serialize(capped),
    content=(
      #|- i
      #|  # h
      #|
      #|  ## h
      #|
      #|  ### h
      #|
      #|  #### h
      #|
      #|  ##### h
      #|
      #|  ###### h
      #|
      #|  - z
      #|
    ),
  )
}

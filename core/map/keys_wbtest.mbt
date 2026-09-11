// キー → 何をするか。DOM も host も知らない表。

///|
fn k(
  key : String,
  shift? : Bool = false,
  mod? : Bool = false,
  alt? : Bool = false,
) -> Key {
  { key, shift, mod, alt, }
}

///|
fn many(ids : Array[Int], anchor : Int) -> Selection {
  { ids, anchor: Some(anchor), }
}

///|
/// r(2) → a(3), 空(4)。空は綴りのある label ""
fn keys_l() -> Layout {
  layout(
    [
      root(node(2, "r", children=[node(3, "a"), node(4, "")]), sides=[
        Right,
        Right,
      ]),
    ],
    size,
  )
}

///|
/// r(2) → Implicit(3)。綴りが無いノードだけの木
fn keys_gap() -> Layout {
  layout(
    [root(node(2, "r", children=[node(3, "", mark=None)]), sides=[Right])],
    size,
  )
}

///|
let empty_op : Intent = Op(
  op=AddNode(at=In(node=@tree.doc_id, side=None), labels=[""]),
  edit=true,
)

///|
test "Enter — 名前のあるノードなら下に兄弟を足して編集、空なら足さずに埋める" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Enter")),
    Some(Op(op=AddNode(at=After(node=3), labels=[""]), edit=true)),
  )
  assert_eq(
    keyed(l, Selection::only(4), k("Enter")),
    Some(Edit(id=4, seed=None)),
  )
  // 何も選んでいなければ拾わない
  assert_eq(keyed(l, none, k("Enter")), None)
}

///|
/// **Implicit は「空」ではない。** 綴りの無いノードは、名前より先に綴りを当てる
/// 操作が要るので、埋めずに兄弟を足す。打ち始めもしない
test "Enter と打鍵 — Implicit は埋める側に回らない" {
  let g = keys_gap()
  assert_eq(
    keyed(g, Selection::only(3), k("Enter")),
    Some(Op(op=AddNode(at=After(node=3), labels=[""]), edit=true)),
  )
  assert_eq(keyed(g, Selection::only(3), k("x")), None)
}

///|
test "Shift+Enter は上に兄弟。Tab は子。Shift+Tab は親で包む。どれも編集開始" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Enter", shift=true)),
    Some(Op(op=AddNode(at=Before(node=3), labels=[""]), edit=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("Tab")),
    Some(Op(op=AddNode(at=In(node=3, side=None), labels=[""]), edit=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("Tab", shift=true)),
    Some(Op(op=Wrap(id=3, label=""), edit=true)),
  )
}

///|
test "ノードが 1 つも無ければ Enter は最初の根" {
  let empty = layout([], size)
  assert_eq(keyed(empty, none, k("Enter")), Some(empty_op))
  assert_eq(keyed(empty, none, k("Enter", mod=true)), Some(empty_op))
}

///|
test "Mod+Enter は anchor の編集開始。いくつ選んでいても同じ" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Enter", mod=true)),
    Some(Edit(id=3, seed=None)),
  )
  assert_eq(
    keyed(l, many([3, 4], 4), k("Enter", mod=true)),
    Some(Edit(id=4, seed=None)),
  )
  assert_eq(keyed(l, none, k("Enter", mod=true)), None)
}

///|
test "空のノードで字を打てば、その字から編集。名前があれば何もしない。Space は除く" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(4), k("x")),
    Some(Edit(id=4, seed=Some("x"))),
  )
  assert_eq(
    keyed(l, Selection::only(4), k("X", shift=true)),
    Some(Edit(id=4, seed=Some("X"))),
  )
  assert_eq(keyed(l, Selection::only(3), k("x")), None)
  assert_eq(keyed(l, Selection::only(4), k(" ")), None)
  assert_eq(keyed(l, Selection::only(4), k("q", mod=true)), None)
}

///|
test "複数選んでいるときの Tab / Shift+Tab は段下げ・上げ。先頭に前の兄弟が無ければ Tab は拾わない" {
  let l = keys_l()
  assert_eq(keyed(l, many([3, 4], 4), k("Tab")), None)
  assert_eq(
    keyed(l, many([3, 4], 4), k("Tab", shift=true)),
    Some(Op(op=MoveNode(ids=[3, 4], at=After(node=2)), edit=false)),
  )
  assert_eq(keyed(l, none, k("Tab")), None)
}

///|
test "複数選んでいても宛先は anchor — 1 つ選んでいるときと同じ" {
  let l = keys_l()
  // anchor に名前があれば後ろに足す
  assert_eq(
    keyed(l, many([3, 4], 3), k("Enter")),
    Some(Op(op=AddNode(at=After(node=3), labels=[""]), edit=true)),
  )
  // anchor が空なら「埋めるが先」も同じに効く
  assert_eq(keyed(l, many([3, 4], 4), k("Enter")), Some(Edit(id=4, seed=None)))
  assert_eq(keyed(l, many([3, 4], 4), k("x")), Some(Edit(id=4, seed=Some("x"))))
}

///|
test "矢印は select、Shift+矢印は伸ばす、Esc は解除、Mod+A は全部、Home は寄せ" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("ArrowDown")),
    Some(Select(sel=Selection::only(4), reveal=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("ArrowDown", shift=true)),
    Some(Select(sel=many([3, 4], 4), reveal=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("Escape")),
    Some(Select(sel=none, reveal=false)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("a", mod=true)),
    Some(Select(sel=many([2, 3, 4], 4), reveal=false)),
  )
  assert_eq(keyed(l, Selection::only(3), k("Home")), Some(Center))
  // 根で ← は行き先が無い → 拾わない
  assert_eq(keyed(l, Selection::only(2), k("ArrowLeft")), None)
}

///|
test "拾わないキーは None（ブラウザに渡す）" {
  let l = keys_l()
  assert_eq(keyed(l, Selection::only(3), k("F5")), None)
  assert_eq(keyed(l, Selection::only(3), k("Enter", alt=true)), None)
}

///|
test "Delete は選択を消す。隣を選ぶのは core の focus" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Delete")),
    Some(Op(op=Delete(ids=[3]), edit=false)),
  )
  assert_eq(
    keyed(l, many([3, 4], 4), k("Backspace")),
    Some(Op(op=Delete(ids=[3, 4]), edit=false)),
  )
  assert_eq(keyed(l, none, k("Delete")), None)
}

///|
test "Mod+C は写す。Mod+X は写してから Delete と同じ消し方" {
  let l = keys_l()
  assert_eq(keyed(l, many([3, 4], 4), k("c", mod=true)), Some(Copy(cut=None)))
  assert_eq(
    keyed(l, Selection::only(3), k("x", mod=true)),
    Some(Copy(cut=Some(Op(op=Delete(ids=[3]), edit=false)))),
  )
  // 何も選んでいなければ拾わない（ブラウザに渡す）
  assert_eq(keyed(l, none, k("c", mod=true)), None)
  assert_eq(keyed(l, none, k("x", mod=true)), None)
  // Shift の組は別の意味に空けておく
  assert_eq(keyed(l, Selection::only(3), k("C", mod=true, shift=true)), None)
}

///|
test "Alt+↑↓ は塊を前の兄弟の前 / 次の兄弟の後ろへ。端では拾わない" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(4), k("ArrowUp", alt=true)),
    Some(Op(op=MoveNode(ids=[4], at=Before(node=3)), edit=false)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("ArrowDown", alt=true)),
    Some(Op(op=MoveNode(ids=[3], at=After(node=4)), edit=false)),
  )
  assert_eq(keyed(l, Selection::only(3), k("ArrowUp", alt=true)), None)
  assert_eq(keyed(l, Selection::only(4), k("ArrowDown", alt=true)), None)
}

///|
test "複数選択の Tab は先頭の前の兄弟の子へ、Shift+Tab は先頭の親の後ろへ" {
  // r(2) → a(3), b(4) → c(5), d(6)
  let m = layout(
    [
      root(
        node(2, "r", children=[
          node(3, "a"),
          node(4, "b", children=[node(5, "c"), node(6, "d")]),
        ]),
        sides=[Right, Right],
      ),
    ],
    size,
  )
  assert_eq(
    keyed(m, many([5, 6], 6), k("Tab", shift=true)),
    Some(Op(op=MoveNode(ids=[5, 6], at=After(node=4)), edit=false)),
  )
  assert_eq(
    keyed(m, many([4, 6], 6), k("Tab")),
    Some(Op(op=MoveNode(ids=[4, 6], at=In(node=3, side=None)), edit=false)),
  )
  // 先頭 a(3) に前の兄弟は無い / 根の親は無い
  assert_eq(keyed(m, many([3, 4], 4), k("Tab")), None)
  assert_eq(keyed(m, many([2, 3], 3), k("Tab", shift=true)), None)
}

///|
/// 畳みは 1 歩ずつ巡る: 畳む（閉）→ 開く（`<details open>`）→ 外す。Implicit も畳む
/// （core が綴る）。無選択は拾わない。`H` はもう畳みではない
test "Shift+F は畳む → 開く → 外す、を巡る。Implicit も畳む。無選択は拾わない" {
  // r(2) → a(3。閉じた畳み), Implicit(4) → x(5), o(6。開いた畳み)
  let f = layout(
    [
      root(
        node(2, "r", children=[
          node(3, "a", fold=Some({ open: false, summary: Some("a"), })),
          node(4, "", mark=None, children=[node(5, "x")]),
          node(6, "o", fold=Some({ open: true, summary: Some("o"), })),
        ]),
        sides=[Right, Right, Right],
      ),
    ],
    size,
  )
  assert_eq(
    keyed(f, Selection::only(2), k("F", shift=true)),
    Some(Op(op=Fold(id=2, open=false), edit=false)),
  )
  assert_eq(
    keyed(f, Selection::only(3), k("F", shift=true)),
    Some(Op(op=Fold(id=3, open=true), edit=false)),
  )
  assert_eq(
    keyed(f, Selection::only(6), k("F", shift=true)),
    Some(Op(op=Unfold(id=6), edit=false)),
  )
  assert_eq(
    keyed(f, Selection::only(4), k("F", shift=true)),
    Some(Op(op=Fold(id=4, open=false), edit=false)),
  )
  assert_eq(keyed(f, none, k("F", shift=true)), None)
  assert_eq(keyed(f, Selection::only(2), k("H", shift=true)), None)
}

///|
test "Shift+L / Shift+C / Shift+D は 1 つ選んでいるときだけ拾う" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("L", shift=true)),
    Some(AddLink(id=3)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("C", shift=true)),
    Some(AddCode(id=3)),
  )
  assert_eq(keyed(l, Selection::only(3), k("D", shift=true)), Some(Draw(id=3)))
  assert_eq(keyed(l, many([3, 4], 4), k("L", shift=true)), None)
  assert_eq(keyed(l, none, k("L", shift=true)), None)
}

///|
test "Mod+V は貼り付け。anchor が無くても拾う" {
  let l = keys_l()
  assert_eq(keyed(l, Selection::only(3), k("v", mod=true)), Some(Paste))
  assert_eq(keyed(l, none, k("v", mod=true)), Some(Paste))
  // 大文字でも同じ（key 自体は大文字で来ることがある）
  assert_eq(keyed(l, none, k("V", mod=true)), Some(Paste))
  // Shift+Mod+V は別の意味に空けておく（貼り付けとして拾わない）
  assert_eq(keyed(l, Selection::only(3), k("v", mod=true, shift=true)), None)
}

// ---- keyed_card — カードを選んでいるときの表 ----
// r(2) に blocks [3: 水平線, 4: mailto リンク, 5: コード]。カードになるのは 3 と 5 で、
// **隣はカードの隣** — 4 はカードにならないので、どの一手にも出てこない

///|
fn keys_c() -> Layout {
  layout(
    [
      root(
        node(2, "r", body=[
          { id: 3, source: None, content: Some(ThematicBreak), },
          {
            id: 4,
            source: None,
            content: Some(Link(text="m", href="mailto:a@b", title="")),
          },
          { id: 5, source: None, content: Some(Code(info="", text="x")), },
        ]),
      ),
    ],
    size,
  )
}

///|
test "keyed_card: Delete / Backspace はそのカードを消す（持ち主を選ぶのは core の focus）" {
  let c = keys_c()
  assert_eq(
    keyed_card(c, 3, k("Delete")),
    Some(Op(op=Delete(ids=[3]), edit=false)),
  )
  assert_eq(
    keyed_card(c, 5, k("Backspace")),
    Some(Op(op=Delete(ids=[5]), edit=false)),
  )
}

///|
test "keyed_card: ↑↓ は隣のカードを選ぶ。端では拾うが動かない。← は持ち主のノード" {
  let c = keys_c()
  assert_eq(keyed_card(c, 3, k("ArrowDown")), Some(Pick(id=Some(5))))
  // 端は Stop — 次の行へ落とさない（#244）。`keyed` と同じく、Stop は None で表に出る
  assert_eq(keyed_card(c, 5, k("ArrowDown")), None)
  assert_eq(keyed_card(c, 5, k("ArrowUp")), Some(Pick(id=Some(3))))
  assert_eq(keyed_card(c, 3, k("ArrowUp")), None)
  assert_eq(
    keyed_card(c, 3, k("ArrowLeft")),
    Some(Select(sel=Selection::only(2), reveal=false)),
  )
}

///|
test "keyed_card: Alt+↑↓ は前後のカードの前後へ並べ替え。端では拾わない" {
  let c = keys_c()
  assert_eq(
    keyed_card(c, 5, k("ArrowUp", alt=true)),
    Some(Op(op=MoveBlock(ids=[5], at=Before(block=3)), edit=false)),
  )
  assert_eq(keyed_card(c, 3, k("ArrowUp", alt=true)), None)
  assert_eq(
    keyed_card(c, 3, k("ArrowDown", alt=true)),
    Some(Op(op=MoveBlock(ids=[3], at=After(block=5)), edit=false)),
  )
  assert_eq(keyed_card(c, 5, k("ArrowDown", alt=true)), None)
}

///|
test "keyed_card: Mod+Enter はその場編集。Escape は外す。Mod+C / Mod+X。持ち主が無ければ None" {
  let c = keys_c()
  assert_eq(keyed_card(c, 3, k("Enter", mod=true)), Some(EditCard(id=3)))
  assert_eq(keyed_card(c, 3, k("Escape")), Some(Pick(id=None)))
  assert_eq(keyed_card(c, 3, k("c", mod=true)), Some(Copy(cut=None)))
  assert_eq(
    keyed_card(c, 5, k("x", mod=true)),
    Some(Copy(cut=Some(Op(op=Delete(ids=[5]), edit=false)))),
  )
  // 居ない中身も、カードにならなかった中身（4）も、持ち主を持たない
  assert_eq(keyed_card(c, 99, k("Delete")), None)
  assert_eq(keyed_card(c, 4, k("Delete")), None)
}

///|
/// **Escape は 1 段ずつ外へ。** 選んでいれば解き、解くものが無ければ帯へ抜ける。
/// ペインは Tab を飲む（子を足す・字下げ）ので、キーボードだけで帯へ戻る道はこれ 1 つ
test "Escape は選択を解き、解くものが無ければ帯へ抜ける" {
  // 選んでいるときの Escape と、カードの Escape は上の表が当てている
  assert_eq(keyed(keys_l(), none, k("Escape")), Some(Leave))
}

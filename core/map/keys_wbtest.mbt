// キー → 何をするか。DOM も host も知らない表。答えは 3 つ — Do（拾った）・
// Pass（拾わない。ブラウザへ）・Stop（拾ったが、いまはできない。ブラウザにも渡さない）

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
  op=AddNode(at=In(node=@tree.doc_id, side=None), label=""),
  edit=true,
)

///|
test "Enter — 名前のあるノードなら下に兄弟を足して編集、空なら足さずに埋める" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Enter")),
    Do(Op(op=AddNode(at=After(node=3), label=""), edit=true)),
  )
  assert_eq(keyed(l, Selection::only(4), k("Enter")), Do(Edit(id=4, seed=None)))
  // 何も選んでいなければ、拾うが足す先が無い
  assert_eq(keyed(l, none, k("Enter")), Stop)
}

///|
/// **Implicit は「空」ではない。** 綴りの無いノードは、名前より先に綴りを当てる
/// 操作が要るので、埋めずに兄弟を足す。打ち始めもしない
test "Enter と打鍵 — Implicit は埋める側に回らない" {
  let g = keys_gap()
  assert_eq(
    keyed(g, Selection::only(3), k("Enter")),
    Do(Op(op=AddNode(at=After(node=3), label=""), edit=true)),
  )
  assert_eq(keyed(g, Selection::only(3), k("x")), Pass)
}

///|
test "Shift+Enter は上に兄弟。Tab は子。Shift+Tab は親で包む。どれも編集開始" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Enter", shift=true)),
    Do(Op(op=AddNode(at=Before(node=3), label=""), edit=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("Tab")),
    Do(Op(op=AddNode(at=In(node=3, side=None), label=""), edit=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("Tab", shift=true)),
    Do(Op(op=Wrap(id=3, label=""), edit=true)),
  )
}

///|
test "ノードが 1 つも無ければ Enter は最初の根" {
  let empty = layout([], size)
  assert_eq(keyed(empty, none, k("Enter")), Do(empty_op))
  assert_eq(keyed(empty, none, k("Enter", mod=true)), Do(empty_op))
}

///|
test "Mod+Enter は anchor の編集開始。いくつ選んでいても同じ" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Enter", mod=true)),
    Do(Edit(id=3, seed=None)),
  )
  assert_eq(
    keyed(l, many([3, 4], 4), k("Enter", mod=true)),
    Do(Edit(id=4, seed=None)),
  )
  assert_eq(keyed(l, none, k("Enter", mod=true)), Stop)
}

///|
test "空のノードで字を打てば、その字から編集。名前があれば何もしない。Space は除く" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(4), k("x")),
    Do(Edit(id=4, seed=Some("x"))),
  )
  assert_eq(
    keyed(l, Selection::only(4), k("X", shift=true)),
    Do(Edit(id=4, seed=Some("X"))),
  )
  assert_eq(keyed(l, Selection::only(3), k("x")), Pass)
  assert_eq(keyed(l, Selection::only(4), k(" ")), Pass)
  assert_eq(keyed(l, Selection::only(4), k("q", mod=true)), Pass)
}

///|
test "複数選んでいるときの Tab / Shift+Tab は段下げ・上げ。先頭に前の兄弟が無ければ Tab は止まる" {
  let l = keys_l()
  assert_eq(keyed(l, many([3, 4], 4), k("Tab")), Stop)
  assert_eq(
    keyed(l, many([3, 4], 4), k("Tab", shift=true)),
    Do(Op(op=MoveNode(ids=[3, 4], at=After(node=2)), edit=false)),
  )
  assert_eq(keyed(l, none, k("Tab")), Stop)
}

///|
test "複数選んでいても宛先は anchor — 1 つ選んでいるときと同じ" {
  let l = keys_l()
  // anchor に名前があれば後ろに足す
  assert_eq(
    keyed(l, many([3, 4], 3), k("Enter")),
    Do(Op(op=AddNode(at=After(node=3), label=""), edit=true)),
  )
  // anchor が空なら「埋めるが先」も同じに効く
  assert_eq(keyed(l, many([3, 4], 4), k("Enter")), Do(Edit(id=4, seed=None)))
  assert_eq(keyed(l, many([3, 4], 4), k("x")), Do(Edit(id=4, seed=Some("x"))))
}

///|
test "矢印は select、Shift+矢印は伸ばす、Esc は解除、Mod+A は全部、Home は寄せ" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("ArrowDown")),
    Do(Select(sel=Selection::only(4), reveal=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("ArrowDown", shift=true)),
    Do(Select(sel=many([3, 4], 4), reveal=true)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("Escape")),
    Do(Select(sel=none, reveal=false)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("a", mod=true)),
    Do(Select(sel=many([2, 3, 4], 4), reveal=false)),
  )
  assert_eq(keyed(l, Selection::only(3), k("Home")), Do(Center))
  // 根で ← は行き先が無い → 拾うが動かない
  assert_eq(keyed(l, Selection::only(2), k("ArrowLeft")), Stop)
}

///|
test "拾わないキーは Pass（ブラウザに渡す）。Alt の組は Alt+↑↓ の行が閉じる" {
  let l = keys_l()
  assert_eq(keyed(l, Selection::only(3), k("F5")), Pass)
  assert_eq(keyed(l, Selection::only(3), k("Enter", alt=true)), Stop)
}

///|
test "Delete は選択を消す。隣を選ぶのは core の focus" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(3), k("Delete")),
    Do(Op(op=Delete(ids=[3]), edit=false)),
  )
  assert_eq(
    keyed(l, many([3, 4], 4), k("Backspace")),
    Do(Op(op=Delete(ids=[3, 4]), edit=false)),
  )
  assert_eq(keyed(l, none, k("Delete")), Stop)
}

///|
test "Mod+C は写す。Mod+X は写してから Delete と同じ消し方" {
  let l = keys_l()
  assert_eq(keyed(l, many([3, 4], 4), k("c", mod=true)), Do(Copy(cut=None)))
  assert_eq(
    keyed(l, Selection::only(3), k("x", mod=true)),
    Do(Copy(cut=Some(Op(op=Delete(ids=[3]), edit=false)))),
  )
  // 何も選んでいなければ拾わない（ブラウザに渡す）
  assert_eq(keyed(l, none, k("c", mod=true)), Pass)
  assert_eq(keyed(l, none, k("x", mod=true)), Pass)
  // Shift の組は別の意味に空けておく
  assert_eq(keyed(l, Selection::only(3), k("C", mod=true, shift=true)), Pass)
}

///|
test "Alt+↑↓ は塊を前の兄弟の前 / 次の兄弟の後ろへ。端では止まる" {
  let l = keys_l()
  assert_eq(
    keyed(l, Selection::only(4), k("ArrowUp", alt=true)),
    Do(Op(op=MoveNode(ids=[4], at=Before(node=3)), edit=false)),
  )
  assert_eq(
    keyed(l, Selection::only(3), k("ArrowDown", alt=true)),
    Do(Op(op=MoveNode(ids=[3], at=After(node=4)), edit=false)),
  )
  assert_eq(keyed(l, Selection::only(3), k("ArrowUp", alt=true)), Stop)
  assert_eq(keyed(l, Selection::only(4), k("ArrowDown", alt=true)), Stop)
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
    Do(Op(op=MoveNode(ids=[5, 6], at=After(node=4)), edit=false)),
  )
  assert_eq(
    keyed(m, many([4, 6], 6), k("Tab")),
    Do(Op(op=MoveNode(ids=[4, 6], at=In(node=3, side=None)), edit=false)),
  )
  // 先頭 a(3) に前の兄弟は無い / 根の親は無い
  assert_eq(keyed(m, many([3, 4], 4), k("Tab")), Stop)
  assert_eq(keyed(m, many([2, 3], 3), k("Tab", shift=true)), Stop)
}

///|
/// 畳みは 1 歩ずつ巡る: 畳む（閉）→ 開く（`<details open>`）→ 外す。Implicit も畳む
/// （core が綴る）。無選択は止まる。`H` はもう畳みではない
test "Shift+F は畳む → 開く → 外す、を巡る。Implicit も畳む。無選択は止まる" {
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
    Do(Op(op=Fold(id=2, open=false), edit=false)),
  )
  assert_eq(
    keyed(f, Selection::only(3), k("F", shift=true)),
    Do(Op(op=Fold(id=3, open=true), edit=false)),
  )
  assert_eq(
    keyed(f, Selection::only(6), k("F", shift=true)),
    Do(Op(op=Unfold(id=6), edit=false)),
  )
  assert_eq(
    keyed(f, Selection::only(4), k("F", shift=true)),
    Do(Op(op=Fold(id=4, open=false), edit=false)),
  )
  assert_eq(keyed(f, none, k("F", shift=true)), Stop)
  assert_eq(keyed(f, Selection::only(2), k("H", shift=true)), Pass)
}

///|
test "Shift+L / Shift+C / Shift+D は 1 つ選んでいるときだけ拾う" {
  let l = keys_l()
  assert_eq(keyed(l, Selection::only(3), k("L", shift=true)), Do(AddLink(id=3)))
  assert_eq(keyed(l, Selection::only(3), k("C", shift=true)), Do(AddCode(id=3)))
  assert_eq(keyed(l, Selection::only(3), k("D", shift=true)), Do(Draw(id=3)))
  assert_eq(keyed(l, many([3, 4], 4), k("L", shift=true)), Stop)
  assert_eq(keyed(l, none, k("L", shift=true)), Stop)
}

///|
test "Mod+V は貼り付け。anchor が無くても拾う" {
  let l = keys_l()
  assert_eq(keyed(l, Selection::only(3), k("v", mod=true)), Do(Paste))
  assert_eq(keyed(l, none, k("v", mod=true)), Do(Paste))
  // 大文字でも同じ（key 自体は大文字で来ることがある）
  assert_eq(keyed(l, none, k("V", mod=true)), Do(Paste))
  // Shift+Mod+V は別の意味に空けておく（貼り付けとして拾わない）
  assert_eq(keyed(l, Selection::only(3), k("v", mod=true, shift=true)), Pass)
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
    Do(Op(op=Delete(ids=[3]), edit=false)),
  )
  assert_eq(
    keyed_card(c, 5, k("Backspace")),
    Do(Op(op=Delete(ids=[5]), edit=false)),
  )
}

///|
test "keyed_card: ↑↓ は隣のカードを選ぶ。端では拾うが動かない。← は持ち主のノード" {
  let c = keys_c()
  assert_eq(keyed_card(c, 3, k("ArrowDown")), Do(Pick(id=Some(5))))
  // 端は Stop — 次の行へ落とさず、ブラウザにも渡さない（#244）
  assert_eq(keyed_card(c, 5, k("ArrowDown")), Stop)
  assert_eq(keyed_card(c, 5, k("ArrowUp")), Do(Pick(id=Some(3))))
  assert_eq(keyed_card(c, 3, k("ArrowUp")), Stop)
  assert_eq(
    keyed_card(c, 3, k("ArrowLeft")),
    Do(Select(sel=Selection::only(2), reveal=false)),
  )
}

///|
test "keyed_card: Alt+↑↓ は前後のカードの前後へ並べ替え。端では止まる" {
  let c = keys_c()
  assert_eq(
    keyed_card(c, 5, k("ArrowUp", alt=true)),
    Do(Op(op=MoveBlock(ids=[5], at=Before(block=3)), edit=false)),
  )
  assert_eq(keyed_card(c, 3, k("ArrowUp", alt=true)), Stop)
  assert_eq(
    keyed_card(c, 3, k("ArrowDown", alt=true)),
    Do(Op(op=MoveBlock(ids=[3], at=After(block=5)), edit=false)),
  )
  assert_eq(keyed_card(c, 5, k("ArrowDown", alt=true)), Stop)
}

///|
test "keyed_card: Mod+Enter はその場編集。Escape は外す。Mod+C / Mod+X。持ち主が無ければ Pass" {
  let c = keys_c()
  assert_eq(keyed_card(c, 3, k("Enter", mod=true)), Do(EditCard(id=3)))
  assert_eq(keyed_card(c, 3, k("Escape")), Do(Pick(id=None)))
  assert_eq(keyed_card(c, 3, k("c", mod=true)), Do(Copy(cut=None)))
  assert_eq(
    keyed_card(c, 5, k("x", mod=true)),
    Do(Copy(cut=Some(Op(op=Delete(ids=[5]), edit=false)))),
  )
  // 居ない中身も、カードにならなかった中身（4）も、持ち主を持たない
  assert_eq(keyed_card(c, 99, k("Delete")), Pass)
  assert_eq(keyed_card(c, 4, k("Delete")), Pass)
}

///|
/// **Escape は 1 段ずつ外へ。** 選んでいれば解き、解くものが無ければ帯へ抜ける。
/// ペインは Tab を飲む（子を足す・字下げ）ので、キーボードだけで帯へ戻る道はこれ 1 つ
test "Escape は選択を解き、解くものが無ければ帯へ抜ける" {
  // 選んでいるときの Escape と、カードの Escape は上の表が当てている
  assert_eq(keyed(keys_l(), none, k("Escape")), Do(Leave))
}

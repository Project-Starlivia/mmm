// 右クリックの行。Intent の表で、沈む行は理由を持つ。

///|
/// r(2) → a(3。畳んである), Implicit(4) → x(5)
fn ctx_l() -> Layout {
  layout(
    [
      root(
        node(2, "r", children=[
          node(3, "a", fold=Some({ open: false, summary: Some("a"), })),
          {
            id: 4,
            label: None,
            fold: None,
            blocks: [],
            children: [node(5, "x")],
          },
        ]),
        sides=[Right, Right],
      ),
    ],
    size,
  )
}

///|
fn labels(es : Array[Entry]) -> Array[String] {
  es.map(e => {
    match e {
      Sep => "—"
      Item(i) => i.label
    }
  })
}

///|
fn row(es : Array[Entry], label : String) -> Item {
  for e in es {
    match e {
      Item(i) => if i.label == label { return i }
      Sep => ()
    }
  }
  abort("\{label} が無い")
}

///|
test "並び — Add / Rename / Hide / Flip side / Link / Code / Draw / Copy / Cut / Paste / Delete" {
  assert_eq(labels(items(ctx_l(), one(3))), [
    "Add", "Rename", "—", "Show (unfold)", "Flip side", "—", "Link", "Code",
    "Draw", "—", "Copy", "Cut", "Paste", "—", "Delete",
  ])
}

///|
test "Copy / Cut はキーと同じ Intent。選んでいなければ沈み、Paste は沈まない" {
  let es = items(ctx_l(), many([3, 5], 5))
  assert_eq(row(es, "Copy").intent, Some(Copy(cut=None)))
  // Cut の消し方は Delete の行そのもの
  assert_eq(row(es, "Cut").intent, Some(Copy(cut=row(es, "Delete").intent)))
  assert_eq(row(es, "Paste").intent, Some(Paste))
  let no = items(ctx_l(), none)
  assert_eq(row(no, "Copy").intent, None)
  assert_eq(row(no, "Cut").intent, None)
  assert_eq(row(no, "Paste").intent, Some(Paste))
}

///|
test "Add は押せば子、開けば 4 つ" {
  let add = row(items(ctx_l(), one(3)), "Add")
  assert_eq(
    add.intent,
    Some(Op(op=AddNode(at=In(node=3, side=None), labels=[""]), edit=true)),
  )
  assert_eq(add.items.unwrap().map(i => i.label), [
    "Child", "Below", "Above", "Parent",
  ])
  // 名前の無いノードでも Below は「足す」（Enter のように「埋める」へ化けない）
  let blank = row(items(ctx_l(), one(4)), "Add").items.unwrap()[1]
  assert_eq(blank.label, "Below")
  assert_eq(
    blank.intent,
    Some(Op(op=AddNode(at=After(node=4), labels=[""]), edit=true)),
  )
}

///|
test "複数選択では宛先が 1 つの行が沈む。Delete は沈まない" {
  let es = items(ctx_l(), many([3, 5], 5))
  assert_eq(row(es, "Add").intent, None)
  assert_eq(row(es, "Add").why, Some("Select one node"))
  assert_eq(row(es, "Rename").why, Some("Select one node"))
  assert_eq(row(es, "Link").why, Some("Select one node"))
  assert_true(row(es, "Delete").intent is Some(_))
}

///|
test "Implicit も畳める。根は側を持たない" {
  assert_eq(
    row(items(ctx_l(), one(4)), "Hide (fold)").intent,
    Some(Op(op=Fold(id=4, open=false), edit=false)),
  )
  assert_eq(
    row(items(ctx_l(), one(2)), "Flip side").why,
    Some("The root has no side"),
  )
  assert_eq(
    row(items(ctx_l(), one(5)), "Flip side").intent,
    Some(Op(op=FlipSide(id=5), edit=false)),
  )
}

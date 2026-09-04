// md と操作の境界を固定する。入力が md なので、ここだけは読みに依存する。
// 見るのは「編集を当てた md」の正規形と focus — 編集の切り方（空行を
// どこまで残すか）は反映の試験のもの。

///|
fn applied(md : String, op : @op.Op) -> (String, Int?) {
  let r = edit(md, op)
  (@tree.serialize(@tree.parse(@tree.apply(md, r.edits))), r.focus)
}

///|
test "Rename — 編集を当てれば名前が替わり、focus はそのノード" {
  assert_eq(applied("# a\n", Rename(id=2, label="b")), ("# b\n", Some(2)))
}

///|
test "できない操作 — 編集は無く、focus も無い" {
  assert_eq(edit("# a\n", Rename(id=9, label="b")), { edits: [], focus: None })
}

///|
test "AddNode — 新しいノードの focus は、読み直したときの番号" {
  // 操作は max+1 の 4 を振るが、a と b の間に差さるので読み直せば 3
  assert_eq(
    applied("# a\n\n# b\n", AddNode(at=After(node=2), labels=["n"])),
    ("# a\n\n# n\n\n# b\n", Some(3)),
  )
}

///|
test "Delete — 消した後は focus が無い" {
  assert_eq(applied("# a\n\n# b\n", Delete(ids=[3])), ("# a\n", None))
}

///|
/// ts が送る形。Op は ToJson の形をそのまま FromJson で受ける。
test "Op は JSON から起こせる — 席の side の None は鍵ごと落ちる" {
  let ops : Array[@op.Op] = [
    AddNode(at=In(node=2, side=None), labels=["n"]),
    AddNode(at=In(node=2, side=Some(Left)), labels=["n"]),
    MoveBlock(ids=[3, 4], at=Before(block=5)),
    AddBlock(at=In(node=2), content=Code(info="js", text="1\n")),
    Fold(id=2, open=false),
  ]
  for op in ops {
    let back : @op.Op = @json.from_json(op.to_json())
    assert_eq(back, op)
  }
  inspect(
    ops[0].to_json().stringify(),
    content=(
      #|["AddNode",{"at":["In",{"node":2}],"labels":["n"]}]
    ),
  )
  inspect(
    ops[1].to_json().stringify(),
    content=(
      #|["AddNode",{"at":["In",{"node":2,"side":"Left"}],"labels":["n"]}]
    ),
  )
  inspect(
    ops[3].to_json().stringify(),
    content=(
      #|["AddBlock",{"at":["In",{"node":2}],"content":["Code",{"info":"js","text":"1\n"}]}]
    ),
  )
}

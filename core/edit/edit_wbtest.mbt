// md と操作の境界を固定する。入力が md なので、ここだけは読みに依存する。
// 見るのは「編集を当てた md」の正規形と focus — 編集の切り方（空行を
// どこまで残すか）は合流の試験のもの。

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
test "Rename — 名前の字はそのまま md に置かれ、読み直しても同じ" {
  assert_eq(
    applied("# a\n", Rename(id=2, label="foo_bar")),
    ("# foo_bar\n", Some(2)),
  )
  assert_eq(
    applied("# a\n", Rename(id=2, label="__init__")),
    ("# __init__\n", Some(2)),
  )
  assert_eq(applied("- a\n", Rename(id=2, label="2*3")), ("- 2*3\n", Some(2)))
}

///|
/// 項目の名前 `---` は md では水平線。項目は無くなり、`a` の中身の水平線になる。
/// 木と md の形が食い違うので focus は無い（番号のまま返すと別のノードを指す）
test "Rename — 書いた md が別の形に読まれるなら focus は無い" {
  assert_eq(
    applied("# a\n\n- b\n", Rename(id=3, label="---")),
    ("# a\n\n---\n", None),
  )
}

///|
test "できない操作 — 編集は無く、focus も無い" {
  assert_eq(edit("# a\n", Rename(id=9, label="b")), { edits: [], focus: None, })
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
test "Delete — 消した後は隣が focus。最後の根なら無い" {
  assert_eq(applied("# a\n\n# b\n", Delete(ids=[3])), ("# a\n", Some(2)))
  assert_eq(applied("# a\n", Delete(ids=[2])), ("", None))
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

///|
/// 貼り付けは Graft そのもの（TS は raw を送るだけ）。断片が持ち込むのは形で、綴りは席。
/// 見本は docs/superpowers/specs/2026-09-06-paste-design.md の例
test "Graft — 貼り付けの見本" {
  // 項目を、子が見出しの見出しへ → 見出し
  assert_eq(
    applied("# r\n\n## a\n", Graft(at=In(node=2, side=None), md="- b\n")),
    ("# r\n\n## a\n\n## b\n", Some(4)),
  )
  // 見出し + 項目を、子が項目の見出しへ → 項目
  assert_eq(
    applied("# r\n\n- a\n", Graft(at=In(node=2, side=None), md="## b\n\n- c\n")),
    ("# r\n\n- a\n- b\n  - c\n", Some(4)),
  )
  // カード 1 枚は中身
  assert_eq(
    applied("# r\n", Graft(at=In(node=2, side=None), md="![](q.png)\n")),
    ("# r\n\n![](q.png)\n", Some(3)),
  )
  // 文書へ中身は断る
  assert_eq(
    edit("# r\n", Graft(at=In(node=@tree.doc_id, side=None), md="![](q.png)\n")),
    { edits: [], focus: None, },
  )
  // 途中の飛びを 6 段目へ — 飛びは空の項目 `- - - b`
  let six = "# 1\n\n## 2\n\n### 3\n\n#### 4\n\n##### 5\n\n###### t\n"
  assert_eq(
    applied(six, Graft(at=In(node=7, side=None), md="# a\n\n#### b\n")),
    (six + "\n- a\n\n  - - - b\n", Some(8)),
  )
}

///|
test "MoveNode — 項目を子が見出しの見出しへ動かせば見出しになる" {
  assert_eq(
    applied(
      "# r\n\n## a\n\n# s\n\n- b\n",
      MoveNode(ids=[5], at=In(node=2, side=None)),
    ),
    ("# r\n\n## a\n\n## b\n\n# s\n", Some(4)),
  )
}

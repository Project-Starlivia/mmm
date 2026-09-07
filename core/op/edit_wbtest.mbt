// md と操作の境界を固定する。入力が md なので、ここだけは読みに依存する。
// 見るのは「編集を当てた md」の正規形と focus — 編集の切り方（空行を
// どこまで残すか）は合流の試験のもの。

///|
fn applied(md : String, op : Op) -> (String, Int?) {
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
/// 名前が `---` の項目の行（`- ---`）は md では水平線。項目は無くなり、`a` の
/// 中身の水平線になる（その行は読んだ原文なのでそのまま残る）。木と md の形が
/// 食い違うので focus は無い（番号のまま返すと別のノードを指す）
test "Rename — 書いた md が別の形に読まれるなら focus は無い" {
  assert_eq(
    applied("# a\n\n- b\n", Rename(id=3, label="---")),
    ("# a\n\n- ---\n", None),
  )
}

///|
/// 根の子の隙間に落ちれば、水平線は側の変わり目。項目 `c` は木から消え、
/// `d` の側が右から左へ変わる。書かれた行（`- ---` も 4 本の水平線）は
/// 読んだ綴りなので、そのまま返る。
test "Rename — 項目が根の子なら、`---` は側の変わり目になる" {
  assert_eq(
    applied("# a\n\n## b\n\n- c\n\n## d\n", Rename(id=4, label="---")),
    ("# a\n\n## b\n\n- ---\n\n## d\n", None),
  )
}

///|
test "境界の綴りは、触っていなければそのまま" {
  let md = "# a\n\n## b\n\n___\n\n## c\n"
  inspect(@tree.serialize(@tree.parse(md)), content=md)
}

///|
/// 閉じの `#` は飾りなので、`# foo ##` は名前 `foo` + 閉じ 2 本に読まれる。
/// 読んだ綴りで書き戻すので行は残るが、木（名前 `foo ##`）と md の形が
/// 食い違うので focus は無い。
test "Rename — 閉じの `#` は飾りなので、書けば読みは変わり focus は無い" {
  assert_eq(
    applied("# a\n", Rename(id=2, label="foo ##")),
    ("# foo ##\n", None),
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
  let ops : Array[Op] = [
    AddNode(at=NodePlace::In(node=2, side=None), labels=["n"]),
    AddNode(at=NodePlace::In(node=2, side=Some(Left)), labels=["n"]),
    MoveBlock(ids=[3, 4], at=Before(block=5)),
    AddBlock(at=BlockPlace::In(node=2), content=Code(info="js", text="1\n")),
    Fold(id=2, open=false),
  ]
  for op in ops {
    let back : Op = @json.from_json(op.to_json())
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
    applied(
      "# r\n\n## a\n",
      Graft(at=NodePlace::In(node=2, side=None), md="- b\n"),
    ),
    ("# r\n\n## a\n\n## b\n", Some(4)),
  )
  // 見出し + 項目を、子が項目の見出しへ → 項目
  assert_eq(
    applied(
      "# r\n\n- a\n",
      Graft(at=NodePlace::In(node=2, side=None), md="## b\n\n- c\n"),
    ),
    ("# r\n\n- a\n- b\n  - c\n", Some(4)),
  )
  // カード 1 枚は中身
  assert_eq(
    applied(
      "# r\n",
      Graft(at=NodePlace::In(node=2, side=None), md="![](q.png)\n"),
    ),
    ("# r\n\n![](q.png)\n", Some(3)),
  )
  // 文書へ中身は断る
  assert_eq(
    edit(
      "# r\n",
      Graft(at=NodePlace::In(node=@tree.doc_id, side=None), md="![](q.png)\n"),
    ),
    { edits: [], focus: None, },
  )
  // 途中の飛びを 6 段目へ — 飛びは空の項目 `- - - b`
  let six = "# 1\n\n## 2\n\n### 3\n\n#### 4\n\n##### 5\n\n###### t\n"
  assert_eq(
    applied(
      six,
      Graft(at=NodePlace::In(node=7, side=None), md="# a\n\n#### b\n"),
    ),
    (six + "\n- a\n\n  - - - b\n", Some(8)),
  )
}

///|
/// #84 — 差すものの綴りは席が決める。隣が `*` の列なら `*`
test "新しい項目は隣の綴りを継ぐ — * の列に足せば *" {
  assert_eq(
    applied("# a\n\n* b\n", AddNode(at=After(node=3), labels=["c"])),
    ("# a\n\n* b\n* c\n", Some(4)),
  )
}

///|
/// #84 — 文書の席（`In(doc_id)`）も最後の根に従う。`sign` と同じ見方
test "新しい根の項目は最後の根の綴りを継ぐ — * の根に足せば *" {
  let md = "* a\n"
  let r = edit(md, AddNode(at=In(node=@tree.doc_id, side=None), labels=["b"]))
  assert_eq(@tree.apply(md, r.edits), "* a\n\n* b\n")
  assert_eq(r.focus, Some(3))
}

///|
/// #84 — 読んだ列の綴りは正規形でも保つ。番号も読んだ数字のまま
test "* の列を触っても * のまま、1. の列は 1. のまま" {
  inspect(
    @tree.serialize(@tree.parse("# a\n\n* b\n* c\n")),
    content="# a\n\n* b\n* c\n",
  )
  inspect(
    @tree.serialize(@tree.parse("# a\n\n1. b\n2. c\n")),
    content="# a\n\n1. b\n2. c\n",
  )
  // 飛んだ番号も読んだまま（ライブラリは列の先頭からしか数えない）
  inspect(
    @tree.serialize(@tree.parse("# a\n\n1. b\n3. c\n")),
    content="# a\n\n1. b\n3. c\n",
  )
}

///|
/// #84 の見本 — 席で綴り直す。`*` の列の項目を `-` の列へ動かせばマーカーは `-`
test "MoveNode — 席の列の綴りを継ぐ" {
  let md = "# h\n\n* a\n\n## s\n\n- x\n- y\n"
  // a（id 3）を x（id 5）の後ろへ
  let r = edit(md, MoveNode(ids=[3], at=After(node=5)))
  assert_eq(@tree.apply(md, r.edits), "# h\n\n## s\n\n- x\n- a\n- y\n")
  assert_eq(r.focus, Some(5))
}

///|
/// #84 — 詰めも席のもの。空いた列から詰まった列へ動かしても、
/// 触っていない隣の項目の間に空行は生えない
test "MoveNode — 詰まった列へ動かせば詰まったまま" {
  let md = "# h\n\n* a\n\n* b\n\n## s\n\n- x\n- y\n"
  // a（id 3）を y（id 7）の後ろへ
  let r = edit(md, MoveNode(ids=[3], at=After(node=7)))
  assert_eq(@tree.apply(md, r.edits), "# h\n\n* b\n\n## s\n\n- x\n- y\n- a\n")
  assert_eq(r.focus, Some(7))
}

///|
test "MoveNode — 項目を子が見出しの見出しへ動かせば見出しになる" {
  assert_eq(
    applied(
      "# r\n\n## a\n\n# s\n\n- b\n",
      MoveNode(ids=[5], at=NodePlace::In(node=2, side=None)),
    ),
    ("# r\n\n## a\n\n## b\n\n# s\n", Some(4)),
  )
}

///|
/// #85 — 2 行の名前の見出しを触っても 2 行のまま。正規形は冪等
test "改行を含む名前は setext のまま — 触っても 2 行目は消えない" {
  let md = "a\nb\n===\n\ntail\n"
  inspect(@tree.serialize(@tree.parse(md)), content=md)
  assert_eq(
    applied(md, Rename(id=2, label="c\nd")),
    ("c\nd\n===\n\ntail\n", Some(2)),
  )
}

///|
/// 深さ 3 へ改行入りの名前を持ち込む操作は断る
test "改行を含む名前を深さ 3 へ — できない操作" {
  let md = "# a\n\n## b\n\nc\nd\n---\n"
  // c\nd（id 4）を b（id 3）の子へ
  assert_eq(edit(md, MoveNode(ids=[4], at=In(node=3, side=None))), {
    edits: [],
    focus: None,
  })
}

///|
/// #85 — 席が変われば綴りも変わる。項目に読んだ 2 行の名前は setext を持たないが、
/// 深さ 2 の見出しの席なら書けるので setext で綴る（ATX に落とすと 2 行目が消える）
test "MoveNode — 改行を含む名前を見出しの席へ動かせば setext で綴る" {
  let md = "# r\n\n- a\n  b\n\n# s\n"
  // a\nb（id 3）を s（id 4）の子へ
  let r = edit(md, MoveNode(ids=[3], at=In(node=4, side=None)))
  assert_eq(@tree.apply(md, r.edits), "# r\n\n# s\n\na\nb\n---\n")
  assert_eq(r.focus, Some(4))
}

///|
/// #85 — 名前が空なら setext では綴れない。`===` だけの行は下線にならず、
/// 見出しが段落に落ちて子が 1 つ浅くなる。席で保てない綴りは ATX に落とす
/// （空の見出しの行は `#` だけ — Implicit を綴った空の見出しと同じ）
test "Rename — 空の名前の setext は ATX に落ちる" {
  assert_eq(
    applied("a\n===\n\ntail\n", Rename(id=2, label="")),
    ("#\n\ntail\n", Some(2)),
  )
}

///|
/// #85 — 綴りは形ではない。改行の無い setext の見出しを深さ 3 へ動かせば
/// `### c` に綴り直されるが、形は変わらないので focus は残り、編集も
/// その行だけ（文書ごとの置き換えに落ちない）
test "MoveNode — setext の見出しを深さ 3 へ動かせば ATX で綴り直す" {
  let md = "# a\n\n## b\n\nc\n---\n"
  // c（id 4）を b（id 3）の子へ
  let r = edit(md, MoveNode(ids=[4], at=In(node=3, side=None)))
  assert_eq(@tree.apply(md, r.edits), "# a\n\n## b\n\n### c\n")
  assert_eq(r.focus, Some(4))
  assert_false(r.edits.any(e => e.from == 0 && e.to == md.length()))
}

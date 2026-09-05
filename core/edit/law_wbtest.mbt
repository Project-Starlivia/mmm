// 操作と反映の結合を法則で固定する。
//
//   法則 — edit の編集を md に当てて読み直せば、apply の後の木と形が一致する
//   focus — 読み替えた focus は、後の木で focus だったのと同じ部分木を指す
//   できない操作 — 編集も focus も無い
//   目印の生存 — 中身だけを変える操作の後、持ち主のラベルの目印は同じノードに着く
//
// 見本 × 全 id × Op の作り方で回す。Op の作り方は op の check の法則と同じ。

///|
let corpus : Array[String] = [
  "# r\n\n## a\n\nhello\n\n#### x\n\n## b\n\n![p](p.png)\n", "- a\n  - b\n\n    ```js\n    1\n    ```\n\n  - c\n- d\n",
  "intro\n\n# r\n\n## a\n\n---\n\n## b\n\n***\n\n## c\n", "---\nk: v\n---\n\n# a\n\n- i\n  - j\n\n# b\n",
  "# r\r\n\r\n## a\r\n\r\n### x\r\n", "# r\n\n<details open>\n<summary>s</summary>\n\n## a\n\nx\n\n</details>\n\n## b\n",
  "hello\n\n- a\n- b\n\n<!-- c -->\n",
]

///|
/// 木の全 id（ノードも中身も）。文書順。
fn ids(doc : @tree.Doc) -> Array[Int] {
  let out = []
  fn blocks(bs : Array[@tree.Block]) {
    for b in bs {
      out.push(b.id)
    }
  }

  fn list(l : @tree.ListNode) {
    out.push(l.id)
    blocks(l.body)
    for k in l.children {
      list(k)
    }
  }

  fn node(x : @tree.Node) {
    match x {
      HeadingNode(h) => {
        out.push(h.id)
        blocks(h.body)
        for k in h.children {
          node(k)
        }
      }
      ListNode(l) => list(l)
      ImplicitNode(g) => {
        out.push(g.id)
        for k in g.children {
          node(k)
        }
      }
    }
  }

  blocks(doc.body)
  for r in doc.roots {
    node(r.node)
  }
  out
}

///|
/// id の部分木（または中身）の、id を消した姿。focus が同じものを指すかを見る。
fn bare(doc : @tree.Doc, id : Int) -> Json? {
  let found : Ref[Json?] = { val: None }
  fn blocks(bs : Array[@tree.Block]) {
    for b in bs {
      if b.id == id {
        found.val = Some(b.content.to_json())
      }
    }
  }

  fn list(l : @tree.ListNode) {
    if l.id == id {
      found.val = Some(strip(ListNode(l)))
    }
    blocks(l.body)
    for k in l.children {
      list(k)
    }
  }

  fn node(x : @tree.Node) {
    match x {
      HeadingNode(h) => {
        if h.id == id {
          found.val = Some(strip(x))
        }
        blocks(h.body)
        for k in h.children {
          node(k)
        }
      }
      ListNode(l) => list(l)
      ImplicitNode(g) => {
        if g.id == id {
          found.val = Some(strip(x))
        }
        for k in g.children {
          node(k)
        }
      }
    }
  }

  blocks(doc.body)
  for r in doc.roots {
    node(r.node)
  }
  found.val
}

///|
/// 部分木の JSON から id を消す。
fn strip(x : @tree.Node) -> Json {
  fn go(j : Json) -> Json {
    match j {
      Object(o) => {
        let out : Map[String, Json] = Map([])
        for k, v in o {
          if k != "id" {
            out[k] = go(v)
          }
        }
        Json::object(out)
      }
      Array(xs) => Json::array(xs.map(go))
      other => other
    }
  }

  go(x.to_json())
}

///|
fn ops_for(all : Array[Int]) -> Array[@op.Op] {
  let ops : Array[@op.Op] = []
  for id in all {
    ops.push(Rename(id~, label="z"))
    ops.push(Fold(id~, open=false))
    ops.push(Unfold(id~))
    ops.push(Delete(ids=[id]))
    ops.push(Wrap(id~, label="w"))
    ops.push(FlipSide(id~))
    ops.push(SetBlock(id~, content=ThematicBreak))
    for to in all {
      ops.push(MoveNode(ids=[id], at=Before(node=to)))
      ops.push(MoveNode(ids=[id], at=After(node=to)))
      ops.push(MoveNode(ids=[id], at=In(node=to, side=Some(Left))))
      ops.push(MoveBlock(ids=[id], at=Before(block=to)))
      ops.push(MoveBlock(ids=[id], at=In(node=to)))
      ops.push(AddNode(at=After(node=to), labels=["n"]))
      ops.push(AddBlock(at=In(node=to), content=ThematicBreak))
      ops.push(Graft(at=In(node=to, side=None), md="# g\n\n- i\n"))
    }
  }
  ops.push(AddNode(at=In(node=@tree.doc_id, side=None), labels=["n"]))
  ops.push(AddBlock(at=In(node=@tree.doc_id), content=ThematicBreak))
  ops
}

///|
test "法則 — 読み直せば操作後の木と形が一致し、focus は同じ部分木を指す" {
  let mut some = 0
  let bad : Array[String] = []
  for i, md in corpus {
    let before = @tree.parse(md)
    for op in ops_for(ids(before)) {
      let what = "\{i} \{op.to_json().stringify()}"
      let r = edit(md, op)
      match @op.apply(before, op) {
        Some(done) => {
          some = some + 1
          let after = @tree.parse(@tree.apply(md, r.edits))
          if @tree.shape(after) != @tree.shape(done.doc) {
            bad.push("\{what}: 形が違う")
            continue
          }
          match (done.focus, r.focus) {
            (None, None) => ()
            (Some(f), Some(g)) =>
              if bare(done.doc, f) != bare(after, g) {
                bad.push(
                  "\{what}: focus \{f} → \{g} が別のものを指す",
                )
              }
            _ => bad.push("\{what}: focus の有無が違う")
          }
        }
        None =>
          if r != { edits: [], focus: None } {
            bad.push("\{what}: できない操作に編集がある")
          }
      }
    }
  }
  // 全部 None に潰れる退化を落とすための下限チェック
  inspect(some, content="552")
  json_inspect(bad, content=[])
}

///|
/// その中身の持ち主。ノードの id なら None
fn owner_of(doc : @tree.Doc, block : Int) -> Int? {
  let found : Ref[Int?] = { val: None }
  fn blocks(owner : Int, bs : Array[@tree.Block]) {
    for b in bs {
      if b.id == block {
        found.val = Some(owner)
      }
    }
  }

  fn list(l : @tree.ListNode) {
    blocks(l.id, l.body)
    for k in l.children {
      list(k)
    }
  }

  fn node(x : @tree.Node) {
    match x {
      HeadingNode(h) => {
        blocks(h.id, h.body)
        for k in h.children {
          node(k)
        }
      }
      ListNode(l) => list(l)
      ImplicitNode(g) =>
        for k in g.children {
          node(k)
        }
    }
  }

  blocks(@tree.doc_id, doc.body)
  for r in doc.roots {
    node(r.node)
  }
  found.val
}

///|
/// 畳まれた部分木の中に居るか（自分も含む）
fn under_fold(doc : @tree.Doc, id : Int) -> Bool {
  fn go(x : @tree.Node, fold : Bool) -> Bool {
    let (here, mine, kids) = match x {
      HeadingNode(h) => (fold || h.fold is Some(_), h.id, h.children)
      ListNode(l) =>
        (
          fold || l.fold is Some(_),
          l.id,
          l.children.map(c => @tree.ListNode(c)),
        )
      ImplicitNode(g) => (fold, g.id, g.children)
    }
    if mine == id {
      return here
    }
    for k in kids {
      if go(k, here) {
        return true
      }
    }
    false
  }

  for r in doc.roots {
    if go(r.node, false) {
      return true
    }
  }
  false
}

///|
/// 中身だけを変える操作で、目印を置いておきたい持ち主のノード。
fn owners_of(doc : @tree.Doc, op : @op.Op) -> Array[Int] {
  let out : Array[Int] = []
  let push = (o : Int?) => {
    match o {
      Some(id) => if id != @tree.doc_id { out.push(id) }
      None => ()
    }
  }
  match op {
    AddBlock(at=In(node~), ..) => push(Some(node))
    AddBlock(at=Before(block~), ..) | AddBlock(at=After(block~), ..) =>
      push(owner_of(doc, block))
    SetBlock(id~, ..) => push(owner_of(doc, id))
    MoveBlock(ids~, at~) => {
      for id in ids {
        push(owner_of(doc, id))
      }
      match at {
        In(node~) => push(Some(node))
        Before(block~) | After(block~) => push(owner_of(doc, block))
      }
    }
    Delete(ids~) =>
      for id in ids {
        push(owner_of(doc, id))
      }
    _ => ()
  }
  out
}

///|
test "法則 — 目印の生存。中身だけを変えれば、持ち主のラベルの目印は同じノードに着く" {
  let bad : Array[String] = []
  let mut seen = 0
  for i, md in corpus {
    let (before, spots) = @tree.survey(md)
    for op in ops_for(ids(before)) {
      let owners = owners_of(before, op)
      if owners.is_empty() {
        continue
      }
      guard @op.apply(before, op) is Some(done) else { continue }
      let what = "\{i} \{op.to_json().stringify()}"
      let r = edit(md, op)
      let marks : Array[@tree.Mark] = []
      let expect : Array[Int?] = []
      for o in owners {
        // 畳みの中は丸ごと書かれる。持ち主ごと消えるなら着く先は無い
        guard spots.get(o) is Some(s) && s.label is Some(label) else {
          continue
        }
        if under_fold(before, o) {
          continue
        }
        marks.push({ from: s.from, label })
        expect.push(@tree.number(done.doc, o))
      }
      seen = seen + marks.length()
      // 目印は編集列で写し、編集を当てた md の地番で誰かを決める（mmmSurvey と同じ）
      let (_, later) = @tree.survey(@tree.apply(md, r.edits))
      for k, t in @tree.follow(later, r.edits, marks) {
        let got = t.bind(x => x.id)
        if got != expect[k] {
          bad.push(
            "\{what}: 目印 \{k} が \{expect[k]} でなく \{got} に着く",
          )
        }
      }
    }
  }
  inspect(seen > 100, content="true")
  json_inspect(bad, content=[])
}

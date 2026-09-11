// 操作と合流の結合を法則で固定する。
//
//   法則 — edit の編集を md に当てて読み直した形が apply の後の木と一致すれば、
//          読み替えた focus は後の木で focus だったのと同じ部分木を指す。
//          一致しなければ focus は無い（`- ---` で項目が水平線になる等）
//   できない操作 — 編集も focus も無い
//   Delete の focus — 消した後の focus は消えていない兄弟か祖先（中身なら持ち主）で、
//              畳みの中に埋もれていない。無いのは最後の根と文書の散文を消したときだけ
//   隙間の保存 — どの操作の後も、元に無かった連続空行と頭の空行は生まれない。
//              足すだけの操作（AddNode / AddBlock / Graft）で空行の数は減らない
//   原文の保存 — 触っていない字は変わらない
//
// 見本 × 全 id × Op の作り方で回す。Op の作り方は op の check の法則と同じ。

///|
let corpus : Array[String] = [
  "# r\n\n## a\n\nhello\n\n#### x\n\n## b\n\n![p](p.png)\n", "- a\n  - b\n\n    ```js\n    1\n    ```\n\n  - c\n- d\n",
  "intro\n\n# r\n\n## a\n\n---\n\n## b\n\n***\n\n## c\n", "---\nk: v\n---\n\n# a\n\n- i\n  - j\n\n# b\n",
  "# r\r\n\r\n## a\r\n\r\n### x\r\n", "# r\n\n<details open>\n<summary>s</summary>\n\n## a\n\nx\n\n</details>\n\n## b\n",
  "hello\n\n- a\n- b\n\n<!-- c -->\n", "# r\n\n## a\n\nhello", "# a\n\n#### deep\n\n## b\n",
  "# a\r\n\r\n#### deep\r\n\r\n## b\r\n", "# a\n  \n#### deep\n\n## b\n", "# r\n\n- a\n- b\n",
  "- x\n\n  y\n\n  - a\n  - b\n",
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

  fn node(x : @tree.Node) {
    out.push(x.id)
    blocks(x.body)
    for k in x.children {
      node(k)
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
fn shape_of(doc : @tree.Doc, id : Int) -> Json? {
  let found : Ref[Json?] = { val: None, }
  fn blocks(bs : Array[@tree.Block]) {
    for b in bs {
      if b.id == id {
        found.val = Some(b.content.to_json())
      }
    }
  }

  fn node(x : @tree.Node) {
    if x.id == id {
      found.val = Some(strip(x))
    }
    blocks(x.body)
    for k in x.children {
      node(k)
    }
  }

  blocks(doc.body)
  for r in doc.roots {
    node(r.node)
  }
  found.val
}

///|
/// 部分木の JSON から id と綴りを消す（`@tree.shape` と同じ「形」の見方）。
/// **綴りは形ではない** — 詰め（`loose`）は列 1 本のもので、操作が列を割れば
/// 1 つの項目に空行は書けず、読み直しは詰まった列になる。
fn strip(x : @tree.Node) -> Json {
  let spelling = ["id", "setext", "closing", "marker", "offset", "loose"]
  fn go(j : Json) -> Json {
    match j {
      Object(o) => {
        let out : Map[String, Json] = Map([])
        for k, v in o {
          if !spelling.contains(k) {
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
/// ノードの席、構築子ぜんぶ。side は Some も None も
fn node_seats(to : Int) -> Array[NodePlace] {
  [
    Before(node=to),
    After(node=to),
    In(node=to, side=Some(Left)),
    In(node=to, side=None),
  ]
}

///|
/// 中身の席、構築子ぜんぶ
fn block_seats(to : Int) -> Array[BlockPlace] {
  [Before(block=to), After(block=to), In(node=to)]
}

///|
/// 全 id × Op の作り方 × 席の構築子。席の相手は全 id と文書（doc_id）
fn ops_for(all : Array[Int]) -> Array[Op] {
  let ops : Array[Op] = []
  let seats = [..all, @tree.doc_id]
  for id in all {
    ops.push(Rename(id~, label="z"))
    // 書けば別の形に読まれる名前。形の食い違いに触れるのはこの 1 つだけ
    ops.push(Rename(id~, label="---"))
    ops.push(Fold(id~, open=false))
    ops.push(Fold(id~, open=true))
    ops.push(Unfold(id~))
    ops.push(Delete(ids=[id]))
    ops.push(Wrap(id~, label="w"))
    ops.push(FlipSide(id~))
    ops.push(SetBlock(id~, content=Some(ThematicBreak), source=None))
    for to in seats {
      for at in node_seats(to) {
        ops.push(MoveNode(ids=[id], at~))
      }
      for at in block_seats(to) {
        ops.push(MoveBlock(ids=[id], at~))
      }
    }
  }
  for to in seats {
    for at in node_seats(to) {
      ops.push(AddNode(at~, label="n"))
      for
        md in [
          "# g\n\n- i\n", "- i\n  - j\n", "- i\n", "![](q.png)\n\ntext\n", "text\n",
          // 字下げの梯子（#118）。深い行が子になっても法則は破れない
           "a\n  b\n",
        ] {
        ops.push(Graft(at~, md~))
      }
    }
    for at in block_seats(to) {
      ops.push(AddBlock(at~, content=Some(ThematicBreak)))
    }
  }
  ops
}

///|
/// **形は md が決める。** 操作後の木が md に書けない形（中身の尻の水平線に骨格が
/// 続く境界）なら、書いた md は境界として読まれるので形が一致しない。
test "法則 — 形が一致すれば focus は同じ部分木を指し、一致しなければ focus は無い" {
  let mut some = 0
  let mut decided = 0
  let bad : Array[String] = []
  for i, md in corpus {
    let before = @tree.parse(md)
    for op in ops_for(ids(before)) {
      let what = "\{i} \{op.to_json().stringify()}"
      let r = edit(md, op)
      match apply(before, op) {
        Some(done) => {
          some = some + 1
          let after = @tree.parse(@tree.patched(md, r.edits))
          if @tree.shape(after) != @tree.shape(done.doc) {
            decided = decided + 1
            if r.focus is Some(_) {
              bad.push("\{what}: 形が違うのに focus がある")
            }
            continue
          }
          match (done.focus, r.focus) {
            (None, None) => ()
            (Some(f), Some(g)) =>
              if shape_of(done.doc, f) != shape_of(after, g) {
                bad.push(
                  "\{what}: focus \{f} → \{g} が別のものを指す",
                )
              }
            _ => bad.push("\{what}: focus の有無が違う")
          }
        }
        None =>
          if r != { edits: [], focus: None, } {
            bad.push("\{what}: できない操作に編集がある")
          }
      }
    }
  }
  json_inspect(bad, content=[])
  // 全部 None に潰れる退化を落とすための下限チェック
  inspect(some, content="2407")
  // md が形を決めた回数。0 なら法則の 2 つ目の道が死んでいる。
  // **減るのは木と md が一致した回数が増えたということ**（#204 で 41 → 38）
  inspect(decided, content="38")
}

///|
/// 畳まれた部分木の中に居るか（自分も含む）。
/// （merge_law_wbtest.mbt にも同じものが在る）
fn under_fold(doc : @tree.Doc, id : Int) -> Bool {
  fn go(x : @tree.Node, fold : Bool) -> Bool {
    let here = fold || x.fold is Some(_)
    if x.id == id {
      return here
    }
    for k in x.children {
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
test "法則 — Delete の focus は消えていない兄弟か祖先（中身なら持ち主）で、畳みの中に埋もれていない" {
  let bad : Array[String] = []
  let mut n = 0
  for i, md in corpus {
    let before = @tree.parse(md)
    for id in ids(before) {
      guard apply(before, Delete(ids=[id])) is Some(done) else { continue }
      let what = "\{i} Delete \{id}"
      let block_owner = owner(before, block=id)
      match done.focus {
        None => {
          let sole_root = before.roots.length() == 1 &&
            parent(before, id) == Some(@tree.doc_id)
          if !sole_root && block_owner != Some(@tree.doc_id) {
            bad.push("\{what}: focus が無い")
          }
        }
        Some(f) => {
          n = n + 1
          if !ids(done.doc).contains(f) {
            bad.push("\{what}: focus \{f} が後の木に無い")
            continue
          }
          let near = match block_owner {
            Some(o) => o == f || ancestors(before, o).contains(f)
            None =>
              parent(before, f) == parent(before, id) ||
              ancestors(before, id).contains(f)
          }
          if !near {
            bad.push("\{what}: focus \{f} は兄弟でも祖先でもない")
          }
          // under_fold は自分自身も数えるので、親に聞けば「埋もれている」だけが出る
          // （focus 自身が畳まれているのは埋もれていない）
          match parent(done.doc, f) {
            Some(p) if p != @tree.doc_id && under_fold(done.doc, p) =>
              bad.push("\{what}: focus \{f} は埋もれている")
            _ => ()
          }
        }
      }
    }
  }
  json_inspect(bad, content=[])
  // 網の広さ。corpus を触れば動く
  inspect(
    n,
    content=(
      #|44
    ),
  )
}

///|
test "法則 — 隙間の保存。どの操作の後も、続く空行は増えず、頭の空行は生まれない" {
  let bad : Array[String] = []
  let mut n = 0
  for i, md in corpus {
    let before = @tree.parse(md)
    for op in ops_for(ids(before)) {
      let r = edit(md, op)
      if r.edits.is_empty() {
        continue
      }
      n = n + 1
      let out = @tree.patched(md, r.edits)
      let keeps = match op {
        // Wrap と Fold は部分木ごと正規形で書き直すので、そこでは正規形の空行の数になる
        AddNode(..) | AddBlock(..) | Graft(..) => true
        _ => false
      }
      if keeps && blank_lines(out) < blank_lines(md) {
        bad.push(
          "\{i} \{op.to_json().stringify()}: 空行が減った \{out.to_json().stringify()}",
        )
      }
      if blank_run(out) > blank_run(md) {
        bad.push(
          "\{i} \{op.to_json().stringify()}: 連続空行 \{out.to_json().stringify()}",
        )
      }
      if !md.has_prefix("\n") &&
        !md.has_prefix("\r\n") &&
        (out.has_prefix("\n") || out.has_prefix("\r\n")) {
        bad.push(
          "\{i} \{op.to_json().stringify()}: 頭の空行 \{out.to_json().stringify()}",
        )
      }
    }
  }
  json_inspect(bad, content=[])
  // 網の広さ。corpus か ops_for を触れば動く
  inspect(n, content="2321")
}

///|
/// 1 ノードの Rename で変わるのは、そのノードの名前の行だけ。ほかの字は 1 つも
/// 変わらない — 表の桁も、フェンスも、素の URL も、定義行の位置も
test "法則 — 触っていない字は変わらない" {
  let md =
    #|# a
    #|
    #|| x | 日本語 |
    #||---|---|
    #|| 1 | 2 |
    #|
    #|~~~
    #|code
    #|~~~
    #|
    #|https://e.com/x
    #|
    #|[r]: https://e.com/r
    #|
    #|* b
    #|* c
    #|
  let r = edit(md, Rename(id=2, label="A"))
  let out = @tree.patched(md, r.edits)
  // 名前の行を元に戻せば、原文そのもの
  assert_eq(out.replace(old="# A\n", new="# a\n"), md)
  // 見本ぜんぶ × 名前の行を持つ全ノードでも同じ。編集は 1 つ残らずその行の中
  let bad : Array[String] = []
  let mut n = 0
  for i, doc in corpus {
    let (before, spans) = @tree.build(doc)
    for id in ids(before) {
      // 名前の行を持たないもの（中身と Implicit）は地番が言う。Rename が
      // Implicit を綴れば行が 1 本増えるので、そこに「触っていない」は無い
      guard spans.get(id) is Some({ label: Some(at), .. }) else { continue }
      // 畳みは `<details>` が部分木を包むので、名前が変われば塊ごと書き直す
      guard !under_fold(before, id) else { continue }
      let edits = edit(doc, Rename(id~, label="z")).edits
      guard !edits.is_empty() else { continue }
      n = n + 1
      let (head, tail) = line_of(doc, at)
      for e in edits {
        if e.from < head || e.to > tail {
          bad.push(
            "\{i} Rename \{id}: 名前の行 [\{head},\{tail}) の外に \{e.to_json().stringify()}",
          )
        }
      }
    }
  }
  json_inspect(bad, content=[])
  // 網の広さ。corpus を触れば動く
  inspect(n, content="40")
}

///|
/// その位置の行の頭と尻（改行の次。末尾に改行が無ければ文書の尻）。
fn line_of(md : String, at : Int) -> (Int, Int) {
  let mut head = at
  while head > 0 && md[head - 1] != '\n' {
    head = head - 1
  }
  let mut tail = at
  while tail < md.length() && md[tail] != '\n' {
    tail = tail + 1
  }
  (head, if tail < md.length() { tail + 1 } else { tail })
}

///|
/// 続く空行の最大数。空白だけの行も空行（読みが空行と見るのと同じ）
fn blank_run(md : String) -> Int {
  let lines = md.replace_all(old="\r\n", new="\n").split("\n").collect()
  let mut best = 0
  let mut run = 0
  for i, line in lines {
    // 末尾の改行の後ろは行ではない
    if i == lines.length() - 1 {
      break
    }
    run = if line.trim(chars=" \t").is_empty() { run + 1 } else { 0 }
    if run > best {
      best = run
    }
  }
  best
}

///|
/// 空行の数（空白だけの行も空行）
fn blank_lines(md : String) -> Int {
  let lines = md.replace_all(old="\r\n", new="\n").split("\n").collect()
  let mut n = 0
  for i, line in lines {
    if i == lines.length() - 1 {
      break
    }
    if line.trim(chars=" \t").is_empty() {
      n = n + 1
    }
  }
  n
}

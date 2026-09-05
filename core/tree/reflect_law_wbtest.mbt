// 反映の法則を総当たりで固定する。
//
//   法則 — 編集を当てて読み直せば、後の木と形が一致する（id は見ない）
//   比例性 — ラベルを変えただけなら、編集はそのノードの地番の中に 1 つ
//   行の不可侵 — 行（ラベル・畳み・種類）が同じノードの行は、どの編集の範囲にも入らない
//   隙間の保存 — 編集を当てた md に、元に無かった連続空行は無い
//
// 文書の見本 × 全ノード × 変え方（ラベル・削除・子を足す）で回す。
// 形の一致は検証が全文へ落として保つので、ここが見ているのは
// **落ちずに済む所で落ちていないか**と、落ちる所で壊れていないか。

///|
let corpus : Array[String] = [
  "# r\n\n## a\n\nhello\n\n### x\n\n## b\n", "- a\n  - b\n    - c\n- d\n\ntext\n",
  "# r\n\n## a\n\n---\n\n## b\n\n***\n\n## c\n", "---\nk: v\n---\n\nhello\n\n# a\n\n[q]: /r\n",
  "# r\r\n\r\n## a\r\n\r\n### x\r\n", "# r\n\n<details>\n<summary>s</summary>\n\n## a\n\nx\n\n</details>\n\n## b\n",
  "# a\n\n### x\n\n# b", "- a\n\n  text\n\n  - b\n- c\n", "# r\n\n- i\n  - j\n\n## a\n",
  "hello\n\n- a\n- b\n", "aaa\n\nbbb\n\n# h\n",
]

///|
/// 変え方。
enum Change {
  /// ラベルの尻に `!` を足す
  Relabel
  /// ノードを部分木ごと消す
  Delete
  /// 子を 1 つ足す（項目の子は項目）
  Adopt
  /// 中身を 1 枚足す
  AddBlock
  /// 最後の中身を消す
  DropBlock
  /// 最初の中身を置き換える
  SetBlock
  /// 最初の 2 枚を入れ替える
  Swap
}

///|
fn name(how : Change) -> String {
  match how {
    Relabel => "Relabel"
    Delete => "Delete"
    Adopt => "Adopt"
    AddBlock => "AddBlock"
    DropBlock => "DropBlock"
    SetBlock => "SetBlock"
    Swap => "Swap"
  }
}

///|
/// id のノードを how で変えた木。
fn changed(doc : Doc, id : Int, how : Change) -> Doc {
  morph(doc, id, x => {
    match how {
      Relabel =>
        Some(
          match x {
            HeadingNode(h) => HeadingNode({ ..h, label: h.label + "!" })
            ListNode(l) => ListNode({ ..l, label: l.label + "!" })
            other => other
          },
        )
      Delete => None
      Adopt =>
        Some(with_children(x, children_of(x) + [newborn(x is ListNode(_))]))
      AddBlock =>
        Some(with_body(x, body_of(x) + [{ id: 999, content: ThematicBreak }]))
      DropBlock =>
        if body_of(x).is_empty() {
          Some(x)
        } else {
          Some(with_body(x, body_of(x)[0:body_of(x).length() - 1].to_owned()))
        }
      SetBlock =>
        Some(
          with_body(
            x,
            body_of(x).mapi((i, b) => {
              if i == 0 {
                { id: b.id, content: Opaque("changed") }
              } else {
                b
              }
            }),
          ),
        )
      Swap => {
        let bs = body_of(x)
        if bs.length() < 2 {
          Some(x)
        } else {
          Some(with_body(x, [bs[1], bs[0]] + bs[2:].to_owned()))
        }
      }
    }
  })
}

///|
/// 畳まれた部分木の中に居るか（自分も含む）。畳みは `<details>` が包むので丸ごと書かれる
fn under_fold(doc : Doc, id : Int) -> Bool {
  fn go(x : Node, fold : Bool) -> Bool {
    let here = fold || folded(x)
    if id_of(x) == id {
      return here
    }
    for k in children_of(x) {
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
/// 全文へ落ちた編集列か（根を全部消したときも同じ形になるが、そのとき残るノードは無い）。
fn whole(md : String, edits : Array[Edit]) -> Bool {
  edits.length() == 1 && edits[0].from == 0 && edits[0].to == md.length()
}

///|
/// 行の不可侵と隙間の保存。全部の変え方で回すので、ここで 1 度に見る。
fn grain(
  md : String,
  before : Doc,
  spans : Map[Int, Spot],
  after : Doc,
  edits : Array[Edit],
  what : String,
) -> Unit raise {
  let out = apply(md, edits)
  let flat = (s : String) => s.replace_all(old="\r\n", new="\n")
  if !flat(md).contains("\n\n\n") && flat(out).contains("\n\n\n") {
    fail("\{what}: 連続空行が生まれた\n--- md\n\{md}\n--- out\n\{out}")
  }
  if !flat(md).has_prefix("\n") && flat(out).has_prefix("\n") {
    fail("\{what}: 頭に空行が生まれた\n--- out\n\{out}")
  }
  if whole(md, edits) {
    return
  }
  let news : Map[Int, Node] = Map([])
  for r in after.roots {
    index(news, r.node)
  }
  let olds : Map[Int, Node] = Map([])
  for r in before.roots {
    index(olds, r.node)
  }
  for id in all_ids(before) {
    guard news.get(id) is Some(x) else { continue }
    let old = spans.get(id).unwrap()
    guard !(x is ImplicitNode(_)) && !under_fold(before, id) else { continue }
    guard same_line(olds.get(id).unwrap(), x) else { continue }
    let line_to = line_end(md, old.from)
    for e in edits {
      if e.from < line_to && e.to > old.from {
        fail(
          "\{what}: 同じ行 \{id} [\{old.from},\{line_to}) に編集 \{e.to_json().stringify()} が掛かる\n--- md\n\{md}",
        )
      }
    }
  }
}

///|
/// 新しいノード（id は読みが振る番号と被らない）。項目の子は項目。
fn newborn(item : Bool) -> Node {
  if item {
    ListNode({ id: 999, label: "new", fold: None, body: [], children: [] })
  } else {
    HeadingNode({ id: 999, label: "new", fold: None, body: [], children: [] })
  }
}

///|
/// 木の全ノードの id（文書順）。
fn all_ids(doc : Doc) -> Array[Int] {
  let out = []
  fn go(x : Node) {
    out.push(id_of(x))
    for k in children_of(x) {
      go(k)
    }
  }

  for r in doc.roots {
    go(r.node)
  }
  out
}

///|
/// id のノードを f で置き換えた Doc。None なら消す。根の側は子と並走を保ち、
/// 子を失った Implicit は在り得ない（check が言う）ので一緒に消える。
fn morph(doc : Doc, id : Int, f : (Node) -> Node?) -> Doc {
  let roots = []
  for r in doc.roots {
    if id_of(r.node) == id {
      match f(r.node) {
        Some(n) => roots.push(({ node: n, sides: fit(r.sides, n) } : Root))
        None => ()
      }
    } else {
      let (kids, sides) = morph_kids(children_of(r.node), r.sides, id, f)
      if r.node is ImplicitNode(_) && kids.is_empty() {
        continue
      }
      roots.push(({ node: with_children(r.node, kids), sides } : Root))
    }
  }
  { ..doc, roots, }
}

///|
fn morph_kids(
  kids : Array[Node],
  sides : Array[Side],
  id : Int,
  f : (Node) -> Node?,
) -> (Array[Node], Array[Side]) {
  let out = []
  let out_sides = []
  for i, k in kids {
    let side = if i < sides.length() { sides[i] } else { Right }
    if id_of(k) == id {
      match f(k) {
        Some(n) => {
          out.push(n)
          out_sides.push(side)
        }
        None => ()
      }
    } else {
      let (kk, _) = morph_kids(children_of(k), [], id, f)
      if k is ImplicitNode(_) && kk.is_empty() {
        continue
      }
      out.push(with_children(k, kk))
      out_sides.push(side)
    }
  }
  (out, out_sides)
}

///|
fn fit(sides : Array[Side], node : Node) -> Array[Side] {
  let n = children_of(node).length()
  Array::makei(n, i => if i < sides.length() { sides[i] } else { Right })
}

///|
/// 法則 — 当てて読み直せば後の木と形が一致する。編集は from 順で重ならない。
fn law(
  md : String,
  before : Doc,
  spans : Map[Int, Spot],
  after : Doc,
  what : String,
) -> Array[Edit] raise {
  let edits = reflect(md, before, spans, after)
  let out = apply(md, edits)
  guard shape(parse(out)) == shape(after) else {
    fail("\{what}: 形が違う\n--- md\n\{md}\n--- out\n\{out}")
  }
  let mut last = 0
  for e in edits {
    guard e.from >= last && e.to >= e.from else {
      fail("\{what}: 範囲が重なる")
    }
    last = e.to
  }
  edits
}

///|
test "法則 — 全ノードのラベルを変える。比例性も見る" {
  for md in corpus {
    let (before, spans) = survey(md)
    for id in all_ids(before) {
      let after = changed(before, id, Relabel)
      let edits = law(md, before, spans, after, "relabel \{id} in \{md}")
      let s = spans.get(id).unwrap()
      // Implicit はラベルが無いので変わらない。それ以外は 1 つ、地番の中
      if after == before {
        guard edits.is_empty() else {
          fail("relabel \{id}: 変わっていないのに編集がある")
        }
      } else {
        guard edits.length() == 1 &&
          edits[0].from >= s.from &&
          edits[0].to <= s.to else {
          fail(
            "relabel \{id} in \{md}: 地番の外に及ぶ \{edits.to_json().stringify()}",
          )
        }
      }
    }
  }
}

///|
test "法則 — 全ノードを消す" {
  for md in corpus {
    let (before, spans) = survey(md)
    for id in all_ids(before) {
      let after = changed(before, id, Delete)
      ignore(law(md, before, spans, after, "delete \{id} in \{md}"))
    }
  }
}

///|
test "法則 — 全ノードに子を足す" {
  for md in corpus {
    let (before, spans) = survey(md)
    for id in all_ids(before) {
      let after = changed(before, id, Adopt)
      ignore(law(md, before, spans, after, "adopt \{id} in \{md}"))
    }
  }
}

///|
test "法則 — 根を足す・消す" {
  for md in corpus {
    let (before, spans) = survey(md)
    let more : Doc = {
      ..before,
      roots: before.roots + [{ node: newborn(false), sides: [] }],
    }
    ignore(law(md, before, spans, more, "add root to \{md}"))
    if !before.roots.is_empty() {
      let less : Doc = { ..before, roots: before.roots[1:].to_owned() }
      ignore(law(md, before, spans, less, "drop root of \{md}"))
    }
  }
}

///|
test "法則 — 行の不可侵と隙間の保存。全ノード × 全部の変え方" {
  for md in corpus {
    let (before, spans) = survey(md)
    for id in all_ids(before) {
      for how in [Relabel, Delete, Adopt, AddBlock, DropBlock, SetBlock, Swap] {
        let after = changed(before, id, how)
        // 書けない木（根の中身の `---` が側の変わり目に化けるなど）は check が断る
        if after == before || !check(after).is_empty() {
          continue
        }
        let what = "\{name(how)} \{id} in \{md}"
        let edits = law(md, before, spans, after, what)
        grain(md, before, spans, after, edits, what)
      }
    }
  }
}

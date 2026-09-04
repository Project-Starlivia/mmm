// 木を読むだけの道具。歩きは each 1 本で、seat / owner / pick / fresh はその上に乗る。
// 3 種のノードの違い（子の型・中身の有無）は id_of / kids / blocks_of で吸う。

///|
fn id_of(n : @tree.Node) -> Int {
  match n {
    HeadingNode(h) => h.id
    ListNode(l) => l.id
    ImplicitNode(g) => g.id
  }
}

///|
/// 子の列。項目の子は項目だが、歩くときは Node に包んで同じ列にする。
fn kids(n : @tree.Node) -> Array[@tree.Node] {
  match n {
    HeadingNode(h) => h.children
    ImplicitNode(g) => g.children
    ListNode(l) => l.children.map(c => @tree.ListNode(c))
  }
}

///|
/// 中身の列。Implicit は持たない。
fn blocks_of(n : @tree.Node) -> Array[@tree.Block] {
  match n {
    HeadingNode(h) => h.body
    ListNode(l) => l.body
    ImplicitNode(_) => []
  }
}

///|
/// 文書順に、ノードと中身を 1 つずつ訪ねる。f は (id, 中身か, 祖先の id 列) を
/// 受ける。祖先の列は歩きが使い回すので、f は持ち帰らない（要るなら copy）。
fn each(doc : @tree.Doc, f : (Int, Bool, Array[Int]) -> Unit) -> Unit {
  let path : Array[Int] = []
  fn node(n : @tree.Node) -> Unit {
    f(id_of(n), false, path)
    path.push(id_of(n))
    for b in blocks_of(n) {
      f(b.id, true, path)
    }
    for c in kids(n) {
      node(c)
    }
    ignore(path.pop())
  }

  for b in doc.body {
    f(b.id, true, path)
  }
  for r in doc.roots {
    node(r.node)
  }
}

///|
/// id のノード。中身の id には応えない。
fn find(doc : @tree.Doc, id : Int) -> @tree.Node? {
  fn go(n : @tree.Node) -> @tree.Node? {
    if id_of(n) == id {
      return Some(n)
    }
    for c in kids(n) {
      match go(c) {
        Some(m) => return Some(m)
        None => ()
      }
    }
    None
  }

  for r in doc.roots {
    match go(r.node) {
      Some(m) => return Some(m)
      None => ()
    }
  }
  None
}

///|
/// 根の添字から辿る道。長さが深さ（根 = 1、根の子 = 2）。中身には応えない。
fn seat(doc : @tree.Doc, id : Int) -> Array[Int]? {
  fn go(n : @tree.Node) -> Array[Int]? {
    if id_of(n) == id {
      return Some([])
    }
    for k, c in kids(n) {
      match go(c) {
        Some(p) => {
          p.insert(0, k)
          return Some(p)
        }
        None => ()
      }
    }
    None
  }

  for i, r in doc.roots {
    match go(r.node) {
      Some(p) => {
        p.insert(0, i)
        return Some(p)
      }
      None => ()
    }
  }
  None
}

///|
/// 祖先の列の末尾。無ければ doc_id（根と、文書の散文）。
fn above(path : Array[Int]) -> Int {
  match path.last() {
    Some(p) => p
    None => @tree.doc_id
  }
}

///|
/// その中身を body に持つノードの id。ノードの id には応えない。
fn owner(doc : @tree.Doc, block~ : Int) -> Int? {
  let found : Ref[Int?] = { val: None }
  each(doc, fn(id, is_block, path) {
    if is_block && id == block {
      found.val = Some(above(path))
    }
  })
  found.val
}

///|
/// 親の id。根なら doc_id、中身なら持ち主。
fn parent(doc : @tree.Doc, id : Int) -> Int? {
  let found : Ref[Int?] = { val: None }
  each(doc, fn(x, _, path) { if x == id { found.val = Some(above(path)) } })
  found.val
}

///|
/// 選んだ id を文書順に並べ、祖先が選ばれているものを落とす（親と一緒に動く）。
/// 知らない id は落ちる。
fn pick(doc : @tree.Doc, ids : Array[Int]) -> Array[Int] {
  let want : Set[Int] = Set::new()
  for id in ids {
    want.add(id)
  }
  let out = []
  each(doc, fn(id, _, path) {
    if want.contains(id) && !path.any(a => want.contains(a)) {
      out.push(id)
    }
  })
  out
}

///|
/// id か、その祖先が ids に居るか。動かすものの中へ落とすのを止める。
fn within(doc : @tree.Doc, id : Int, ids : Array[Int]) -> Bool {
  let hit : Ref[Bool] = { val: false }
  each(doc, fn(x, _, path) {
    if x == id && (ids.contains(x) || path.any(a => ids.contains(a))) {
      hit.val = true
    }
  })
  hit.val
}

///|
/// 文書に無い id。最大 + 1。空の文書なら doc_id + 1。
fn fresh(doc : @tree.Doc) -> Int {
  let top : Ref[Int] = { val: @tree.doc_id }
  each(doc, fn(id, _, _) { if id > top.val { top.val = id } })
  top.val + 1
}

///|
/// ノードでも中身でも、その id が在るか。
fn has(doc : @tree.Doc, id : Int) -> Bool {
  let hit : Ref[Bool] = { val: false }
  each(doc, fn(x, _, _) { if x == id { hit.val = true } })
  hit.val
}

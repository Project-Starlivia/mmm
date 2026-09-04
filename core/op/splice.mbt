// 書きの道具。id の席を f の返した列に置き換え、根までの道を組み直す。
//
// **check の書き込み版。** 読む側で check が見張る 3 つの約束（項目の子は項目 /
// Implicit は子を持つ / sides は根の子と並走）を、書く側で破らないように組む
// 唯一の場所。f は「どうしたいか」だけを言い、できるかは席を知るここが決める。

///|
/// 1 回の置き換え。歩きながら「席が見つかったか」「席の型に合わなかったか」を残す。
priv struct Splice {
  id : Int
  f : (@tree.Node) -> Array[@tree.Node]
  mut hit : Bool
  mut bad : Bool
}

///|
/// id の席を f の返した列に置き換える。0 = 抜く、1 = 替える、n = 差す。
/// None は 2 つ: id が無い / 席の型に返された列が合わない（項目の下に見出し）。
fn splice(
  doc : @tree.Doc,
  id : Int,
  f : (@tree.Node) -> Array[@tree.Node],
) -> @tree.Doc? {
  let s : Splice = { id, f, hit: false, bad: false }
  let roots : Array[@tree.Root] = []
  for r in doc.roots {
    if id_of(r.node) == id {
      s.hit = true
      for y in f(r.node) {
        roots.push({ node: y, sides: sides_for(y, r) })
      }
    } else {
      match reroot(s, r) {
        Some(x) => roots.push(x)
        None => ()
      }
    }
  }
  if !s.hit || s.bad {
    None
  } else {
    Some({ ..doc, roots, })
  }
}

///|
/// 根の席に置くものの sides。id も子の数も同じなら元のまま、それ以外は Right × 子の数
/// （新しい根は右から始まる。包んだ根が `[Right]` になるのもこの規則）。
fn sides_for(y : @tree.Node, old : @tree.Root) -> Array[@tree.Side] {
  let n = kids(y).length()
  if id_of(y) == id_of(old.node) && n == old.sides.length() {
    old.sides
  } else {
    Array::make(n, @tree.Right)
  }
}

///|
/// 根 1 本。子の列と sides を並走して組み直す。Implicit の子が尽きたら None。
fn reroot(s : Splice, r : @tree.Root) -> @tree.Root? {
  match r.node {
    HeadingNode(h) => {
      let (children, sides) = wing(s, h.children, r.sides)
      Some({ node: HeadingNode({ ..h, children, }), sides })
    }
    ImplicitNode(g) => {
      let (children, sides) = wing(s, g.children, r.sides)
      if children.is_empty() {
        None
      } else {
        Some({ node: ImplicitNode({ ..g, children, }), sides })
      }
    }
    ListNode(l) => {
      let (children, sides) = wing_items(s, l.children, r.sides)
      Some({ node: ListNode({ ..l, children, }), sides })
    }
  }
}

///|
/// 根の子の列。席なら、その側を返された数だけ複製する。
fn wing(
  s : Splice,
  xs : Array[@tree.Node],
  sides : Array[@tree.Side],
) -> (Array[@tree.Node], Array[@tree.Side]) {
  let out = []
  let out_sides = []
  for i, x in xs {
    let side = if i < sides.length() { sides[i] } else { @tree.Right }
    if id_of(x) == s.id {
      s.hit = true
      for y in (s.f)(x) {
        out.push(y)
        out_sides.push(side)
      }
    } else {
      match rebuild(s, x) {
        Some(y) => {
          out.push(y)
          out_sides.push(side)
        }
        None => ()
      }
    }
  }
  (out, out_sides)
}

///|
/// 項目が根のときの子の列。
fn wing_items(
  s : Splice,
  xs : Array[@tree.ListNode],
  sides : Array[@tree.Side],
) -> (Array[@tree.ListNode], Array[@tree.Side]) {
  let out = []
  let out_sides = []
  for i, x in xs {
    let side = if i < sides.length() { sides[i] } else { @tree.Right }
    if x.id == s.id {
      s.hit = true
      for y in (s.f)(@tree.ListNode(x)) {
        match y {
          ListNode(l) => {
            out.push(l)
            out_sides.push(side)
          }
          _ => s.bad = true
        }
      }
    } else {
      out.push(relist(s, x))
      out_sides.push(side)
    }
  }
  (out, out_sides)
}

///|
/// ノード 1 つ。子の列を組み直し、Implicit の子が尽きたら None。
fn rebuild(s : Splice, x : @tree.Node) -> @tree.Node? {
  match x {
    HeadingNode(h) => Some(HeadingNode({ ..h, children: nodes(s, h.children) }))
    ListNode(l) => Some(ListNode(relist(s, l)))
    ImplicitNode(g) => {
      let children = nodes(s, g.children)
      if children.is_empty() {
        None
      } else {
        Some(ImplicitNode({ ..g, children, }))
      }
    }
  }
}

///|
/// 見出し・Implicit の子の列。何でも来る。
fn nodes(s : Splice, xs : Array[@tree.Node]) -> Array[@tree.Node] {
  let out = []
  for x in xs {
    if id_of(x) == s.id {
      s.hit = true
      for y in (s.f)(x) {
        out.push(y)
      }
    } else {
      match rebuild(s, x) {
        Some(y) => out.push(y)
        None => ()
      }
    }
  }
  out
}

///|
fn relist(s : Splice, l : @tree.ListNode) -> @tree.ListNode {
  { ..l, children: items(s, l.children) }
}

///|
/// 項目の子の列。項目しか置けない（型が強いる）。
fn items(s : Splice, xs : Array[@tree.ListNode]) -> Array[@tree.ListNode] {
  let out = []
  for x in xs {
    if x.id == s.id {
      s.hit = true
      for y in (s.f)(@tree.ListNode(x)) {
        match y {
          ListNode(l) => out.push(l)
          _ => s.bad = true
        }
      }
    } else {
      out.push(relist(s, x))
    }
  }
  out
}

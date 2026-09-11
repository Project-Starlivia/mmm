// 書きの道具。id の席を f の返した列に置き換え、根までの道を組み直す。
//
// **check の書き込み版。** 読む側で check が見張る約束（sides は根の子と並走）を、
// 書く側で破らないように組む唯一の場所。f は「どうしたいか」だけを言い、
// 席を知るここが並走を保つ。
// 子が尽きた Implicit は残す — 抜いてから差す操作の途中で席が消えないように。
// 掃除は門（mend）の仕事。

///|
/// 1 回の置き換え。歩きながら「席が見つかったか」を残す。
priv struct Splice {
  id : Int
  f : (@tree.Node) -> Array[@tree.Node]
  mut hit : Bool
}

///|
/// id の席を f の返した列に置き換える。0 = 抜く、1 = 替える、n = 差す。
/// None は id が無いときだけ — **席は種類を選ばない**（項目の中は、その項目の
/// 深さを 0 とした文書）。
fn splice(
  doc : @tree.Doc,
  id : Int,
  f : (@tree.Node) -> Array[@tree.Node],
) -> @tree.Doc? {
  let s : Splice = { id, f, hit: false, }
  let roots : Array[@tree.Root] = []
  for r in doc.roots {
    if r.node.id == id {
      s.hit = true
      for y in f(r.node) {
        roots.push({ node: y, sides: sides_for(y, r), rules: rules_for(y, r), })
      }
    } else {
      roots.push(rebuild_root(s, r))
    }
  }
  if !s.hit {
    None
  } else {
    Some({ ..doc, roots, })
  }
}

///|
/// 根の席に置くものの sides。id も子の数も同じなら元のまま、それ以外は Right × 子の数
/// （新しい根は右から始まる。包んだ根が `[Right]` になるのもこの規則）。
fn sides_for(y : @tree.Node, old : @tree.Root) -> Array[@tree.Side] {
  let n = y.children.length()
  if y.id == old.node.id && n == old.sides.length() {
    old.sides
  } else {
    Array::make(n, @tree.Right)
  }
}

///|
/// 根の席に置くものの rules。sides と同じ規則で、綴りの無い所は空（書く側が `---`）。
fn rules_for(y : @tree.Node, old : @tree.Root) -> Array[String] {
  let n = y.children.length()
  if y.id == old.node.id && n == old.sides.length() {
    old.rules
  } else {
    Array::make(n, "")
  }
}

///|
/// 根の子の側。書かれていない所は Right（`sides` は子と並走するが、短ければ
/// 足りない所は `---` が書かれていないということ）。
fn side_at(r : @tree.Root, j : Int) -> @tree.Side {
  r.sides.get(j).unwrap_or(@tree.Right)
}

///|
/// 根 1 本。子の列と sides・rules を並走して組み直す。
fn rebuild_root(s : Splice, r : @tree.Root) -> @tree.Root {
  let out = []
  let sides = []
  let rules = []
  for i, x in r.node.children {
    let side = side_at(r, i)
    let rule = r.rules.get(i).unwrap_or("")
    // 席なら、その側と綴りを返された数だけ複製する
    for y in rebuild_child(s, x) {
      out.push(y)
      sides.push(side)
      rules.push(rule)
    }
  }
  { node: { ..r.node, children: out, }, sides, rules, }
}

///|
/// ノード 1 つ。子の列を組み直す。
fn rebuild_node(s : Splice, x : @tree.Node) -> @tree.Node {
  let out = []
  for k in x.children {
    for y in rebuild_child(s, k) {
      out.push(y)
    }
  }
  { ..x, children: out, }
}

///|
/// 子 1 つを組み直した列。席なら f の返した列、そうでなければ組み直した 1 つ。
fn rebuild_child(s : Splice, x : @tree.Node) -> Array[@tree.Node] {
  if x.id != s.id {
    return [rebuild_node(s, x)]
  }
  s.hit = true
  (s.f)(x)
}

///|
/// 子の列に足したノード。**種類は問わない** — 項目の中は、その項目の深さを
/// 0 とした文書（docs/spec.md「項目の中」）。
fn with_kids(n : @tree.Node, more : Array[@tree.Node]) -> @tree.Node {
  { ..n, children: [..n.children, ..more], }
}

///|
/// In の席。隣が居ないので f でなく列を受け取り、子の列の末尾に足す。
/// node が根なら sides も足す — side があればそれ、無ければ末尾の子の側、
/// 子が無ければ Right。node が doc_id なら新しい根（sides は Right × 子の数）。
fn append(
  doc : @tree.Doc,
  node~ : Int,
  side? : @tree.Side,
  nodes : Array[@tree.Node],
) -> @tree.Doc? {
  if node == @tree.doc_id {
    let roots = doc.roots.copy()
    for y in nodes {
      roots.push({
        node: y,
        sides: Array::make(y.children.length(), @tree.Right),
        rules: Array::make(y.children.length(), ""),
      })
    }
    return Some({ ..doc, roots, })
  }
  for i, r in doc.roots {
    if r.node.id == node {
      let n = with_kids(r.node, nodes)
      let s = side.unwrap_or(side_at(r, r.node.children.length() - 1))
      let sides = r.sides.copy()
      let rules = r.rules.copy()
      for _ in nodes {
        sides.push(s)
        rules.push("")
      }
      let roots = doc.roots.copy()
      roots[i] = { node: n, sides, rules, }
      return Some({ ..doc, roots, })
    }
  }
  guard find(doc, node) is Some(n) else { return None }
  splice(doc, node, _ => [with_kids(n, nodes)])
}

///|
/// 中身の列を直す。node が doc_id なら文書の散文。Implicit は中身を持たないので None。
fn body(
  doc : @tree.Doc,
  node~ : Int,
  f : (Array[@tree.Block]) -> Array[@tree.Block],
) -> @tree.Doc? {
  if node == @tree.doc_id {
    return Some({ ..doc, body: f(doc.body), })
  }
  guard find(doc, node) is Some(n) else { return None }
  // Implicit は綴りが無いので中身も持てない
  guard n.mark is Some(_) else { return None }
  let m = { ..n, body: f(n.body), }
  splice(doc, node, _ => [m])
}

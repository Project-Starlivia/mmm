// 反映 — 前後の木を比べ、変わった所だけを原文 md に映す。
//
// 受け取るのは原文・前の Doc とその地番・後の Doc の 4 つで、返すのは編集列だけ。
// 後の Doc が誰にどう作られたか（操作・undo のスナップショット）は知らない。
//
// 前後の木を id で突き合わせ、変わったノード（dirty）の地番を断片で置き換える。
// 入れ子は一番上だけ（範囲が重ならない）。出来た文章を読み直して後の木と
// 形が一致しなければ全文を正規形に落とす — **正しさはこの検証が持つ**ので、
// 比較がどれだけ雑でも壊れない。決めは docs/core.md「反映」。

///|
/// 編集 1 つ。from..to を insert に置き換える（CodeMirror の changes と同じ形）。
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug, ToJson)

///|
/// 後の木を映す編集列。from 順で、範囲は重ならない。
pub fn reflect(
  md : String,
  before : Doc,
  spans : Map[Int, @markdown.Span],
  after : Doc,
) -> Array[Edit] {
  match plan(md, before, spans, after) {
    Some(edits) if shape(parse(apply(md, edits))) == shape(after) => edits
    _ => [{ from: 0, to: md.length(), insert: serialize(after) }]
  }
}

///|
/// 編集列を md に当てる。後ろから当てれば座標がずれない。
pub fn apply(md : String, edits : Array[Edit]) -> String {
  let mut out = md
  for i = edits.length() - 1; i >= 0; i = i - 1 {
    let e = edits[i]
    out = slice(out, 0, e.from) + e.insert + slice(out, e.to, out.length())
  }
  out
}

///|
/// 比較の途中。
priv struct Reflect {
  md : String
  spans : Map[Int, @markdown.Span]
  eol : Eol
  /// 前の木のノードを id で引く
  old : Map[Int, Node]
  out : Array[Edit]
}

///|
/// 触った所だけの編集列。文書ぜんぶに関わる変化（frontmatter・改行・根の増減）は
/// 断片では書けないので None — 全文へ落ちる。
fn plan(
  md : String,
  before : Doc,
  spans : Map[Int, @markdown.Span],
  after : Doc,
) -> Array[Edit]? {
  guard before.frontmatter == after.frontmatter && before.eol == after.eol else {
    return None
  }
  guard ids(before.roots.map(r => r.node)) == ids(after.roots.map(r => r.node)) else {
    return None
  }
  let r : Reflect = { md, spans, eol: before.eol, old: Map([]), out: [] }
  for root in before.roots {
    index(r.old, root.node)
  }
  if before.body != after.body {
    r.out.push(edit(r, doc_id, prose(after.body, r.eol)))
  }
  for i, root in after.roots {
    // 側は根のもの。変われば根が丸ごと
    if before.roots[i].sides != root.sides {
      replace(r, root.node, 1, root.sides)
    } else {
      walk(r, root.node, 1, root.sides)
    }
  }
  r.out.sort_by((a, b) => a.from - b.from)
  Some(r.out)
}

///|
/// 前の木の同じ id と比べ、違えばそこで書く。同じなら子へ降りる
/// （子の id 列も同じなので、番号で組になる）。
fn walk(r : Reflect, x : Node, depth : Int, sides : Array[Side]) -> Unit {
  match r.old.get(id_of(x)) {
    Some(old) if same(old, x) =>
      for k in children_of(x) {
        walk(r, k, depth + 1, [])
      }
    _ => replace(r, x, depth, sides)
  }
}

///|
/// 部分木ごと断片にして、地番に差す。
fn replace(r : Reflect, x : Node, depth : Int, sides : Array[Side]) -> Unit {
  r.out.push(edit(r, id_of(x), fragment(x, depth, sides, r.eol)))
}

///|
/// 地番 id の範囲を text で置き換える編集。項目の入れ子は列 0 で出るので、
/// 容器の桁に揃える（1 行目はもう容器が字下げしている）。
fn edit(r : Reflect, id : Int, text : String) -> Edit {
  // 前の木に無い id はここへ来ない — 親の子 id 列が違うので親が書かれる
  let s = r.spans.get(id).unwrap()
  { from: s.from, to: s.to, insert: indent(text, column(r.md, s.from)) }
}

///|
/// 2 行目以降を n 桁字下げする。空行はそのまま。
fn indent(text : String, n : Int) -> String {
  if n == 0 {
    return text
  }
  let pad = String::make(n, ' ')
  let out = StringBuilder::new()
  let mut head = false
  for c in text {
    if head && c != '\n' && c != '\r' {
      out.write_string(pad)
    }
    out.write_char(c)
    head = c == '\n'
  }
  out.to_string()
}

///|
/// ノード自身が同じか — ラベル・中身・畳み・子の id 列。子の中は見ない。
fn same(a : Node, b : Node) -> Bool {
  match (a, b) {
    (HeadingNode(p), HeadingNode(q)) =>
      p.label == q.label &&
      p.fold == q.fold &&
      p.body == q.body &&
      ids(p.children) == ids(q.children)
    (ListNode(p), ListNode(q)) =>
      p.label == q.label &&
      p.fold == q.fold &&
      p.body == q.body &&
      p.children.map(c => c.id) == q.children.map(c => c.id)
    (ImplicitNode(p), ImplicitNode(q)) => ids(p.children) == ids(q.children)
    _ => false
  }
}

///|
fn index(into : Map[Int, Node], x : Node) -> Unit {
  into[id_of(x)] = x
  for k in children_of(x) {
    index(into, k)
  }
}

///|
fn id_of(x : Node) -> Int {
  match x {
    HeadingNode(h) => h.id
    ListNode(l) => l.id
    ImplicitNode(g) => g.id
  }
}

///|
fn children_of(x : Node) -> Array[Node] {
  match x {
    HeadingNode(h) => h.children
    ListNode(l) => l.children.map(c => ListNode(c))
    ImplicitNode(g) => g.children
  }
}

///|
fn ids(xs : Array[Node]) -> Array[Int] {
  xs.map(id_of)
}

///|
/// id を消した木。読みは id を振り直し、後の木の新しいノードは別の id を
/// 持つので、形を比べるときは id を見ない。
pub fn shape(doc : Doc) -> Doc {
  {
    ..doc,
    body: faceless(doc.body),
    roots: doc.roots.map(r => { node: faceless_node(r.node), sides: r.sides }),
  }
}

///|
fn faceless_node(x : Node) -> Node {
  match x {
    HeadingNode(h) =>
      HeadingNode({
        ..h,
        id: 0,
        body: faceless(h.body),
        children: h.children.map(faceless_node),
      })
    ListNode(l) => ListNode(faceless_list(l))
    ImplicitNode(g) =>
      ImplicitNode({ id: 0, children: g.children.map(faceless_node) })
  }
}

///|
fn faceless_list(l : ListNode) -> ListNode {
  {
    ..l,
    id: 0,
    body: faceless(l.body),
    children: l.children.map(faceless_list),
  }
}

///|
fn faceless(body : Array[Block]) -> Array[Block] {
  body.map(b => {
    match b {
      Details(text~, ..) => Details(id=0, text~)
      other => other
    }
  })
}

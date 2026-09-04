// Doc → View。削るだけで、足すものは無い。
//
// 消えるのは、書き戻すためだけの欄（frontmatter・eol・散文の body）と、
// ノードの種類と、Opaque。core が「読み解かない」と裁定したものだけが
// map に届かない。

///|
pub fn project(doc : @tree.Doc) -> Array[Tree] {
  doc.roots.map(r => { node: cast(r.node), sides: r.sides })
}

///|
fn cast(n : @tree.Node) -> Node {
  match n {
    HeadingNode(h) =>
      {
        id: h.id,
        label: Some(h.label),
        fold: h.fold,
        blocks: read(h.body),
        children: h.children.map(cast),
      }
    ListNode(l) => cast_item(l)
    ImplicitNode(i) =>
      {
        id: i.id,
        label: None,
        fold: None,
        blocks: [],
        children: i.children.map(cast),
      }
  }
}

///|
fn cast_item(l : @tree.ListNode) -> Node {
  {
    id: l.id,
    label: Some(l.label),
    fold: l.fold,
    blocks: read(l.body),
    children: l.children.map(cast_item),
  }
}

///|
/// 読み解いたものだけ。id は Doc のままなので、落ちた分で番号はずれない。
fn read(body : Array[@tree.Block]) -> Array[@tree.Block] {
  body.filter(b => !(b.content is Opaque(_)))
}

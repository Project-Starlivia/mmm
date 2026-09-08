// Doc → View。削るだけで、足すものは無い。
//
// 消えるのは、書き戻すためだけの欄（散文の body・境界の綴り）と、ノードの種類と、
// Raw。中身は `@tree.Block` のまま持つので、書き戻すためだけの原文（`source`）は
// 付いてくる — map は見ない。frontmatter だけは残す — 画像フォルダの宣言がそこに
// 書かれていて、描くのに要る。core が「読み解かない」と裁定したものだけが map に届かない。

///|
pub fn project(doc : @tree.Doc) -> View {
  {
    frontmatter: doc.frontmatter,
    roots: doc.roots.map(r => { node: cast(r.node), sides: r.sides, }),
  }
}

///|
fn cast(n : @tree.Node) -> Node {
  {
    id: n.id,
    // Implicit（綴りが無い）は名前を持たない。空の見出し（`## `）は `Some("")`
    label: if n.mark is Some(_) {
      Some(n.label)
    } else {
      None
    },
    fold: n.fold,
    blocks: read(n.body),
    children: n.children.map(cast),
  }
}

///|
/// 読み解いたものだけ。id は Doc のままなので、落ちた分で番号はずれない。
fn read(body : Array[@tree.Block]) -> Array[@tree.Block] {
  body.filter(b => b.content is Some(_))
}

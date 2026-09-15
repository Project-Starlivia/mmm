// 木の形 — id と綴りを消した比較の物差し。合流の検証（`verdict`）と、edit が focus の
// 要否を見るのに使う。

///|
/// 木の形。id と綴りを消したもの — 読みは id を振り直し、後の木の新しい
/// ノードは別の id を持つ。境界の綴り（`rules`）は原文から来るもので、
/// 操作が作った境界は綴りを持たない（書けば `---` として読み直される）。
/// edit が focus の要否を見るのにも使う。
pub fn shape(doc : Doc) -> Doc {
  {
    ..doc,
    body: faceless(doc.body),
    roots: doc.roots.map(r => {
      node: faceless_node(r.node),
      sides: r.sides,
      rules: [],
    }),
  }
}

///|
/// 綴りの書き方（setext・閉じの `#`・マーカー・字下げ幅・詰め）は原文から来る
/// もので、席が変われば綴り直される。**形は種類だけを見る。**
fn faceless_node(x : Node) -> Node {
  {
    ..x,
    id: 0,
    body: faceless(x.body),
    children: x.children.map(faceless_node),
    mark: match sign_of(x) {
      Some(Heading) => Some(atx)
      Some(Item) => Some(bullet)
      None => None
    },
  }
}

///|
/// **形の比較は原文を見ない** — 書いた原文と読み直した原文は、改行の剥ぎ方で
/// 違い得る。意味が同じなら同じ形。
fn faceless(body : Array[Block]) -> Array[Block] {
  body.map(b => { id: 0, content: b.content, source: None, })
}

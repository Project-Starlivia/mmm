// 木を手で組む道具。**`parse` は使わない** — 使うと、ここの試験が全部
// 読みに依存する。id は明示する（操作は id で席を言うので、0 では困る）。

///|
fn doc(roots : Array[@tree.Root], body? : Array[@tree.Block] = []) -> @tree.Doc {
  { frontmatter: None, body, roots, }
}

///|
/// 境界の綴りは書き戻すためだけのもので、操作は作らない。**綴りは側と同じ数の空** —
/// 綴りを指す試験が要るときに任意引数を戻す（#86）。
fn root(node : @tree.Node, sides? : Array[@tree.Side] = []) -> @tree.Root {
  { node, sides, rules: Array::make(sides.length(), ""), }
}

///|
fn h(
  id : Int,
  label : String,
  children? : Array[@tree.Node] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.Node {
  { id, label, fold, body, children, mark: Some(@tree.atx), }
}

///|
fn item(
  id : Int,
  label : String,
  children? : Array[@tree.Node] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
  marker? : String = "-",
) -> @tree.Node {
  {
    id,
    label,
    fold,
    body,
    children,
    mark: Some(Item(marker~, offset=2, loose=false)),
  }
}

///|
fn gap(id : Int, children : Array[@tree.Node]) -> @tree.Node {
  { id, label: "", fold: None, body: [], children, mark: None, }
}

///|
/// source は読んだ原文。断片から来た中身だけが持つ
fn pic(id : Int, source? : String? = None) -> @tree.Block {
  { id, source, content: Some(Image(alt="", src="p.png", title="")), }
}

///|
fn code(id : Int) -> @tree.Block {
  { id, source: None, content: Some(Code(info="", text="x")), }
}

// 木を手で組む道具。**`parse` は使わない** — 使うと、ここの試験が全部
// 読みに依存する。id は明示する（操作は id で席を言うので、0 では困る）。

///|
fn doc(roots : Array[@tree.Root], body? : Array[@tree.Block] = []) -> @tree.Doc {
  { frontmatter: None, eol: Lf, body, roots }
}

///|
fn root(node : @tree.Node, sides? : Array[@tree.Side] = []) -> @tree.Root {
  { node, sides }
}

///|
fn h(
  id : Int,
  label : String,
  children? : Array[@tree.Node] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.Node {
  @tree.HeadingNode({ id, label, fold, body, children })
}

///|
fn li(
  id : Int,
  label : String,
  children? : Array[@tree.ListNode] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.ListNode {
  { id, label, fold, body, children }
}

///|
fn item(
  id : Int,
  label : String,
  children? : Array[@tree.ListNode] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.Node {
  @tree.ListNode(li(id, label, children~, body~, fold~))
}

///|
fn gap(id : Int, children : Array[@tree.Node]) -> @tree.Node {
  @tree.ImplicitNode({ id, children })
}

///|
fn pic(id : Int) -> @tree.Block {
  { id, content: Image(alt="", src="p.png", title="") }
}

///|
fn code(id : Int) -> @tree.Block {
  { id, content: Code(info="", text="x") }
}

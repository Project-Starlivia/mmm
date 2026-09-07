// 木を手で組む道具。**`parse` は使わない** — 使うと、ここの試験が全部
// 読みに依存する。id は明示する（操作は id で席を言うので、0 では困る）。

///|
fn doc(roots : Array[@tree.Root], body? : Array[@tree.Block] = []) -> @tree.Doc {
  { frontmatter: None, body, roots, }
}

///|
/// 境界の綴りは書き戻すためだけのもので、操作は作らない。既定は側と同じ数の空。
fn root(
  node : @tree.Node,
  sides? : Array[@tree.Side] = [],
  rules? : Array[String] = Array::make(sides.length(), ""),
) -> @tree.Root {
  { node, sides, rules, }
}

///|
fn h(
  id : Int,
  label : String,
  children? : Array[@tree.Node] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.Node {
  @tree.HeadingNode({
    id,
    label,
    fold,
    body,
    setext: false,
    closing: 0,
    children,
  })
}

///|
fn li(
  id : Int,
  label : String,
  children? : Array[@tree.ListNode] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
  marker? : String = "-",
  offset? : Int = 2,
  loose? : Bool = false,
) -> @tree.ListNode {
  { id, label, fold, body, marker, offset, loose, children, }
}

///|
fn item(
  id : Int,
  label : String,
  children? : Array[@tree.ListNode] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
  marker? : String = "-",
  offset? : Int = 2,
  loose? : Bool = false,
) -> @tree.Node {
  @tree.ListNode(
    li(id, label, children~, body~, fold~, marker~, offset~, loose~),
  )
}

///|
fn gap(id : Int, children : Array[@tree.Node]) -> @tree.Node {
  @tree.ImplicitNode({ id, children, })
}

///|
/// source は読んだ原文。断片から来た中身だけが持つ
fn pic(id : Int, source? : String? = None) -> @tree.Block {
  { id, source, content: Image(alt="", src="p.png", title=""), }
}

///|
fn code(id : Int) -> @tree.Block {
  { id, source: None, content: Code(info="", text="x"), }
}

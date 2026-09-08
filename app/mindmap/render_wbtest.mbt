// Layout → SVG の差分更新を happy-dom で固定する。何を描くか（形・class・data-*）は
// ts の style.css とハンドラとの契約なので、ここで綴りまで見る。

///|
/// 全部 100 × 30
fn size(_n : @view.Node, _cards : Array[@map.Card], _buried : Int) -> @map.Size {
  { w: 100, h: 30, }
}

///|
fn node(
  id : Int,
  label : String,
  children? : Array[@view.Node] = [],
  fold? : @tree.Fold? = None,
  blocks? : Array[@tree.Block] = [],
) -> @view.Node {
  { id, label: Some(label), fold, blocks, children, }
}

///|
fn root(n : @view.Node, sides? : Array[@tree.Side] = []) -> @view.Root {
  { node: n, sides, }
}

///|
/// 1 文字 7px。実測の代わり
fn seven(_font : @map.Font, text : String) -> Double {
  text.char_length().to_double() * 7.0
}

///|
fn scene(
  roots : Array[@view.Root],
  image_url? : (String) -> String? = _ => None,
  image_hint? : String? = None,
  epoch? : Int = 0,
) -> Scene {
  {
    layout: @map.layout(roots, size),
    measure: seven,
    image_url,
    image_hint,
    // 色分けは 1 行 1 塊の地の文
    tokens: (lines, _lang) => lines.map(l => [{ text: l, cls: "", }]),
    epoch,
  }
}

///|
fn attr(e : @dom.Element, name : String) -> String {
  e.getAttribute(name).unwrap()
}

///|
fn one(e : @dom.Element, selector : String) -> @dom.Element {
  e.querySelector(selector).unwrap()
}

///|
test "ノードごとに .node[data-id]、親を持つものに .edge。位置は transform、線は d" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  r.draw(scene([root(node(1, "r", children=[node(2, "a")]))]))
  assert_eq(r.node_layer.children().length(), 2)
  assert_eq(r.edge_layer.children().length(), 1)
  let g = r.node_el(2).unwrap()
  assert_eq(attr(g, "class"), "node")
  assert_eq(attr(g, "data-id"), "2")
  assert_eq(attr(g, "transform"), "translate(145 0)")
  assert_eq(attr(r.node_el(1).unwrap(), "class"), "node root")
  assert_eq(attr(r.edge_el(2).unwrap(), "d"), "M 100 15 L 145 15")
  assert_true(r.edge_el(1) is None)
  // 中身: 箱・字・題
  assert_eq(attr(one(g, ".box"), "width"), "100")
  let label = one(g, ".label")
  assert_eq(label.textContent(), "a")
  assert_eq(attr(label, "font-size"), "13")
  assert_eq(attr(label, "x"), "12")
  assert_eq(one(g, "title").textContent(), "a")
}

///|
test "空の字はプレースホルダを出し、畳んだノードは字を詰めてバッジを付ける" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  let folded = node(
    2,
    "abcdefghijklmnopqrstuvwxyz",
    children=[node(3, "x")],
    fold=Some({ open: false, summary: None, }),
  )
  r.draw(scene([root(node(1, "", children=[folded]))]))
  let empty = one(r.node_el(1).unwrap(), ".label")
  assert_eq(attr(empty, "class"), "label empty")
  assert_eq(empty.textContent(), "(empty)")
  let g = r.node_el(2).unwrap()
  assert_eq(attr(g, "class"), "node folded")
  let label = one(g, ".label")
  assert_eq(label.textContent(), "abcdefghijklm…  +1")
  assert_eq(attr(label, "font-size"), "11")
  assert_eq(
    one(g, "title").textContent(),
    "abcdefghijklmnopqrstuvwxyz\n(1 folded)",
  )
  assert_true(r.node_el(3) is None)
}

///|
test "2 度描いても、変わっていないノードは作り直さない（同じ要素のまま）" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  let roots = [root(node(1, "r", children=[node(2, "a"), node(3, "b")]))]
  r.draw(scene(roots))
  let before = one(r.node_el(2).unwrap(), ".label")
  let edge = r.edge_el(2).unwrap()
  r.draw(scene(roots))
  let after = one(r.node_el(2).unwrap(), ".label")
  assert_true(before.isSameNode(Some(after.as_node())))
  assert_true(edge.isSameNode(Some(r.edge_el(2).unwrap().as_node())))
  // 字が変われば中身だけ作り直す。要素 g は同じ
  let g = r.node_el(2).unwrap()
  r.draw(scene([root(node(1, "r", children=[node(2, "A"), node(3, "b")]))]))
  assert_true(g.isSameNode(Some(r.node_el(2).unwrap().as_node())))
  assert_eq(one(g, ".label").textContent(), "A")
}

///|
test "畳んで戻すと、消えた線が新しい path に d 込みで戻る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  let open = [
    root(node(1, "r", children=[node(2, "a", children=[node(3, "x")])])),
  ]
  let shut = [
    root(
      node(1, "r", children=[
        node(
          2,
          "a",
          children=[node(3, "x")],
          fold=Some({ open: false, summary: None, }),
        ),
      ]),
    ),
  ]
  r.draw(scene(open))
  let d = attr(r.edge_el(3).unwrap(), "d")
  r.draw(scene(shut))
  assert_true(r.node_el(3) is None)
  assert_true(r.edge_el(3) is None)
  assert_eq(r.node_layer.children().length(), 2)
  r.draw(scene(open))
  assert_eq(attr(r.edge_el(3).unwrap(), "d"), d)
  assert_eq(r.node_layer.children().length(), 3)
}

///|
test "paint は変わった箱だけ触り、箱が無い id は戻ったときに塗る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  let roots = [root(node(1, "r", children=[node(2, "a")]))]
  r.draw(scene(roots))
  r.paint([1, 9])
  assert_true(@web.has_class(r.node_el(1).unwrap(), "selected"))
  assert_true(!@web.has_class(r.node_el(2).unwrap(), "selected"))
  r.paint([2])
  assert_true(!@web.has_class(r.node_el(1).unwrap(), "selected"))
  assert_true(@web.has_class(r.node_el(2).unwrap(), "selected"))
  // 選んだまま消えて戻った箱には印が付く
  r.draw(scene([root(node(1, "r"))]))
  assert_true(r.node_el(2) is None)
  r.draw(scene(roots))
  assert_true(@web.has_class(r.node_el(2).unwrap(), "selected"))
  r.paint([])
  assert_true(!@web.has_class(r.node_el(2).unwrap(), "selected"))
}

///|
test "文書順が変われば DOM の並び（重なり順）も変わる" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  r.draw(scene([root(node(1, "a")), root(node(2, "b"))]))
  assert_eq(r.node_layer.children().map(e => attr(e, "data-id")), ["1", "2"])
  r.draw(scene([root(node(2, "b")), root(node(1, "a"))]))
  assert_eq(r.node_layer.children().map(e => attr(e, "data-id")), ["2", "1"])
}

///|
test "カードは仕切り線に続けて種類ごとの形で並び、data-card は「id,枚目」" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let r = Renderer::new(w.document())
  let blocks : Array[@tree.Block] = [
    {
      id: 5,
      source: None,
      content: Some(Link(text="t", href="https://x.example/p", title="")),
    },
    { id: 6, source: None, content: Some(Code(info="js", text="1\n2\n")), },
    {
      id: 7,
      source: None,
      content: Some(Image(alt="", src="./p.png", title="")),
    },
    { id: 8, source: None, content: Some(ThematicBreak), },
    {
      id: 9,
      source: None,
      content: Some(Details(open=true, summary=Some("s"), body="d\n")),
    },
    { id: 10, source: None, content: Some(Svg("<svg/>")), },
  ]
  r.draw(scene([root(node(1, "r", blocks~))], image_hint=Some("connect")))
  let g = r.node_el(1).unwrap()
  assert_eq(g.querySelectorAll(".sep").length(), 6)
  let hit = one(g, ".link-hit")
  assert_eq(attr(hit, "data-card"), "1,0")
  assert_eq(attr(one(g, ".link-open"), "data-url"), "https://x.example/p")
  assert_eq(one(g, ".link-row").textContent(), "t")
  assert_eq(one(g, ".code-bg title").textContent(), "js")
  assert_eq(g.querySelectorAll(".code-line").length(), 2)
  assert_eq(one(g, ".code-line").textContent(), "1")
  // 画像は読めていないので場所取りと名前と入口
  assert_eq(one(g, ".image-name").textContent(), "p.png")
  assert_eq(one(g, ".image-connect").textContent(), "connect")
  assert_eq(attr(one(g, ".image-connect"), "data-connect"), "1")
  assert_eq(attr(one(g, ".break"), "data-card"), "1,3")
  assert_eq(one(g, ".details-mark").textContent(), "▾")
  assert_eq(one(g, ".details-row").textContent(), "s")
  assert_eq(one(g, ".details-line").textContent(), "d")
  assert_eq(
    attr(one(g, "image"), "href"),
    "data:image/svg+xml;charset=utf-8,%3Csvg%2F%3E",
  )
  // 画像が読めれば <image> に、入口は消える
  r.draw(
    scene([root(node(1, "r", blocks~))], image_url=p => {
      if p == "p.png" {
        Some("blob:x")
      } else {
        None
      }
    }),
  )
  assert_eq(g.querySelectorAll("image").length(), 2)
  assert_true(g.querySelector(".image-connect") is None)
}

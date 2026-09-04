// 「この Doc はこの View になる」を固定する。
//
// 入力は **手で組んだ Doc** で、`parse` は通さない — 通すと、ここの試験が
// 全部読みに依存する（読みは build_wbtest が固定している）。
// 期待値は `json_inspect` が `moon test -u` で埋める。

///|
fn doc(roots : Array[@tree.Root]) -> @tree.Doc {
  { frontmatter: None, eol: Lf, body: [], roots }
}

///|
fn root(node : @tree.Node, sides? : Array[@tree.Side] = []) -> @tree.Root {
  { node, sides }
}

///|
fn heading(
  id : Int,
  label : String,
  children? : Array[@tree.Node] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.Node {
  @tree.HeadingNode({ id, label, fold, body, children })
}

///|
fn item(
  id : Int,
  label : String,
  children? : Array[@tree.ListNode] = [],
  body? : Array[@tree.Block] = [],
  fold? : @tree.Fold? = None,
) -> @tree.ListNode {
  { id, label, fold, body, children }
}

///|
fn implicit(id : Int, children : Array[@tree.Node]) -> @tree.Node {
  @tree.ImplicitNode({ id, children })
}

///|
test "見出し 1 つが木 1 本になる" {
  json_inspect(project(doc([root(heading(2, "a"))])), content=[
    {
      "node": { "id": 2, "label": "a", "blocks": [], "children": [] },
      "sides": [],
    },
  ])
}

///|
test "Implicit はラベルの無いノードになる" {
  let r = heading(2, "r", children=[implicit(3, [heading(4, "x")])])
  json_inspect(project(doc([root(r, sides=[Right])])), content=[
    {
      "node": {
        "id": 2,
        "label": "r",
        "blocks": [],
        "children": [
          {
            "id": 3,
            "blocks": [],
            "children": [
              { "id": 4, "label": "x", "blocks": [], "children": [] },
            ],
          },
        ],
      },
      "sides": ["Right"],
    },
  ])
}

///|
test "空のラベルは Implicit と区別が付く" {
  json_inspect(project(doc([root(heading(2, ""))])), content=[
    {
      "node": { "id": 2, "label": "", "blocks": [], "children": [] },
      "sides": [],
    },
  ])
}

///|
test "項目も子の項目も同じノードになる" {
  let a = @tree.ListNode(item(2, "a", children=[item(3, "b")]))
  json_inspect(project(doc([root(a)])), content=[
    {
      "node": {
        "id": 2,
        "label": "a",
        "blocks": [],
        "children": [{ "id": 3, "label": "b", "blocks": [], "children": [] }],
      },
      "sides": [],
    },
  ])
}

///|
test "Opaque だけが落ちる。並びは保つ" {
  let body : Array[@tree.Block] = [
    @tree.Image(alt="", src="p.png", title=""),
    @tree.Opaque("prose"),
    @tree.Link(text="t", href="u", title=""),
    @tree.Code(info="js", text="1\n"),
    @tree.Svg("<svg/>"),
    @tree.ThematicBreak,
    @tree.Details(id=3, text="<details>x</details>"),
  ]
  json_inspect(project(doc([root(heading(2, "a", body~))])), content=[
    {
      "node": {
        "id": 2,
        "label": "a",
        "blocks": [
          ["Image", { "alt": "", "src": "p.png", "title": "" }],
          ["Link", { "text": "t", "href": "u", "title": "" }],
          ["Code", { "info": "js", "text": "1\n" }],
          ["Svg", "<svg/>"],
          "ThematicBreak",
          ["Details", { "id": 3, "text": "<details>x</details>" }],
        ],
        "children": [],
      },
      "sides": [],
    },
  ])
}

///|
test "畳みはそのまま通る" {
  let a = heading(2, "a", fold=Some({ open: true, summary: Some("a") }))
  json_inspect(project(doc([root(a)])), content=[
    {
      "node": {
        "id": 2,
        "label": "a",
        "fold": { "open": true, "summary": "a" },
        "blocks": [],
        "children": [],
      },
      "sides": [],
    },
  ])
}

///|
test "側は根の子と並んで通る" {
  let r = heading(2, "r", children=[
    heading(3, "a"),
    heading(4, "b"),
    heading(5, "c"),
  ])
  json_inspect(project(doc([root(r, sides=[Right, Left, Left])])), content=[
    {
      "node": {
        "id": 2,
        "label": "r",
        "blocks": [],
        "children": [
          { "id": 3, "label": "a", "blocks": [], "children": [] },
          { "id": 4, "label": "b", "blocks": [], "children": [] },
          { "id": 5, "label": "c", "blocks": [], "children": [] },
        ],
      },
      "sides": ["Right", "Left", "Left"],
    },
  ])
}

///|
test "木は本数のまま" {
  json_inspect(project(doc([root(heading(2, "a")), root(heading(3, "b"))])), content=[
    {
      "node": { "id": 2, "label": "a", "blocks": [], "children": [] },
      "sides": [],
    },
    {
      "node": { "id": 3, "label": "b", "blocks": [], "children": [] },
      "sides": [],
    },
  ])
}

///|
test "書き戻すためだけの欄は消える" {
  let d : @tree.Doc = {
    frontmatter: Some("k: v\n"),
    eol: Crlf,
    body: [@tree.ThematicBreak, @tree.Opaque("prose")],
    roots: [root(heading(2, "a"))],
  }
  json_inspect(project(d), content=[
    {
      "node": { "id": 2, "label": "a", "blocks": [], "children": [] },
      "sides": [],
    },
  ])
}

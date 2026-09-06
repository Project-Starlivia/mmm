// mmmTree → mdAst。build の逆。
//
// 我々の写像は**骨格だけ** — 深さを `#` の数に、側の変わり目を水平線に、
// 畳みを `<details>` の塊にする。ラベルは原文の 1 行を生の行として渡す
// （md として読み直さない）。中身は md として読み直す（PR 2 で原文に揃える）。
//
// 字下げ・フェンスの長さ・空行・エスケープ・定義行の置き場は
// ライブラリの serializer が持ち、ここには文字列の規則が 1 つも無い。
// その正規化（`_em_` → `*em*`、定義行の末尾への移動、setext → ATX）は
// **この段では素直に受ける**。補正するなら合流の段。

///|
/// 組み立て中。定義行は文書ぜんぶで 1 列なので、中身から拾ったものを集める。
priv struct Unbuild {
  defs : Array[@markdown.LinkDefinition]
}

///|
/// 木を mdAst にする。
pub fn unbuild(doc : Doc) -> @markdown.Document {
  let u : Unbuild = { defs: [], }
  let out = []
  for b in doc.body {
    content(u, out, b)
  }
  for r in doc.roots {
    node(u, out, r.node, 1, r.sides)
  }
  {
    // serialize は frontmatter を自分で書く（本文との間に空行を置くため）。
    // ここで持つのは、指紋（ast_sig）が mdAst ぜんぶを見るため
    frontmatter: doc.frontmatter.map(raw => {
      ({ raw, entries: [], span: nowhere, } : @markdown.Frontmatter)
    }),
    children: out,
    definitions: u.defs,
    span: nowhere,
  }
}

///|
/// 部分木 1 つを mdAst にする（断片）。`depth` はその根の見出しの深さ、
/// `sides` は Doc の根のときだけ在る。定義行は断片の中に留まる。
pub fn unbuild_node(
  x : Node,
  depth : Int,
  sides : Array[Side],
) -> @markdown.Document {
  let u : Unbuild = { defs: [], }
  let out = []
  node(u, out, x, depth, sides)
  { frontmatter: None, children: out, definitions: u.defs, span: nowhere, }
}

///|
/// 散文（骨格を持たない中身の列）を mdAst にする。
pub fn unbuild_prose(body : Array[Block]) -> @markdown.Document {
  let u : Unbuild = { defs: [], }
  let out = []
  for b in body {
    content(u, out, b)
  }
  { frontmatter: None, children: out, definitions: u.defs, span: nowhere, }
}

///|
/// 位置は持たない。mdAst の span は原文の座標で、組んだ木に原文は無い。
let nowhere : @markdown.Span = @markdown.Span::empty()

///|
/// 兄弟の列を書く。`sides` は根の子のときだけ来る（深い所の側は型に無い）。
///
/// **続く項目は 1 つの列にまとめる**（兄弟は詰める）。列が割れるのは、側が
/// 変わるとき（間に `---`）と、畳まれた項目（自分の `<details>` に包まれる）。
fn nodes(
  u : Unbuild,
  out : Array[@markdown.Block],
  xs : Array[Node],
  depth : Int,
  sides : Array[Side],
) -> Unit {
  let run : Array[ListNode] = []
  fn flush() {
    if !run.is_empty() {
      out.push(bullets(u, run))
      run.clear()
    }
  }

  let mut prev = Right
  for i, x in xs {
    let side = if i < sides.length() { sides[i] } else { prev }
    if side != prev {
      flush()
      out.push(rule())
      prev = side
    }
    match x {
      ListNode(l) if l.fold is None => run.push(l)
      _ => {
        flush()
        node(u, out, x, depth, [])
      }
    }
  }
  flush()
}

///|
/// ノード 1 つと、その部分木。`sides` はその子に効く（根のときだけ在る）。
/// 項目の根に側は書けない — 項目の中の `---` は中身なので、側は落ちる。
fn node(
  u : Unbuild,
  out : Array[@markdown.Block],
  x : Node,
  depth : Int,
  sides : Array[Side],
) -> Unit {
  match x {
    ListNode(l) => wrap(out, l.fold, () => out.push(bullets(u, [l])))
    HeadingNode(n) =>
      wrap(out, n.fold, () => {
        out.push(heading(depth, n.label))
        for b in n.body {
          content(u, out, b)
        }
        nodes(u, out, n.children, depth + 1, sides)
      })
    ImplicitNode(g) => nodes(u, out, g.children, depth + 1, sides)
  }
}

///|
/// 畳みで包む。開きの塊は「開き」か「開き + 名前」、閉じは閉じだけ。
fn wrap(out : Array[@markdown.Block], fold : Fold?, inner : () -> Unit) -> Unit {
  match fold {
    None => inner()
    Some({ open, summary, }) => {
      let head = StringBuilder()
      head.write_string(spelling(Open(open~)))
      match summary {
        Some(s) => {
          head.write_char('\n')
          head.write_string(spelling(Name(s)))
        }
        None => ()
      }
      out.push(html(head.to_string()))
      inner()
      out.push(html(spelling(Close)))
    }
  }
}

///|
/// 項目の列 1 つ。**ラベルと入れ子の列だけの項目が並ぶときだけ tight。**
/// 中身は空行で分けないと段落に飲み込まれ、畳まれた子の `<details>` は
/// 空行で終わる塊なので、分けないと次の項目を飲み込む。ラベルの直後の空の
/// 項目も分ける（`underlined`）— 正規形は並びで変わる。
fn bullets(u : Unbuild, run : Array[ListNode]) -> @markdown.Block {
  BulletList(
    marker=Dash,
    tight=run
      .iter()
      .all(l => {
        l.body.is_empty() &&
        l.children.iter().all(c => c.fold is None) &&
        !underlined(l)
      }),
    items=run.map(l => list_item(u, l)),
    span=nowhere,
    leading_trivia=@markdown.Trivia::empty(),
    trailing_trivia=@markdown.Trivia::empty(),
  )
}

///|
/// ラベルの直後に空の項目が続く形。詰めて書くと `-` 1 本が段落の setext の
/// 下線に読まれ、ラベルが消えて子も読まれない。空行で分ければ空の項目に読まれる。
fn underlined(l : ListNode) -> Bool {
  l.label != "" && l.children is [{ label: "", .. }, ..]
}

///|
/// 項目 1 つ。ラベルは 1 行目の段落。無ければ段落も無い。
fn list_item(u : Unbuild, l : ListNode) -> @markdown.ListItem {
  let kids = []
  if l.label != "" {
    kids.push(paragraph([verbatim_inline(l.label)]))
  }
  for b in l.body {
    content(u, kids, b)
  }
  nodes(u, kids, l.children.map(c => ListNode(c)), 0, [])
  {
    children: kids,
    checked: None,
    marker_offset: 0,
    content_offset: 2,
    span: nowhere,
  }
}

///|
/// 中身 1 枚。絵の 4 つは mdAst の形に、原文で持つものは md として読み直す。
fn content(u : Unbuild, out : Array[@markdown.Block], b : Block) -> Unit {
  match b.content {
    Image(alt~, src~, title~) =>
      out.push(paragraph([Image(alt~, url=src, title~, span=nowhere)]))
    Link(text~, href~, title~) =>
      out.push(
        paragraph([
          Link(children=[verbatim_inline(text)], url=href, title~, span=nowhere),
        ]),
      )
    Code(info~, text~) =>
      out.push(
        FencedCode(
          fence_marker=Backtick,
          fence_length=3,
          info~,
          code=text,
          indent=0,
          span=nowhere,
          leading_trivia=@markdown.Trivia::empty(),
          trailing_trivia=@markdown.Trivia::empty(),
        ),
      )
    Svg(s) => out.push(html(s))
    ThematicBreak => out.push(rule())
    Details(text~, ..) => splice(u, out, text)
    Opaque(text) => splice(u, out, text)
  }
}

///|
/// 原文のまま持っていたものを md として読み直し、塊をそのまま並べる。
/// 空行は記法なので落とす。定義行は文書の列へ集める。
fn splice(u : Unbuild, out : Array[@markdown.Block], text : String) -> Unit {
  let d = read(text)
  for b in d.children {
    if b is BlankLines(..) {
      continue
    }
    out.push(b)
  }
  u.defs.append(d.definitions)
}

///|
/// 見出しの行。**名前は md の 1 行の原文**なので、ライブラリに読み直させず
/// 生の行として渡す（`HtmlBlock` は中身を逃がさずそのまま書く）。
/// 空の名前は `##` だけ（Implicit を綴った空の見出しと同じ）。
fn heading(level : Int, label : String) -> @markdown.Block {
  let line = String::make(level, '#')
  html(if label == "" { line } else { line + " " + label })
}

///|
/// 項目の名前と Link の題。生の字として段落に置く（逃がさない）。
fn verbatim_inline(text : String) -> @markdown.Inline {
  HtmlInline(html=text, span=nowhere)
}

///|
fn paragraph(children : Array[@markdown.Inline]) -> @markdown.Block {
  Paragraph(
    children~,
    span=nowhere,
    leading_trivia=@markdown.Trivia::empty(),
    trailing_trivia=@markdown.Trivia::empty(),
  )
}

///|
fn html(s : String) -> @markdown.Block {
  HtmlBlock(
    html=s,
    span=nowhere,
    leading_trivia=@markdown.Trivia::empty(),
    trailing_trivia=@markdown.Trivia::empty(),
  )
}

///|
fn rule() -> @markdown.Block {
  ThematicBreak(
    marker='-',
    count=3,
    span=nowhere,
    leading_trivia=@markdown.Trivia::empty(),
    trailing_trivia=@markdown.Trivia::empty(),
  )
}

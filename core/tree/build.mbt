// mdAst → mmmTree。mmm の解釈はここにしか無い。
//
// 骨格（いまは見出しだけ）を深さで積み上げる。深さが飛んだら、間を Implicit が
// 埋める — 飛びは構造なので保存し、綴りが無いことだけを型で表す。
//
// 積むあいだは深さだけを見る平らな Frame で持ち、役割型（Root / Wing / Branch）
// への割り付けは最後に 1 回だけやる。深さ 1 / 2 / 3 以降で型が違うので、
// その違いをここへ閉じ込める。

///|
/// 積み上げ中のノード。深さは stack の高さが持つので、自分では持たない。
priv struct Frame {
  node : Node
  kids : Array[Frame]
}

///|
/// md を木にする。
pub fn parse(md : String) -> Doc {
  build(md, read(md))
}

///|
/// mdAst を mmmTree にする。ラベルは原文から切り出す（mmm はインラインを解釈しない）。
pub fn build(md : String, ast : @markdown.Document) -> Doc {
  let forest : Array[Frame] = []
  let stack : Array[Frame] = []
  for block in ast.children {
    match block {
      Heading(level~, style~, children~, span~, ..) =>
        put(
          forest,
          stack,
          level,
          Explicit(
            sign=Heading,
            label=label_of(md, span, style, children),
            folded=false,
            body=[],
          ),
        )
      _ => ()
    }
  }
  let next = { val: doc_id + 1 }
  {
    frontmatter: ast.frontmatter.map(f => f.raw),
    eol: if md.contains("\r\n") {
      Crlf
    } else {
      Lf
    },
    body: [],
    roots: forest.map(f => to_root(f, next)),
  }
}

///|
/// 文書そのものの id。親を指すときの番兵。
pub let doc_id : Int = 1

///|
/// 深さ level のノードを置く。浅く戻るときは積んだぶんを落とし、
/// 深く飛ぶときは間を Implicit で埋める（飛びは綴りであって、無ではない）。
fn put(
  forest : Array[Frame],
  stack : Array[Frame],
  level : Int,
  node : Node,
) -> Unit {
  while stack.length() >= level {
    ignore(stack.unsafe_pop())
  }
  while stack.length() < level - 1 {
    let gap : Frame = { node: Implicit, kids: [] }
    seat(forest, stack, gap)
    stack.push(gap)
  }
  let f : Frame = { node, kids: [] }
  seat(forest, stack, f)
  stack.push(f)
}

///|
/// 積んである親の子にする。親が居なければ森の 1 本として生やす。
fn seat(forest : Array[Frame], stack : Array[Frame], f : Frame) -> Unit {
  if stack.is_empty() {
    forest.push(f)
  } else {
    stack[stack.length() - 1].kids.push(f)
  }
}

///|
/// 見出しの中身を、原文からそのまま切り出す（mmm はインラインを解釈しない）。
/// 中身が無ければ空ラベル（`## ` のような行）。
///
/// インラインの span は**中身に対する 0 始まりの相対**なので、原文の
/// どこから中身が始まるかは自分で数える。実測（`# a` / `#   a` / `# a #` /
/// setext）は probe_wbtest.mbt に固定してある。
fn label_of(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
  children : Array[@markdown.Inline],
) -> String {
  if children.is_empty() {
    return ""
  }
  let from = head_start(md, span, style)
  let len = span_of(children[children.length() - 1]).to
  String::unsafe_substring(md, start=from, end=from + len)
}

///|
/// 見出しの中身が原文で始まる位置。ATX は飾りの字下げと `#` とその後ろの
/// 空白を飛ばす。setext には `#` が無いので飛ばさない（`#hashtag` を
/// 食べてしまうため）。
fn head_start(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
) -> Int {
  let mut p = skip_blank(md, span.from, span.to)
  if style is Atx {
    while p < span.to && md[p] == '#' {
      p = p + 1
    }
    p = skip_blank(md, p, span.to)
  }
  p
}

///|
fn skip_blank(md : String, from : Int, to : Int) -> Int {
  let mut p = from
  while p < to && (md[p] == ' ' || md[p] == '	') {
    p = p + 1
  }
  p
}

///|
fn span_of(i : @markdown.Inline) -> @markdown.Span {
  match i {
    Text(span~, ..) => span
    SoftBreak(span~) => span
    HardBreak(span~, ..) => span
    Emphasis(span~, ..) => span
    Strong(span~, ..) => span
    Strikethrough(span~, ..) => span
    Code(span~, ..) => span
    Directive(span~, ..) => span
    WikiLink(span~, ..) => span
    Link(span~, ..) => span
    RefLink(span~, ..) => span
    Autolink(span~, ..) => span
    Image(span~, ..) => span
    RefImage(span~, ..) => span
    HtmlInline(span~, ..) => span
    FootnoteReference(span~, ..) => span
  }
}

///|
/// 番号を配る箱。木を歩きながら文書順に振る。
priv struct Counter {
  mut val : Int
}

///|
/// 森の 1 本を根にする。子は翼になる（側はいまのところ全部右）。
fn to_root(f : Frame, next : Counter) -> Root {
  let id = next.val
  next.val = id + 1
  { id, node: f.node, wings: f.kids.map(k => to_wing(k, next)) }
}

///|
fn to_wing(f : Frame, next : Counter) -> Wing {
  { side: Right, branch: to_branch(f, next) }
}

///|
fn to_branch(f : Frame, next : Counter) -> Branch {
  let id = next.val
  next.val = id + 1
  { id, node: f.node, children: f.kids.map(k => to_branch(k, next)) }
}

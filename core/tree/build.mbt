// mdAst → mmmTree。mmm の解釈はここにしか無い。
//
// 骨格（見出しと項目）を深さで積み上げる。深さが飛んだら、間を Implicit が
// 埋める — 飛びは構造なので保存し、綴りが無いことだけを型で表す。
//
// 積むあいだは深さだけを見る平らな Frame で持ち、役割型（Root / Wing / Branch）
// への割り付けは最後に 1 回だけやる。深さ 1 / 2 / 3 以降で型が違うので、
// その違いをここへ閉じ込める。

///|
/// 積み上げ中のノード。深さは stack の高さが持つので、自分では持たない。
priv struct Frame {
  skel : Skeleton
  kids : Array[Frame]
  /// 翼になる深さ 2 の枠だけが意味を持つ。深いところの側は型で存在しない
  mut side : Side
  /// 文書順の番号。形を割り付ける前に振るので、割り付けが順序を動かしても動かない
  mut id : Int
}

///|
/// 積むあいだの骨格。役割（根・翼・見出し・項目）はまだ決まっていないので、
/// **見出しと項目を 1 つの型で平らに持つ**。割り付けは最後に 1 回だけやる。
priv enum Skeleton {
  /// 骨格行が無い。深さの飛びが綴り
  Gap
  Line(sign~ : Sign, label~ : String, details~ : Bool, body~ : Array[Block])
}

///|
/// md を木にする。
pub fn parse(md : String) -> Doc {
  build(md, read(md))
}

///|
/// mdAst を mmmTree にする。ラベルは原文から切り出す（mmm はインラインを解釈しない）。
pub fn build(md : String, ast : @markdown.Document) -> Doc {
  let b : Build = {
    md,
    forest: [],
    stack: [],
    body: [],
    head: 0,
    side: Right,
    pend: false,
  }
  for block in ast.children {
    take(b, block, 0)
  }
  // 後続の翼が無いまま終わった区切りは、直前のノードの飾りに落ちる
  drop_pend(b)
  let next = { val: doc_id + 1 }
  let forest = b.forest
  for f in forest {
    number(f, next)
  }
  {
    frontmatter: ast.frontmatter.map(f => f.raw),
    eol: if b.md.contains("\r\n") {
      Crlf
    } else {
      Lf
    },
    body: b.body,
    roots: forest.map(to_root),
  }
}

///|
/// 文書そのものの id。親を指すときの番兵。
pub let doc_id : Int = 1

///|
/// 積み上げの途中。`head` は直近の見出しの深さで、**見出しは入れ子をリセットする**
/// ので、項目の深さは「直近の見出しの深さ + 1 + 入れ子段数」になる。
priv struct Build {
  md : String
  forest : Array[Frame]
  stack : Array[Frame]
  /// 最初の骨格より前の散文
  body : Array[Block]
  mut head : Int
  /// 次の翼の側。木が変わるたびに右へ戻る
  mut side : Side
  /// 隙間に区切りが有ったか。**本数によらず 1 回**なので Bool で持つ
  mut pend : Bool
}

///|
/// ブロック 1 枚を積む。`nest` は項目の入れ子段数。
fn take(b : Build, block : @markdown.Block, nest : Int) -> Unit {
  match block {
    // **単調性 — 項目の子孫は項目。** 項目の領土に書かれた見出しは骨格に
    // ならず、逐語のまま中身になる（列 0 へ出れば項目が閉じて木が変わる）
    Heading(..) if nest > 0 => fill(b, Opaque(verbatim(b.md, block)))
    Heading(level~, style~, children~, span~, ..) => {
      b.head = level
      put(
        b,
        level,
        Line(
          sign=Head,
          label=head_label(b.md, span, style, children),
          details=false,
          body=[],
        ),
      )
    }
    BulletList(items~, ..) => items_take(b, items, nest)
    OrderedList(items~, ..) => items_take(b, items, nest)
    // 区切りは**根の領土の隙間**でだけ翼の境目になる。項目の中は中身
    ThematicBreak(marker~, ..) =>
      if marker == '-' && nest == 0 {
        b.pend = true
      } else {
        fill(b, Rule)
      }
    _ =>
      match content_of(b.md, block) {
        Some(c) => fill(b, c)
        None => ()
      }
  }
}

///|
/// 項目の列。**最初の段落がラベル**で、残りは中身か入れ子の項目。
fn items_take(b : Build, items : Array[@markdown.ListItem], nest : Int) -> Unit {
  for it in items {
    let rest = []
    let mut label = ""
    let mut named = false
    for c in it.children {
      if !named && c is Paragraph(..) {
        label = item_label(b.md, c)
        named = true
      } else {
        rest.push(c)
      }
    }
    put(b, b.head + 1 + nest, Line(sign=List, label~, details=false, body=[]))
    for c in rest {
      take(b, c, nest + 1)
    }
  }
}

///|
/// 項目のラベル。段落の span は中身の先頭から始まるので、見出しと違って
/// マーカーの読み飛ばしが要らない（実測は probe を参照）。
fn item_label(md : String, p : @markdown.Block) -> String {
  guard p is Paragraph(children~, span~, ..) else { return "" }
  if children.is_empty() {
    return ""
  }
  let len = span_of(children[children.length() - 1]).to
  String::unsafe_substring(md, start=span.from, end=span.from + len)
}

///|
/// 深さ level のノードを置く。浅く戻るときは積んだぶんを落とし、
/// 深く飛ぶときは間を Implicit で埋める（飛びは綴りであって、無ではない）。
fn put(b : Build, level : Int, skel : Skeleton) -> Unit {
  // **見出しは見出しの背骨にしか積まれない。** 項目の枠は見出しの親に
  // なれないので落とす（列 0 の見出しは md でも項目を閉じる）。C17 を
  // 深さ 1 から全部の深さへ広げたもの。これが無いと項目の子が見出しになる
  if skel is Line(sign=Head, ..) {
    while b.stack.length() > 0 &&
          b.stack[b.stack.length() - 1].skel is Line(sign=List, ..) {
      ignore(b.stack.unsafe_pop())
    }
  }
  if level == 1 || b.stack.is_empty() {
    // 新しい木を始める。待っている区切りは行き先を失うので飾りに落ち、
    // 側は右へ戻る。
    //
    // **根がまだ無ければ、区切りは側になれない。** 側は根の持ち物なので、
    // 裏返す相手が居ない。深さ 2 から始まる文書（根が Implicit）でも同じで、
    // ここを分けないと、後ろが `#` か `##` かで同じ `---` の意味が変わる
    drop_pend(b)
    b.side = Right
  } else if b.pend {
    // **区切りは翼の境目を作る。** 深さ 3 以降でも親に飲まれず、
    // 深さ 2 から Implicit が埋める反対側の翼になる
    while b.stack.length() > 1 {
      ignore(b.stack.unsafe_pop())
    }
  }
  while b.stack.length() >= level {
    ignore(b.stack.unsafe_pop())
  }
  while b.stack.length() < level - 1 {
    let gap : Frame = { skel: Gap, kids: [], side: Right, id: 0 }
    seat(b, gap)
    b.stack.push(gap)
  }
  let f : Frame = { skel, kids: [], side: Right, id: 0 }
  seat(b, f)
  b.stack.push(f)
}

///|
/// 積んである親の子にする。親が居なければ森の 1 本として生やす。
/// **翼になるのは深さ 2 の枠だけ**で、側が意味を持つのもそこだけ。
fn seat(b : Build, f : Frame) -> Unit {
  if b.stack.is_empty() {
    b.forest.push(f)
    return
  }
  if b.stack.length() == 1 {
    if b.pend {
      b.side = flipped(b.side)
      b.pend = false
    }
    f.side = b.side
  }
  b.stack[b.stack.length() - 1].kids.push(f)
}

///|
fn flipped(s : Side) -> Side {
  if s is Right {
    Left
  } else {
    Right
  }
}

///|
/// 行き先の翼が来ないまま終わった区切りを、飾りの水平線に落とす。
/// 側は場所の属性なので、置き場所が無ければ側にはなれない。
fn drop_pend(b : Build) -> Unit {
  if b.pend {
    b.pend = false
    fill(b, Rule)
  }
}

///|
/// 見出しの中身を、原文からそのまま切り出す（mmm はインラインを解釈しない）。
/// 中身が無ければ空ラベル（`## ` のような行）。
///
/// インラインの span は**中身に対する 0 始まりの相対**なので、原文の
/// どこから中身が始まるかは自分で数える。実測（`# a` / `#   a` / `# a #` /
/// setext）は probe_wbtest.mbt に固定してある。
fn head_label(
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
/// 番号を文書順に振る。形を割り付ける前に済ませるので、割り付けが
/// 順序を動かしても番号は動かない。
fn number(f : Frame, next : Counter) -> Unit {
  f.id = next.val
  next.val = f.id + 1
  for k in f.kids {
    number(k, next)
  }
}

///|
/// 森の 1 本を根にする。子の側は積むときに決まっている。
fn to_root(f : Frame) -> Root {
  { node: to_node(f), sides: f.kids.map(k => k.side) }
}

///|
/// 枠をノードにする。項目だけは子も項目に畳む（単調性）。
fn to_node(f : Frame) -> Node {
  match f.skel {
    Gap => Implicit({ id: f.id, children: f.kids.map(to_node) })
    Line(sign=List, label~, details~, body~) =>
      List({ id: f.id, label, details, body, children: f.kids.map(to_list) })
    Line(label~, details~, body~, ..) =>
      Head({ id: f.id, label, details, body, children: f.kids.map(to_node) })
  }
}

///|
/// 項目にする。飛びは綴りが無いので空ラベルへ落ちる（項目の子に飛びは
/// 来ないので、実際には通らない）。
fn to_list(f : Frame) -> ListNode {
  match f.skel {
    Gap =>
      {
        id: f.id,
        label: "",
        details: false,
        body: [],
        children: f.kids.map(to_list),
      }
    Line(label~, details~, body~, ..) =>
      { id: f.id, label, details, body, children: f.kids.map(to_list) }
  }
}

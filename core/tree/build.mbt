// mdAst → mmmTree。mmm の解釈はここにしか無い。
//
// 骨格（見出しと項目）を深さで積み上げる。深さが飛んだら、間を Implicit が
// 埋める — 飛びは構造なので保存し、綴りが無いことだけを型で表す。
//
// 積むあいだは深さだけを見る平らな Frame で持ち、根と側の割り付け
// への割り付けは最後に 1 回だけやる。深さ 1 / 2 / 3 以降で型が違うので、
// その違いをここへ閉じ込める。

///|
/// 積み上げ中のノード。深さは stack の高さが持つので、自分では持たない。
priv struct Frame {
  skel : Notation
  kids : Array[Frame]
  /// 深さ 2 の枠だけが持つ。深い所の側は型に存在しない
  mut side : Side
  /// 文書順の番号。形を割り付ける前に振るので、割り付けが順序を動かしても動かない
  mut id : Int
}

///|
/// 行に書かれていた記法。見出しと項目を 1 つの型で平らに持ち、
/// 種類ごとの型への割り付けは最後に 1 回だけやる。
priv enum Notation {
  /// 記法が無い。深さの飛びがそれを言う
  Gap
  Line(
    sign~ : Sign,
    label~ : String,
    details~ : Bool,
    open~ : Bool,
    body~ : Array[Block]
  )
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
    low: deep,
    dry: false,
  }
  for piece in pieces(md, ast.children, ast.definitions.map(d => d.span), 0) {
    lay(b, piece, 0)
  }
  // 行き先の見出し・項目が来ないまま終わった水平線は、その場の中身に落ちる
  spill(b)
  let next = { val: doc_id + 1 }
  let forest = b.forest
  // 文書の中身は最初の見出し・項目より前にあるので、先に振る
  number_details(b.body, next)
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
  /// 次の子の側。木が変わるたびに右へ戻る
  mut side : Side
  /// 行き先待ちの水平線が有るか。**本数に意味は無い**ので Bool で持つ
  mut pend : Bool
  /// このブロックで生まれた一番浅い枠の深さ。骨格でなければ `deep` のまま
  mut low : Int
  /// 深さを測るだけの空打ちか。畳みを見ないので、項目の中も読み解かない
  dry : Bool
}

///|
/// 骨格ではない深さ。どの見出しより深い（`# ` 〜 `######` は 1〜6）。
let deep : Int = 99

///|
/// 畳みを見ずに骨格だけ積み、ブロックごとに**そこで生まれた一番浅い枠の深さ**
/// を返す。畳みの領域が部分木と一致するかは、md の見出しの深さではなく
/// この深さで測る — 境界の `---` は部分木を深さ 2 へ引き出し、飛びは Implicit
/// で埋まるので、md の `#` の数と積まれた深さはずれる。
fn depths(
  md : String,
  blocks : Array[@markdown.Block],
  spells : Array[Spell],
  nest : Int,
) -> Array[Int] {
  let b : Build = {
    md,
    forest: [],
    stack: [],
    body: [],
    head: 0,
    side: Right,
    pend: false,
    low: deep,
    dry: true,
  }
  let out = Array::make(blocks.length(), deep)
  for i, block in blocks {
    // **畳みの綴りだけの塊は跨ぐ。** 測っているのは「この領域が畳みだったら
    // 部分木を覆うか」なので、その前提では綴りは落ちている。中身として数えると
    // 保留中の水平線がそこで装飾に落ち、本番の木と深さがずれる
    if only_marks(spells[i]) {
      continue
    }
    b.low = deep
    take(b, block, nest)
    out[i] = b.low
  }
  out
}

///|
/// ひと切れを積む。畳みは見出し・項目の行に印を付けるか、中身の 1 枚になる。
fn lay(b : Build, piece : Piece, nest : Int) -> Unit {
  match piece {
    Raw(block) => take(b, block, nest, details=false, open=false)
    Folded(block, open~) => take(b, block, nest, details=true, open~)
    Capsule(text) => {
      // 中身が来たので、保留中の水平線は境界になれない
      spill(b)
      // id は割り付けの直前に文書順で振るので、ここでは 0 を置く
      fill(b, Details(id=0, text~))
    }
    Text(text) => {
      spill(b)
      fill(b, Opaque(text))
    }
  }
}

///|
/// ブロック 1 枚を積む。`nest` は項目の入れ子段数。
fn take(
  b : Build,
  block : @markdown.Block,
  nest : Int,
  details? : Bool = false,
  open? : Bool = false,
) -> Unit {
  match block {
    // **単調性 — 項目の子孫は項目。** 項目の領土に書かれた見出しは骨格に
    // ならず、原文のまま中身になる（列 0 へ出れば項目が閉じて木が変わる）
    Heading(..) if nest > 0 => fill(b, Opaque(verbatim(b.md, block)))
    Heading(level~, style~, children~, span~, ..) => {
      b.head = level
      put(
        b,
        level,
        Line(
          sign=Heading,
          label=head_label(b.md, span, style, children),
          details~,
          open~,
          body=[],
        ),
      )
    }
    BulletList(items~, ..) => items_take(b, items, nest, details~, open~)
    OrderedList(items~, ..) => items_take(b, items, nest, details~, open~)
    // 区切りは**根の領土の隙間**でだけ側の変わり目になる。項目の中は中身なので
    // 保留せずその場に置く（保留すると、置く前に項目の枠が閉じられたとき
    // 帰る場所が無くなって文書へ落ちる）
    ThematicBreak(..) if nest > 0 => fill(b, ThematicBreak)
    // 記法(`---` `***` `___`)も本数も差別しない。意味は常に「隣を区切る」で、
    // 行き先は**直後のブロックが何か**で決まる。ここでは保留するだけ
    ThematicBreak(..) => b.pend = true
    _ =>
      match content_of(b.md, block) {
        Some(c) => {
          // 中身が来た時点で、保留中の水平線は境界になれない
          spill(b)
          fill(b, c)
        }
        None => ()
      }
  }
}

///|
/// 項目の列。**最初の段落がラベル**で、残りは中身か入れ子の項目。
fn items_take(
  b : Build,
  items : Array[@markdown.ListItem],
  nest : Int,
  details? : Bool = false,
  open? : Bool = false,
) -> Unit {
  for it in items {
    // **ラベルは項目の 1 行目。** 途中の段落を引き上げると、その文字が
    // ラベルと中身の両方になる（切り出しはブロックの範囲でやるので、抜いたはずの
    // 段落が切り出しの内側に入る）。1 行目が段落でなければラベルは無い
    let rest = []
    let mut label = ""
    for i, c in it.children {
      if i == 0 && c is Paragraph(..) {
        label = item_label(b.md, c)
      } else {
        rest.push(c)
      }
    }
    put(b, b.head + 1 + nest, Line(sign=Item, label~, details~, open~, body=[]))
    // 空打ちでは畳みを見ない（深さを測るのに畳みは要らず、
    // 畳みの判定はこの深さを使うので、呼び合いになる）
    let inner = if b.dry {
      rest.map(c => Raw(c))
    } else {
      pieces(b.md, rest, [], nest + 1)
    }
    for c in inner {
      lay(b, c, nest + 1)
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
  String::unsafe_substring(md, start=span.from, end=reach(md, span.from, len))
}

///|
/// 中身の長さ（容器の字下げと `\r` を除いた数）ぶんだけ原文を進んだ位置。
/// **インラインの span は中身に対する相対**なので、原文の絶対位置にそのまま
/// 足すと、行ごとの字下げと `\r` の総量ぶん手前で切れてラベルの末尾が消える。
fn reach(md : String, from : Int, len : Int) -> Int {
  let indent = column(md, from)
  let mut i = from
  let mut seen = 0
  let mut head = false
  while i < md.length() && seen < len {
    if head {
      let mut k = 0
      while k < indent && i < md.length() && (md[i] == ' ' || md[i] == '\t') {
        i = i + 1
        k = k + 1
      }
      head = false
      continue
    }
    if md[i] == '\r' {
      i = i + 1
      continue
    }
    head = md[i] == '\n'
    i = i + 1
    seen = seen + 1
  }
  i
}

///|
/// 深さ level のノードを置く。浅く戻るときは積んだぶんを落とし、
/// 深く飛ぶときは間を Implicit で埋める（飛びは綴りであって、無ではない）。
fn put(b : Build, level : Int, skel : Notation) -> Unit {
  // 境界のとき、項目は**深さ 2 に直接置く**。項目は相対記法なので深さが
  // 導出値で、引き出し先に合わせて置き直せる（見出しは絶対座標なので
  // 動かせず、足りない深さを Implicit が埋める）
  let level = if b.pend && skel is Line(sign=Item, ..) { 2 } else { level }
  // **見出しは見出しの背骨にしか積まれない。** 項目の枠は見出しの親に
  // なれないので落とす（列 0 の見出しは md でも項目を閉じる）。C17 を
  // 深さ 1 から全部の深さへ広げたもの。これが無いと項目の子が見出しになる
  if skel is Line(sign=Heading, ..) {
    while b.stack.length() > 0 &&
          b.stack[b.stack.length() - 1].skel is Line(sign=Item, ..) {
      ignore(b.stack.unsafe_pop())
    }
  }
  if level == 1 || b.stack.is_empty() {
    // 新しい木を始める。根は側を持たないので、引き出す先が無い —
    // 保留中の水平線は装飾に落ちる
    spill(b)
    b.side = Right
  } else if b.pend {
    // **境界。「直前のものの一部ではない」という宣言**なので、深さ 2 まで
    // 引き出す。足りない深さは下の穴埋めが Implicit で埋める
    while b.stack.length() > 1 {
      ignore(b.stack.unsafe_pop())
    }
  }
  while b.stack.length() >= level {
    ignore(b.stack.unsafe_pop())
  }
  while b.stack.length() < level - 1 {
    let gap : Frame = { skel: Gap, kids: [], side: Right, id: 0 }
    sink(b)
    seat(b, gap)
    b.stack.push(gap)
  }
  let f : Frame = { skel, kids: [], side: Right, id: 0 }
  sink(b)
  seat(b, f)
  b.stack.push(f)
}

///|
/// これから座る枠の深さを控える。深さは stack の高さが持つ。
fn sink(b : Build) -> Unit {
  let depth = b.stack.length() + 1
  if depth < b.low {
    b.low = depth
  }
}

///|
/// 積んである親の子にする。親が居なければ森の 1 本として生やす。
/// **側を持つのは深さ 2 の枠だけ**（根の子）。
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
/// 境界になれなかった水平線を、その場の中身として落とす。
/// 書かれた位置がそのまま保たれる。
fn spill(b : Build) -> Unit {
  if b.pend {
    b.pend = false
    fill(b, ThematicBreak)
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
  String::unsafe_substring(md, start=from, end=reach(md, from, len))
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
  // 中身は子より前に書かれているので、先に振る
  match f.skel {
    Line(body~, ..) => number_details(body, next)
    Gap => ()
  }
  for k in f.kids {
    number(k, next)
  }
}

///|
/// 中身に混ざっている畳みへ、文書順の番号を振る。
fn number_details(body : Array[Block], next : Counter) -> Unit {
  for i, x in body {
    if x is Details(text~, ..) {
      body[i] = Details(id=next.val, text~)
      next.val = next.val + 1
    }
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
    Gap => ImplicitNode({ id: f.id, children: f.kids.map(to_node) })
    Line(sign=Item, label~, details~, open~, body~) =>
      ListNode({
        id: f.id,
        label,
        details,
        open,
        body,
        children: f.kids.map(to_list),
      })
    Line(label~, details~, open~, body~, ..) =>
      HeadingNode({
        id: f.id,
        label,
        details,
        open,
        body,
        children: f.kids.map(to_node),
      })
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
        open: false,
        body: [],
        children: f.kids.map(to_list),
      }
    Line(label~, details~, open~, body~, ..) =>
      { id: f.id, label, details, open, body, children: f.kids.map(to_list) }
  }
}

// 骨格でないものは、いま積んでいるノードの中身になる。
//
// 絵になるのは 4 つ（画像・リンク・コード・SVG）だけで、**疑わしきは読み解かない**。
// 読み解かなければ意味は空で、原文が `source` に残る — 読み解かないと決めることが、
// 「意味を 1 ビットも失わない」の実体になる。

///|
/// 中身を、いま積んでいるノードに足す。骨格がまだ無ければ文書の散文になる。
/// id は割り付けの直前に文書順で振るので、ここでは 0 を置く。
/// `from`・`to` はその中身の原文での範囲で、`to` は持ち主の地番もそこまで伸ばす。
/// `source` は読んだ原文 — 書き戻しはこれをそのまま返す。
fn fill(
  b : Build,
  content : Content?,
  from~ : Int,
  to~ : Int,
  source~ : String?,
) -> Unit {
  let block : Block = { id: 0, content, source, }
  let at : Spot = { from, label: None, to, }
  if b.stack.is_empty() {
    b.body.push(block)
    b.body_at.push(at)
    if to > b.body_to {
      b.body_to = to
    }
    return
  }
  // 飛び（Implicit）は綴りが無いので中身も持てないが、put は必ず実体を最後に
  // 積むので、ここに積まれるのは実体の枠だけ
  let f = b.stack[b.stack.length() - 1]
  f.body.push(block)
  f.body_at.push(at)
  if to > f.to {
    f.to = to
  }
}

///|
/// mdAst のブロック 1 枚の意味。**読み解けなければ None** — 原文は `source` が
/// 持つので、ここで字を抱えない。骨格と区切りはここへ来ない。
fn content_of(md : String, block : @markdown.Block) -> Content? {
  match block {
    FencedCode(info~, code~, ..) => Some(Code(info~, text=code))
    // インデントコードは読めるが書かない（正規形はフェンス）
    IndentedCode(code~, ..) => Some(Code(info="", text=code))
    HtmlBlock(html~, ..) => if is_svg(html) { Some(Svg(html)) } else { None }
    Paragraph(children~, span~, ..) => sole(md, span, children)
    _ => None
  }
}

///|
/// 段落まるごとが 1 枚の絵か。そうでなければ Raw（`text ![a](b)` のように
/// 混ざったものは、切り分けると意味が変わるので分けない）。
fn sole(
  md : String,
  span : @markdown.Span,
  children : Array[@markdown.Inline],
) -> Content? {
  guard children.length() == 1 else { return None }
  match children[0] {
    Image(alt~, url~, title~, ..) => Some(Image(alt~, src=url, title~))
    Link(children~, url~, title~, ..) =>
      Some(Link(text=inline_text(md, span.from, children), href=url, title~))
    // `<URL>`。ライブラリが URL だと言い切っている
    Autolink(url~, ..) => bare(url)
    // 素の URL の行。CommonMark ではただの字なので、URL かどうかはここが見る
    Text(..) => bare(inline_text(md, span.from, children))
    _ => None
  }
}

///|
/// 開ける先（`http(s)`）の URL ちょうど 1 つならリンク。**見える字が URL そのもの**
/// なので text も URL になる。字が混ざる行や開けない scheme は None（疑わしきは Raw）。
///
/// **読みは寛容に、書きは CommonMark に。** 素の URL は CommonMark ではただの字で、
/// リンクとして描くのは GFM の方言。読む側はそれに合わせる。読んだ素の URL は
/// 原文のまま返る（`Block.source`）。`[URL](URL)` に綴るのは mmm が Link を
/// 新しく作るときだけ。
fn bare(text : String) -> Content? {
  let scheme = if text.has_prefix("https://") {
    8
  } else if text.has_prefix("http://") {
    7
  } else {
    return None
  }
  // scheme だけの字は行き先が無い
  guard text.length() > scheme else { return None }
  for i = scheme; i < text.length(); i = i + 1 {
    let c = text[i]
    // 空白が混ざれば URL 1 つの行ではない
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      return None
    }
  }
  Some(Link(text~, href=text, title=""))
}

///|
/// 原文のまま持つ中身（Raw）が段落 1 つなら、その行の列（前後の空白と `\r` を
/// 除き、空の行は落とす）。表・引用・HTML など段落でなければ None。
/// 貼るとき、一番外の段落だけを「行ごとにノード」にするための問い —
/// 段落かどうかは mdAst しか知らないので、ここで読み直す。
pub fn lines(text : String) -> Array[String]? {
  let blocks = read(text).children.filter(b => !(b is BlankLines(..)))
  guard blocks is [Paragraph(..)] else { return None }
  Some(
    text
    .split("\n")
    .map(l => l.trim(chars=" \t\r").to_owned())
    .filter(l => !l.is_empty())
    .collect(),
  )
}

///|
/// インラインの列が原文で占めている範囲。span は中身に対する相対なので、
/// 段落の開始位置を足して絶対に直す。
fn inline_text(
  md : String,
  from : Int,
  children : Array[@markdown.Inline],
) -> String {
  if children.is_empty() {
    return ""
  }
  let a = from + span_of(children[0]).from
  let z = from + span_of(children[children.length() - 1]).to
  String::unsafe_substring(md, start=a, end=z)
}

///|
/// ブロックが原文で占めている綴りそのもの。
fn verbatim(md : String, block : @markdown.Block) -> String {
  let s = block_span(block)
  carve(md, s.from, s.to)
}

///|
/// この範囲に書かれた定義行だけ。定義は文書ぜんぶで 1 列なので、入れ子の中を
/// 読み解くときは切り出して渡す（そうしないと手前の定義が中へ紛れ込む）。
fn defs_in(
  defs : Array[@markdown.Span],
  from : Int,
  to : Int,
) -> Array[@markdown.Span] {
  defs.filter(s => s.from >= from && s.to <= to)
}

///|
/// 原文の切り出し。**容器の字下げは剥がす** — 項目や引用の中では行頭の空白は
/// その容器の記法であって中身ではないので、切り出しに混ぜると列がずれる
/// （深く入れ子にすると、切り出しを読み直したとき字下げコードに化ける）。
/// 1 行目は mdAst の span がもう剥がしているので、残りの行を同じだけ揃える。
/// 末尾の改行も記法なので落とす。
fn carve(md : String, from : Int, to : Int) -> String {
  let mut z = to
  while z > from && (md[z - 1] == '\n' || md[z - 1] == '\r') {
    z = z - 1
  }
  let indent = column(md, from)
  if indent == 0 {
    return String::unsafe_substring(md, start=from, end=z)
  }
  let out = StringBuilder()
  let mut i = from
  let mut head = false
  while i < z {
    if head {
      let mut n = 0
      while n < indent && i < z && (md[i] == ' ' || md[i] == '\t') {
        i = i + 1
        n = n + 1
      }
      head = false
      continue
    }
    let c = md[i]
    out.write_char(c.unsafe_to_char())
    head = c == '\n'
    i = i + 1
  }
  out.to_string()
}

///|
/// 行頭からの桁。容器の字下げの幅になる。
fn column(md : String, at : Int) -> Int {
  let mut i = at
  while i > 0 && md[i - 1] != '\n' {
    i = i - 1
  }
  at - i
}

///|
/// その位置の行の頭。
fn line_start(md : String, at : Int) -> Int {
  at - column(md, at)
}

///|
/// その位置の行の尻（改行の次）。末尾に改行が無ければ文書の尻。
fn line_end(md : String, at : Int) -> Int {
  let mut i = at
  while i < md.length() && md[i] != '\n' {
    i = i + 1
  }
  if i < md.length() {
    i + 1
  } else {
    i
  }
}

///|
/// 行頭 `at` の手前に続く空行の頭。空行が無ければその位置のまま。
/// 空行は「改行までが空白だけの行」— 読みが空行と見るのと同じ。改行は `\n`（CRLF の
/// `\r` は行の中身ではない）。
fn blank_start(md : String, at : Int) -> Int {
  let mut p = at
  while p > 0 && md[p - 1] == '\n' {
    let nl = if p >= 2 && md[p - 2] == '\r' { p - 2 } else { p - 1 }
    let head = line_start(md, nl)
    guard skip_blank(md, head, nl) == nl else { break }
    p = head
  }
  p
}

///|
fn is_svg(html : String) -> Bool {
  let t = html.trim()
  t.has_prefix("<svg") && t.has_suffix("</svg>")
}

///|
fn block_span(b : @markdown.Block) -> @markdown.Span {
  match b {
    ThematicBreak(span~, ..) => span
    Heading(span~, ..) => span
    Paragraph(span~, ..) => span
    FencedCode(span~, ..) => span
    MathBlock(span~, ..) => span
    Directive(span~, ..) => span
    DefinitionList(span~, ..) => span
    Attributed(span~, ..) => span
    IndentedCode(span~, ..) => span
    Blockquote(span~, ..) => span
    Alert(span~, ..) => span
    BulletList(span~, ..) => span
    OrderedList(span~, ..) => span
    HtmlBlock(span~, ..) => span
    Table(span~, ..) => span
    BlankLines(span~, ..) => span
    FootnoteDefinition(span~, ..) => span
  }
}

///|
/// 先頭の `./` を落とした形。`./x` と `x` は同じ場所を指すので、比べる前に
/// 必ずこの形へ寄せる。カードが持つ path も、画像の鍵（app/assets.ts）も、
/// 宣言の下に在るかの判定（read/head.mbt）も、みなこの形
pub fn bare_path(path : String) -> String {
  match path.strip_prefix("./") {
    Some(v) => v.to_owned()
    None => path
  }
}

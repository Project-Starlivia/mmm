// 骨格でないものは中身（`Card`）と裁定され、組み立てが直前の行に配る。
//
// 絵になるのは 4 つ（画像・リンク・コード・SVG）だけで、**疑わしきは読み解かない**。
// 読み解かなければ意味は空で、原文が `source` に残る — 読み解かないと決めることが、
// 「意味を 1 ビットも失わない」の実体になる。

///|
/// mdAst のブロック 1 枚の意味。**読み解けなければ None** — 原文は `source` が
/// 持つので、ここで字を抱えない。骨格と区切りはここへ来ない。
fn content_of(md : String, block : @markdown.Block) -> Content? {
  match block {
    FencedCode(info~, code~, ..) => Some(Code(info~, text=code))
    // インデントコードの意味はフェンスと同じ。記法（字下げ 4 桁）は `source` が持つので、
    // 書き戻せば字下げのまま（方言が span に 4 桁を戻している。#206）
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

// 骨格でないものは、いま積んでいるノードの中身になる。
//
// 絵になるのは 4 つ（画像・リンク・コード・SVG）だけで、**疑わしきは Opaque**。
// Opaque は原文の逐語で、mmm は中を読み解かない — 読み解かないと決めることが、
// 「意味を 1 ビットも失わない」の実体になる。

///|
/// 中身を、いま積んでいるノードに足す。骨格がまだ無ければ文書の散文になる。
fn fill(b : Build, block : Block) -> Unit {
  if b.stack.is_empty() {
    b.body.push(block)
    return
  }
  match b.stack[b.stack.length() - 1].skel {
    Line(body~, ..) => body.push(block)
    // 飛びは綴りが無いので中身も持てない。put は必ず実体を最後に積むので、
    // ここに来ることは無い
    Gap => ()
  }
}

///|
/// mdAst のブロック 1 枚を中身にする。骨格と区切りはここへ来ない。
fn content_of(md : String, block : @markdown.Block) -> Block? {
  match block {
    // 空行は綴りであってモデルには無い。serialize が正規形として置き直す
    BlankLines(..) => None
    FencedCode(info~, code~, ..) => Some(Code(info~, text=code))
    // インデントコードは読めるが書かない（正規形はフェンス）
    IndentedCode(code~, ..) => Some(Code(info="", text=code))
    HtmlBlock(html~, ..) =>
      if is_svg(html) {
        Some(Svg(html))
      } else {
        Some(Opaque(verbatim(md, block)))
      }
    Paragraph(children~, span~, ..) =>
      match sole(md, span, children) {
        Some(c) => Some(c)
        None => Some(Opaque(verbatim(md, block)))
      }
    _ => Some(Opaque(verbatim(md, block)))
  }
}

///|
/// 段落まるごとが 1 枚の絵か。そうでなければ Opaque（`text ![a](b)` のように
/// 混ざったものは、切り分けると意味が変わるので分けない）。
fn sole(
  md : String,
  span : @markdown.Span,
  children : Array[@markdown.Inline],
) -> Block? {
  guard children.length() == 1 else { return None }
  match children[0] {
    Image(alt~, url~, ..) => Some(Image(alt~, src=url))
    Link(children~, url~, ..) =>
      Some(Link(text=inline_text(md, span.from, children), href=url))
    _ => None
  }
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
/// ブロックが原文で占めている綴りそのもの。末尾の改行は綴りなので落とす。
fn verbatim(md : String, block : @markdown.Block) -> String {
  let s = block_span(block)
  let mut z = s.to
  while z > s.from && (md[z - 1] == '\n' || md[z - 1] == '\r') {
    z = z - 1
  }
  String::unsafe_substring(md, start=s.from, end=z)
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

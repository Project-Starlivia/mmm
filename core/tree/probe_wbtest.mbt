///|
/// `$$` と `:::` が mdAst のどのブロックになるかを実測する。
test "probe: $$ と ::: のブロック種" {
  fn kind(b : @markdown.Block) -> String {
    match b {
      MathBlock(span~, ..) => "MathBlock\{span.from},\{span.to}"
      Directive(span~, ..) => "Directive\{span.from},\{span.to}"
      Paragraph(span~, ..) => "Paragraph\{span.from},\{span.to}"
      HtmlBlock(span~, ..) => "HtmlBlock\{span.from},\{span.to}"
      FencedCode(span~, ..) => "FencedCode\{span.from},\{span.to}"
      _ => "other"
    }
  }

  let a = read("# r\n\n$$\nx\n$$\n").children.map(kind)
  let b = read("# r\n\n:::note\nx\n:::\n").children.map(kind)
  json_inspect([a, b], content=[
    ["other", "other", "MathBlock5,10"],
    ["other", "other", "Directive5,15"],
  ])
}

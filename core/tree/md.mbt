// md を読む段。読みの正義は CommonMark で、実装は mizchi/markdown が持つ。
//
// 自前で書かないのは、ブロック規則を手で写すと間違いを照合する相手が
// 居なくなるから。旧 core はそれで往復を壊していた（字下げ行を段落と読み、
// 書き戻すと見出しが生える）。
//
// 払った値段は **配布物で gzip +31KB**（591KB → 622KB。vite の dist で実測）。
// 上流に parser だけを取る道は無く、MoonBit にパッケージ単位の DCE も無い。
// 生の出力では +49KB だが、到達しないコードは rollup が落とす。

///|
/// md の AST。ここを通すことで、パーサの差し替えがこの 1 ファイルに閉じる。
pub fn read(md : String) -> @markdown.Document {
  @markdown.parse(md).document
}

///|
/// ブロック 1 枚の指紋。`種類[from,to]`。入れ子は括弧の中に並べる。
fn dump(b : @markdown.Block) -> String {
  match b {
    ThematicBreak(marker~, count~, span~, ..) =>
      "Rule\{marker}\{count}\{at(span)}"
    Heading(level~, style~, span~, ..) => "H\{level}\{style}\{at(span)}"
    Paragraph(span~, ..) => "P\{at(span)}"
    FencedCode(info~, span~, ..) => "Fence(\{info})\{at(span)}"
    IndentedCode(span~, ..) => "Indent\{at(span)}"
    HtmlBlock(span~, ..) => "Html\{at(span)}"
    BlankLines(count~, span~) => "Blank\{count}\{at(span)}"
    BulletList(marker~, tight~, items~, span~, ..) =>
      "List\{marker}\{tight}\{at(span)}(\{items.length()})"
    OrderedList(items~, span~, ..) => "Ord\{at(span)}(\{items.length()})"
    Blockquote(span~, ..) => "Quote\{at(span)}"
    Table(span~, ..) => "Table\{at(span)}"
    _ => "?"
  }
}

///|
fn at(s : @markdown.Span) -> String {
  "[\{s.from},\{s.to}]"
}

///|
/// 文書ぜんぶの指紋。frontmatter が在れば頭に付く。
pub fn ast_sig(md : String) -> String {
  let doc = read(md)
  let sb = StringBuilder::new()
  match doc.frontmatter {
    Some(f) => sb.write_string("Front\{at(f.span)} ")
    None => ()
  }
  for i, b in doc.children {
    if i > 0 {
      sb.write_string(" ")
    }
    sb.write_string(dump(b))
  }
  sb.to_string()
}

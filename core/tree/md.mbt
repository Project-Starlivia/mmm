// md との境界。読み書きの正義は CommonMark で、実装は mizchi/markdown が持つ。
// ライブラリに触るのはこのファイルだけ — 差し替えがここに閉じる。
//
// 自前で書かないのは、ブロック規則を手で写すと間違いを照合する相手が
// 居なくなるから。旧 core はそれで往復を壊していた（字下げ行を段落と読み、
// 書き戻すと見出しが生える）。
//
// 払った値段は **配布物で gzip +31KB**（591KB → 622KB。vite の dist で実測）。
// 上流に parser だけを取る道は無く、MoonBit にパッケージ単位の DCE も無い。
// 生の出力では +49KB だが、到達しないコードは rollup が落とす。

///|
/// md → mdAst。
pub fn read(md : String) -> @markdown.Document {
  @markdown.parse(md).document
}

///|
/// 木 → 正規形の md。mdAst に戻す（unbuild.mbt）のが我々の仕事で、
/// 綴り（字下げ・フェンス・空行・エスケープ）はライブラリの仕事。
/// ライブラリは LF で書くので、CRLF の文書は最後に揃える。
pub fn serialize(doc : Doc) -> String {
  let body = write(unbuild({ ..doc, frontmatter: None }), doc.eol)
  match doc.frontmatter {
    None => body
    // frontmatter と本文の間は空行 1 つ。読みは frontmatter の後ろの空行を落とすので、書く側で置く
    // （置かないと、反映の base が「頭の要素に隙間は無い」と言って原文の空行を消す）
    Some(raw) => newline("---\n" + raw + "---\n\n", doc.eol) + body
  }
}

///|
/// 部分木 1 つ → 正規形の md（断片）。反映が dirty の地番に差す。
pub fn fragment(
  x : Node,
  depth : Int,
  sides : Array[Side],
  eol : Eol,
) -> String {
  write(unbuild_node(x, depth, sides), eol)
}

///|
/// 散文 → 正規形の md。文書の頭（最初の骨格より前）の断片。
pub fn prose(body : Array[Block], eol : Eol) -> String {
  write(unbuild_prose(body), eol)
}

///|
fn write(ast : @markdown.Document, eol : Eol) -> String {
  newline(@markdown.serialize(ast), eol)
}

///|
/// LF で組んだ字を、文書の改行の流儀に。
fn newline(md : String, eol : Eol) -> String {
  match eol {
    Lf => md
    Crlf => md.replace_all(old="\n", new="\r\n")
  }
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
/// 範囲。組んだ mdAst（unbuild）は位置を持たないので、空なら何も付けない。
fn at(s : @markdown.Span) -> String {
  if s.from == 0 && s.to == 0 {
    ""
  } else {
    "[\{s.from},\{s.to}]"
  }
}

///|
/// md を読んだ mdAst の指紋。
pub fn md_ast_sig(md : String) -> String {
  ast_sig(read(md))
}

///|
/// mdAst ぜんぶの指紋。frontmatter が在れば頭に付く。
pub fn ast_sig(doc : @markdown.Document) -> String {
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

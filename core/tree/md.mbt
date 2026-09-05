// md との境界。読み書きの正義は CommonMark で、実装は mizchi/markdown が持つ。
// ライブラリに触るのはこのファイルだけ — 差し替えがここに閉じる。
//
// 読みも書きも「ライブラリ」と「方言」の直列:
//
//   read(md)   = @markdown.parse(md) |> mend(md)      mdAst → mmm の方言の mdAst
//   write(ast) = @markdown.serialize(ast) |> spell     字 → mmm の綴り
//
// 方言はライブラリの癖を mmm の決めに揃える所で、build / content / fold / reflect は
// 方言の mdAst だけを見る。癖の一覧は docs/core.md「読み書き」。
//
// 自前で書かないのは、ブロック規則を手で写すと間違いを照合する相手が
// 居なくなるから。旧 core はそれで往復を壊していた（字下げ行を段落と読み、
// 書き戻すと見出しが生える）。
//
// 払った値段は **配布物で gzip +31KB**（591KB → 622KB。vite の dist で実測）。
// 上流に parser だけを取る道は無く、MoonBit にパッケージ単位の DCE も無い。
// 生の出力では +49KB だが、到達しないコードは rollup が落とす。

///|
/// md → 方言の mdAst。
pub fn read(md : String) -> @markdown.Document {
  mend(md, @markdown.parse(md).document)
}

///|
/// 読みの方言。span を mmm の決めに揃える — **塊の尻は行末の改行込み**。
/// ライブラリはフェンス付きの塊（コード・`$$`・`:::`）の span を閉じの行の手前で
/// 止め、定義行の span を改行の手前で止める。他の塊（段落・見出し）は改行込みなので
/// 揃える。段落の span が中身の頭から始まること、インラインの span が段落の中身に
/// 対する相対であることは、ライブラリの決めとしてそのまま使う。`Blank` は触らない
/// （入れ子の項目の周りで範囲が壊れているので、隙間は原文の字で測る）。
fn mend(md : String, doc : @markdown.Document) -> @markdown.Document {
  {
    ..doc,
    children: doc.children.map(b => mend_block(md, b)),
    definitions: doc.definitions.map(d => {
      ..d,
      span: { from: d.span.from, to: line_end(md, d.span.to) },
    }),
  }
}

///|
/// 塊 1 つの方言。容器は中まで歩く。
fn mend_block(md : String, b : @markdown.Block) -> @markdown.Block {
  let items = (xs : Array[@markdown.ListItem]) => {
    xs.map(it => { ..it, children: it.children.map(c => mend_block(md, c)) })
  }
  match b {
    FencedCode(
      fence_marker~,
      fence_length~,
      info~,
      code~,
      indent~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      FencedCode(
        fence_marker~,
        fence_length~,
        info~,
        code~,
        indent~,
        span=closed(md, if fence_marker is Backtick { '`' } else { '~' }, span),
        leading_trivia~,
        trailing_trivia~,
      )
    MathBlock(value~, fence_length~, span~, leading_trivia~, trailing_trivia~) =>
      MathBlock(
        value~,
        fence_length~,
        span=closed(md, '$', span),
        leading_trivia~,
        trailing_trivia~,
      )
    Directive(
      name~,
      meta~,
      children~,
      fence_length~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Directive(
        name~,
        meta~,
        children=children.map(c => mend_block(md, c)),
        fence_length~,
        span=closed(md, ':', span),
        leading_trivia~,
        trailing_trivia~,
      )
    BulletList(
      marker~,
      tight~,
      items=xs,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      BulletList(
        marker~,
        tight~,
        items=items(xs),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    OrderedList(
      start~,
      delimiter~,
      tight~,
      items=xs,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      OrderedList(
        start~,
        delimiter~,
        tight~,
        items=items(xs),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Blockquote(children~, span~, leading_trivia~, trailing_trivia~) =>
      Blockquote(
        children=children.map(c => mend_block(md, c)),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Alert(kind~, children~, span~, leading_trivia~, trailing_trivia~) =>
      Alert(
        kind~,
        children=children.map(c => mend_block(md, c)),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    FootnoteDefinition(
      label~,
      children~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      FootnoteDefinition(
        label~,
        children=children.map(c => mend_block(md, c)),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Attributed(block~, attributes~, span~) =>
      Attributed(block=mend_block(md, block), attributes~, span~)
    other => other
  }
}

///|
/// 閉じのフェンスの行の改行まで伸ばした span。次の行が閉じのフェンス（同じ字が
/// 2 つ以上、後ろは空白だけ）でなければそのまま（閉じの無いフェンス）。
fn closed(md : String, fence : UInt16, span : @markdown.Span) -> @markdown.Span {
  let mut i = span.to
  while i < md.length() && (md[i] == '\n' || md[i] == '\r' || md[i] == ' ') {
    i = i + 1
  }
  let from = i
  while i < md.length() && md[i] == fence {
    i = i + 1
  }
  guard i - from >= 2 else { return span }
  while i < md.length() && (md[i] == ' ' || md[i] == '\t') {
    i = i + 1
  }
  if i >= md.length() || md[i] == '\n' || md[i] == '\r' {
    { from: span.from, to: line_end(md, i) }
  } else {
    span
  }
}

///|
/// 木 → 正規形の md。mdAst に戻す（unbuild.mbt）のが我々の仕事で、
/// 綴り（字下げ・フェンス・空行・エスケープ）はライブラリの仕事。
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
/// mdAst → md。ライブラリが LF で書いた字を mmm の綴りに直し、文書の改行の流儀に揃える。
fn write(ast : @markdown.Document, eol : Eol) -> String {
  newline(spell(@markdown.serialize(ast)), eol)
}

///|
/// 書きの綴り。**書いた字を読み直して当てる** — span で当てるので、コードの中の
/// 同じ字は触らない。
///
/// - 区切り線は `---`。ライブラリは marker に関わらず `***` と書く。同じ長さなので
///   置き換えても span はずれない
fn spell(md : String) -> String {
  let rules : Array[@markdown.Span] = []
  fn rule(b : @markdown.Block) {
    match b {
      ThematicBreak(span~, ..) => rules.push(span)
      BulletList(items~, ..) | OrderedList(items~, ..) =>
        for it in items {
          for c in it.children {
            rule(c)
          }
        }
      Blockquote(children~, ..)
      | Alert(children~, ..)
      | Directive(children~, ..)
      | FootnoteDefinition(children~, ..) =>
        for c in children {
          rule(c)
        }
      Attributed(block~, ..) => rule(block)
      _ => ()
    }
  }

  for b in @markdown.parse(md).document.children {
    rule(b)
  }
  // 区切り線の span の中の `*` は marker だけ（同じ長さの `-` に）
  let sb = StringBuilder::new()
  let mut at = 0
  for s in rules {
    sb.write_string(slice(md, at, s.from))
    sb.write_string(slice(md, s.from, s.to).replace_all(old="*", new="-"))
    at = s.to
  }
  sb.write_string(slice(md, at, md.length()))
  sb.to_string()
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
    MathBlock(span~, ..) => "Math\{at(span)}"
    Directive(name~, span~, ..) => "Directive(\{name})\{at(span)}"
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
/// md を読んだ mdAst（方言）の指紋。
pub fn md_ast_sig(md : String) -> String {
  ast_sig(read(md))
}

///|
/// ライブラリが読んだままの mdAst の指紋。方言との差を試験で並べるため。
pub fn raw_ast_sig(md : String) -> String {
  ast_sig(@markdown.parse(md).document)
}

///|
/// mdAst ぜんぶの指紋。frontmatter が在れば頭に付く。定義行は尻に `Def[from,to]`。
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
  for d in doc.definitions {
    sb.write_string(" Def\{at(d.span)}")
  }
  sb.to_string()
}

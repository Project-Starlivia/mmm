// md との境界。読み書きの正義は CommonMark で、実装は mizchi/markdown が持つ。
// ライブラリに触るのはこのファイルだけ — 差し替えがここに閉じる。
//
// 読みも書きも「ライブラリ」と「方言」の直列:
//
//   read(md)   = @markdown.parse(md) |> dialect(md)      mdAst → mmm の方言の mdAst
//   write(ast) = @markdown.serialize(ast) |> spell     字 → mmm の綴り
//
// 方言はライブラリの癖を mmm の決めに揃える所で、build / content / fold / merge は
// 方言の mdAst だけを見る。癖の一覧は docs/core.md「方言」。
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
  dialect(md, @markdown.parse(md).document)
}

///|
/// 読みの方言。span を mmm の決めに揃える — **塊の尻は行末の改行込み**。
/// ライブラリはフェンス付きの塊（コード・`$$`・`:::`）の span を閉じの行の手前で
/// 止め、定義行の span を改行の手前で止める。他の塊（段落・見出し）は改行込みなので
/// 揃える。段落の span が中身の頭から始まること、インラインの span が段落の中身に
/// 対する相対であることは、ライブラリの決めとしてそのまま使う。`Blank` は触らない
/// （入れ子の項目の周りで範囲が壊れているので、隙間は原文の字で測る）。
fn dialect(md : String, doc : @markdown.Document) -> @markdown.Document {
  // フェンス付きの塊の開きの行。閉じのフェンスを探すとき、別の塊の開きを閉じと見ないため
  // （閉じの無いフェンスが容器の尻で切れると、次の開きが閉じに見える）
  let openers : Set[Int] = Set([])
  fn note(b : @markdown.Block) {
    match b {
      FencedCode(span~, ..) | MathBlock(span~, ..) | Directive(span~, ..) =>
        openers.add(line_start(md, span.from))
      _ => ()
    }
    match b {
      BulletList(items~, ..) | OrderedList(items~, ..) =>
        for it in items {
          for c in it.children {
            note(c)
          }
        }
      Blockquote(children~, ..)
      | Alert(children~, ..)
      | Directive(children~, ..)
      | FootnoteDefinition(children~, ..) =>
        for c in children {
          note(c)
        }
      Attributed(block~, ..) => note(block)
      _ => ()
    }
  }

  for b in doc.children {
    note(b)
  }
  {
    ..doc,
    children: dialect_blocks(md, openers, doc.children),
    // ライブラリの定義行の span は、次も定義行なら改行込み・そうでなければ改行の手前で
    // 止まる。改行の手前なら改行まで、もう改行の次なら据え置き
    definitions: doc.definitions.map(d => {
      ..d,
      span: { from: d.span.from, to: after_newline(md, d.span.to) },
    }),
  }
}

///|
/// 塊の列の方言。伸ばした span に丸ごと飲まれた塊は落とす — 入れ子の `:::` の閉じを
/// ライブラリが段落と読むと、外の span を閉じまで伸ばした後に同じ字が 2 度書かれる。
fn dialect_blocks(
  md : String,
  openers : Set[Int],
  bs : Array[@markdown.Block],
) -> Array[@markdown.Block] {
  let out : Array[@markdown.Block] = []
  let mut reach = -1
  for b in bs {
    let m = dialect_block(md, openers, b)
    let s = block_span(m)
    if s.from < reach && s.to <= reach {
      continue
    }
    if s.to > reach {
      reach = s.to
    }
    out.push(m)
  }
  out
}

///|
/// 塊 1 つの方言。容器は中まで歩く。
fn dialect_block(
  md : String,
  openers : Set[Int],
  b : @markdown.Block,
) -> @markdown.Block {
  let inner = (bs : Array[@markdown.Block]) => dialect_blocks(md, openers, bs)
  let items = (xs : Array[@markdown.ListItem]) => {
    xs.map(it => { ..it, children: inner(it.children) })
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
        span=closed(
          md,
          openers,
          if fence_marker is Backtick {
            '`'
          } else {
            '~'
          },
          span,
        ),
        leading_trivia~,
        trailing_trivia~,
      )
    MathBlock(value~, fence_length~, span~, leading_trivia~, trailing_trivia~) =>
      MathBlock(
        value~,
        fence_length~,
        span=closed(md, openers, '$', span),
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
    ) => {
      // 中身が 2 塊以上だと span は最初の塊の尻で止まる。中身の尻まで伸ばしてから閉じを探す
      let kids = inner(children)
      let to = kids.fold(init=span.to, (t, c) => {
        let s = block_span(c)
        if s.to > t {
          s.to
        } else {
          t
        }
      })
      Directive(
        name~,
        meta~,
        children=kids,
        fence_length~,
        span=closed(md, openers, ':', { from: span.from, to }),
        leading_trivia~,
        trailing_trivia~,
      )
    }
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
        children=inner(children),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Alert(kind~, children~, span~, leading_trivia~, trailing_trivia~) =>
      Alert(
        kind~,
        children=inner(children),
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
        children=inner(children),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Attributed(block~, attributes~, span~) =>
      Attributed(block=dialect_block(md, openers, block), attributes~, span~)
    other => other
  }
}

///|
/// 閉じのフェンスの行の改行まで伸ばした span。**次の行**が閉じのフェンス（同じ字が
/// 2 つ以上、後ろは空白だけ）でなければそのまま（閉じの無いフェンス）。
/// 閉じの字数を開きと比べないのは、ライブラリが span を早く切るのが容器の尻と文書の尻だけで、
/// 短い閉じは中身として正しく読まれているから
fn closed(
  md : String,
  openers : Set[Int],
  fence : UInt16,
  span : @markdown.Span,
) -> @markdown.Span {
  // 生の span の尻は最後の中身の行の改行の次（= 次の行の頭）。字下げだけ飛ばし、
  // 空行は越えない。その行が別のフェンスの開きなら、それは閉じではない
  if openers.contains(span.to) {
    return span
  }
  let mut i = span.to
  while i < md.length() && md[i] == ' ' {
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
/// at が改行ならその行の終わり（改行の次）、でなければ at のまま。
fn after_newline(md : String, at : Int) -> Int {
  if at < md.length() && (md[at] == '\n' || md[at] == '\r') {
    line_end(md, at)
  } else {
    at
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
    // （置かないと、合流の base が「頭の要素に隙間は無い」と言って原文の空行を消す）
    Some(raw) => newline("---\n" + raw + "---\n\n", doc.eol) + body
  }
}

///|
/// 部分木 1 つ → 正規形の md（断片）。合流が dirty の地番に差す。
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
///   置き換えても span はずれない。**段落の直後に立つ線だけは `***` のまま** — そこに
///   `---` を置くと setext 見出しの下線になる（引用と詰まった項目の中でライブラリが
///   空行を落とすとき）
fn spell(md : String) -> String {
  let rules : Array[@markdown.Span] = []
  fn rule(b : @markdown.Block) {
    match b {
      ThematicBreak(span~, ..) => if alone(md, span.from) { rules.push(span) }
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
/// その行の直前の行が空か（容器の前置き `>` と空白だけか）。文書の頭も空。
fn alone(md : String, at : Int) -> Bool {
  let head = line_start(md, at)
  if head == 0 {
    return true
  }
  let prev = line_start(md, head - 1)
  for k in prev..<(head - 1) {
    if md[k] != ' ' && md[k] != '\t' && md[k] != '>' {
      return false
    }
  }
  true
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

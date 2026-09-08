// md との境界。読み書きの正義は CommonMark で、実装は mizchi/markdown が持つ。
// ライブラリに触るのはこのファイルだけ — 差し替えがここに閉じる。
//
// 読みも書きも「ライブラリ」と「方言」の直列:
//
//   read(md)   = @markdown.parse(md) |> stretch(md)      mdAst → mmm の方言の mdAst
//   write(ast) = @markdown.serialize(ast)
//
// 方言はライブラリの癖を mmm の決めに揃える所で、**意味は 1 つも足さない** —
// やるのは span の尻を行末まで伸ばすことだけ（`stretch`）。build / content / fold / merge は
// 方言の mdAst だけを見る。癖の一覧は docs/core.md「方言」。書く側に方言は要らない
// — 読んだ原文は生の塊で渡すので、ライブラリが綴るのは並びと字下げだけ。
// 例外は項目の列（unbuild.mbt）— マーカー・ラベルの桁・詰めをライブラリの書き手が
// 読まないので、そこだけ mmm が組んだ字を生の塊で渡す。
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
  stretch(md, @markdown.parse(md).document)
}

///|
/// 読みの方言。span を mmm の決めに揃える — **塊の尻は行末の改行込み**。
/// ライブラリはフェンス付きの塊（コード・`$$`・`:::`）の span を閉じの行の手前で
/// 止め、定義行の span を改行の手前で止める。他の塊（段落・見出し）は改行込みなので
/// 揃える。段落の span が中身の頭から始まること、インラインの span が段落の中身に
/// 対する相対であることは、ライブラリの決めとしてそのまま使う。`Blank` は触らない
/// （入れ子の項目の周りで範囲が壊れているので、隙間は原文の字で測る）。
fn stretch(md : String, doc : @markdown.Document) -> @markdown.Document {
  {
    ..doc,
    children: stretch_all(md, openers_of(md, doc.children), doc.children),
    // ライブラリの定義行の span は、次も定義行なら改行込み・そうでなければ改行の手前で
    // 止まる。改行の手前なら改行まで、もう改行の次なら据え置き
    definitions: doc.definitions.map(d => {
      ..d,
      span: { from: d.span.from, to: after_newline(md, d.span.to), },
    }),
  }
}

///|
/// フェンス付きの塊の開きの行。閉じのフェンスを探すとき、別の塊の開きを閉じと
/// 見ないために要る（閉じの無いフェンスが容器の尻で切れると、次の開きが閉じに見える）。
fn openers_of(md : String, blocks : Array[@markdown.Block]) -> Set[Int] {
  let out : Set[Int] = Set([])
  fn note(b : @markdown.Block) {
    match b {
      FencedCode(span~, ..) | MathBlock(span~, ..) | Directive(span~, ..) =>
        out.add(line_start(md, span.from))
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

  for b in blocks {
    note(b)
  }
  out
}

///|
/// 塊の列。1 枚ずつ伸ばしてから、丸ごと飲まれた塊を落とす。
fn stretch_all(
  md : String,
  openers : Set[Int],
  bs : Array[@markdown.Block],
) -> Array[@markdown.Block] {
  unswallowed(bs.map(b => stretch_block(md, openers, b)))
}

///|
/// 伸ばした span に丸ごと飲まれた塊を落とす — 入れ子の `:::` の閉じを
/// ライブラリが段落と読むと、外の span を閉じまで伸ばした後に同じ字が 2 度書かれる。
fn unswallowed(bs : Array[@markdown.Block]) -> Array[@markdown.Block] {
  let out : Array[@markdown.Block] = []
  let mut reach = -1
  for b in bs {
    let s = block_span(b)
    if s.from < reach && s.to <= reach {
      continue
    }
    if s.to > reach {
      reach = s.to
    }
    out.push(b)
  }
  out
}

///|
/// 塊 1 つ。**容器を先に歩く** — `:::` は中身の尻まで伸ばしてから閉じを探すので、
/// 中の塊が伸びた後でないと尻が決まらない。
fn stretch_block(
  md : String,
  openers : Set[Int],
  b : @markdown.Block,
) -> @markdown.Block {
  stretched(md, openers, nested(md, openers, b))
}

///|
/// フェンス付きの塊（コード・`$$`・`:::`）の span を、閉じの行の改行まで伸ばす。
/// ほかの塊はそのまま。
fn stretched(
  md : String,
  openers : Set[Int],
  b : @markdown.Block,
) -> @markdown.Block {
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
      let to = children.fold(init=span.to, (t, c) => {
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
        children~,
        fence_length~,
        span=closed(md, openers, ':', { from: span.from, to, }),
        leading_trivia~,
        trailing_trivia~,
      )
    }
    other => other
  }
}

///|
/// 容器の中の塊も方言に直す。ほかの塊はそのまま。
fn nested(
  md : String,
  openers : Set[Int],
  b : @markdown.Block,
) -> @markdown.Block {
  let inner = (bs : Array[@markdown.Block]) => stretch_all(md, openers, bs)
  match b {
    BulletList(
      marker~,
      tight~,
      items~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      BulletList(
        marker~,
        tight~,
        items=items.map(it => { ..it, children: inner(it.children), }),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    OrderedList(
      start~,
      delimiter~,
      tight~,
      items~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      OrderedList(
        start~,
        delimiter~,
        tight~,
        items=items.map(it => { ..it, children: inner(it.children), }),
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
        children=inner(children),
        fence_length~,
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
      Attributed(block=stretch_block(md, openers, block), attributes~, span~)
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
    { from: span.from, to: line_end(md, i), }
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
/// 木 → 正規形の md。mdAst に戻す（unbuild.mbt）のが我々の仕事で、綴りは木が持つ
/// 読んだ字（`source` / `rules` / `marker` / `offset` / `loose` / `setext`）から出る。
/// ライブラリがやるのはブロックの並べ方と字下げだけ。
pub fn serialize(doc : Doc) -> String {
  let body = write(unbuild({ ..doc, frontmatter: None, }))
  match doc.frontmatter {
    None => body
    // frontmatter と本文の間は空行 1 つ。読みは frontmatter の後ろの空行を落とすので、書く側で置く
    // （置かないと、合流の base が「頭の要素に隙間は無い」と言って原文の空行を消す）
    Some(raw) => "---\n" + raw + "---\n\n" + body
  }
}

///|
/// 部分木 1 つ → 正規形の md（断片）。合流が dirty の地番に差す。
pub fn fragment(
  x : Node,
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> String {
  write(unbuild_node(x, depth, sides, rules))
}

///|
/// 散文 → 正規形の md。文書の頭（最初の骨格より前）の断片。
pub fn prose(body : Array[Block]) -> String {
  write(unbuild_prose(body))
}

///|
/// mdAst → md。**改行は LF だけ**（spec「文字コードと改行」）。
fn write(ast : @markdown.Document) -> String {
  @markdown.serialize(ast)
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
  let sb = StringBuilder()
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

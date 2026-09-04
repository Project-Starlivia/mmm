// 骨格でないものは、いま積んでいるノードの中身になる。
//
// 絵になるのは 4 つ（画像・リンク・コード・SVG）だけで、**疑わしきは Opaque**。
// Opaque は原文のままで、mmm は中を読み解かない — 読み解かないと決めることが、
// 「意味を 1 ビットも失わない」の実体になる。

///|
/// 中身を、いま積んでいるノードに足す。骨格がまだ無ければ文書の散文になる。
/// id は割り付けの直前に文書順で振るので、ここでは 0 を置く。
/// `from`・`to` はその中身の原文での範囲で、`to` は持ち主の地番もそこまで伸ばす。
fn fill(b : Build, content : Content, from~ : Int, to~ : Int) -> Unit {
  let block : Block = { id: 0, content }
  let at : Spot = { from, label: None, to }
  if b.stack.is_empty() {
    b.body.push(block)
    b.body_at.push(at)
    if to > b.body_to {
      b.body_to = to
    }
    return
  }
  let f = b.stack[b.stack.length() - 1]
  match f.skel {
    Line(body~, ..) => {
      body.push(block)
      f.body_at.push(at)
    }
    // 飛びは綴りが無いので中身も持てない。put は必ず実体を最後に積むので、
    // ここに来ることは無い
    Gap => ()
  }
  if to > f.to {
    f.to = to
  }
}

///|
/// mdAst のブロック 1 枚を中身にする。骨格と区切りはここへ来ない。
fn content_of(md : String, block : @markdown.Block) -> Content? {
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
) -> Content? {
  guard children.length() == 1 else { return None }
  match children[0] {
    Image(alt~, url~, title~, ..) => Some(Image(alt~, src=url, title~))
    Link(children~, url~, title~, ..) =>
      Some(Link(text=inline_text(md, span.from, children), href=url, title~))
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
/// ブロックが原文で占めている綴りそのもの。
fn verbatim(md : String, block : @markdown.Block) -> String {
  let s = block_span(block)
  carve(md, s.from, closing(md, block, s.to))
}

///|
/// 閉じのフェンスまで含めた終わり。`$$` / `:::` / コードの span は閉じの行を
/// 含まないので、原文のまま持つと閉じが落ち、地番で切り出すと閉じが残る。
/// コードのフェンスは開きの字（`` ` `` か `~`）で閉じる
fn closing(md : String, block : @markdown.Block, to : Int) -> Int {
  let fence : UInt16 = match block {
    MathBlock(..) => '$'
    Directive(..) => ':'
    FencedCode(span~, ..) => {
      let mut j = span.from
      while j < md.length() && md[j] == ' ' {
        j = j + 1
      }
      guard j < md.length() else { return to }
      md[j]
    }
    _ => return to
  }
  // 次の行が閉じのフェンスだけなら、その行の終わりまで
  let mut i = to
  while i < md.length() && (md[i] == '\n' || md[i] == '\r' || md[i] == ' ') {
    i = i + 1
  }
  let from = i
  while i < md.length() && md[i] == fence {
    i = i + 1
  }
  guard i - from >= 2 else { return to }
  while i < md.length() && (md[i] == ' ' || md[i] == '\t') {
    i = i + 1
  }
  if i >= md.length() || md[i] == '\n' || md[i] == '\r' {
    i
  } else {
    to
  }
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
  let out = StringBuilder::new()
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

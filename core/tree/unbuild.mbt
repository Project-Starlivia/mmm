// mmmTree → mdAst。build の逆。
//
// 我々の写像は**骨格だけ** — 深さを `#` の数に、側の変わり目を水平線に、
// 畳みを `<details>` の塊にする。ラベルも中身も原文の字を生のまま渡す
// （md として読み直さない）。
//
// **読んだ原文はそのまま返す。** ライブラリが担うのはブロックの並びと前後の空行
// だけ。綴るのは mmm が新しく作ったものだけ。項目の列は、マーカー・ラベルの桁・
// 詰めを読める者がライブラリに居ないので、列 1 本ぶんの字を mmm が組む
// （中身はライブラリに綴らせて桁ぶん字下げする）。

///|
/// 木を mdAst にする。
pub fn unbuild(doc : Doc) -> @markdown.Document {
  let out = []
  for b in doc.body {
    content(out, b)
  }
  for r in doc.roots {
    node(out, r.node, 1, r.sides, r.rules)
  }
  {
    // serialize は frontmatter を自分で書く（本文との間に空行を置くため）。
    // ここで持つのは、指紋（ast_sig）が mdAst ぜんぶを見るため
    frontmatter: doc.frontmatter.map(raw => {
      ({ raw, entries: [], span: nowhere, } : @markdown.Frontmatter)
    }),
    children: out,
    definitions: [],
    span: nowhere,
  }
}

///|
/// 部分木 1 つを mdAst にする（断片）。`depth` はその根の見出しの深さ、
/// `sides` と `rules` は Doc の根のときだけ在る。
pub fn unbuild_node(
  x : Node,
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> @markdown.Document {
  let out = []
  node(out, x, depth, sides, rules)
  { frontmatter: None, children: out, definitions: [], span: nowhere, }
}

///|
/// 散文（骨格を持たない中身の列）を mdAst にする。
pub fn unbuild_prose(body : Array[Block]) -> @markdown.Document {
  let out = []
  for b in body {
    content(out, b)
  }
  { frontmatter: None, children: out, definitions: [], span: nowhere, }
}

///|
/// 位置は持たない。mdAst の span は原文の座標で、組んだ木に原文は無い。
let nowhere : @markdown.Span = @markdown.Span::empty()

///|
/// 兄弟の列を書く。`sides` と `rules` は根の子のときだけ来る（深い所の側は型に無い）。
///
/// **続く項目は 1 つの列にまとめる**（兄弟は詰める）。列が割れるのは、側が
/// 変わるとき（間に水平線）と、畳まれた項目（自分の `<details>` に包まれる）と、
/// マーカーの種類が変わるとき（md でもそこで別の列になる）。
/// 水平線は読んだ綴りをそのまま。無ければ（操作が作った境界）`---`。
fn nodes(
  out : Array[@markdown.Block],
  xs : Array[Node],
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> Unit {
  let run : Array[Node] = []
  fn flush() {
    if !run.is_empty() {
      out.push(bullets(run))
      run.clear()
    }
  }

  let mut prev = Right
  for i, x in xs {
    let side = if i < sides.length() { sides[i] } else { prev }
    if side != prev {
      flush()
      let rule = if i < rules.length() { rules[i] } else { "" }
      out.push(html(if rule == "" { "---" } else { rule }))
      prev = side
    }
    match x.mark {
      Some(Item(marker~, ..)) if x.fold is None => {
        if run is [first, ..] && kind_of(marker_of(first)) != kind_of(marker) {
          flush()
        }
        run.push(x)
      }
      _ => {
        flush()
        node(out, x, depth, [], [])
      }
    }
  }
  flush()
}

///|
/// ノード 1 つと、その部分木。`sides` と `rules` はその子に効く（根のときだけ在る）。
/// 項目の根に側は書けない — 項目の中の水平線は中身なので、側は落ちる。
fn node(
  out : Array[@markdown.Block],
  x : Node,
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> Unit {
  match x.mark {
    Some(Item(..)) => wrap(out, x.fold, () => out.push(bullets([x])))
    Some(Heading(setext~, closing~)) =>
      wrap(out, x.fold, () => {
        out.push(heading(depth, x.label, setext, closing))
        for b in x.body {
          content(out, b)
        }
        nodes(out, x.children, depth + 1, sides, rules)
      })
    None => nodes(out, x.children, depth + 1, sides, rules)
  }
}

///|
/// 畳みで包む。開きの塊は「開き」か「開き + 名前」、閉じは閉じだけ。
fn wrap(out : Array[@markdown.Block], fold : Fold?, inner : () -> Unit) -> Unit {
  match fold {
    None => inner()
    Some({ open, summary, }) => {
      let head = StringBuilder()
      head.write_string(spelling(Open(open~)))
      match summary {
        Some(s) => {
          head.write_char('\n')
          head.write_string(spelling(Name(s)))
        }
        None => ()
      }
      out.push(html(head.to_string()))
      inner()
      out.push(html(spelling(Close)))
    }
  }
}

///|
/// 項目の列 1 つ。**列の字は mmm が組む** — マーカー・ラベルの桁・項目の間の
/// 詰めを読める者がライブラリに居ないので、包み（`HtmlBlock`）の中だけ自分で
/// 綴る。文書の中での並びと前後の空行はライブラリのまま。
///
/// 空行は 2 か所に要る。**項目と項目の間**は、読んだ列が loose だったとき。
/// **ラベルと中身の間**は、ラベルと入れ子の列だけの項目が並ぶとき以外（`tight`）—
/// 中身は空行で分けないと段落に飲み込まれ、畳まれた子の `<details>` は空行で
/// 終わる塊なので、分けないと次の項目を飲み込む。ラベルの直後の空の項目も
/// 分ける（`underlined`）— 正規形は並びで変わる。
fn bullets(run : Array[Node]) -> @markdown.Block {
  let tight = run
    .iter()
    .all(l => {
      l.body.is_empty() &&
      l.children.iter().all(c => c.fold is None) &&
      !underlined(l)
    })
  let loose = run.iter().any(l => l.mark is Some(Item(loose=true, ..)))
  let sb = StringBuilder()
  for i, l in run {
    if i > 0 && loose {
      sb.write_char('\n')
    }
    sb.write_string(list_item(l, tight))
  }
  html(sb.to_string())
}

///|
/// マーカーの種類。番号なら尻の 1 字（`.` か `)`）、でなければマーカーそのもの。
/// 種類が変われば md でもそこで列が割れるので、書くときも割る。
fn kind_of(marker : String) -> String {
  if marker.length() > 0 && marker[0] >= '0' && marker[0] <= '9' {
    String::unsafe_substring(
      marker,
      start=marker.length() - 1,
      end=marker.length(),
    )
  } else {
    marker
  }
}

///|
/// ラベルの直後に空の項目が続く形。詰めて書くと `-` 1 本が段落の setext の
/// 下線に読まれ、ラベルが消えて子も読まれない。空行で分ければ空の項目に読まれる。
fn underlined(l : Node) -> Bool {
  l.label != "" && l.children is [{ label: "", .. }, ..]
}

///|
/// 項目 1 つ。1 行目はマーカーとラベル、続きは中身と入れ子の列 —
/// **その字はライブラリに綴らせ**、ラベルの桁ぶん字下げしてぶら下げる。
/// ラベルも中身も無ければマーカーだけの行。
fn list_item(l : Node, tight : Bool) -> String {
  let kids = []
  for b in l.body {
    content(kids, b)
  }
  // **項目の中は、その項目の深さを 0 とした文書。** 子の見出しは項目からの
  // 深さぶんの `#` で書く（docs/spec.md「項目の中」）
  nodes(kids, l.children, 1, [], [])
  let inner = StringBuilder()
  if l.label != "" {
    inner.write_string(l.label)
    inner.write_char('\n')
  }
  if !kids.is_empty() {
    if l.label != "" && !tight {
      inner.write_char('\n')
    }
    inner.write_string(
      write({
        frontmatter: None,
        children: kids,
        definitions: [],
        span: nowhere,
      }),
    )
  }
  let marker = marker_of(l)
  let text = inner.to_string()
  if text == "" {
    return marker + "\n"
  }
  // ラベルの桁は読んだ幅。マーカーで埋まっていれば空白 1 つ
  let offset = match l.mark {
    Some(Item(offset~, ..)) => offset
    _ => 0
  }
  let width = if offset > marker.length() {
    offset
  } else {
    marker.length() + 1
  }
  marker + pad(width - marker.length()) + indent(text, width)
}

///|
/// 読んだマーカーの字。項目でなければ既定（項目として書く席に来ている）。
fn marker_of(l : Node) -> String {
  match l.mark {
    Some(Item(marker~, ..)) => marker
    _ => "-"
  }
}

///|
/// 中身 1 枚。**読んだ原文はそのまま返す。** mmm が作った中身（source が無い）だけ、
/// 種類ごとに綴る — 絵の 3 つは mdAst の形で、原文で持つものは生の塊で。
fn content(out : Array[@markdown.Block], b : Block) -> Unit {
  match b.source {
    Some(source) => out.push(html(source))
    None =>
      match b.content {
        Image(alt~, src~, title~) =>
          out.push(paragraph([Image(alt~, url=src, title~, span=nowhere)]))
        Link(text~, href~, title~) =>
          out.push(
            paragraph([
              Link(
                children=[verbatim_inline(text)],
                url=href,
                title~,
                span=nowhere,
              ),
            ]),
          )
        Code(info~, text~) =>
          out.push(
            FencedCode(
              fence_marker=Backtick,
              fence_length=3,
              info~,
              code=text,
              indent=0,
              span=nowhere,
              leading_trivia=@markdown.Trivia::empty(),
              trailing_trivia=@markdown.Trivia::empty(),
            ),
          )
        Svg(s) => out.push(html(s))
        ThematicBreak => out.push(html("---"))
        Details(text~, ..) => out.push(html(text))
        Raw(text) => out.push(html(text))
      }
  }
}

///|
/// 見出しの行。**名前は md の 1 行の原文**なので、ライブラリに読み直させず
/// 生の行として渡す（`HtmlBlock` は中身を逃がさずそのまま書く）。
/// 空の名前は `##` だけ（Implicit を綴った空の見出しと同じ）。
///
/// setext は深さ 2 までしか無いので、深ければ ATX。名前が空でも ATX —
/// 下線だけの行は下線にならず、見出しごと段落に落ちる。閉じの `#` は読んだ数。
///
/// **改行を含む名前は setext でしか書けない**ので、読んだ綴りが setext でなくても
/// setext で綴る（ATX に落とすと 2 行目が名前から千切れる）。書けない深さは check が断る。
fn heading(
  depth : Int,
  label : String,
  setext : Bool,
  closing : Int,
) -> @markdown.Block {
  if (setext || label.contains("\n")) && depth <= 2 && label != "" {
    let line = String::make(3, if depth == 1 { '=' } else { '-' })
    return html(label + "\n" + line)
  }
  let sharps = String::make(depth, '#')
  let tail = if closing > 0 { " " + String::make(closing, '#') } else { "" }
  html(if label == "" { sharps } else { sharps + " " + label + tail })
}

///|
/// 項目の名前と Link の題。生の字として段落に置く（逃がさない）。
fn verbatim_inline(text : String) -> @markdown.Inline {
  HtmlInline(html=text, span=nowhere)
}

///|
fn paragraph(children : Array[@markdown.Inline]) -> @markdown.Block {
  Paragraph(
    children~,
    span=nowhere,
    leading_trivia=@markdown.Trivia::empty(),
    trailing_trivia=@markdown.Trivia::empty(),
  )
}

///|
fn html(s : String) -> @markdown.Block {
  HtmlBlock(
    html=s,
    span=nowhere,
    leading_trivia=@markdown.Trivia::empty(),
    trailing_trivia=@markdown.Trivia::empty(),
  )
}

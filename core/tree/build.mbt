// mdAst → mmmTree。mmm の解釈はここにしか無い。
//
// 骨格（見出しと項目）を深さで積み上げる。深さが飛んだら、間を Implicit が
// 埋める — 飛びは構造なので保存し、綴りが無いことだけを型で表す。
//
// 積むあいだは深さだけを見る平らな Frame で持ち、根と側の割り付け
// への割り付けは最後に 1 回だけやる。深さ 1 / 2 / 3 以降で型が違うので、
// その違いをここへ閉じ込める。

///|
/// 積み上げ中のノード。深さは stack の高さが持つので、自分では持たない。
priv struct Frame {
  skel : Notation
  kids : Array[Frame]
  /// 深さ 2 の枠だけが持つ。深い所の側は型に存在しない
  mut side : Side
  /// 文書順の番号。形を割り付ける前に振るので、割り付けが順序を動かしても動かない
  mut id : Int
  /// 原文の範囲（地番）。骨格の行の頭から、自分の最後の中身の尻まで。
  /// 飛び（Gap）は行を持たないので -1 で置き、最後に子の和で埋める
  mut from : Int
  mut to : Int
  /// ラベルの頭（マーカーの後ろ）。飛び（Gap）は行を持たないので -1
  label : Int
  /// 中身（body）と並走する地番。chart が番号と付き合わせて spans に写す
  body_at : Array[Spot]
}

///|
/// 行に書かれていた記法。見出しと項目を 1 つの型で平らに持ち、
/// 種類ごとの型への割り付けは最後に 1 回だけやる。
priv enum Notation {
  /// 記法が無い。深さの飛びがそれを言う
  Gap
  Line(sign~ : Sign, label~ : String, fold~ : Fold?, body~ : Array[Block])
}

///|
/// md を木にする。
pub fn parse(md : String) -> Doc {
  build(md, read(md)).0
}

///|
/// 地番。ノードが原文のどこに書かれているか。`label` はラベルの頭（マーカーの後ろ）で、
/// 選択が md の打鍵をまたいで同じノードを指し続けるための目印（follow.mbt）。
/// Implicit と文書の散文は行を持たないので None。
pub(all) struct Spot {
  from : Int
  label : Int?
  to : Int
} derive(Eq, Debug, ToJson)

///|
/// md を木にし、地番（ノード id → 原文の範囲）も返す。合流が使う。
pub fn survey(md : String) -> (Doc, Map[Int, Spot]) {
  build(md, read(md))
}

///|
/// mdAst を mmmTree にする。ラベルは原文から切り出す（mmm はインラインを解釈しない）。
/// 地番は Doc に載せず並べて返す — 載せると Doc が特定の原文に縛られ、
/// 手で組む木に在り得ない欄が生える。
pub fn build(md : String, ast : @markdown.Document) -> (Doc, Map[Int, Spot]) {
  let b : Build = {
    md,
    defs: ast.definitions.map(d => d.span),
    roots: [],
    stack: [],
    body: [],
    body_at: [],
    body_to: 0,
    side: Right,
    pend: false,
    pend_from: 0,
    pend_to: 0,
    fold_at: None,
    top: deep,
    own: deep,
    dry: false,
    owner: 0,
  }
  for piece in pieces(md, ast.children, b.defs, 0) {
    lay(b, piece, 0)
  }
  // 行き先の見出し・項目が来ないまま終わった水平線は、その場の中身に落ちる
  spill(b)
  let next = { val: doc_id + 1 }
  let roots = b.roots
  // 文書の中身は最初の見出し・項目より前にあるので、先に振る
  number_blocks(b.body, next)
  for f in roots {
    number_frame(f, next)
  }
  let spans : Map[Int, Spot] = Map([])
  // 文書の散文は frontmatter の尻から。中身が無ければ空の範囲
  let from = match ast.frontmatter {
    Some(f) => f.span.to
    None => 0
  }
  spans[doc_id] = {
    from,
    label: None,
    to: if b.body_to > from {
      b.body_to
    } else {
      from
    },
  }
  for i, at in b.body_at {
    spans[b.body[i].id] = at
  }
  for f in roots {
    chart(f, spans)
  }
  let doc : Doc = {
    frontmatter: ast.frontmatter.map(f => f.raw),
    eol: if b.md.contains("\r\n") {
      Crlf
    } else {
      Lf
    },
    body: b.body,
    roots: roots.map(to_root),
  }
  (doc, spans)
}

///|
/// 地番の指紋。`id[from,label,to]` を id 順に並べる。
pub fn spans_sig(md : String) -> String {
  let (_, spans) = survey(md)
  let ids = spans.keys().collect()
  ids.sort()
  ids
  .map(id => {
    match spans.get(id) {
      Some(s) => {
        let label = match s.label {
          Some(l) => l.to_string()
          None => "-"
        }
        "\{id}[\{s.from},\{label},\{s.to}]"
      }
      None => ""
    }
  })
  .join(" ")
}

///|
/// 地番を id で引けるようにする。飛びは子の和 — 子を先に埋めるので、
/// 飛びの中の飛びも埋まる。畳みの尻（`</details>`）は子より後ろに在るので、
/// 大きいほうを採れば保たれる。
fn chart(f : Frame, spans : Map[Int, Spot]) -> Unit {
  for k in f.kids {
    chart(k, spans)
  }
  if !f.kids.is_empty() {
    if f.from < 0 {
      f.from = f.kids[0].from
    }
    let last = f.kids[f.kids.length() - 1].to
    if last > f.to {
      f.to = last
    }
  }
  spans[f.id] = {
    from: f.from,
    label: if f.label < 0 {
      None
    } else {
      Some(f.label)
    },
    to: f.to,
  }
  match f.skel {
    Line(body~, ..) =>
      for i, at in f.body_at {
        spans[body[i].id] = at
      }
    Gap => ()
  }
}

///|
/// 文書そのものの id。親を指すときの番兵。
pub let doc_id : Int = 1

///|
/// 積み上げの途中。**深さを持つのは `stack` だけ** — 見出しの `#` の数を
/// 控えると、境界が枠を引き出したあとに元の数から数えてしまう。
priv struct Build {
  md : String
  /// 文書ぜんぶのリンクの定義行。項目の中を読み解くときに切り出して渡す
  defs : Array[@markdown.Span]
  roots : Array[Frame]
  stack : Array[Frame]
  /// 最初の骨格より前の散文
  body : Array[Block]
  /// その散文と並走する地番
  body_at : Array[Spot]
  /// その散文の尻（地番）
  mut body_to : Int
  /// 次の子の側。木が変わるたびに右へ戻る
  mut side : Side
  /// 行き先待ちの水平線が有るか。**本数に意味は無い**ので Bool で持つ
  mut pend : Bool
  /// その水平線の頭。飾りに落ちたとき地番に入れる
  mut pend_from : Int
  /// その水平線の尻。飾りに落ちたとき地番に入れる
  mut pend_to : Int
  /// いま積む骨格が畳まれているなら、その `<details>` 〜 `</details>` の範囲
  mut fold_at : @markdown.Span?
  /// このブロックで生まれた一番浅い枠の深さ。骨格でなければ `deep` のまま
  mut top : Int
  /// このブロック自身のノードの深さ。飛びを埋めた Implicit は数えない
  mut own : Int
  /// 深さを測るだけの空打ちか。畳みを見ないので、項目の中も読み解かない
  dry : Bool
  /// いま中身を読んでいる項目の深さ。**入れ子の列はその 1 つ下に座る** —
  /// stack の高さで測ると、前の列の項目が積まれたままなので次の列がその子になる
  mut owner : Int
}

///|
/// 骨格ではない深さ。どの見出しより深い（`# ` 〜 `######` は 1〜6）。
let deep : Int = 99

///|
/// ブロック 1 枚を積んだときにできた枠の深さ。**2 つ要る** — 1 枚の塊が
/// 枠を何段も積むから（飛びを埋める Implicit、入れ子の項目）。
priv struct Depth {
  /// 一番浅い枠。部分木の中か外かはこれで見る（Implicit も部分木の一部）
  top : Int
  /// 最初に座った綴られた枠 = **その塊自身のノード**。持ち主の深さはこれ
  own : Int
}

///|
/// 畳みを見ずに骨格だけ積み、ブロックごとに**そこで生まれた一番浅い枠の深さ**
/// を返す。畳みの領域が部分木と一致するかは、md の見出しの深さではなく
/// この深さで測る — 境界の `---` は部分木を深さ 2 へ引き出し、飛びは Implicit
/// で埋まるので、md の `#` の数と積まれた深さはずれる。
fn depths(
  md : String,
  blocks : Array[@markdown.Block],
  gone : Array[Bool],
  ahead : Array[Bool],
  nest : Int,
) -> Array[Depth] {
  let b : Build = {
    md,
    defs: [],
    roots: [],
    stack: [],
    body: [],
    body_at: [],
    body_to: 0,
    side: Right,
    pend: false,
    pend_from: 0,
    pend_to: 0,
    fold_at: None,
    top: deep,
    own: deep,
    dry: true,
    owner: 0,
  }
  let out = Array::make(blocks.length(), { top: deep, own: deep })
  for i, block in blocks {
    // 塊にならない中身（リンクの定義行）も中身なので、保留中の水平線は
    // そこで飾りに落ちる。本番と同じ前提で測らないと深さが食い違う
    if ahead[i] {
      spill(b)
    }
    // **跨ぐのは実際に落ちる塊だけ。** 綴りに見えても落ちない塊（対にならない
    // `<summary>` など）は本番では中身になり、そこで保留中の水平線が装飾に落ちる。
    // 跨いでしまうと水平線が保留のまま次の骨格を引き出し、本番と深さがずれる
    if gone[i] {
      continue
    }
    b.top = deep
    b.own = deep
    take(b, block, nest)
    out[i] = { top: b.top, own: b.own }
  }
  out
}

///|
/// ひと切れを積む。畳みは見出し・項目の行に印を付けるか、中身の 1 枚になる。
fn lay(b : Build, piece : Piece, nest : Int) -> Unit {
  match piece {
    Raw(block) => take(b, block, nest)
    Folded(block, fold~, at~) => {
      b.fold_at = Some(at)
      take(b, block, nest, fold=Some(fold))
      b.fold_at = None
    }
    Capsule(text~, open~, summary~, body~, from~, to~) => {
      // 中身が来たので、保留中の水平線は境界になれない
      spill(b)
      fill(b, Details(text~, open~, summary~, body~), from~, to~)
    }
    Text(text, from~, to~) => {
      spill(b)
      fill(b, Opaque(text), from~, to~)
    }
  }
}

///|
/// ブロック 1 枚を積む。`nest` は項目の入れ子段数。
fn take(
  b : Build,
  block : @markdown.Block,
  nest : Int,
  fold? : Fold? = None,
) -> Unit {
  match block {
    // **単調性 — 項目の子孫は項目。** 項目の領土に書かれた見出しは骨格に
    // ならず、原文のまま中身になる（列 0 へ出れば項目が閉じて木が変わる）
    Heading(span~, ..) if nest > 0 =>
      fill(b, Opaque(verbatim(b.md, block)), from=span.from, to=span.to)
    Heading(level~, style~, children~, span~, ..) =>
      put(
        b,
        level,
        Line(
          sign=Heading,
          label=head_label(b.md, span, style, children),
          fold~,
          body=[],
        ),
        at=span,
        label=head_start(b.md, span, style),
      )
    BulletList(items~, ..) => items_take(b, items, nest, fold~)
    OrderedList(items~, ..) => items_take(b, items, nest, fold~)
    // 区切りは**根の領土の隙間**でだけ側の変わり目になる。項目の中は中身なので
    // 保留せずその場に置く（保留すると、置く前に項目の枠が閉じられたとき
    // 帰る場所が無くなって文書へ落ちる）
    ThematicBreak(span~, ..) if nest > 0 =>
      fill(b, ThematicBreak, from=span.from, to=span.to)
    // 記法(`---` `***` `___`)も本数も差別しない。意味は常に「隣を区切る」で、
    // 行き先は**直後のブロックが何か**で決まる。ここでは保留するだけ
    ThematicBreak(span~, ..) => {
      b.pend = true
      b.pend_from = span.from
      b.pend_to = span.to
    }
    _ =>
      match content_of(b.md, block) {
        Some(c) => {
          // 中身が来た時点で、保留中の水平線は境界になれない
          spill(b)
          let s = block_span(block)
          fill(b, c, from=s.from, to=s.to)
        }
        None => ()
      }
  }
}

///|
/// 項目の列。**最初の段落がラベル**で、残りは中身か入れ子の項目。
fn items_take(
  b : Build,
  items : Array[@markdown.ListItem],
  nest : Int,
  fold? : Fold? = None,
) -> Unit {
  // **項目の深さは、この列が座る枠の 1 つ下。** 入れ子の段数や `#` の数から
  // 数え直すと、境界が手前の項目を深さ 2 へ引き出したときに元の位置から
  // 数えてしまい、間に綴られていない項目が生える（項目は相対記法なので
  // 飛びは存在しない）。列に入る前に 1 度だけ測る — 中で測ると前の兄弟を
  // 積んだぶんずれる
  let mut level = if nest == 0 { spine(b) + 1 } else { b.owner + 1 }
  for it in items {
    // **ラベルは項目の 1 行目。** 途中の段落を引き上げると、その文字が
    // ラベルと中身の両方になる（切り出しはブロックの範囲でやるので、抜いたはずの
    // 段落が切り出しの内側に入る）。1 行目が段落でなければラベルは無い
    let rest = []
    let mut label = ""
    // ラベルの頭。1 行目が段落ならその頭（段落の span は中身の先頭から始まる）。
    // 段落が無ければマーカーを読み飛ばした位置
    let mut label_at = item_start(b.md, it.span)
    // ラベルの範囲に入った定義行はラベルが持っている。残りは項目の中身
    let mut from = it.span.from
    for i, c in it.children {
      if i == 0 && c is Paragraph(..) {
        label = item_label(b.md, c)
        label_at = block_span(c).from
        from = block_span(c).to
      } else {
        rest.push(c)
      }
    }
    put(
      b,
      level,
      Line(sign=Item, label~, fold~, body=[]),
      at=it.span,
      label=label_at,
    )
    // **同じ列の項目は兄弟。** 境界は最初の項目を深さ 2 へ引き出すので、
    // 残りも引き出された先に並ぶ（数え直すと元の位置から数えてしまう）
    level = b.stack.length()
    // 空打ちでは畳みを見ない（深さを測るのに畳みは要らず、
    // 畳みの判定はこの深さを使うので、呼び合いになる）
    let inner = if b.dry {
      rest.map(c => Raw(c))
    } else {
      pieces(b.md, rest, defs_in(b.defs, from, it.span.to), nest + 1)
    }
    let outer = b.owner
    b.owner = level
    for c in inner {
      lay(b, c, nest + 1)
    }
    b.owner = outer
  }
}

///|
/// 項目のラベル。段落の span は中身の先頭から始まるので、見出しと違って
/// マーカーの読み飛ばしが要らない（実測は probe を参照）。
/// 見出しと同じく**インラインの並びからは導かない** — mdAst が中身の一部を
/// リンクの定義として引き取ると、インラインが行の全部を覆わないことがある。
fn item_label(md : String, p : @markdown.Block) -> String {
  guard p is Paragraph(span~, ..) else { return "" }
  carve(md, span.from, span.to)
}

///|
/// 列 0 の項目が座る枠の深さ。列 0 へ出た項目は開いている項目を閉じる
/// （md でもそうなる）ので、見出しの背骨の底が座る枠になる。
fn spine(b : Build) -> Int {
  let mut h = b.stack.length()
  while h > 0 && b.stack[h - 1].skel is Line(sign=Item, ..) {
    h = h - 1
  }
  h
}

///|
/// 深さ level のノードを置く。浅く戻るときは積んだぶんを落とし、
/// 深く飛ぶときは間を Implicit で埋める（飛びは綴りであって、無ではない）。
/// `at` はその骨格の行（項目なら入れ子込み）の原文の範囲。
fn put(
  b : Build,
  level : Int,
  skel : Notation,
  at~ : @markdown.Span,
  label~ : Int,
) -> Unit {
  // 境界のとき、項目は**深さ 2 に直接置く**。項目は相対記法なので深さが
  // 導出値で、引き出し先に合わせて置き直せる（見出しは絶対座標なので
  // 動かせず、足りない深さを Implicit が埋める）
  let level = if b.pend && skel is Line(sign=Item, ..) { 2 } else { level }
  // **見出しは見出しの背骨にしか積まれない。** 項目の枠は見出しの親に
  // なれないので落とす（列 0 の見出しは md でも項目を閉じる）。C17 を
  // 深さ 1 から全部の深さへ広げたもの。これが無いと項目の子が見出しになる
  if skel is Line(sign=Heading, ..) {
    while b.stack.length() > 0 &&
          b.stack[b.stack.length() - 1].skel is Line(sign=Item, ..) {
      ignore(b.stack.unsafe_pop())
    }
  }
  if level == 1 || b.stack.is_empty() {
    // 新しい木を始める。根は側を持たないので、引き出す先が無い —
    // 保留中の水平線は装飾に落ちる
    spill(b)
    b.side = Right
  } else if b.pend {
    // **境界。「直前のものの一部ではない」という宣言**なので、深さ 2 まで
    // 引き出す。足りない深さは下の穴埋めが Implicit で埋める
    while b.stack.length() > 1 {
      ignore(b.stack.unsafe_pop())
    }
  }
  while b.stack.length() >= level {
    ignore(b.stack.unsafe_pop())
  }
  while b.stack.length() < level - 1 {
    let gap : Frame = {
      skel: Gap,
      kids: [],
      side: Right,
      id: 0,
      from: -1,
      to: -1,
      label: -1,
      body_at: [],
    }
    sink(b)
    seat(b, gap)
    b.stack.push(gap)
  }
  // 畳まれていれば範囲は `<details>` 〜 `</details>`（部分木を過不足なく覆う）
  let at = match b.fold_at {
    Some(s) => s
    None => at
  }
  let f : Frame = {
    skel,
    kids: [],
    side: Right,
    id: 0,
    from: at.from,
    to: at.to,
    label,
    body_at: [],
  }
  sink(b)
  // **そのブロック自身のノードは、最初に座る綴られた枠。** 手前の穴埋めは足場、
  // 後ろに続くのは入れ子の子（1 つの塊が項目を何段も積むことがある）
  if b.own == deep {
    b.own = b.stack.length() + 1
  }
  seat(b, f)
  b.stack.push(f)
}

///|
/// これから座る枠の深さを控える（一番浅いものだけ）。深さは stack の高さが持つ。
fn sink(b : Build) -> Unit {
  let depth = b.stack.length() + 1
  if depth < b.top {
    b.top = depth
  }
}

///|
/// 積んである親の子にする。親が居なければ森の 1 本として生やす。
/// **側を持つのは深さ 2 の枠だけ**（根の子）。
fn seat(b : Build, f : Frame) -> Unit {
  if b.stack.is_empty() {
    b.roots.push(f)
    return
  }
  if b.stack.length() == 1 {
    if b.pend {
      b.side = flipped(b.side)
      b.pend = false
    }
    f.side = b.side
  }
  b.stack[b.stack.length() - 1].kids.push(f)
}

///|
fn flipped(s : Side) -> Side {
  if s is Right {
    Left
  } else {
    Right
  }
}

///|
/// 境界になれなかった水平線を、その場の中身として落とす。
/// 書かれた位置がそのまま保たれる。
fn spill(b : Build) -> Unit {
  if b.pend {
    b.pend = false
    fill(b, ThematicBreak, from=b.pend_from, to=b.pend_to)
  }
}

///|
/// 見出しの中身を、原文からそのまま切り出す（mmm はインラインを解釈しない）。
/// 中身が無ければ空ラベル（`## ` のような行）。
///
/// インラインの span は**中身に対する 0 始まりの相対**なので、原文の
/// どこから中身が始まるかは自分で数える。実測（`# a` / `#   a` / `# a #` /
/// setext）は probe_wbtest.mbt に固定してある。
fn head_label(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
  children : Array[@markdown.Inline],
) -> String {
  if children.is_empty() {
    return ""
  }
  let from = head_start(md, span, style)
  carve(md, from, head_end(md, span, style))
}

///|
/// 見出しの中身が原文で終わる位置。
///
/// **インラインの並びからは導けない。** mdAst は 1 行目がリンクの定義行の形を
/// していると中身の一部を定義として引き取るので、インラインが行の全部を覆わない
/// ことがある（`[q]: /r` + 改行 + `ZZZ` + `---` で `ZZZ` が落ちていた）。
/// 記法は md の規則で決まるので、そちらから引く。
fn head_end(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
) -> Int {
  let mut z = span.to
  // 末尾の空白と改行は記法
  while z > span.from && blank(md[z - 1]) {
    z = z - 1
  }
  if style is Atx {
    // 閉じの `#` は飾り。前に空白があるときだけ（`a#` は中身）
    let mut h = z
    while h > span.from && md[h - 1] == '#' {
      h = h - 1
    }
    if h < z && (h == span.from || blank(md[h - 1])) {
      z = h
      while z > span.from && blank(md[z - 1]) {
        z = z - 1
      }
    }
  } else {
    // setext の下線 1 行ぶんを落とす
    while z > span.from && md[z - 1] != '\n' {
      z = z - 1
    }
    while z > span.from && blank(md[z - 1]) {
      z = z - 1
    }
  }
  z
}

///|
/// 見出しの中身が原文で始まる位置。ATX は飾りの字下げと `#` とその後ろの
/// 空白を飛ばす。setext には `#` が無いので飛ばさない（`#hashtag` を
/// 食べてしまうため）。
fn head_start(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
) -> Int {
  let mut p = skip_blank(md, span.from, span.to)
  if style is Atx {
    while p < span.to && md[p] == '#' {
      p = p + 1
    }
    p = skip_blank(md, p, span.to)
  }
  p
}

///|
/// 項目のラベルの頭。マーカー（`-` `*` `+`、または数字と `.` `)`）と空白を読み飛ばす。
/// 1 行目が段落ならその span の頭と一致する。段落の無い項目のために持つ。
fn item_start(md : String, span : @markdown.Span) -> Int {
  let mut p = skip_blank(md, span.from, span.to)
  while p < span.to && md[p] >= '0' && md[p] <= '9' {
    p = p + 1
  }
  if p < span.to &&
    (
      md[p] == '-' ||
      md[p] == '*' ||
      md[p] == '+' ||
      md[p] == '.' ||
      md[p] == ')'
    ) {
    p = p + 1
  }
  skip_blank(md, p, span.to)
}

///|
fn skip_blank(md : String, from : Int, to : Int) -> Int {
  let mut p = from
  while p < to && (md[p] == ' ' || md[p] == '	') {
    p = p + 1
  }
  p
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

///|
/// 番号を配る箱。木を歩きながら文書順に振る。
priv struct Counter {
  mut val : Int
}

///|
/// 番号を文書順に振る。形を割り付ける前に済ませるので、割り付けが
/// 順序を動かしても番号は動かない。
fn number_frame(f : Frame, next : Counter) -> Unit {
  f.id = next.val
  next.val = f.id + 1
  // 中身は子より前に書かれているので、先に振る
  match f.skel {
    Line(body~, ..) => number_blocks(body, next)
    Gap => ()
  }
  for k in f.kids {
    number_frame(k, next)
  }
}

///|
/// id のノード・中身が、文書順に振り直されたら得る番号。読みと同じ振り方
/// （文書の中身 → 根ごとに ノード → その中身 → 子）なので、木を書き戻して
/// 読み直したときの id を先に言える。操作の後の focus を読み替えるのに使う。
/// 無い id は None。
pub fn number(doc : Doc, id : Int) -> Int? {
  if id == doc_id {
    return Some(doc_id)
  }
  let next = { val: doc_id + 1 }
  fn blocks(body : Array[Block]) -> Int? {
    for b in body {
      if b.id == id {
        return Some(next.val)
      }
      next.val = next.val + 1
    }
    None
  }

  fn node(x : Node) -> Int? {
    if id_of(x) == id {
      return Some(next.val)
    }
    next.val = next.val + 1
    let body = match x {
      HeadingNode(h) => h.body
      ListNode(l) => l.body
      ImplicitNode(_) => []
    }
    match blocks(body) {
      Some(n) => return Some(n)
      None => ()
    }
    for k in children_of(x) {
      match node(k) {
        Some(n) => return Some(n)
        None => ()
      }
    }
    None
  }

  match blocks(doc.body) {
    Some(n) => return Some(n)
    None => ()
  }
  for r in doc.roots {
    match node(r.node) {
      Some(n) => return Some(n)
      None => ()
    }
  }
  None
}

///|
/// 中身へ、ノードと同じ列で文書順の番号を振る。読み解かなかったものにも
/// 振るので、View が Opaque を落としても残りの番号は動かない。
fn number_blocks(body : Array[Block], next : Counter) -> Unit {
  for i, x in body {
    body[i] = { id: next.val, content: x.content }
    next.val = next.val + 1
  }
}

///|
/// 森の 1 本を根にする。子の側は積むときに決まっている。
fn to_root(f : Frame) -> Root {
  { node: to_node(f), sides: f.kids.map(k => k.side) }
}

///|
/// 枠をノードにする。項目だけは子も項目に畳む（単調性）。
fn to_node(f : Frame) -> Node {
  match f.skel {
    Gap => ImplicitNode({ id: f.id, children: f.kids.map(to_node) })
    Line(sign=Item, label~, fold~, body~) =>
      ListNode({ id: f.id, label, fold, body, children: f.kids.map(to_list) })
    Line(label~, fold~, body~, ..) =>
      HeadingNode({ id: f.id, label, fold, body, children: f.kids.map(to_node) })
  }
}

///|
/// 項目にする。飛びは綴りが無いので空ラベルへ落ちる（項目の子に飛びは
/// 来ないので、実際には通らない）。
fn to_list(f : Frame) -> ListNode {
  match f.skel {
    Gap =>
      {
        id: f.id,
        label: "",
        fold: None,
        body: [],
        children: f.kids.map(to_list),
      }
    Line(label~, fold~, body~, ..) =>
      { id: f.id, label, fold, body, children: f.kids.map(to_list) }
  }
}

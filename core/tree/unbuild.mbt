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
//
// **側は書く前に書く形（`Laid`）へ写す。** 書く歩きは側を知らず、行に添えた
// 境界の綴りを、その行の手前に置くだけ。

///|
/// 書く形の枠 1 つ。木のノードに、手前に書く境界の水平線を添えたもの。
/// 子は `kids` が持つ — 境界の直後の Implicit は、手前の兄弟の尻へ移っている（`laid`）
priv struct Laid {
  node : Node
  /// この行の手前に書く境界の綴り。無ければ None
  rule : String?
  kids : Array[Laid]
}

///|
/// 境界を持たない部分木の書く形。
fn Laid::of(n : Node) -> Laid {
  { node: n, rule: None, kids: n.children.map(Laid::of), }
}

///|
/// 根の書く形。**側の変わり目は、変わる子の行の手前に書く境界**（綴りは読んだ字、
/// 無ければ `---`）。
///
/// **境界の直後の Implicit は、手前の兄弟の尻へ移す。** Implicit は深さを保って
/// 置き直された行の足場で、行が無いので、手前の兄弟の尻の同じ深さの行の中に
/// 書くしか深さを保つ道が無い（docs/spec.md「水平線」）。移せなければそのまま書き、
/// 読み直しが形を決める
fn laid(r : Root) -> Laid {
  let out : Array[Laid] = []
  let mut prev = Right
  for i, k in r.node.children {
    let side = r.sides.get(i).unwrap_or(prev)
    if side == prev {
      out.push(Laid::of(k))
      continue
    }
    prev = side
    let rule = match r.rules.get(i) {
      Some(s) if s != "" => s
      _ => "---"
    }
    if k.mark is None && out.last() is Some(p) && tuck(p, k, rule) is Some(q) {
      out[out.length() - 1] = q
    } else {
      out.push({ ..Laid::of(k), rule: Some(rule), })
    }
  }
  { node: r.node, rule: None, kids: out, }
}

///|
/// Implicit `gap` の子を、同じ深さの書かれた行 `host` の尻へ移し、移した先頭の行の
/// 手前に境界 `rule` を添える。`gap` の先頭の子も Implicit なら、`host` の最後の子の
/// 尻へさらに降りる。移せなければ None
fn tuck(host : Laid, gap : Node, rule : String) -> Laid? {
  guard host.node.mark is Some(_) && gap.children is [first, .. rest] else {
    return None
  }
  let after : Array[Laid] = rest.iter().map(Laid::of).collect()
  if first.mark is None {
    guard host.kids.last() is Some(tail) &&
      tuck(tail, first, rule) is Some(moved) else {
      return None
    }
    let kids = host.kids.copy()
    kids[kids.length() - 1] = moved
    return Some({ ..host, kids: [..kids, ..after], })
  }
  Some({
    ..host,
    kids: [..host.kids, { ..Laid::of(first), rule: Some(rule), }, ..after],
  })
}

///|
/// 木を mdAst にする。
pub fn unbuild(doc : Doc) -> @markdown.Document {
  let out = []
  for b in doc.body {
    content(out, b)
  }
  // **木は桁 0 の兄弟。** md で桁 0 に並ぶ項目は 1 本の列で、木が本ごとに
  // 分かれるのは読みの都合。木ごとに書くと間に空行がライブラリから入り、
  // 読んだ詰めが消える（#203）
  nodes(out, doc.roots.map(laid), 1)
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
fn unbuild_node(
  x : Node,
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> @markdown.Document {
  let out = []
  node(out, laid({ node: x, sides, rules, }), depth)
  { frontmatter: None, children: out, definitions: [], span: nowhere, }
}

///|
/// 散文（骨格を持たない中身の列）を mdAst にする。
fn unbuild_prose(body : Array[Block]) -> @markdown.Document {
  let out = []
  for b in body {
    content(out, b)
  }
  { frontmatter: None, children: out, definitions: [], span: nowhere, }
}

///|
/// 階層が言う隙間 — 正規形で、要素ごとに手前が空行で分かれるか。
/// 合流の base と theirs はこれで、**正規形を書いて読み直す道は要らない**。
///
/// **下の walk と同じ順に歩く。** 正規形の塊はライブラリが必ず空行で分けるので、
/// 分かれないのは 3 か所だけ:
///
/// - 文書の頭。frontmatter が在れば、その後ろは空行 1 つ（`serialize` が置く）
/// - 詰めた列の 2 つ目からの兄弟（`loose` が偽）
/// - 詰めた項目のラベルと最初の中身（`tight`）。ラベルが無ければ中身はマーカーの
///   行に乗るので、項目自身の答えを継ぐ
///
/// 書く字が無い中身（check の `Wordless`）が在れば None — 正規形に塊が出ず要素が
/// 並ばないので、合流は全文へ落ちる。
fn parted(doc : Doc) -> Map[Int, Bool]? {
  let p : Part = {
    out: Map([]),
    next: doc.frontmatter is Some(_),
    torn: false,
  }
  for b in doc.body {
    p.content(b)
  }
  p.nodes(doc.roots.map(laid))
  if p.torn {
    None
  } else {
    Some(p.out)
  }
}

///|
/// 隙間を数える途中。
priv struct Part {
  out : Map[Int, Bool]
  /// 次に置く塊の答え — 手前が空行で分かれるか
  mut next : Bool
  /// 書く字が無い中身に当たった
  mut torn : Bool
}

///|
/// 塊 1 つを置く。**ライブラリは塊を空行で分ける**ので、次の塊は必ず分かれる。
/// 要素でない塊（境界の水平線・畳みの角）は id を持たないが、頭の席は使う。
fn Part::place(self : Part, id : Int?) -> Unit {
  if id is Some(id) {
    self.out[id] = self.next
  }
  self.next = true
}

///|
/// 兄弟の列。`nodes` と同じ規則で列を割る（境界・畳まれた項目・マーカーの種類が変わる）。
fn Part::nodes(self : Part, xs : Array[Laid]) -> Unit {
  let run : Array[Laid] = []
  fn flush() {
    if !run.is_empty() {
      self.bullets(run)
      run.clear()
    }
  }

  for x in xs {
    if x.rule is Some(_) {
      flush()
      self.place(None)
    }
    match x.node.mark {
      Some(Item(marker~, ..)) if x.node.fold is None => {
        if splits(run, marker) {
          flush()
        }
        run.push(x)
      }
      _ => {
        flush()
        self.node(x)
      }
    }
  }
  flush()
}

///|
/// ノード 1 つと、その部分木。`node` と同じ順。
fn Part::node(self : Part, x : Laid) -> Unit {
  match x.node.mark {
    Some(Item(..)) => self.wrap(x.node, () => self.bullets([x]))
    Some(Heading(..)) =>
      self.wrap(x.node, () => {
        self.place(Some(x.node.id))
        for b in x.node.body {
          self.content(b)
        }
        self.nodes(x.kids)
      })
    // 飛び（Implicit）は行を持たないので、隙間は最初の要素のもの
    None => {
      self.nodes(x.kids)
      if head_element(x) is Some(first) {
        self.out[x.node.id] = self.out.get(first).unwrap_or(true)
      }
    }
  }
}

///|
/// 畳みは `<details>` と `</details>` の塊で部分木を挟む。どちらも塊なので、
/// 中の頭も次の兄弟も必ず空行で分かれる。
///
/// **畳まれた行の隙間は、開きの手前のもの。** 地番が `<details>` から始まる
/// （`put`）ので、合流が測る隙間もそこの手前。中で付いた答え（開きの塊で
/// 分かれている）を、開き自身の答えで上書きする
fn Part::wrap(self : Part, x : Node, inner : () -> Unit) -> Unit {
  match x.fold {
    None => inner()
    Some(_) => {
      let mine = self.next
      self.place(None)
      inner()
      self.place(None)
      self.out[x.id] = mine
    }
  }
}

///|
/// 項目の列 1 つ。**塊は 1 つ**（`bullets` が生の塊で綴る）なので、兄弟の間の
/// 空行はライブラリでなく読んだ詰め（`loose_of`）が決める。ラベルと中身の間は
/// `tight_of`。
fn Part::bullets(self : Part, run : Array[Laid]) -> Unit {
  let tight = tight_of(run)
  let loose = loose_of(run)
  let head = self.next
  for i, l in run {
    let mine = if i == 0 { head } else { loose }
    self.out[l.node.id] = mine
    // **項目の中は、その項目の深さを 0 とした文書。** ラベルが無ければ中身は
    // マーカーの行に乗るので、隙間は項目自身のもの
    self.next = if l.node.label == "" { mine } else { !tight }
    for b in l.node.body {
      self.content(b)
    }
    self.nodes(l.kids)
  }
  self.next = true
}

///|
/// 中身 1 枚。**書く字が無ければ塊が出ない** — `Details` も `source` も無い中身で、
/// check の `Wordless`。そのときは隙間を言えないので折れる
fn Part::content(self : Part, b : Block) -> Unit {
  if b.source is Some(_) || !(b.content is (Some(Details(..)) | None)) {
    self.place(Some(b.id))
  } else {
    self.torn = true
  }
}

///|
/// 部分木の最初の要素。飛び（Implicit）を下って最初の行を持つノード。
/// 子の無い飛びは在り得ない（check が言う）ので None は来ない。
fn head_element(x : Laid) -> Int? {
  if x.node.mark is Some(_) {
    return Some(x.node.id)
  }
  match x.kids.get(0) {
    Some(k) => head_element(k)
    None => None
  }
}

///|
/// 位置は持たない。mdAst の span は原文の座標で、組んだ木に原文は無い。
let nowhere : @markdown.Span = @markdown.Span::empty()

///|
/// 兄弟の列を書く。境界を添えた行の手前には、その水平線を置く。
///
/// **続く項目は 1 つの列にまとめる**（兄弟は詰める）。列が割れるのは、境界の
/// 水平線と、畳まれた項目（自分の `<details>` に包まれる）と、マーカーの種類が
/// 変わるとき（md でもそこで別の列になる）。
fn nodes(out : Array[@markdown.Block], xs : Array[Laid], depth : Int) -> Unit {
  let run : Array[Laid] = []
  fn flush() {
    if !run.is_empty() {
      out.push(bullets(run))
      run.clear()
    }
  }

  for x in xs {
    if x.rule is Some(rule) {
      flush()
      out.push(html(rule))
    }
    match x.node.mark {
      Some(Item(marker~, ..)) if x.node.fold is None => {
        if splits(run, marker) {
          flush()
        }
        run.push(x)
      }
      _ => {
        flush()
        node(out, x, depth)
      }
    }
  }
  flush()
}

///|
/// ノード 1 つと、その部分木。
fn node(out : Array[@markdown.Block], x : Laid, depth : Int) -> Unit {
  match x.node.mark {
    Some(Item(..)) => wrap(out, x.node.fold, () => out.push(bullets([x])))
    Some(Heading(setext~, closing~)) =>
      wrap(out, x.node.fold, () => {
        out.push(heading(depth, x.node.label, setext, closing))
        for b in x.node.body {
          content(out, b)
        }
        nodes(out, x.kids, depth + 1)
      })
    None => nodes(out, x.kids, depth + 1)
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
/// 空行は 2 か所に要る。**項目と項目の間**は `loose_of`、**ラベルと中身の間**は
/// `tight_of` が言う。
fn bullets(run : Array[Laid]) -> @markdown.Block {
  let tight = tight_of(run)
  let loose = loose_of(run)
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
/// 列のラベルと中身を詰めて書けるか — ラベルと入れ子の列だけの項目が並ぶとき。
/// 中身は空行で分けないと段落に飲み込まれ、畳まれた子の `<details>` は空行で
/// 終わる塊なので、分けないと次の項目を飲み込む。ラベルの直後の空の項目も
/// 分ける（`underlined`）— 正規形は並びで変わる。**先頭の子の手前に境界を書くなら
/// 分ける** — 詰めると水平線がラベルの setext の下線に読まれる
fn tight_of(run : Array[Laid]) -> Bool {
  run
  .iter()
  .all(l => {
    l.node.body.is_empty() &&
    l.kids.iter().all(c => c.node.fold is None) &&
    !underlined(l) &&
    !(l.kids.get(0) is Some({ rule: Some(_), .. }))
  })
}

///|
/// 項目の間に空行を置くか — 読んだ列が loose だったとき。
fn loose_of(run : Array[Laid]) -> Bool {
  run.iter().any(l => l.node.mark is Some(Item(loose=true, ..)))
}

///|
/// このマーカーで列が割れるか — 種類が列の頭と違うとき。
/// 種類が変われば md でもそこで別の列になるので、書くときも割る。
fn splits(run : Array[Laid], marker : String) -> Bool {
  run is [first, ..] && kind_of(marker_of(first.node)) != kind_of(marker)
}

///|
/// マーカーの種類。番号なら尻の 1 字（`.` か `)`）、でなければマーカーそのもの。
fn kind_of(marker : String) -> String {
  if marker.length() > 0 && marker[0] >= '0' && marker[0] <= '9' {
    slice(marker, marker.length() - 1, marker.length())
  } else {
    marker
  }
}

///|
/// ラベルの直後に空の項目が続く形。詰めて書くと `-` 1 本が段落の setext の
/// 下線に読まれ、ラベルが消えて子も読まれない。空行で分ければ空の項目に読まれる。
fn underlined(l : Laid) -> Bool {
  l.node.label != "" && l.kids.get(0) is Some({ node: { label: "", .. }, .. })
}

///|
/// 項目 1 つ。1 行目はマーカーとラベル、続きは中身と入れ子の列 —
/// **その字はライブラリに綴らせ**、ラベルの桁ぶん字下げしてぶら下げる。
/// ラベルも中身も無ければマーカーだけの行。
fn list_item(l : Laid, tight : Bool) -> String {
  let kids = []
  for b in l.node.body {
    content(kids, b)
  }
  // **項目の中は、その項目の深さを 0 とした文書。** 子の見出しは項目からの
  // 深さぶんの `#` で書く（docs/spec.md「項目の中」）。項目の根の側の境界も
  // 項目の段に書く
  nodes(kids, l.kids, 1)
  let inner = StringBuilder()
  if l.node.label != "" {
    inner.write_string(l.node.label)
    inner.write_char('\n')
  }
  if !kids.is_empty() {
    if l.node.label != "" && !tight {
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
  let marker = marker_of(l.node)
  let text = inner.to_string()
  if text == "" {
    return marker + "\n"
  }
  // ラベルの桁は読んだ幅。マーカーで埋まっていれば空白 1 つ
  let offset = match l.node.mark {
    Some(Item(offset~, ..)) => offset
    _ => 0
  }
  let width = if offset > marker.length() {
    offset
  } else {
    marker.length() + 1
  }
  let line = marker + pad(width - marker.length()) + indent(text, width)
  // **mmm が組んだ字が別の記法に読まれるなら、その形では書かない。** 名前の無い
  // 項目が 3 段続くとマーカーだけが 1 行に並び、md は水平線を優先する（`- - -`。
  // docs/spec.md「項目の中」）。子を次の行へ落とせば、桁が入れ子を言う。
  // **名前が在る行は直さない** — その字は利用者のもので、`- ---` が水平線に
  // 読まれるのは md の文法どおり（docs/spec.md「ノードの名前」）
  if l.node.label == "" && ruled(line) {
    marker + "\n" + pad(width) + indent(text, width)
  } else {
    line
  }
}

///|
/// 1 行目が md では水平線に読まれるか。空白を除いて `-` `_` `*` のどれか 1 種が
/// 3 つ以上だけ並ぶ行。
fn ruled(text : String) -> Bool {
  let mut mark = ' '
  let mut count = 0
  for c in text {
    if c == '\n' {
      break
    }
    if c == ' ' || c == '\t' || c == '\r' {
      continue
    }
    if c != '-' && c != '_' && c != '*' {
      return false
    }
    if count == 0 {
      mark = c
    } else if c != mark {
      return false
    }
    count = count + 1
  }
  count >= 3
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
        Some(Image(alt~, src~, title~)) =>
          out.push(paragraph([Image(alt~, url=src, title~, span=nowhere)]))
        Some(Link(text~, href~, title~)) =>
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
        Some(Code(info~, text~)) =>
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
        Some(Svg(s)) => out.push(html(s))
        Some(ThematicBreak) => out.push(html("---"))
        // 畳みにならなかった領域も、読み解かなかった中身も、原文だけが書き戻せる
        // （`source` が持つ）。どちらも無ければ書く字が無い（check の `Wordless`）
        Some(Details(..)) | None => ()
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

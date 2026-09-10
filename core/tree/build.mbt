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
/// **作ったら変えない。** 番号と地番は導けるので持たず、`to_node` が配る。
priv struct Frame {
  /// 行に書かれていた綴り。飛び（Implicit）は None
  mark : Mark?
  label : String
  fold : Fold?
  body : Array[Block]
  kids : Array[Frame]
  /// 深さ 2 の枠だけが持つ。深い所の側は型に存在しない
  side : Side
  /// 自分の手前で側を変えた水平線の原文。変えていなければ空
  rule : String
  /// **骨格の行だけ**の原文の範囲。中身と子の尻は `to_node` が足す。
  /// 飛び（Implicit）は行を持たないので -1
  from : Int
  to : Int
  /// ラベルの頭（マーカーの後ろ）。飛び（Implicit）は行を持たないので -1
  at_label : Int
  /// 中身（body）と並走する地番。`to_node` が番号と付き合わせて spans に写す
  body_at : Array[Spot]
}

///|
/// 行を持たない枠（飛び）の目印。範囲は子の和で決まる。
let no_line : Int = -1

///|
/// md を木にする。
pub fn parse(md : String) -> Doc {
  build(md).0
}

///|
/// 地番。ノードが原文のどこに書かれているか。`label` はラベルの頭（マーカーの後ろ）で、
/// 地図の選択の位置（ts の anchors）に使うラベルの頭。位置は CodeMirror が編集で写す。
/// Implicit と文書の散文は行を持たないので None。
pub(all) struct Spot {
  from : Int
  label : Int?
  to : Int
} derive(Eq, Debug, ToJson)

///|
/// md を木にする。**裁定は読みの段が下している** — ここがやるのは piece の列から
/// 枠を積み直すことだけ（`assemble`）。地番は Doc に載せず並べて返す — 載せると
/// Doc が特定の原文に縛られ、手で組む木に在り得ない欄が生える。
pub fn build(md : String) -> (Doc, Map[Int, Spot]) {
  assemble(notation(md))
}

///|
/// 地番の指紋。`id[from,label,to]` を id 順に並べる。
pub fn spans_sig(md : String) -> String {
  let (_, spans) = build(md)
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
  /// まだ閉じていない畳みの、畳んだノードの深さ。**閉じは境界と同じ** —
  /// 領域は部分木を過不足なく覆うので、閉じの後ろはその部分木の外。
  /// 閉じで枠を降ろせば、続く骨格は畳んだノードの兄弟から測る
  fold_roots : Array[Int]
  /// このブロックで生まれた一番浅い枠の深さ。骨格でなければ `deep` のまま
  mut top : Int
  /// このブロック自身のノードの深さ。飛びを埋めた Implicit は数えない
  mut own : Int
  /// 深さを測るだけの空打ちか。畳みを見ないので、項目の中も読み解かない
  dry : Bool
  /// いま中身を読んでいる持ち主（項目、またはその中の見出し）の深さ。
  /// **入れ子の列はその 1 つ下に座る** — stack の高さで測ると、前の列の
  /// 項目が積まれたままなので次の列がその子になる
  mut owner : Int
  /// いま中身を読んでいる項目の深さ。**`#` の本数はここから測る** —
  /// 項目の中は、その項目の深さを 0 とした文書（docs/spec.md「項目の中」）。
  /// 文書そのものを読んでいる間は 0
  mut base : Int
  /// 下した裁定の控え（記法構造）。**木の組み立てには 1 つも効かない** —
  /// 段 6 で判断そのものを読みの段へ移すまでの、網を張るための控え
  pieces : Array[Piece]
}

///|
/// 積み始め。`dry` は深さを測るだけの空打ち（畳みを見ず、項目の中も読み解かない）。
fn Build::new(
  md : String,
  defs : Array[@markdown.Span],
  dry? : Bool = false,
) -> Build {
  {
    md,
    defs,
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
    fold_roots: [],
    top: deep,
    own: deep,
    dry,
    owner: 0,
    base: 0,
    pieces: [],
  }
}

///|
/// 裁定を 1 つ控える。深さを測るだけの空打ち（`dry`）では控えない —
/// 本番と同じ裁定を 2 度書くことになる
fn keep(b : Build, at : @markdown.Span, verdict : Verdict) -> Unit {
  if !b.dry && at.to > at.from {
    b.pieces.push({ at, verdict: Some(verdict), })
  }
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
  opens : Array[Bool],
  closes : Array[Bool],
  nest : Int,
) -> Array[Depth] {
  let b = Build::new(md, [], dry=true)
  let out = Array::make(blocks.length(), { top: deep, own: deep, })
  // 直前に開きの綴りを跨いだ。次に座る枠が畳みの根
  let mut opening = false
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
      // 落ちる綴りでも、畳みの開きと閉じは深さを動かす（本番の `lay` と同じ）
      if closes[i] {
        shut(b)
      }
      if opens[i] {
        opening = true
      }
      continue
    }
    b.top = deep
    b.own = deep
    take(b, block, nest)
    if opening {
      b.fold_roots.push(b.stack.length())
      opening = false
    }
    out[i] = { top: b.top, own: b.own, }
  }
  out
}

///|
/// ひと切れを積む。畳みは見出し・項目の行に印を付けるか、中身の 1 枚になる。
fn lay(b : Build, cut : Slice, nest : Int) -> Unit {
  match cut {
    Plain(block) => take(b, block, nest)
    Folded(block, fold~, at~, open_at~) => {
      keep(b, open_at, FoldOpen(open=fold.open, summary=fold.summary))
      b.fold_at = Some(at)
      take(b, block, nest, fold=Some(fold))
      b.fold_at = None
      b.fold_roots.push(b.stack.length())
    }
    Closed(from~, to~) => {
      keep(b, { from, to, }, FoldClose)
      shut(b)
    }
    Capsule(text~, open~, summary~, body~, from~, to~) => {
      // 中身が来たので、保留中の水平線は境界になれない
      spill(b)
      fill(
        b,
        Some(Details(open~, summary~, body~)),
        from~,
        to~,
        source=Some(text),
      )
    }
    Text(text, from~, to~) => {
      spill(b)
      fill(b, None, from~, to~, source=Some(text))
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
    Heading(level~, style~, children~, closing_hashes~, span~, ..) => {
      // **項目の中は、その項目の深さを 0 とした文書。** `#` の本数はそこから
      // 測る絶対の深さで、飛びは put が Implicit で埋める。見出しの後ろの中身と
      // 入れ子はその見出しのもの（owner を進める）
      let depth = b.base + level
      b.owner = depth
      put(
        b,
        depth,
        Some(Heading(setext=style is Setext, closing=closing_hashes)),
        label=head_label(b.md, span, style, children),
        fold~,
        at=span,
        at_label=head_start(b.md, span, style),
      )
    }
    BulletList(items~, ..) => items_take(b, items, nest, fold~)
    OrderedList(items~, ..) => items_take(b, items, nest, fold~)
    // 区切りは**根の領土の隙間**でだけ側の変わり目になる。項目の中は中身なので
    // 保留せずその場に置く（保留すると、置く前に項目の枠が閉じられたとき
    // 帰る場所が無くなって文書へ落ちる）
    ThematicBreak(span~, ..) if nest > 0 =>
      fill(
        b,
        Some(ThematicBreak),
        from=span.from,
        to=span.to,
        source=Some(carve(b.md, span.from, span.to)),
      )
    // 記法(`---` `***` `___`)も本数も差別しない。意味は常に「隣を区切る」で、
    // 行き先は**直後のブロックが何か**で決まる。ここでは保留するだけ
    ThematicBreak(span~, ..) => {
      // 水平線が続くなら、手前の 1 本は境界になれない（直後が骨格でない）ので
      // その場の中身に落ちる。保留は 1 本しか持てないので、上書きの前に吐き出す
      spill(b)
      b.pend = true
      b.pend_from = span.from
      b.pend_to = span.to
    }
    // 空行は綴りであってモデルには無い。serialize が正規形として置き直す
    BlankLines(..) => ()
    _ => {
      // 中身が来た時点で、保留中の水平線は境界になれない
      spill(b)
      let s = block_span(block)
      fill(
        b,
        content_of(b.md, block),
        from=s.from,
        to=s.to,
        source=Some(verbatim(b.md, block)),
      )
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
  let loose = item_gaps(b.md, items)
  // **項目の深さは、この列が座る枠の 1 つ下。** 入れ子の段数や `#` の数から
  // 数え直すと、境界が手前の項目を深さ 2 へ引き出したときに元の位置から
  // 数えてしまい、間に綴られていない項目が生える（項目は相対記法なので
  // 飛びは存在しない）。列に入る前に 1 度だけ測る — 中で測ると前の兄弟を
  // 積んだぶんずれる
  let mut level = if nest == 0 { spine(b) + 1 } else { b.owner + 1 }
  for i, it in items {
    let face = face_of(b.md, it)
    put(
      b,
      level,
      Some(
        Item(
          marker=item_marker(b.md, it.span),
          offset=it.content_offset,
          loose=loose[i],
        ),
      ),
      label=face.label,
      fold~,
      at=it.span,
      at_label=face.at,
      line=Some({
        from: it.span.from,
        to: if face.from > face.at {
          face.from
        } else {
          face.at
        },
      }),
    )
    // **同じ列の項目は兄弟。** 境界は最初の項目を深さ 2 へ引き出すので、
    // 残りも引き出された先に並ぶ（数え直すと元の位置から数えてしまう）
    level = b.stack.length()
    inside(b, it, face, level, nest)
  }
}

///|
/// 項目の顔。**ラベルは項目の 1 行目**（顔が段落のときだけ）で、残りは中身か
/// 入れ子の項目。途中の段落を引き上げると、その文字がラベルと中身の両方になる
/// （切り出しはブロックの範囲でやるので、抜いたはずの段落が切り出しの内側に入る）。
priv struct Face {
  label : String
  /// ラベルの頭。1 行目が段落ならその頭（段落の span は中身の先頭から始まる）、
  /// 段落が無ければマーカーを読み飛ばした位置
  at : Int
  /// ラベルの尻 = 残りの中身の頭。ラベルの範囲に入った定義行はラベルが持っている
  from : Int
  rest : Array[@markdown.Block]
}

///|
/// 項目 1 つの顔を読む。1 行目が段落でなければラベルは無く、その塊は
/// md の解釈どおりに読む（docs/spec.md「項目の中」）。
fn face_of(md : String, it : @markdown.ListItem) -> Face {
  let rest = []
  let mut label = ""
  let mut at = item_start(md, it.span)
  let mut from = it.span.from
  for i, c in it.children {
    if i == 0 && c is Paragraph(span~, ..) {
      // **インラインの並びからは導かない** — mdAst が中身の一部をリンクの
      // 定義として引き取ると、インラインが行の全部を覆わないことがある。
      // 段落の span は中身の先頭から始まるので、ふつうはマーカーの後ろと一致する。
      // ずれるのは GFM のタスクリスト（`- [ ] a`）— ライブラリが `[ ]` を食べて
      // 段落をその後ろから始める。**チェックは綴り**（mmm は GFM のタスクリストを
      // 解釈しない）なので、頭が手前ならマーカーの後ろから測る
      let head = if at < span.from { at } else { span.from }
      label = carve(md, head, span.to)
      at = head
      from = span.to
    } else {
      rest.push(c)
    }
  }
  // 塊が 1 つも残らない項目は、マーカーの後ろの字がそのままラベル。
  // ライブラリが食べて塊を残さない綴り（`- [ ]`）のため
  if it.children.is_empty() {
    label = carve(md, at, it.span.to)
  }
  { label, at, from, rest, }
}

///|
/// 項目の中を読む。**その項目の深さを 0 とした文書**なので、`owner` と `base` を
/// その項目まで進めて同じ規則で積む。空打ちでは畳みを見ない（深さを測るのに
/// 畳みは要らず、畳みの判定はこの深さを使うので、呼び合いになる）。
fn inside(
  b : Build,
  it : @markdown.ListItem,
  face : Face,
  level : Int,
  nest : Int,
) -> Unit {
  let inner = if b.dry {
    face.rest.map(c => Plain(c))
  } else {
    sift(b.md, face.rest, defs_in(b.defs, face.from, it.span.to), nest + 1)
  }
  let outer_owner = b.owner
  let outer_base = b.base
  b.owner = level
  b.base = level
  for c in inner {
    lay(b, c, nest + 1)
  }
  b.owner = outer_owner
  b.base = outer_base
}

///|
/// 列 0 の項目が座る枠の深さ。列 0 へ出た項目は開いている項目を閉じる
/// （md でもそうなる）ので、見出しの背骨の底が座る枠になる。
fn spine(b : Build) -> Int {
  let mut h = b.stack.length()
  while h > 0 && b.stack[h - 1].mark is Some(Item(..)) {
    h = h - 1
  }
  h
}

///|
/// 深さ level のノードを置く。`at` はその骨格の行（項目なら入れ子込み）の
/// 原文の範囲で、畳まれていれば `<details>` 〜 `</details>`（部分木を過不足なく覆う）。
fn put(
  b : Build,
  level : Int,
  mark : Mark?,
  label~ : String,
  fold~ : Fold?,
  at~ : @markdown.Span,
  at_label~ : Int,
  line? : @markdown.Span? = None,
) -> Unit {
  let level = seat_level(b, level, mark)
  // 控えるのは**行そのものの範囲**。地番（`at`）は項目なら部分木ぜんぶ、
  // 畳まれた行なら `<details>` の範囲まで伸びるが、記法構造ではその外側は
  // 別のひと切れなので、行は行の字だけを持つ
  let own_at = match line {
    Some(l) => l
    None => at
  }
  clear(b, level, mark)
  // **閉じた後に残った高さ**。深さだけでは組み直せない — 列 0 の見出しが
  // 開いている項目を閉じたか、境界が部分木を引き出したかは、ここでしか分からない
  let under = b.stack.length()
  bridge(b, level)
  let at = match b.fold_at {
    Some(s) => s
    None => at
  }
  keep(
    b,
    own_at,
    Line(
      depth=b.stack.length() + 1,
      under~,
      label=at_label,
      mark~,
      text=label,
      fold~,
      at~,
    ),
  )
  // **そのブロック自身のノードは、最初に座る綴られた枠。** 手前の穴埋めは足場、
  // 後ろに続くのは入れ子の子（1 つの塊が項目を何段も積むことがある）
  if b.own == deep {
    b.own = b.stack.length() + 1
  }
  let (side, rule) = born(b)
  seat(b, {
    mark,
    label,
    fold,
    body: [],
    kids: [],
    side,
    rule,
    from: at.from,
    to: at.to,
    at_label,
    body_at: [],
  })
}

///|
/// その綴りが実際に座る深さ。**境界のとき、項目は深さ 2 に直接置く** —
/// 項目は相対記法なので深さが導出値で、引き出し先に合わせて置き直せる
/// （見出しは絶対座標なので動かせず、足りない深さを Implicit が埋める）。
fn seat_level(b : Build, level : Int, mark : Mark?) -> Int {
  if b.pend && mark is Some(Item(..)) {
    2
  } else {
    level
  }
}

///|
/// 座る前に落とす枠。**列 0 の見出しは開いている項目を閉じ**（md でもそうなる。
/// 項目の中の見出し `b.base > 0` はその項目の子なので閉じない）、**境界は深さ 1 まで
/// 引き出し**（「直前のものの一部ではない」という宣言）、あとは level 以上を落とす。
/// 新しい木（深さ 1）は側を持たないので、保留中の水平線は装飾に落ちる。
fn clear(b : Build, level : Int, mark : Mark?) -> Unit {
  if b.base == 0 && mark is Some(Heading(..)) {
    while b.stack.length() > 0 &&
          b.stack[b.stack.length() - 1].mark is Some(Item(..)) {
      ignore(b.stack.unsafe_pop())
    }
  }
  if level == 1 || b.stack.is_empty() {
    spill(b)
    b.side = Right
  } else if b.pend {
    while b.stack.length() > 1 {
      ignore(b.stack.unsafe_pop())
    }
  }
  while b.stack.length() >= level {
    ignore(b.stack.unsafe_pop())
  }
}

///|
/// 足りない深さを Implicit で埋める（飛びは綴りであって、無ではない）。
fn bridge(b : Build, level : Int) -> Unit {
  while b.stack.length() < level - 1 {
    let (side, rule) = born(b)
    seat(b, {
      mark: None,
      label: "",
      fold: None,
      body: [],
      kids: [],
      side,
      rule,
      from: no_line,
      to: no_line,
      at_label: no_line,
      body_at: [],
    })
  }
}

///|
/// これから座る枠の側と、その手前で側を変えた水平線の原文。
/// **側を持つのは深さ 2 の枠だけ**（根の子）で、境界になった水平線はここで
/// 綴りを譲り、側を裏返す。深い枠と根は側を持たないので Right のまま。
fn born(b : Build) -> (Side, String) {
  guard b.stack.length() == 1 else { return (Right, "") }
  guard b.pend else { return (b.side, "") }
  // 境界になった水平線。書き戻しに要るのは綴りだけなので原文を控える
  let rule = carve(b.md, b.pend_from, b.pend_to)
  keep(b, { from: b.pend_from, to: b.pend_to, }, Border(rule~))
  b.side = flipped(b.side)
  b.pend = false
  (b.side, rule)
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
/// 積んである親の子にし、次の子の親にする。親が居なければ森の 1 本として生やす。
fn seat(b : Build, f : Frame) -> Unit {
  sink(b)
  if b.stack.is_empty() {
    b.roots.push(f)
  } else {
    b.stack[b.stack.length() - 1].kids.push(f)
  }
  b.stack.push(f)
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
/// 畳みの閉じ。**その部分木が終わったという宣言**なので、畳んだノードの枠を
/// 降ろす（領域は部分木を過不足なく覆うので、閉じの後ろはその外）。
/// 続く骨格は畳んだノードの兄弟から測り、深い見出しは Implicit が間を埋める。
/// 側は裏返らない — 裏返すのは `---` だけ。
fn shut(b : Build) -> Unit {
  guard b.fold_roots.pop() is Some(root) else { return }
  while b.stack.length() >= root && !b.stack.is_empty() {
    ignore(b.stack.unsafe_pop())
  }
}

///|
/// 境界になれなかった水平線を、その場の中身として落とす。
/// 書かれた位置がそのまま保たれる。
fn spill(b : Build) -> Unit {
  if b.pend {
    b.pend = false
    fill(
      b,
      Some(ThematicBreak),
      from=b.pend_from,
      to=b.pend_to,
      source=Some(carve(b.md, b.pend_from, b.pend_to)),
    )
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
/// 項目のラベルの頭。マーカーと空白を読み飛ばす。
/// 1 行目が段落ならその span の頭と一致する。段落の無い項目のために持つ。
fn item_start(md : String, span : @markdown.Span) -> Int {
  skip_blank(md, marker_end(md, span), span.to)
}

///|
/// 列の詰め — 項目ごとに、手前の項目との間に空行が有るか。
///
/// **ライブラリの `tight` では測れない。** CommonMark の `tight` は列のどこかに
/// 空行があれば偽なので、項目 1 つの中の空行でも列ぜんぶが loose になる。それで
/// 書き戻すと、空行が項目と項目の**間**へ移る（触っていない字が変わり、冪等でもない）。
/// 隙間は原文から測る。
///
/// 列の頭の隙間は列の手前のもの（その項目のものではない）ので、2 つ目に従う。
/// 項目が 1 つだけなら間が無いので詰まっている。
fn item_gaps(md : String, items : Array[@markdown.ListItem]) -> Array[Bool] {
  let out = Array::makei(items.length(), i => {
    let head = line_start(md, items[i].span.from)
    i > 0 && blank_start(md, head) < head
  })
  if out.length() > 1 {
    out[0] = out[1]
  }
  out
}

///|
/// 項目のマーカーの字。**読んだ綴りをそのまま持つ** — 番号はライブラリが
/// 列の先頭から振り直すので、飛んだ数字（`1.` の次が `5.`）は原文からしか取れない。
fn item_marker(md : String, span : @markdown.Span) -> String {
  carve(md, skip_blank(md, span.from, span.to), marker_end(md, span))
}

///|
/// 項目のマーカーの尻。`-` `*` `+` か、数字と `.` `)`。
fn marker_end(md : String, span : @markdown.Span) -> Int {
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
  p
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
/// id のノード・中身が、文書順に振り直されたら得る番号。読みと同じ振り方
/// （文書の中身 → 根ごとに ノード → その中身 → 子）なので、木を書き戻して
/// 読み直したときの id を先に言える。操作の後の focus を読み替えるのに使う。
/// 無い id は None。
pub fn number(doc : Doc, id : Int) -> Int? {
  if id == doc_id {
    return Some(doc_id)
  }
  let next = { val: doc_id + 1, }
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
    if x.id == id {
      return Some(next.val)
    }
    next.val = next.val + 1
    match blocks(x.body) {
      Some(n) => return Some(n)
      None => ()
    }
    for k in x.children {
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
/// 振るので、View が Raw を落としても残りの番号は動かない。
fn number_blocks(body : Array[Block], next : Counter) -> Unit {
  for i, x in body {
    body[i] = { id: next.val, content: x.content, source: x.source, }
    next.val = next.val + 1
  }
}

///|
/// 森の 1 本を根にする。子の側と境界の綴りは積むときに決まっている。
fn to_root(f : Frame, next : Counter, spans : Map[Int, Spot]) -> Root {
  {
    node: to_node(f, next, spans),
    sides: f.kids.map(k => k.side),
    rules: f.kids.map(k => k.rule),
  }
}

///|
/// 枠をノードにし、番号と地番を配る。綴りはそのまま運ぶ。
/// **番号は文書順**（自分 → 中身 → 子）なので行きがけに振り、**地番は子が
/// 揃ってからでないと決まらない**ので帰りがけに置く。
fn to_node(f : Frame, next : Counter, spans : Map[Int, Spot]) -> Node {
  let id = next.val
  next.val = id + 1
  // 中身は子より前に書かれているので、先に振る
  number_blocks(f.body, next)
  for i, at in f.body_at {
    spans[f.body[i].id] = at
  }
  let children = f.kids.map(k => to_node(k, next, spans))
  spans[id] = frame_at(f, children, spans)
  { id, label: f.label, fold: f.fold, body: f.body, children, mark: f.mark, }
}

///|
/// 枠の地番。骨格の行の頭から、**自分の最後の中身の尻まで**（子の中身も含む）。
/// 行を持たない飛びは範囲ごと子の和。畳みの尻（`</details>`）は子より後ろに
/// 在るので、大きいほうを採れば保たれる。
fn frame_at(f : Frame, children : Array[Node], spans : Map[Int, Spot]) -> Spot {
  let mut from = f.from
  let mut to = f.to
  for at in f.body_at {
    if at.to > to {
      to = at.to
    }
  }
  if !children.is_empty() {
    if from == no_line {
      from = spans[children[0].id].from
    }
    let tail = spans[children[children.length() - 1].id].to
    if tail > to {
      to = tail
    }
  }
  {
    from,
    label: if f.at_label == no_line {
      None
    } else {
      Some(f.at_label)
    },
    to,
  }
}

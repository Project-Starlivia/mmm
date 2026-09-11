// md を読んで裁定を下す。**mmm の解釈はここにしか無い。**
//
// 骨格（見出しと項目）を深さで積み上げ、深さが飛んだら間を Implicit が埋める —
// 飛びは構造なので保存し、綴りが無いことだけを型で表す。
//
// **出すのは裁定だけ**（`Piece` の列）。木を組むのは `assemble` で、こちらが積むのは
// 深さの stack ひとつ。ひと切れの範囲は「行そのもの」で、地番のように中身や子の尻まで
// 伸びることはない（伸ばす所は組み立てが決める）。
//
// 記法がどこまでかを原文から測る所は `measure.mbt`、字と行の算術は `text.mbt`。

///|
/// 読みの途中。**深さを持つのは `stack` だけ** — 見出しの `#` の数を控えると、
/// 境界が枠を引き出したあとに元の数から数えてしまう。
priv struct Deem {
  md : String
  /// 文書ぜんぶのリンクの定義行。項目の中を読み解くときに切り出して渡す
  defs : Array[@markdown.Span]
  /// 積んである骨格の綴り。**高さが深さ**で、中身は「項目か」を見るのに使う
  /// （列 0 の見出しは開いている項目を閉じる）。飛び（Implicit）は None
  stack : Array[Mark?]
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
  /// 下した裁定。**これがこの機械の出力ぜんぶ**（`notation` が敷き詰めて列にする）
  pieces : Array[Piece]
}

///|
/// 読み始め。`dry` は深さを測るだけの空打ち（畳みを見ず、項目の中も読み解かない）。
fn Deem::new(
  md : String,
  defs : Array[@markdown.Span],
  dry? : Bool = false,
) -> Deem {
  {
    md,
    defs,
    stack: [],
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
fn keep(d : Deem, at : @markdown.Span, verdict : Verdict) -> Unit {
  if !d.dry && at.to > at.from {
    d.pieces.push({ at, verdict: Some(verdict), })
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
  let d = Deem::new(md, [], dry=true)
  let out = Array::make(blocks.length(), { top: deep, own: deep, })
  // 直前に開きの綴りを跨いだ。次に座る枠が畳みの根
  let mut opening = false
  for i, block in blocks {
    // 塊にならない中身（リンクの定義行）も中身なので、保留中の水平線は
    // そこで飾りに落ちる。本番と同じ前提で測らないと深さが食い違う
    if ahead[i] {
      spill(d)
    }
    // **跨ぐのは実際に落ちる塊だけ。** 綴りに見えても落ちない塊（対にならない
    // `<summary>` など）は本番では中身になり、そこで保留中の水平線が装飾に落ちる。
    // 跨いでしまうと水平線が保留のまま次の骨格を引き出し、本番と深さがずれる
    if gone[i] {
      // 落ちる綴りでも、畳みの開きと閉じは深さを動かす（本番の `deem` と同じ）
      if closes[i] {
        shut(d)
      }
      if opens[i] {
        opening = true
      }
      continue
    }
    d.top = deep
    d.own = deep
    take(d, block, nest)
    if opening {
      d.fold_roots.push(d.stack.length())
      opening = false
    }
    out[i] = { top: d.top, own: d.own, }
  }
  out
}

///|
/// ひと切れを積む。畳みは見出し・項目の行に印を付けるか、中身の 1 枚になる。
fn deem(d : Deem, cut : Slice, nest : Int) -> Unit {
  match cut {
    Plain(block) => take(d, block, nest)
    Folded(block, fold~, at~, open_at~) => {
      keep(d, open_at, FoldOpen(open=fold.open, summary=fold.summary))
      d.fold_at = Some(at)
      take(d, block, nest, fold=Some(fold))
      d.fold_at = None
      d.fold_roots.push(d.stack.length())
    }
    Closed(from~, to~) => {
      keep(d, { from, to, }, FoldClose)
      shut(d)
    }
    Capsule(text~, open~, summary~, body~, from~, to~) => {
      // 中身が来たので、保留中の水平線は境界になれない
      spill(d)
      keep(
        d,
        { from, to, },
        Card(content=Some(Details(open~, summary~, body~)), source=Some(text)),
      )
    }
    Text(text, from~, to~) => {
      spill(d)
      keep(d, { from, to, }, Card(content=None, source=Some(text)))
    }
  }
}

///|
/// ブロック 1 枚を積む。`nest` は項目の入れ子段数。
fn take(
  d : Deem,
  block : @markdown.Block,
  nest : Int,
  fold? : Fold? = None,
) -> Unit {
  match block {
    Heading(level~, style~, children~, closing_hashes~, span~, ..) => {
      // **項目の中は、その項目の深さを 0 とした文書。** `#` の本数はそこから
      // 測る絶対の深さで、飛びは put が Implicit で埋める。見出しの後ろの中身と
      // 入れ子はその見出しのもの（owner を進める）
      let depth = d.base + level
      d.owner = depth
      put(
        d,
        depth,
        Some(Heading(setext=style is Setext, closing=closing_hashes)),
        label=head_label(d.md, span, style, children),
        fold~,
        at=span,
        at_label=head_start(d.md, span, style),
      )
    }
    BulletList(items~, ..) => items_take(d, items, nest, fold~)
    OrderedList(items~, ..) => items_take(d, items, nest, fold~)
    // 区切りは**根の領土の隙間**でだけ側の変わり目になる。項目の中は中身なので
    // 保留せずその場に置く（保留すると、置く前に項目の枠が閉じられたとき
    // 帰る場所が無くなって文書へ落ちる）
    ThematicBreak(span~, ..) if nest > 0 =>
      keep(
        d,
        span,
        Card(
          content=Some(ThematicBreak),
          source=Some(carve(d.md, span.from, span.to)),
        ),
      )
    // 記法(`---` `***` `___`)も本数も差別しない。意味は常に「隣を区切る」で、
    // 行き先は**直後のブロックが何か**で決まる。ここでは保留するだけ
    ThematicBreak(span~, ..) => {
      // 水平線が続くなら、手前の 1 本は境界になれない（直後が骨格でない）ので
      // その場の中身に落ちる。保留は 1 本しか持てないので、上書きの前に吐き出す
      spill(d)
      d.pend = true
      d.pend_from = span.from
      d.pend_to = span.to
    }
    // 空行は綴りであってモデルには無い。serialize が正規形として置き直す
    BlankLines(..) => ()
    _ => {
      // 中身が来た時点で、保留中の水平線は境界になれない
      spill(d)
      keep(
        d,
        block_span(block),
        Card(
          content=content_of(d.md, block),
          source=Some(verbatim(d.md, block)),
        ),
      )
    }
  }
}

///|
/// 項目の列。**最初の段落がラベル**で、残りは中身か入れ子の項目。
fn items_take(
  d : Deem,
  items : Array[@markdown.ListItem],
  nest : Int,
  fold? : Fold? = None,
) -> Unit {
  let loose = item_gaps(d.md, items)
  // **項目の深さは、この列が座る枠の 1 つ下。** 入れ子の段数や `#` の数から
  // 数え直すと、境界が手前の項目を深さ 2 へ引き出したときに元の位置から
  // 数えてしまい、間に綴られていない項目が生える（項目は相対記法なので
  // 飛びは存在しない）。列に入る前に 1 度だけ測る — 中で測ると前の兄弟を
  // 積んだぶんずれる
  let mut level = if nest == 0 { spine(d) + 1 } else { d.owner + 1 }
  for i, it in items {
    let face = face_of(d.md, it)
    put(
      d,
      level,
      Some(
        Item(
          marker=item_marker(d.md, it.span),
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
    level = d.stack.length()
    inside(d, it, face, level, nest)
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
  d : Deem,
  it : @markdown.ListItem,
  face : Face,
  level : Int,
  nest : Int,
) -> Unit {
  let inner = if d.dry {
    face.rest.map(c => Plain(c))
  } else {
    sift(d.md, face.rest, defs_in(d.defs, face.from, it.span.to), nest + 1)
  }
  let outer_owner = d.owner
  let outer_base = d.base
  d.owner = level
  d.base = level
  for c in inner {
    deem(d, c, nest + 1)
  }
  d.owner = outer_owner
  d.base = outer_base
}

///|
/// 列 0 の項目が座る枠の深さ。列 0 へ出た項目は開いている項目を閉じる
/// （md でもそうなる）ので、見出しの背骨の底が座る枠になる。
fn spine(d : Deem) -> Int {
  let mut h = d.stack.length()
  while h > 0 && d.stack[h - 1] is Some(Item(..)) {
    h = h - 1
  }
  h
}

///|
/// 深さ level のノードを置く。`at` はその骨格の行（項目なら入れ子込み）の
/// 原文の範囲で、畳まれていれば `<details>` 〜 `</details>`（部分木を過不足なく覆う）。
fn put(
  d : Deem,
  level : Int,
  mark : Mark?,
  label~ : String,
  fold~ : Fold?,
  at~ : @markdown.Span,
  at_label~ : Int,
  line? : @markdown.Span? = None,
) -> Unit {
  let level = seat_level(d, level, mark)
  // 控えるのは**行そのものの範囲**。地番（`at`）は項目なら部分木ぜんぶ、
  // 畳まれた行なら `<details>` の範囲まで伸びるが、記法構造ではその外側は
  // 別のひと切れなので、行は行の字だけを持つ
  let own_at = match line {
    Some(l) => l
    None => at
  }
  clear(d, level, mark)
  // **閉じた後に残った高さ**。深さだけでは組み直せない — 列 0 の見出しが
  // 開いている項目を閉じたか、境界が部分木を引き出したかは、ここでしか分からない
  let under = d.stack.length()
  bridge(d, level)
  // 畳まれた行の地番は `<details>` の範囲まで伸びる。**伸びるのは畳んだ行 1 本だけ** —
  // 項目は部分木ぜんぶが 1 枚の塊なので、下って積む子まで伸ばすと子の行が
  // 見失われる（隙間も畳みの手前のものになる）
  let at = match d.fold_at {
    Some(s) => {
      d.fold_at = None
      s
    }
    None => at
  }
  keep(
    d,
    own_at,
    Line(
      depth=d.stack.length() + 1,
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
  if d.own == deep {
    d.own = d.stack.length() + 1
  }
  border(d)
  seat(d, mark)
}

///|
/// その綴りが実際に座る深さ。**境界のとき、項目は深さ 2 に直接置く** —
/// 項目は相対記法なので深さが導出値で、引き出し先に合わせて置き直せる
/// （見出しは絶対座標なので動かせず、足りない深さを Implicit が埋める）。
fn seat_level(d : Deem, level : Int, mark : Mark?) -> Int {
  if d.pend && mark is Some(Item(..)) {
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
fn clear(d : Deem, level : Int, mark : Mark?) -> Unit {
  if d.base == 0 && mark is Some(Heading(..)) {
    while d.stack.length() > 0 &&
          d.stack[d.stack.length() - 1] is Some(Item(..)) {
      ignore(d.stack.unsafe_pop())
    }
  }
  if level == 1 || d.stack.is_empty() {
    spill(d)
  } else if d.pend {
    while d.stack.length() > 1 {
      ignore(d.stack.unsafe_pop())
    }
  }
  while d.stack.length() >= level {
    ignore(d.stack.unsafe_pop())
  }
}

///|
/// 足りない深さを Implicit で埋める（飛びは綴りであって、無ではない）。
fn bridge(d : Deem, level : Int) -> Unit {
  while d.stack.length() < level - 1 {
    border(d)
    seat(d, None)
  }
}

///|
/// 保留中の水平線を、これから座る枠の手前の境界にする。**側の変わり目になれるのは
/// 深さ 2 の枠の手前だけ**（根の子）。裏返した先の側は控えない — 側を数え直すのは
/// 組み立て（`Lay::born`）で、こちらは「ここが変わり目だ」と言うだけ。
fn border(d : Deem) -> Unit {
  guard d.stack.length() == 1 && d.pend else { return }
  // 書き戻しに要るのは綴りだけなので原文を控える
  keep(
    d,
    { from: d.pend_from, to: d.pend_to, },
    Border(rule=carve(d.md, d.pend_from, d.pend_to)),
  )
  d.pend = false
}

///|
/// 枠を 1 つ積む。深さは高さが持つので、載せるのは綴りだけ。
/// **一番浅い深さはここで控える** — 1 枚の塊が枠を何段も積むので、後から測れない。
fn seat(d : Deem, mark : Mark?) -> Unit {
  let depth = d.stack.length() + 1
  if depth < d.top {
    d.top = depth
  }
  d.stack.push(mark)
}

///|
/// 畳みの閉じ。**その部分木が終わったという宣言**なので、畳んだノードの枠を
/// 降ろす（領域は部分木を過不足なく覆うので、閉じの後ろはその外）。
/// 続く骨格は畳んだノードの兄弟から測り、深い見出しは Implicit が間を埋める。
/// 側は裏返らない — 裏返すのは `---` だけ。
fn shut(d : Deem) -> Unit {
  guard d.fold_roots.pop() is Some(root) else { return }
  while d.stack.length() >= root && !d.stack.is_empty() {
    ignore(d.stack.unsafe_pop())
  }
}

///|
/// 境界になれなかった水平線を、その場の中身として落とす。
/// 書かれた位置がそのまま保たれる。
fn spill(d : Deem) -> Unit {
  if d.pend {
    d.pend = false
    keep(
      d,
      { from: d.pend_from, to: d.pend_to, },
      Card(
        content=Some(ThematicBreak),
        source=Some(carve(d.md, d.pend_from, d.pend_to)),
      ),
    )
  }
}

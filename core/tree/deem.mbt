// md を読んで裁定を下す。**mmm の解釈はここにしか無い。**
//
// 骨格（見出しと項目）を深さで積み上げ、深さが飛んだら間を Implicit が埋める —
// 飛びは構造なので保存し、綴りが無いことだけを型で表す。
//
// **積みは 2 つ。** `read` は `---` で左右が変わらないものとしての読みで、深さと中身の
// 持ち主はここから測る。`tree` は木そのもので、境界が根より深い行を閉じる。境界は
// 置き場を変えるだけで、深さも持ち主も変えない（docs/spec.md「水平線」）。
//
// **出すのは裁定だけ**（`Piece` の列）。木を組むのは `assemble` で、ひと切れの範囲は
// 「行そのもの」で、地番のように中身や子の尻まで伸びることはない（伸ばす所は組み立てが決める）。
//
// 記法がどこまでかを原文から測る所は `measure.mbt`、字と行の算術は `text.mbt`。

///|
/// 積んだ枠 1 つ。
priv struct Seat {
  /// 行の綴り。飛び（Implicit）は None
  mark : Mark?
  /// 行の頭（`Line` のひと切れの from）。中身の持ち主はこれで指す。Implicit は None
  line : Int?
}

///|
/// 読みの途中。
priv struct Deem {
  md : String
  /// 文書ぜんぶのリンクの定義行。項目の中を読み解くときに切り出して渡す
  defs : Array[@markdown.Span]
  /// `---` で左右が変わらないものとしての積み。**高さが深さ**で、深さと中身の持ち主はここから測る
  read : Array[Seat]
  /// 木の積み。境界が根より深い行を閉じるので `read` とは親が違いうるが、同じ行の深さは同じ
  tree : Array[Seat]
  /// 行き先待ちの水平線。**本数に意味は無い**ので 1 本しか持たない
  mut pend : Pend?
  /// いま積む骨格が畳まれているなら、その `<details>` 〜 `</details>` の範囲
  mut fold_at : @markdown.Span?
  /// まだ閉じていない畳みの、畳んだノードの深さ。**閉じは部分木の終わり** —
  /// 閉じで枠を降ろせば、続く骨格は畳んだノードの兄弟から測る
  fold_roots : Array[Int]
  /// このブロックで生まれた一番浅い枠の深さ。骨格でなければ `deep` のまま
  mut top : Int
  /// このブロック自身のノードの深さ。飛びを埋めた Implicit は数えない
  mut own : Int
  /// 深さを測るだけの空打ちか。畳みを見ないので、項目の中も読み解かない
  dry : Bool
  /// いま中身を読んでいる項目の深さ。**`#` の本数はここから測り**、ここより深い
  /// 項目は字下げが戻れば閉じている（docs/spec.md「項目の中」）。文書そのものは 0
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
    read: [],
    tree: [],
    pend: None,
    fold_at: None,
    fold_roots: [],
    top: deep,
    own: deep,
    dry,
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
/// 行き先待ちの水平線。境界になれば綴りを、装飾になれば中身をここから切り出す。
/// **持ち主は書かれた所で決まる** — 落ちるのは後の裁定でも、座るのはこの位置の持ち主
priv struct Pend {
  at : @markdown.Span
  owner : Int?
}

///|
/// 塊を 1 枚控える。持ち主はいまの読みの持ち主（`owner`）。
fn card(
  d : Deem,
  at : @markdown.Span,
  content~ : Content?,
  source~ : String?,
) -> Unit {
  keep(d, at, Card(content~, source~, owner=owner(d)))
}

///|
/// 開いている高さ。**段（`base`）より深い最初の項目から上は閉じている** — 字下げが
/// この段まで戻ったので、その項目の中身だった。文書の段（0）なら、列 0 は項目を全部閉じる
fn open_height(stack : Array[Seat], base : Int) -> Int {
  for i in base..<stack.length() {
    if stack[i].mark is Some(Item(..)) {
      return i
    }
  }
  stack.length()
}

///|
/// 塊の持ち主の行。`---` が無かったものとしての読み（`read`）で決める —
/// 段の中で開いている一番深い、**書かれた**行（見出しの節）。無ければ段の項目自身、
/// 文書の段なら文書（None）。Implicit は書かれた行ではないので持ち主にならない
fn owner(d : Deem) -> Int? {
  let h = open_height(d.read, d.base)
  for i = h - 1; i >= d.base; i = i - 1 {
    if d.read[i].line is Some(line) {
      return Some(line)
    }
  }
  if d.base > 0 {
    d.read[d.base - 1].line
  } else {
    None
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
/// この深さで測る — 境界は後ろの行を根の下へ置き直し、飛びは Implicit で埋まるので、
/// md の `#` の数と木の親はずれる。
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
    // そこで装飾になる。本番と同じ前提で測らないと深さが食い違う
    if ahead[i] {
      spill(d)
    }
    // **跨ぐのは実際に落ちる塊だけ。** 綴りに見えても落ちない塊（対にならない
    // `<summary>` など）は本番では中身になり、そこで保留中の水平線が装飾になる。
    // 跨いでしまうと水平線が保留のまま次の骨格を境界にし、本番と深さがずれる
    if gone[i] {
      // 落ちる綴りでも、畳みの開きと閉じは深さを動かす（本番の `deem` と同じ）
      if closes[i] {
        d.shut()
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
      d.fold_roots.push(d.tree.length())
      opening = false
    }
    out[i] = { top: d.top, own: d.own, }
  }
  out
}

///|
/// ひと切れを積む。畳みは見出し・項目の行に印を付けるか、中身の 1 枚になる。
fn deem(d : Deem, cut : Cut, nest : Int) -> Unit {
  match cut {
    Plain(block) => take(d, block, nest)
    Folded(block, fold~, at~, open_at~) => {
      keep(d, open_at, FoldOpen(open=fold.open, summary=fold.summary))
      d.fold_at = Some(at)
      take(d, block, nest, fold=Some(fold))
      d.fold_at = None
      d.fold_roots.push(d.tree.length())
    }
    Closed(from~, to~) => {
      keep(d, { from, to, }, FoldClose)
      d.shut()
    }
    Capsule(text~, open~, summary~, body~, from~, to~) => {
      // 中身が来たので、保留中の水平線は境界になれない
      spill(d)
      card(
        d,
        { from, to, },
        // `summary` は綴りの照合を原文でやるので、木へ渡すここで LF に揃える
        // （`text` と `body` は `carve` / `strip` が済ませている）
        content=Some(Details(open~, summary=summary.map(lf), body~)),
        source=Some(text),
      )
    }
    Text(text, from~, to~) => {
      spill(d)
      card(d, { from, to, }, content=None, source=Some(text))
    }
  }
}

///|
/// ブロック 1 枚を積む。`nest` は項目の入れ子段数（ふるいに渡す）。
fn take(
  d : Deem,
  block : @markdown.Block,
  nest : Int,
  fold? : Fold? = None,
) -> Unit {
  match block {
    Heading(level~, style~, children~, closing_hashes~, span~, ..) =>
      // **項目の中は、その項目の深さを 0 とした文書。** `#` の本数はそこから
      // 測る絶対の深さで、飛びは put が Implicit で埋める
      put(
        d,
        d.base + level,
        Some(Heading(setext=style is Setext, closing=closing_hashes)),
        label=head_label(d.md, span, style, children),
        fold~,
        at=span,
        at_label=head_start(d.md, span, style),
      )
    BulletList(items~, ..) => items_take(d, items, nest, fold)
    OrderedList(items~, ..) => items_take(d, items, nest, fold)
    // 記法(`---` `***` `___`)も本数も、項目の中か外かも差別しない。行き先は
    // **直後のブロックが何か**で決まるので、ここでは持ち主を控えて保留するだけ
    ThematicBreak(span~, ..) => {
      // 水平線が続くなら、手前の 1 本は境界になれない（直後が骨格でない）ので
      // その場の中身に落ちる。保留は 1 本しか持てないので、上書きの前に吐き出す
      spill(d)
      d.pend = Some({ at: span, owner: owner(d), })
    }
    // 空行は綴りであってモデルには無い。serialize が正規形として置き直す
    BlankLines(..) => ()
    _ => {
      // 中身が来た時点で、保留中の水平線は境界になれない
      spill(d)
      card(
        d,
        block_span(block),
        content=content_of(d.md, block),
        // 段落は、書き戻して読み直しても段落のままの字で持つ（`paragraphed`）
        source=Some(
          if block is Paragraph(..) {
            paragraphed(verbatim(d.md, block))
          } else {
            verbatim(d.md, block)
          },
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
  fold : Fold?,
) -> Unit {
  let loose = item_gaps(d.md, items)
  // **項目の深さは、書かれた入れ物の 1 つ下。** `<li>` の中ならその項目、文書の段なら
  // 見出しの節 — 段より深い項目は字下げが戻って閉じている。同じ列の項目は兄弟なので
  // 深さは列に 1 つ（境界が置き場を変えても深さは変わらない）
  let level = open_height(d.read, d.base) + 1
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
      label = lines_of(carve(md, head, span.to))
      at = head
      from = span.to
    } else {
      rest.push(c)
    }
  }
  // 塊が 1 つも残らない項目は、マーカーの後ろの字がそのままラベル。
  // ライブラリが食べて塊を残さない綴り（`- [ ]`）のため
  if it.children.is_empty() {
    label = lines_of(carve(md, at, it.span.to))
  }
  { label, at, from, rest, }
}

///|
/// 項目の中を読む。**その項目の深さを 0 とした文書**なので、段（`base`）を
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
  let outer = d.base
  d.base = level
  for c in inner {
    deem(d, c, nest + 1)
  }
  d.base = outer
}

///|
/// 深さ `depth` のノードを置く。`at` はその骨格の行（項目なら入れ子込み）の
/// 原文の範囲で、畳まれていれば `<details>` 〜 `</details>`（部分木を過不足なく覆う）。
/// `line` は行そのものの範囲（項目の行は入れ子を含まない）。
fn put(
  d : Deem,
  depth : Int,
  mark : Mark?,
  label~ : String,
  fold~ : Fold?,
  at~ : @markdown.Span,
  at_label~ : Int,
  line? : @markdown.Span? = None,
) -> Unit {
  // 控えるのは**行そのものの範囲**。地番（`at`）は項目なら部分木ぜんぶ、
  // 畳まれた行なら `<details>` の範囲まで伸びるが、記法構造ではその外側は
  // 別のひと切れなので、行は行の字だけを持つ
  let own_at = line.unwrap_or(at)
  // **字下げが戻った見出しは、段より深い項目を閉じる**（列 0 なら全部）
  if mark is Some(Heading(..)) {
    close(d.read, d.base)
    close(d.tree, d.base)
  }
  lower(d.read, depth)
  // 閉じた後に読みの根が残っていれば、この行は水平線と同じ木に入る
  let flip = resolve(d, joins=!d.read.is_empty())
  fill(d.read, depth, s => d.read.push(s))
  // **境界は根より深い行を閉じる。** 深さは変えないので、足りない段は Implicit が埋める
  if flip {
    lower(d.tree, 2)
  }
  lower(d.tree, depth)
  // **閉じた後に残った高さ**。深さだけでは組み直せない — 列 0 の見出しが
  // 開いている項目を閉じたか、境界が行を閉じたかは、ここでしか分からない
  let under = d.tree.length()
  fill(d.tree, depth, s => d.seat(s))
  // 畳まれた行の地番は `<details>` の範囲まで伸びる。**伸びるのは畳んだ行 1 本だけ** —
  // 項目は部分木ぜんぶが 1 枚の塊なので、下って積む子まで伸ばすと子の行が
  // 見失われる（隙間も畳みの手前のものになる）
  let extent = match d.fold_at {
    Some(s) => {
      d.fold_at = None
      s
    }
    None => at
  }
  keep(
    d,
    own_at,
    Line(depth~, under~, label~, at_label~, mark~, fold~, at=extent),
  )
  // **そのブロック自身のノードは、最初に座る綴られた枠。** 手前の穴埋めは足場、
  // 後ろに続くのは入れ子の子（1 つの塊が項目を何段も積むことがある）
  if d.own == deep {
    d.own = depth
  }
  let seat : Seat = { mark, line: Some(own_at.from), }
  d.read.push(seat)
  d.seat(seat)
}

///|
/// 保留中の水平線の行き先を、これから置く行で決める。境界なら綴りを控えて真。
/// **境界になるのは 3 つを全部満たすときだけ** — 持ち主がノード、直後が骨格の行
/// （いまここ）、その行が同じ木（`joins` — 読みの根が閉じずに残る。深さ 1 の行も、
/// 列 0 の見出しが項目を全部閉じた後の行も新しい木）。満たさなければ持ち主の中身
fn resolve(d : Deem, joins~ : Bool) -> Bool {
  guard d.pend is Some({ at, owner, }) else { return false }
  guard owner is Some(_) && joins else {
    spill(d)
    return false
  }
  d.pend = None
  // 書き戻しに要るのは綴りだけなので原文を控える
  keep(d, at, Border(rule=carve(d.md, at.from, at.to)))
  true
}

///|
/// 段（`base`）より深い最初の項目から上を降ろす。
fn close(stack : Array[Seat], base : Int) -> Unit {
  let h = open_height(stack, base)
  while stack.length() > h {
    ignore(stack.unsafe_pop())
  }
}

///|
/// 深さ `depth` 以上の枠を降ろす。
fn[T] lower(stack : Array[T], depth : Int) -> Unit {
  while stack.length() >= depth && !stack.is_empty() {
    ignore(stack.unsafe_pop())
  }
}

///|
/// 足りない深さを Implicit で埋める（飛びは綴りであって、無ではない）。積み方は `push` —
/// 木の積みは `Deem::seat` で積み、一番浅い深さを控えさせる
fn fill(stack : Array[Seat], depth : Int, push : (Seat) -> Unit) -> Unit {
  while stack.length() < depth - 1 {
    push({ mark: None, line: None, })
  }
}

///|
/// 木に枠を 1 つ積む。深さは高さが持つ。
/// **一番浅い深さはここで控える** — 1 枚の塊が枠を何段も積むので、後から測れない。
fn Deem::seat(d : Deem, s : Seat) -> Unit {
  let depth = d.tree.length() + 1
  if depth < d.top {
    d.top = depth
  }
  d.tree.push(s)
}

///|
/// 畳みの閉じ。**その部分木が終わったという宣言**なので、畳んだノードの枠を
/// 両方の積みから降ろす（領域は部分木を過不足なく覆うので、閉じの後ろはその外 —
/// 行も中身も）。続く骨格は畳んだノードの兄弟から測り、深い見出しは Implicit が間を
/// 埋める。側は裏返らない — 裏返すのは `---` だけ。
fn Deem::shut(d : Deem) -> Unit {
  guard d.fold_roots.pop() is Some(root) else { return }
  lower(d.read, root)
  lower(d.tree, root)
}

///|
/// 畳みの閉じの、組み立ての側。**降ろし方は 1 つ** — 裁定（`Deem::shut`）と同じ規則で降ろす。
fn[T] shut(stack : Array[T], fold_roots : Array[Int]) -> Unit {
  guard fold_roots.pop() is Some(root) else { return }
  lower(stack, root)
}

///|
/// 境界になれなかった水平線を、その場の中身として落とす。
/// **書かれた位置も持ち主もそのまま保たれる**（`Pend`）。
fn spill(d : Deem) -> Unit {
  guard d.pend is Some({ at, owner, }) else { return }
  d.pend = None
  keep(
    d,
    at,
    Card(
      content=Some(ThematicBreak),
      source=Some(carve(d.md, at.from, at.to)),
      owner~,
    ),
  )
}

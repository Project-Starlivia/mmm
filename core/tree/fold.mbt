// `<details>` を読む。
//
// **綴りの定義は 1 つ。** `spelling` が「mmm が畳みを書くときの文字」を返し、
// 読みはそれとの照合でしかない。畳みが立つのは、原文のその範囲が
// **mmm がそのノードを畳んだときに書く文字と一致する**ときだけ。
// 一致しなければ中身の 1 枚（`Block::Details`）になる。裁定は docs/spec.md。
//
// 「details タグとは何か」を知っているのは `tag_at` だけ。他は `Tag` しか見ない。
// 対にするのは**タグの並び**で、塊の境目は数えない（md のブロック境界と
// タグの入れ子は元々そろっていないので、そろっている前提を持たない）。

///|
/// 積む前のひと切れ。**記法構造の `Piece` とは別物** — こちらは畳みを解いた
/// 積む順の並びで、原文を隙間なく覆う約束は持たない（落ちた綴りは出てこない）。
priv enum Slice {
  /// 畳みに関わらない、素の塊
  Plain(@markdown.Block)
  /// 畳まれたノードの見出し・項目の行。中身は普通に読む。
  /// `at` は `<details>` 〜 `</details>` の原文の範囲（地番になる）。
  /// `open_at` は開きの綴りそのものの範囲 — 綴りは木から落ちるが、記法構造は
  /// その字も 1 枚として持つので、範囲だけ連れて回る
  Folded(
    @markdown.Block,
    fold~ : Fold,
    at~ : @markdown.Span,
    open_at~ : @markdown.Span
  )
  /// 綴りとして読めなかった領域。原文のまま中身になる。open / summary / body は
  /// GitHub が描くのと同じ読み取り（最初の開きと、その直後の名前と、閉じまでの間）。
  /// `from`・`to` は原文での範囲（地番になる）
  Capsule(
    text~ : String,
    open~ : Bool,
    summary~ : String?,
    body~ : String,
    from~ : Int,
    to~ : Int
  )
  /// mdAst がブロックとして返さないもの（リンクの定義行）。原文のまま中身になる
  Text(String, from~ : Int, to~ : Int)
  /// 立った畳みの閉じ。**その部分木が終わったという宣言**で、字は持たない
  /// （綴りは落ちている）。積む側が枠を降ろす目印
  Closed(from~ : Int, to~ : Int)
}

///|
/// 畳みの綴り 1 つ。
priv enum Spelling {
  Open(open~ : Bool)
  Name(String)
  Close
}

///|
/// 木からこの綴りを書き戻したときの文字。**mmm が書ける形はこれだけ。**
/// 「塊が記法だけで出来ているか」の判定は、すべてこの 1 行との比較に還元される。
fn spelling(m : Spelling) -> String {
  match m {
    Open(open=false) => "<details>"
    Open(open=true) => "<details open>"
    Name(s) => "<summary>\{s}</summary>"
    Close => "</details>"
  }
}

///|
/// 原文に見つけた綴り 1 つ。位置は**原文のバイト**でだけ持つ
/// （塊の html 文字列の添字は字下げでずれるので、座標には使わない）。
priv struct Tag {
  mark : Spelling
  from : Int
  to : Int
  /// 原文がそのまま `spelling(mark)` か。違えば触らずに書き戻せないので畳めない
  ok : Bool
}

///|
/// 塊 1 つの読み。
priv struct Spell {
  tags : Array[Tag]
  /// **塊まるごとが綴りで出来ている。** 空白を除いた原文が `spelling` の
  /// 並びそのもので、地の文も知らないタグも混じっていない。畳みが立つと
  /// この塊は丸ごと落ちるので、1 つでも書き戻せない字があれば立てられない
  writes : Bool
}

// ══════════════════════════════════════════════════════════════════
// 字句 — ここだけが「details タグとは何か」を知っている
// ══════════════════════════════════════════════════════════════════

///|
fn blank(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn slice(md : String, from : Int, to : Int) -> String {
  String::unsafe_substring(md, start=from, end=to)
}

///|
/// md の i に pat がそのまま在るか。
fn has(md : String, i : Int, pat : String, to : Int) -> Bool {
  guard i >= 0 && i + pat.length() <= to else { return false }
  for k in 0..<pat.length() {
    guard md[i + k] == pat[k] else { return false }
  }
  true
}

///|
/// タグ名の照合。HTML の名前は大小を区別しない。
fn name_at(md : String, i : Int, name : String, to : Int) -> Bool {
  guard i >= 0 && i + name.length() <= to else { return false }
  for k in 0..<name.length() {
    let c = md[i + k]
    let d = if c >= 'A' && c <= 'Z' { c + 32 } else { c }
    guard d == name[k] else { return false }
  }
  true
}

///|
/// pat の次の位置。無ければ to。
fn after(md : String, i : Int, pat : String, to : Int) -> Int {
  let mut k = i
  while k < to {
    if has(md, k, pat, to) {
      return k + pat.length()
    }
    k = k + 1
  }
  to
}

///|
/// タグ名がぴったり `name` か。名前の直後は空白・`>`・`/` のどれか
/// （`<pre` の前方一致で `<presentation>` を生テキストと読まないため）。
fn elem_name(md : String, i : Int, name : String, to : Int) -> Bool {
  guard name_at(md, i, name, to) else { return false }
  let z = i + name.length()
  z >= to || blank(md[z]) || md[z] == '>' || md[z] == '/'
}

///|
/// `</name …>` を大小を無視して探し、その次の位置。無ければ塊の終わり。
fn raw_end(md : String, i : Int, name : String, to : Int) -> Int {
  let mut k = i
  while k < to {
    if md[k] == '<' &&
      k + 1 < to &&
      md[k + 1] == '/' &&
      elem_name(md, k + 2, name, to) {
      let z = elem_end(md, k + 2 + name.length(), to)
      return if z > 0 { z } else { to }
    }
    k = k + 1
  }
  to
}

///|
/// コメント・擬似コメント・生テキストの終わり。**中に綴りは無いものとして跨ぐ。**
/// md が「ここは生の HTML」と言った範囲で HTML の字句規則に従うだけなので、
/// md の読み解き直しではない。`<script>var x = "</details>"` を閉じと読まない。
fn opaque_end(md : String, i : Int, to : Int) -> Int? {
  guard md[i] == '<' else { return None }
  if has(md, i, "<!--", to) {
    // `<!-->` と `<!--->` はそこで閉じた空のコメント
    if has(md, i, "<!-->", to) {
      return Some(i + 5)
    }
    if has(md, i, "<!--->", to) {
      return Some(i + 6)
    }
    return Some(after(md, i + 4, "-->", to))
  }
  // `<!` に `--` が続かない形と `<?` は擬似コメント。最初の `>` までが中身
  if has(md, i, "<!", to) || has(md, i, "<?", to) {
    return Some(after(md, i + 2, ">", to))
  }
  // 生テキスト（script / style）と RCDATA（textarea / title）は中を読まない。
  // svg は foreign content で、中の `details` は SVG の要素であって畳みではない
  for name in ["script", "style", "textarea", "title", "svg"] {
    if elem_name(md, i + 1, name, to) {
      return Some(raw_end(md, i, name, to))
    }
  }
  None
}

///|
/// 開きタグの終わり（`>` の次）。属性値を囲む引用符の中の `>` は数えない。
/// 名前の直後が空白・`>`・`/` でなければタグではない（`<details-x>` を弾く）。
/// **引用符が値を囲むのは `=` の直後だけ** — それ以外の位置の `"` は
/// HTML では属性名のただの文字なので、そこで囲みが始まったことにしない。
fn elem_end(md : String, i : Int, to : Int) -> Int {
  guard i < to else { return -1 }
  let c = md[i]
  guard blank(c) || c == '>' || c == '/' else { return -1 }
  let mut k = i
  let mut quote : UInt16 = 32
  let mut eq = false
  while k < to {
    let c = md[k]
    if quote != ' ' {
      if c == quote {
        quote = ' '
      }
    } else if c == '>' {
      return k + 1
    } else if c == '=' {
      eq = true
    } else if eq && (c == '"' || c == '\'') {
      quote = c
      eq = false
    } else if !blank(c) {
      eq = false
    }
    k = k + 1
  }
  -1
}

///|
/// i から始まる details / summary の綴り。
fn tag_at(md : String, i : Int, to : Int) -> Tag? {
  guard md[i] == '<' else { return None }
  let shut = i + 1 < to && md[i + 1] == '/'
  let n = if shut { i + 2 } else { i + 1 }
  if name_at(md, n, "details", to) {
    let z = elem_end(md, n + 7, to)
    guard z > 0 else { return None }
    let raw = slice(md, i, z)
    if shut {
      return Some({ mark: Close, from: i, to: z, ok: raw == spelling(Close), })
    }
    let mark = Open(open=raw == spelling(Open(open=true)))
    return Some({ mark, from: i, to: z, ok: raw == spelling(mark), })
  }
  // 閉じの `</summary>` は開きと組で 1 つの綴りにするので、単独では拾わない
  if !shut && name_at(md, n, "summary", to) {
    let a = elem_end(md, n + 7, to)
    guard a > 0 else { return None }
    let z = after(md, a, "</summary>", to)
    let b = z - 10
    guard has(md, b, "</summary>", to) else { return None }
    let mark = Name(slice(md, a, b))
    return Some({ mark, from: i, to: z, ok: slice(md, i, z) == spelling(mark), })
  }
  None
}

///|
/// 塊 1 つのタグを読む。生の HTML の塊だけを見る
/// （段落の中のタグは md が中身と言っているので、mmm は綴りにしない）。
fn spell_of(md : String, b : @markdown.Block) -> Spell {
  guard b is HtmlBlock(..) else { return { tags: [], writes: false, } }
  let s = block_span(b)
  let tags = []
  // **タグの間の空白は綴りではない。** 1 行に並べても行で分けても言っている
  // ことは同じで、書き戻すときは mmm の並べ方になる
  let mut writes = true
  let mut i = s.from
  while i < s.to {
    if blank(md[i]) {
      i = i + 1
      continue
    }
    // コメントと生テキストの中は綴りではない。中のタグを拾わないよう跨ぐ
    if opaque_end(md, i, s.to) is Some(z) {
      writes = false
      i = z
      continue
    }
    match tag_at(md, i, s.to) {
      Some(t) => {
        tags.push(t)
        writes = writes && t.ok
        i = t.to
      }
      None => {
        writes = false
        i = i + 1
      }
    }
  }
  { tags, writes: writes && tags.length() > 0, }
}

// ══════════════════════════════════════════════════════════════════
// 対にする — タグの並びで数える。塊の境目は関係ない
// ══════════════════════════════════════════════════════════════════

///|
/// 綴り 1 つと、それが在った塊。
priv struct Found {
  tag : Tag
  block : Int
}

///|
/// 開きと閉じの組。どちらも `spots` の添字。
priv struct Pair {
  open : Int
  close : Int
}

///|
/// 全部のタグを、居た塊と一緒に 1 列に並べる。**対は塊の境目を数えない**ので、
/// 対にする前に列を平らにする。
fn found(spells : Array[Spell]) -> Array[Found] {
  let out = []
  for i, s in spells {
    for t in s.tags {
      out.push({ tag: t, block: i, })
    }
  }
  out
}

///|
/// 原文のまま持つ領域と、その読み取り。GitHub が `<details>` を描くのと同じ
/// もの — 最初の開きの `open`、その直後に在れば `<summary>` の字、閉じまでの間の
/// 原文。**読み解かない裁定は変えない**（body は切り出すだけで、意味は付けない）。
fn capsule(
  md : String,
  spots : Array[Found],
  head : Int,
  tail : Int,
  from : Int,
  upto : Int,
) -> Slice {
  let open = spots[head].tag.mark is Open(open=true)
  let mut summary = None
  let mut inner = spots[head].tag.to
  if head + 1 < tail && spots[head + 1].tag.mark is Name(text) {
    summary = Some(text)
    inner = spots[head + 1].tag.to
  }
  Capsule(
    text=carve(md, from, upto),
    open~,
    summary~,
    body=strip(md, inner, spots[tail].tag.from),
    from~,
    to=upto,
  )
}

///|
/// 原文の切り出し。前後の改行と空白を落とすだけ（`carve` と違い、行頭から
/// 始まらないので容器の字下げは見ない）。
fn strip(md : String, from : Int, to : Int) -> String {
  let mut a = from
  while a < to && blank(md[a]) {
    a = a + 1
  }
  let mut z = to
  while z > a && blank(md[z - 1]) {
    z = z - 1
  }
  // 木が抱える字は LF だけ（`carve` と同じ不変量）
  lf(slice(md, a, z))
}

///|
/// 開きと閉じの対。相手の居ないタグは対にならず、ただの文字のまま残る。
fn paired(spots : Array[Found]) -> Array[Pair] {
  let stack = []
  let out = []
  for k, s in spots {
    match s.tag.mark {
      Open(..) => stack.push(k)
      Close =>
        if stack.length() > 0 {
          out.push({ open: stack.unsafe_pop(), close: k, })
        }
      Name(_) => ()
    }
  }
  out
}

// ══════════════════════════════════════════════════════════════════
// 裁定 — 領域が「mmm の書く形」と一致するか
// ══════════════════════════════════════════════════════════════════

///|
/// 空行を飛ばした次の位置。空行は記法であって中身ではない。
fn next(blocks : Array[@markdown.Block], i : Int) -> Int {
  let mut k = i + 1
  while k < blocks.length() && blocks[k] is BlankLines(..) {
    k = k + 1
  }
  k
}

///|
/// 記法を飛ばした次の位置。空行と**落ちる綴りの塊**だけを跨ぐ。
/// 兄弟の畳みが並んでいれば、見えるのは次の骨格の行になる。
/// 立たない畳みの綴りは中身（Details・ただの文字）になるので跨がない —
/// 跨ぐと、領域の外に在る中身を畳みの内側へ引き込んでしまう。
fn beyond(blocks : Array[@markdown.Block], gone : Array[Bool], i : Int) -> Int {
  let mut k = i + 1
  while k < blocks.length() && (blocks[k] is BlankLines(..) || gone[k]) {
    k = k + 1
  }
  k
}

///|
/// 塊にならない中身が、この塊の手前に在るか。mdAst はリンクの定義行を
/// ブロックとして返さない（`Document.definitions` に分けて持つ）が、原文には
/// 在って中身になる。**どの塊の範囲にも入っていないものだけ** — 段落や見出しの
/// 範囲に入っていれば、その文字はその塊が持っている
fn ahead_of(
  blocks : Array[@markdown.Block],
  defs : Array[@markdown.Span],
) -> Array[Bool] {
  let out = Array::make(blocks.length(), false)
  for s in defs {
    let mut k = 0
    while k < blocks.length() && block_span(blocks[k]).from <= s.from {
      k = k + 1
    }
    // k は定義行の後ろの最初の塊。手前の塊が抱えていれば、そこに文字は在る
    if k > 0 && block_span(blocks[k - 1]).to > s.from {
      continue
    }
    if k < blocks.length() {
      out[k] = true
    }
  }
  out
}

///|
/// 開きの塊が言っている畳み。**塊が綴りだけで出来ていることは `folds` が確かめる**
/// ので、ここは読むだけ。
fn fold_of(s : Spell) -> Fold {
  let open = s.tags[0].mark is Open(open=true)
  // 木が抱える字は LF だけ。綴りの照合（`Found.ok`）は原文のままやるので、
  // 揃えるのは木へ渡すここ
  let summary = if s.tags.length() > 1 && s.tags[1].mark is Name(text) {
    Some(lf(text))
  } else {
    None
  }
  { open, summary, }
}

///|
/// 領域が、1 つのノードの body・children とその body を過不足なく覆っているか。
///
/// 深さは md の `#` の数ではなく **build が実際に積んだ深さ**（`depths`）で測る。
/// 境界の `---` は部分木を深さ 2 へ引き出し、飛びは Implicit で埋まるので、
/// `#` の数で測ると「領域の外に出た子」を覆っているつもりになる。
fn covers(
  blocks : Array[@markdown.Block],
  depth : Array[Depth],
  gone : Array[Bool],
  head : Int,
  last : Int,
) -> Bool {
  // 1 つの塊に項目が 2 つ以上あると、同じ深さの枠が 2 つ生まれる。
  // 深さの列では見分けられないのでここで見る
  let alone = match blocks[head] {
    BulletList(items~, ..) | OrderedList(items~, ..) => items.length() == 1
    _ => true
  }
  guard alone else { return false }
  // 比べる基準は**そのノード自身の深さ**。飛びを埋めた Implicit の深さで比べると、
  // 兄弟（同じ足場の下に並ぶノード）まで部分木の中に見えてしまう
  let level = depth[head].own
  guard level < deep else { return false }
  // 中に同じか浅い枠が生まれていたら、その部分木より広い
  let mut k = head + 1
  while k <= last {
    guard depth[k].top > level else { return false }
    // 領域の中に書いた水平線の行き先が領域の外の骨格なら、その水平線は
    // 部分木のものではない（書き戻すと領域の外に出る）。行き先が中なら、
    // 引き出された骨格は上の深さで弾かれるか、飾りとして中身に残る。
    // **行き先は直後の塊だけ** — 水平線が続けば手前は飾りに落ちる（#178）
    if blocks[k] is ThematicBreak(..) {
      let w = beyond(blocks, gone, k)
      guard !(w > last && w < blocks.length() && depth[w].own < deep) else {
        return false
      }
    }
    k = k + 1
  }
  // **後ろが骨格なら深さは見ない。** 閉じは「この部分木が終わった」という宣言で、
  // 続く骨格は定義上その外（`shut` が枠を降ろし、深ければ間を Implicit が埋める）。
  // 骨格でなければ、その中身はこのノードの body ＝ 領域が狭いということ
  let z = beyond(blocks, gone, last)
  guard z < blocks.length() else { return true }
  // 水平線は単体では中身ではない。**直後が骨格なら境界**（部分木の外）で、
  // そうでなければ飾り＝このノードの中身なので、領域が狭い
  // （水平線が続けば手前は飾り。境界を取るのは最後の 1 本だけ。#178）
  if blocks[z] is ThematicBreak(..) {
    let w = beyond(blocks, gone, z)
    return w < blocks.length() && depth[w].top < deep
  }
  depth[z].top < deep
}

// ══════════════════════════════════════════════════════════════════
// ふるう — 綴りを落とし、中身と畳みの印を残す
// ══════════════════════════════════════════════════════════════════

///|
/// ふるいの途中。どの語彙も同じ材料を見るので、束ねて持ち回る。
priv struct Sift {
  md : String
  blocks : Array[@markdown.Block]
  /// 塊にならない中身（リンクの定義行）。原文の位置に戻すのに要る
  defs : Array[@markdown.Span]
  /// 項目の入れ子段数
  nest : Int
  /// 塊ごとの綴りの読み
  spells : Array[Spell]
  /// 全部のタグ。塊の境目は数えない
  spots : Array[Found]
  /// 開きと閉じの対
  pairs : Array[Pair]
  /// 塊ごと、手前に塊にならない中身が在るか
  ahead : Array[Bool]
  /// 塊ごと、対の開き・閉じを持つか。落ちる綴りでも深さは動かすので、
  /// 深さの空打ち（`depths`）に渡す
  opens : Array[Bool]
  closes : Array[Bool]
}

///|
/// 塊の列を、畳みを解いたひと切れの列にする。
fn sift(
  md : String,
  blocks : Array[@markdown.Block],
  defs : Array[@markdown.Span],
  nest : Int,
) -> Array[Slice] {
  let spells = blocks.map(b => spell_of(md, b))
  let spots = found(spells)
  let pairs = paired(spots)
  let opens = Array::make(blocks.length(), false)
  let closes = Array::make(blocks.length(), false)
  for p in pairs {
    opens[spots[p.open].block] = true
    closes[spots[p.close].block] = true
  }
  let s : Sift = {
    md,
    blocks,
    defs,
    nest,
    spells,
    spots,
    pairs,
    ahead: ahead_of(blocks, defs),
    opens,
    closes,
  }
  let v = standing(s)
  restore(s, arrange(s, v, marks(s, v), raws(s, v)))
}

///|
/// 畳みが立つかの裁定。**どの対が畳みとして立つか**と**どの塊が綴りとして落ちるか**は
/// 互いに依るので、1 つの答えとして一緒に決まる（`standing`）。
priv struct Stand {
  /// 対ごと。立つ対は畳みになる
  folded : Array[Bool]
  /// 塊ごと。落ちる塊は綴りなので、ひと切れにならない
  gone : Array[Bool]
}

///|
/// 立つ対と落ちる塊を、固定点で決める。畳みが立つかは「後ろに何が居るか」に依り、
/// そこに居るのが綴りか中身かは畳みが立つかに依るので、たがいに要る。
/// 全部落ちる側から始めて、落ちないものが出るたびにやり直す。
/// 落ちる塊は減る一方なので必ず止まる。**深さの空打ち（`depths`）を呼ぶのはここだけ。**
fn standing(s : Sift) -> Stand {
  let n = s.blocks.length()
  let gone = Array::makei(n, i => s.spells[i].writes)
  let mut folded = s.pairs.map(_ => false)
  for _ in 0..<=s.pairs.length() {
    // 深さも同じ `gone` で測る。跨ぐ塊が変われば本番の木も変わるので、
    // 判定と同じ前提で測り直さないと食い違う
    let depth = depths(s.md, s.blocks, gone, s.ahead, s.opens, s.closes, s.nest)
    folded = s.pairs.map(p => stands(s, depth, gone, p))
    let now = fallen(s, folded)
    let mut moved = false
    for i in 0..<n {
      if gone[i] && !now[i] {
        gone[i] = false
        moved = true
      }
    }
    if !moved {
      break
    }
  }
  // 落とせない塊に頼る畳みは立てない（同じタグが綴りと文字の両方になる）
  for k, p in s.pairs {
    if folded[k] &&
      !(gone[s.spots[p.open].block] && gone[s.spots[p.close].block]) {
      folded[k] = false
    }
  }
  { folded, gone, }
}

///|
/// 立った対にタグを全部取られた塊。**その塊は綴りだけで出来ている**ので落ちる。
/// 立っていない綴りが 1 つでも混じっていたら落とせない（その文字が消える）。
fn fallen(s : Sift, folded : Array[Bool]) -> Array[Bool] {
  let n = s.blocks.length()
  let claimed = Array::make(s.spots.length(), false)
  for k, p in s.pairs {
    if folded[k] {
      // 開きの塊は綴りだけで出来ている（`stands` が確かめた）ので、
      // その塊のタグは名前ごと全部落ちる
      for j, x in s.spots {
        if x.block == s.spots[p.open].block {
          claimed[j] = true
        }
      }
      claimed[p.close] = true
    }
  }
  let held = Array::make(n, false)
  let free = Array::make(n, true)
  for k, x in s.spots {
    held[x.block] = true
    if !claimed[k] {
      free[x.block] = false
    }
  }
  Array::makei(n, i => held[i] && free[i])
}

///|
/// 対 1 つが畳みとして立つか。**mmm がこのノードを畳んだら書く形**と
/// 一致するかを見るだけ。
fn stands(s : Sift, depth : Array[Depth], gone : Array[Bool], p : Pair) -> Bool {
  let ob = s.spots[p.open].block
  let cb = s.spots[p.close].block
  // 開きの塊は「開き」か「開き + 名前」だけ。他の文字が混じっていたら
  // 塊ごと落とせないので畳みにできない
  let os = s.spells[ob]
  guard os.writes && os.tags[0].mark is Open(..) else { return false }
  if os.tags.length() == 2 {
    guard os.tags[1].mark is Name(_) else { return false }
  } else {
    guard os.tags.length() == 1 else { return false }
  }
  // 閉じの塊は閉じだけ（重なっていてもよい。落ちるのは塊ごと）
  let cs = s.spells[cb]
  guard cs.writes else { return false }
  for t in cs.tags {
    guard t.mark is Close else { return false }
  }
  // 開きの次が骨格の行で、領域がその部分木を過不足なく覆っている。
  // **名前は持ち主を決めていない** — 決めているのは範囲のほうなので、
  // `<summary>` がラベルと一致するかは問わず、書かれたまま持つ
  let head = next(s.blocks, ob)
  guard head < cb else { return false }
  // 定義行は塊にならないので `next` では見えないが、中身であることに変わりは
  // ない。開きとノードの間に在れば、それはこのノードのものではない要素
  for k in (ob + 1)..<=head {
    guard !s.ahead[k] else { return false }
  }
  covers(s.blocks, depth, gone, head, cb - 1)
}

///|
/// 立った対が印を付ける骨格の行 → その畳みと、`<details>` 〜 `</details>` の
/// 原文の範囲。印の無い行は None。
fn marks(s : Sift, v : Stand) -> Array[(Fold, @markdown.Span, @markdown.Span)?] {
  let out : Array[(Fold, @markdown.Span, @markdown.Span)?] = Array::make(
    s.blocks.length(),
    None,
  )
  for k, p in s.pairs {
    if v.folded[k] {
      let ob = s.spots[p.open].block
      let open_at = block_span(s.blocks[ob])
      let at : @markdown.Span = {
        from: open_at.from,
        to: block_span(s.blocks[s.spots[p.close].block]).to,
      }
      out[next(s.blocks, ob)] = Some((fold_of(s.spells[ob]), at, open_at))
    }
  }
  out
}

///|
/// 綴りとして読めなかった領域。原文のまま 1 枚の中身になる。
priv struct Raw {
  /// 終わりの塊
  last : Int
  from : Int
  to : Int
  /// 開きと閉じの綴り（`spots` の添字）。中身としての読み取りに要る
  head : Int
  tail : Int
}

///|
/// 立たなかった対が原文のまま持つ領域 → 始まりの塊で引く。
/// 同じ塊から複数の対が始まるときは、**一番外**を採る。
fn raws(s : Sift, v : Stand) -> Array[Raw?] {
  let out : Array[Raw?] = Array::make(s.blocks.length(), None)
  for k, p in s.pairs {
    if v.folded[k] {
      continue
    }
    let ob = s.spots[p.open].block
    let cb = s.spots[p.close].block
    let had = match out[ob] {
      Some(r) => r.last
      None => -1
    }
    if cb <= had {
      continue
    }
    // 切るのは**塊まるごと** — タグからタグまでにすると、同じ塊に居た
    // 他の文字（余った閉じ・タグの前後の地の文）が落ちる
    out[ob] = Some({
      last: cb,
      from: block_span(s.blocks[ob]).from,
      to: block_span(s.blocks[cb]).to,
      head: p.open,
      tail: p.close,
    })
  }
  out
}

///|
/// 裁定どおりに並べる。落ちる塊は出さず、印の在る行は畳み、
/// 読めなかった領域は原文のまま 1 枚にする。
fn arrange(
  s : Sift,
  v : Stand,
  folds : Array[(Fold, @markdown.Span, @markdown.Span)?],
  raws : Array[Raw?],
) -> Array[Slice] {
  let out = []
  let mut i = 0
  while i < s.blocks.length() {
    match raws[i] {
      Some(r) => {
        out.push(capsule(s.md, s.spots, r.head, r.tail, r.from, r.to))
        i = r.last + 1
      }
      None => {
        if v.gone[i] {
          // 立った畳みの閉じは、字は落ちても**部分木の終わり**は残す
          if closing(s, v, i) {
            let at = block_span(s.blocks[i])
            out.push(Closed(from=at.from, to=at.to))
          }
        } else {
          out.push(
            match folds[i] {
              Some((fold, at, open_at)) =>
                Folded(s.blocks[i], fold~, at~, open_at~)
              None => Plain(s.blocks[i])
            },
          )
        }
        i = i + 1
      }
    }
  }
  out
}

///|
/// その塊が、立った畳みの閉じか。1 つの塊が閉じを何本も持つことはあるので、
/// **どれか 1 本でも立った対の閉じなら**その塊で部分木が終わる。
fn closing(s : Sift, v : Stand, block : Int) -> Bool {
  for k, p in s.pairs {
    if v.folded[k] && s.spots[p.close].block == block {
      return true
    }
  }
  false
}

///|
/// リンクの定義行を、書いてあった位置に戻す。mdAst はこれをブロックとして
/// 返さない（`Document.definitions` に分けて持つ）が、原文には在って中身になる。
/// 文書のどこに書いてもよい記法なので、まとめて 1 か所へ動かすと触っていない場所が動く。
///
/// **同じ行を 2 度は出さない** — 原文のまま持つ領域は定義ごと抱えるし、mdAst は
/// 定義行を段落や見出しの範囲に含めることがある（項目の中の定義は、項目を
/// 読み解くときに置かれる）。どこまでの原文がもうひと切れの中に入ったかで見る。
fn restore(s : Sift, pieces : Array[Slice]) -> Array[Slice] {
  let out = []
  let mut d = 0
  let mut carried = 0
  fn flush(before : Int) -> Unit {
    while d < s.defs.length() && s.defs[d].from < before {
      if s.defs[d].from >= carried {
        out.push(
          Text(
            carve(s.md, s.defs[d].from, s.defs[d].to),
            from=s.defs[d].from,
            to=s.defs[d].to,
          ),
        )
      }
      d = d + 1
    }
  }

  for p in pieces {
    let at = piece_span(p)
    flush(at.from)
    out.push(p)
    carried = at.to
  }
  flush(s.md.length() + 1)
  out
}

///|
/// ひと切れが原文で占める範囲。畳みは**骨格の行**の範囲で数える
/// （`<details>` の開きは落ちた綴りで、その手前の定義行は開きの塊が引き受けた）。
fn piece_span(p : Slice) -> @markdown.Span {
  match p {
    Plain(b) => block_span(b)
    Folded(b, ..) => block_span(b)
    Capsule(from~, to~, ..) => { from, to, }
    Text(_, from~, to~) => { from, to, }
    Closed(from~, to~) => { from, to, }
  }
}

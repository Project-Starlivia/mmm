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
/// 積む前のひと切れ。
priv enum Piece {
  Raw(@markdown.Block)
  /// 畳まれたノードの見出し・項目の行。中身は普通に読む
  Folded(@markdown.Block, open~ : Bool)
  /// 綴りとして読めなかった領域。原文のまま中身になる
  Capsule(String)
  /// mdAst がブロックとして返さないもの（リンクの定義行）。原文のまま中身になる
  Text(String)
}

///|
/// 畳みの綴り 1 つ。
priv enum Mark {
  Open(open~ : Bool)
  Name(String)
  Close
}

///|
/// 木からこの綴りを書き戻したときの文字。**mmm が書ける形はこれだけ。**
/// 「塊が記法だけで出来ているか」の判定は、すべてこの 1 行との比較に還元される。
fn spelling(m : Mark) -> String {
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
  mark : Mark
  to : Int
  /// 原文がそのまま `spelling(mark)` か。違えば触らずに書き戻せないので畳めない
  writes : Bool
}

///|
/// 塊 1 つの読み。
priv struct Spell {
  tags : Array[Tag]
  /// 綴り以外の文字があった（骨格の行・地の文・知らないタグ）
  plain : Bool
}

///|
/// 綴りだけで出来た塊か。畳みが立ったとき、この塊は丸ごと落ちる。
fn only_marks(s : Spell) -> Bool {
  !s.plain && s.tags.length() > 0
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
      return Some({ mark: Close, to: z, writes: raw == spelling(Close) })
    }
    let mark = Open(open=raw == spelling(Open(open=true)))
    return Some({ mark, to: z, writes: raw == spelling(mark) })
  }
  // 閉じの `</summary>` は開きと組で 1 つの綴りにするので、単独では拾わない
  if !shut && name_at(md, n, "summary", to) {
    let a = elem_end(md, n + 7, to)
    guard a > 0 else { return None }
    let z = after(md, a, "</summary>", to)
    let b = z - 10
    guard has(md, b, "</summary>", to) else { return None }
    let mark = Name(slice(md, a, b))
    return Some({ mark, to: z, writes: slice(md, i, z) == spelling(mark) })
  }
  None
}

///|
/// 塊を綴りとして読む。生の HTML の塊だけを見る
/// （段落の中のタグは md が中身と言っているので、mmm は綴りにしない）。
fn read_spell(md : String, b : @markdown.Block) -> Spell {
  guard b is HtmlBlock(..) else { return { tags: [], plain: true } }
  let s = block_span(b)
  let tags = []
  let mut plain = false
  let mut i = s.from
  while i < s.to {
    if blank(md[i]) {
      i = i + 1
      continue
    }
    if opaque_end(md, i, s.to) is Some(z) {
      plain = true
      i = z
      continue
    }
    match tag_at(md, i, s.to) {
      Some(t) => {
        tags.push(t)
        i = t.to
      }
      None => {
        plain = true
        i = i + 1
      }
    }
  }
  { tags, plain }
}

// ══════════════════════════════════════════════════════════════════
// 対にする — タグの並びで数える。塊の境目は関係ない
// ══════════════════════════════════════════════════════════════════

///|
/// 綴り 1 つと、それが在った塊。
priv struct Spot {
  tag : Tag
  block : Int
}

///|
/// 開きと閉じの対。相手の居ないタグは対にならず、ただの文字のまま残る。
fn pairs(spots : Array[Spot]) -> Array[(Int, Int)] {
  let stack = []
  let out = []
  for k, s in spots {
    match s.tag.mark {
      Open(..) => stack.push(k)
      Close => if stack.length() > 0 { out.push((stack.unsafe_pop(), k)) }
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
/// 包まれた行のラベル。見出しと項目でラベルの切り出し方が違う。
fn label_of(md : String, b : @markdown.Block) -> String {
  match b {
    Heading(style~, children~, span~, ..) =>
      head_label(md, span, style, children)
    BulletList(items~, ..) | OrderedList(items~, ..) =>
      match items[0].children.iter().find_first(c => c is Paragraph(..)) {
        Some(p) => item_label(md, p)
        None => ""
      }
    _ => ""
  }
}

///|
/// 領域が、1 つのノードの body・children とその body を過不足なく覆っているか。
///
/// 深さは md の `#` の数ではなく **build が実際に積んだ深さ**（`depths`）で測る。
/// 境界の `---` は部分木を深さ 2 へ引き出し、飛びは Implicit で埋まるので、
/// `#` の数で測ると「領域の外に出た子」を覆っているつもりになる。
fn covers(
  blocks : Array[@markdown.Block],
  low : Array[Int],
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
  let level = low[head]
  guard level < deep else { return false }
  // 中に同じか浅い枠が生まれていたら、その部分木より広い
  let mut k = head + 1
  while k <= last {
    guard low[k] > level else { return false }
    k = k + 1
  }
  // 後ろが部分木の中なら狭い
  let z = beyond(blocks, gone, last)
  guard z < blocks.length() else { return true }
  // 水平線は単体では中身ではない。**その先が骨格なら境界**（部分木の外）で、
  // そうでなければ飾り＝このノードの中身なので、領域が狭いということ
  if blocks[z] is ThematicBreak(..) {
    let w = beyond(blocks, gone, z)
    return w < blocks.length() && low[w] <= level
  }
  low[z] <= level
}

// ══════════════════════════════════════════════════════════════════
// 並べ直す
// ══════════════════════════════════════════════════════════════════

///|

///|
/// ブロックの並びを、畳みを解いたひと切れの列にする。
fn pieces(
  md : String,
  blocks : Array[@markdown.Block],
  defs : Array[@markdown.Span],
  nest : Int,
) -> Array[Piece] {
  let n = blocks.length()
  let spells = blocks.map(b => read_spell(md, b))
  let low = depths(md, blocks, spells, nest)
  let spots = []
  for i in 0..<n {
    for t in spells[i].tags {
      spots.push({ tag: t, block: i })
    }
  }
  let ps = pairs(spots)

  // **どの塊が綴りとして落ちるか**を決める。畳みが立つかは「後ろに何が居るか」
  // に依り、そこに居るのが綴りか中身かは畳みが立つかに依るので、たがいに要る。
  // 全部落ちる側から始めて、落ちないものが出るたびにやり直す。
  // 落ちる塊は減る一方なので必ず止まる。
  let gone = Array::makei(n, i => only_marks(spells[i]))
  let ok = ps.map(_ => false)
  for _ in 0..<=ps.length() {
    for k, p in ps {
      ok[k] = folds(md, blocks, spells, low, gone, spots, p.0, p.1)
    }
    // 塊が落ちるのは、**その塊の綴りが全部立った畳みのもの**のときだけ。
    // 立っていない綴りが混じっていたら落とせない（その文字が消える）
    let claimed = Array::make(spots.length(), false)
    for k, p in ps {
      if ok[k] {
        // 開きの塊は「開き + 名前」なので、名前も一緒に落ちる
        claimed[p.0] = true
        claimed[p.0 + 1] = true
        claimed[p.1] = true
      }
    }
    let held = Array::make(n, false)
    let free = Array::make(n, true)
    for k, s in spots {
      held[s.block] = true
      if !claimed[k] {
        free[s.block] = false
      }
    }
    let mut moved = false
    for i in 0..<n {
      let now = held[i] && free[i]
      if gone[i] && !now {
        gone[i] = false
        moved = true
      }
    }
    if !moved {
      break
    }
  }
  for k, p in ps {
    // 落とせない塊に頼る畳みは立てない（同じタグが綴りと文字の両方になる）
    if ok[k] && !(gone[spots[p.0].block] && gone[spots[p.1].block]) {
      ok[k] = false
    }
  }

  // 畳まれる骨格の行 → open か（-1 は畳みでない）
  let mark = Array::make(n, -1)
  // 原文のまま持つ領域 → 終わりの塊・原文の範囲
  let last = Array::make(n, -1)
  let from = Array::make(n, 0)
  let upto = Array::make(n, 0)
  for k, p in ps {
    let ob = spots[p.0].block
    if ok[k] {
      mark[next(blocks, ob)] = if spots[p.0].tag.mark is Open(open=true) {
        1
      } else {
        0
      }
    } else if spots[p.1].block > last[ob] {
      // 同じ塊から複数の対が始まるときは、一番外を採る。
      // 切るのは**塊まるごと** — タグからタグまでにすると、同じ塊に居た
      // 他の文字（余った閉じ・タグの前後の地の文）が落ちる
      last[ob] = spots[p.1].block
      from[ob] = block_span(blocks[ob]).from
      upto[ob] = block_span(blocks[spots[p.1].block]).to
    }
  }
  let out = []
  // リンクの定義行は mdAst がブロックとして返さない（`Document.definitions`
  // に分けて持つ）。**書いてあった位置に戻す** — 文書のどこに書いてもよい
  // 記法なので、まとめて 1 か所へ動かすと触っていない場所が動く
  let mut d = 0
  fn flush(before : Int) -> Unit {
    while d < defs.length() && defs[d].from < before {
      out.push(Text(carve(md, defs[d].from, defs[d].to)))
      d = d + 1
    }
  }

  let mut i = 0
  while i < n {
    flush(block_span(blocks[i]).from)
    if last[i] >= 0 {
      // 綴りとして読めなかった領域。丸ごと原文のまま持つ
      out.push(Capsule(carve(md, from[i], upto[i])))
      i = last[i] + 1
    } else if gone[i] {
      i = i + 1
    } else {
      out.push(
        if mark[i] >= 0 {
          Folded(blocks[i], open=mark[i] == 1)
        } else {
          Raw(blocks[i])
        },
      )
      i = i + 1
    }
  }
  flush(md.length() + 1)
  out
}

///|
/// 対 (o, c) が畳みとして立つか。**mmm がこのノードを畳んだら書く形**と
/// 一致するかを見るだけ。
fn folds(
  md : String,
  blocks : Array[@markdown.Block],
  spells : Array[Spell],
  low : Array[Int],
  gone : Array[Bool],
  spots : Array[Spot],
  o : Int,
  c : Int,
) -> Bool {
  guard spots[o].tag.writes && spots[c].tag.writes else { return false }
  let ob = spots[o].block
  let cb = spots[c].block
  // 開きの塊は「開き + 名前」だけ。他の文字が混じっていたら塊ごと落とせない
  let os = spells[ob]
  guard !os.plain && os.tags.length() == 2 else { return false }
  guard os.tags[1].mark is Name(name) && os.tags[1].writes else { return false }
  // 閉じの塊は閉じだけ（重なっていてもよい。落ちるのは塊ごと）
  let cs = spells[cb]
  guard !cs.plain else { return false }
  for t in cs.tags {
    guard t.mark is Close else { return false }
  }
  // 開きの次が骨格の行で、名前がそのラベルと一致する
  let head = next(blocks, ob)
  guard head < cb else { return false }
  guard name == label_of(md, blocks[head]) else { return false }
  covers(blocks, low, gone, head, cb - 1)
}

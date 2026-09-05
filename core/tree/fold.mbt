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
  /// 畳まれたノードの見出し・項目の行。中身は普通に読む。
  /// `at` は `<details>` 〜 `</details>` の原文の範囲（地番になる）
  Folded(@markdown.Block, fold~ : Fold, at~ : @markdown.Span)
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
      return Some({ mark: Close, from: i, to: z, ok: raw == spelling(Close) })
    }
    let mark = Open(open=raw == spelling(Open(open=true)))
    return Some({ mark, from: i, to: z, ok: raw == spelling(mark) })
  }
  // 閉じの `</summary>` は開きと組で 1 つの綴りにするので、単独では拾わない
  if !shut && name_at(md, n, "summary", to) {
    let a = elem_end(md, n + 7, to)
    guard a > 0 else { return None }
    let z = after(md, a, "</summary>", to)
    let b = z - 10
    guard has(md, b, "</summary>", to) else { return None }
    let mark = Name(slice(md, a, b))
    return Some({ mark, from: i, to: z, ok: slice(md, i, z) == spelling(mark) })
  }
  None
}

///|
/// 塊を綴りとして読む。生の HTML の塊だけを見る
/// （段落の中のタグは md が中身と言っているので、mmm は綴りにしない）。
fn read_spell(md : String, b : @markdown.Block) -> Spell {
  guard b is HtmlBlock(..) else { return { tags: [], writes: false } }
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
  { tags, writes: writes && tags.length() > 0 }
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
) -> Piece {
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
  slice(md, a, z)
}

///|
/// 開きと閉じの対。相手の居ないタグは対にならず、ただの文字のまま残る。
fn pairs(spots : Array[Found]) -> Array[(Int, Int)] {
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
/// 保留中の水平線が行き先に選ぶ塊。**本数に意味は無い**ので水平線が続くうちは
/// 先へ送り、骨格でない塊に当たればそこで飾りに落ちる。
fn lands(blocks : Array[@markdown.Block], gone : Array[Bool], i : Int) -> Int {
  let mut k = beyond(blocks, gone, i)
  while k < blocks.length() && blocks[k] is ThematicBreak(..) {
    k = beyond(blocks, gone, k)
  }
  k
}

///|
/// 開きの塊が言っている畳み。**塊が綴りだけで出来ていることは `folds` が確かめる**
/// ので、ここは読むだけ。
fn fold_of(s : Spell) -> Fold {
  let open = s.tags[0].mark is Open(open=true)
  let summary = if s.tags.length() > 1 && s.tags[1].mark is Name(text) {
    Some(text)
  } else {
    None
  }
  { open, summary }
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
    // 引き出された骨格は上の深さで弾かれるか、飾りとして中身に残る
    if blocks[k] is ThematicBreak(..) {
      let w = lands(blocks, gone, k)
      guard !(w > last && w < blocks.length() && depth[w].own < deep) else {
        return false
      }
    }
    k = k + 1
  }
  // 後ろが部分木の中なら狭い
  let z = beyond(blocks, gone, last)
  guard z < blocks.length() else { return true }
  // 水平線は単体では中身ではない。**その先が骨格なら境界**（部分木の外）で、
  // そうでなければ飾り＝このノードの中身なので、領域が狭いということ
  if blocks[z] is ThematicBreak(..) {
    let w = lands(blocks, gone, z)
    return w < blocks.length() && depth[w].top <= level
  }
  depth[z].top <= level
}

// ══════════════════════════════════════════════════════════════════
// 並べ直す
// ══════════════════════════════════════════════════════════════════

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
  let spots = []
  for i in 0..<n {
    for t in spells[i].tags {
      spots.push({ tag: t, block: i })
    }
  }
  let ps = pairs(spots)
  let ahead = ahead_of(blocks, defs)

  // **どの塊が綴りとして落ちるか**を決める。畳みが立つかは「後ろに何が居るか」
  // に依り、そこに居るのが綴りか中身かは畳みが立つかに依るので、たがいに要る。
  // 全部落ちる側から始めて、落ちないものが出るたびにやり直す。
  // 落ちる塊は減る一方なので必ず止まる。
  let gone = Array::makei(n, i => spells[i].writes)
  let ok = ps.map(_ => false)
  let mut depth = depths(md, blocks, gone, ahead, nest)
  for _ in 0..<=ps.length() {
    // 深さも同じ `gone` で測る。跨ぐ塊が変われば本番の木も変わるので、
    // 判定と同じ前提で測り直さないと食い違う
    depth = depths(md, blocks, gone, ahead, nest)
    for k, p in ps {
      ok[k] = folds(blocks, spells, depth, gone, ahead, spots, p.0, p.1)
    }
    // 塊が落ちるのは、**その塊の綴りが全部立った畳みのもの**のときだけ。
    // 立っていない綴りが混じっていたら落とせない（その文字が消える）
    let claimed = Array::make(spots.length(), false)
    for k, p in ps {
      if ok[k] {
        // 開きの塊は綴りだけで出来ている（folds が確かめた）ので、
        // その塊のタグは名前ごと全部落ちる
        for j, s in spots {
          if s.block == spots[p.0].block {
            claimed[j] = true
          }
        }
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

  // 畳まれる骨格の行 → その畳みと、`<details>` 〜 `</details>` の範囲（None は畳みでない）
  let mark : Array[(Fold, @markdown.Span)?] = Array::make(n, None)
  // 原文のまま持つ領域 → 終わりの塊・原文の範囲
  let last = Array::make(n, -1)
  let from = Array::make(n, 0)
  let upto = Array::make(n, 0)
  // 領域の開きと閉じの綴り（spots の添字）。中身として持つときの読み取りに要る
  let head = Array::make(n, 0)
  let tail = Array::make(n, 0)
  for k, p in ps {
    let ob = spots[p.0].block
    if ok[k] {
      let cb = spots[p.1].block
      let at : @markdown.Span = {
        from: block_span(blocks[ob]).from,
        to: block_span(blocks[cb]).to,
      }
      mark[next(blocks, ob)] = Some((fold_of(spells[ob]), at))
    } else if spots[p.1].block > last[ob] {
      // 同じ塊から複数の対が始まるときは、一番外を採る。
      // 切るのは**塊まるごと** — タグからタグまでにすると、同じ塊に居た
      // 他の文字（余った閉じ・タグの前後の地の文）が落ちる
      last[ob] = spots[p.1].block
      from[ob] = block_span(blocks[ob]).from
      upto[ob] = block_span(blocks[spots[p.1].block]).to
      head[ob] = p.0
      tail[ob] = p.1
    }
  }
  let out = []
  // リンクの定義行は mdAst がブロックとして返さない（`Document.definitions`
  // に分けて持つ）。**書いてあった位置に戻す** — 文書のどこに書いてもよい
  // 記法なので、まとめて 1 か所へ動かすと触っていない場所が動く
  let mut d = 0
  // どこまでの原文が、もうひと切れの中に入ったか。**同じ行を 2 度は出さない** —
  // 原文のまま持つ領域は定義ごと抱えるし、mdAst は定義行を段落や見出しの範囲に
  // 含めることがある。項目の中の定義は、項目を読み解くときに置かれる
  let mut carried = 0
  fn flush(before : Int) -> Unit {
    while d < defs.length() && defs[d].from < before {
      if defs[d].from >= carried {
        out.push(
          Text(
            carve(md, defs[d].from, defs[d].to),
            from=defs[d].from,
            to=defs[d].to,
          ),
        )
      }
      d = d + 1
    }
  }

  let mut i = 0
  while i < n {
    flush(block_span(blocks[i]).from)
    if last[i] >= 0 {
      // 綴りとして読めなかった領域。丸ごと原文のまま持つ
      out.push(capsule(md, spots, head[i], tail[i], from[i], upto[i]))
      carried = upto[i]
      i = last[i] + 1
    } else if gone[i] {
      i = i + 1
    } else {
      out.push(
        match mark[i] {
          Some((fold, at)) => Folded(blocks[i], fold~, at~)
          None => Raw(blocks[i])
        },
      )
      carried = block_span(blocks[i]).to
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
  blocks : Array[@markdown.Block],
  spells : Array[Spell],
  depth : Array[Depth],
  gone : Array[Bool],
  ahead : Array[Bool],
  spots : Array[Found],
  o : Int,
  c : Int,
) -> Bool {
  let ob = spots[o].block
  let cb = spots[c].block
  // 開きの塊は「開き」か「開き + 名前」だけ。他の文字が混じっていたら
  // 塊ごと落とせないので畳みにできない
  let os = spells[ob]
  guard os.writes && os.tags[0].mark is Open(..) else { return false }
  if os.tags.length() == 2 {
    guard os.tags[1].mark is Name(_) else { return false }
  } else {
    guard os.tags.length() == 1 else { return false }
  }
  // 閉じの塊は閉じだけ（重なっていてもよい。落ちるのは塊ごと）
  let cs = spells[cb]
  guard cs.writes else { return false }
  for t in cs.tags {
    guard t.mark is Close else { return false }
  }
  // 開きの次が骨格の行で、領域がその部分木を過不足なく覆っている。
  // **名前は持ち主を決めていない** — 決めているのは範囲のほうなので、
  // `<summary>` がラベルと一致するかは問わず、書かれたまま持つ
  let head = next(blocks, ob)
  guard head < cb else { return false }
  // 定義行は塊にならないので `next` では見えないが、中身であることに変わりは
  // ない。開きとノードの間に在れば、それはこのノードのものではない要素
  for k in (ob + 1)..<=head {
    guard !ahead[k] else { return false }
  }
  covers(blocks, depth, gone, head, cb - 1)
}

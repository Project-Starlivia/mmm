// 型で言えない不変条件を見る。
//
// 型は「あり得ない形」だけを殺す。関係の規則— id の一意さ、Implicit の
// 存在条件、側の本数 —は静的に書けないので、ここが見る。
//
// **md に書けない形**もここが見る。読みは前後の行から意味を決めるので、
// 木としては組めても、書いて読み直すと別の木になる並びがある。
//
// **parse の出力は必ず通る**（通らなければ読みのバグ）。操作の結果も通るべき。

///|
/// 見つかった破れ。直せるものと直せないものを分けない — 直すのは op の mend。
pub(all) enum Flaw {
  /// 同じ id が 2 度出た
  DupeId(Int)
  /// 子を持たない Implicit。飛びを埋める理由が無く、書き出す文字も無い
  BarrenImplicit(Int)
  /// 側の本数が根の子と合わない
  SideCount(root~ : Int, sides~ : Int, children~ : Int)
  /// 行の無い根（Implicit）の最初の子が左。手前の `---` は文書の段に書かれ、持ち主が
  /// 文書なので境界にならない（`--- / ## a`）。根を綴れば書ける
  Ownerless(Int)
  /// ノードの中身の尻の水平線に、同じ木の骨格の行が続く。境界（側の変わり目）に
  /// 読まれて中身に残らない
  BorderBreak(Int)
  /// 見出し（綴られた・綴られない）に続く項目、境界なしで続く Implicit。その見出しに
  /// 飲み込まれる — 項目は子に読まれ（境界が在っても深さは入れ物から測る）、飛びはその見出しの深さから測られる
  Swallowed(Int)
  /// Implicit の直下の項目。項目は書かれた入れ物から深さを測るので、行の無い
  /// Implicit を挟めない（境界の直後で、手前の兄弟の尻に書ける所は除く）
  GappedItem(Int)
  /// 深さ 7 以上の見出し。`#` は `deepest` 本までで、7 本目からは段落に読まれる
  TooDeep(Int)
  /// 深さ 3 以上で名前に改行。setext は深さ 2 までしか無く、ATX は 1 行しか持てない
  DeepSetext(Int)
  /// 綴りの無いノード（Implicit）が、行の要るもの（名前・畳み・中身）を持つ。
  /// 行を省いた空の見出しなので、綴ってからでないと当てられない
  Unmarked(Int)
  /// 書き戻す字が無い中身。読み解かなかったものと、畳めなかった `<details>` の
  /// 領域は原文でしか書けないので、`source` が無ければ書いたときに消える
  Wordless(Int)
} derive(Eq, ToJson)

///|
/// 見出しの最も深い所。`#` は 6 本まで（CommonMark）。項目は相対記法なので、
/// 見出しの下で何段深くても書ける — 階層に上限は無く、見出しにだけ在る。
pub let deepest : Int = 6

///|
/// 文書ぜんぶを見る。破れが無ければ空。
pub fn check(doc : Doc) -> Array[Flaw] {
  let c : Check = {
    flaws: [],
    seen: Set([]),
    trail: None,
    containers: Map([]),
  }
  for r in doc.roots {
    note(c, side_count(r))
    note(c, ownerless(r))
    containers(c.containers, r)
  }
  // 文書の中身の水平線は境界にならない（持ち主がノードでない）ので持ち回らない
  each_block(c, doc.body)
  walk(c, doc.roots.map(r => r.node), 1, 0, [], i => {
    turns(doc.roots[i]).map(t => t is Some(_))
  })
  c.flaws
}

///|
/// 検めの途中。id は文書ぜんぶで 1 つの列なので覚え、中身の尻の水平線は次の骨格まで
/// 文書順に持ち回る。境界の直後の Implicit をどこに書けるかは、書く側に先に聞いておく。
priv struct Check {
  flaws : Array[Flaw]
  seen : Set[Int]
  /// 文書順で 1 つ前の骨格が、中身の尻に置いた水平線
  mut trail : Int?
  /// 境界の直後の Implicit の鎖ごとに、その下に書いた項目の入れ物になる行の深さ（`containers`）
  containers : Map[Int, Int]
}

///|
/// 境界の直後の Implicit の鎖ごとに、その下に書いた項目の**入れ物になる行の深さ**を控える。
/// 項目は書かれた入れ物の 1 つ下に読まれるので、鎖の深さと一致すれば書ける。
/// **書く側と同じ道を辿る** — 書く側（`laid`）が手前の兄弟の尻へ移せた（`tuck`）なら鎖の
/// 深さそのもの。移せなければ境界の後ろ、根の段に書かれ、入れ物はそこで開いたままの
/// 一番深い見出しの節（`sections` — 手前の兄弟たちが開いた節は、境界では閉じない）、
/// 無ければ根（行の無い根なら文書 = 0）。
/// 先頭の子を辿る Implicit の鎖は丸ごと同じ所に書かれるので、鎖ぜんぶに控える
fn containers(out : Map[Int, Int], r : Root) -> Unit {
  let kept : Set[Int] = Set([])
  for l in laid(r).kids {
    kept.add(l.node.id)
  }
  let turned = turns(r)
  let root = if r.node.mark is None { 0 } else { 1 }
  let open : Array[Int] = []
  for i, k in r.node.children {
    if k.mark is None && turned[i] is Some(_) {
      let tucked = !kept.contains(k.id)
      let container = open.last().unwrap_or(root)
      let mut g : Node? = Some(k)
      let mut depth = 2
      while g is Some(n) {
        out[n.id] = if tucked { depth } else { container }
        g = match n.children {
          [first, ..] if first.mark is None => Some(first)
          _ => None
        }
        depth = depth + 1
      }
    }
    sections(open, k, 2)
  }
}

///|
/// 根の段で開いている見出しの節（深さ、浅い順）を、深さ `depth` の部分木 `n` を書いた後へ
/// 進める。見出しは同じか深い節を閉じて開き、項目は中の節ごと字下げの戻りで閉じ、
/// 畳みは閉じの後ろで部分木ごと閉じる。水平線は節を閉じない
fn sections(open : Array[Int], n : Node, depth : Int) -> Unit {
  guard !(n.mark is Some(Item(..))) else { return }
  if n.mark is Some(Heading(..)) {
    while open.last() is Some(d) && d >= depth {
      ignore(open.pop())
    }
    open.push(depth)
  }
  for k in n.children {
    sections(open, k, depth + 1)
  }
  if n.fold is Some(_) {
    while open.last() is Some(d) && d >= depth {
      ignore(open.pop())
    }
  }
}

///|
/// ノード 1 つが座っている席。**並びの規則はここから読む** — 前後の行で決まる
/// ことは、その席が言えるようにしてある。
priv struct Site {
  node : Node
  /// 深さ。根が 1
  depth : Int
  /// この列を抱える項目の深さ。**`#` の本数はそこから測る**（項目の中は、
  /// その項目の深さを 0 とした文書）。項目の外は 0
  base : Int
  /// 直前の兄弟。列の頭なら無い
  prev : Node?
  /// 直前の兄弟との間で側が変わる。そこには境界（`---`）が書かれる
  bordered : Bool
  /// 文書順で 1 つ前の骨格が、中身の尻に置いた水平線
  trail : Int?
  /// 境界の直後の Implicit の鎖なら、その下に書いた項目の入れ物になる行の深さ（`containers`）
  container : Int?
}

///|
/// 同じ列の兄弟を順に見る。`turned` はこの列の子ごとに手前へ境界が書かれるか（根の子だけが
/// 持つ）、`kids` は i 番目の子の列のそれ（根なら境界の表 `turns`、深ければ無い）。
fn walk(
  c : Check,
  xs : Array[Node],
  depth : Int,
  base : Int,
  turned : Array[Bool],
  kids : (Int) -> Array[Bool],
  mid? : Int? = None,
) -> Unit {
  for i, x in xs {
    // 新しい木の手前の水平線は境界にならない。親の中身が手前に挟まる子（`middle`）も
    if depth == 1 || mid == Some(x.id) {
      c.trail = None
    }
    // 手前に境界の `---` が書かれるか。**書く側と同じ表**（`turns`）
    let bordered = turned.get(i) == Some(true)
    let s : Site = {
      node: x,
      depth,
      base,
      prev: if i > 0 {
        Some(xs[i - 1])
      } else {
        None
      },
      bordered,
      trail: c.trail,
      container: c.containers.get(x.id),
    }
    c.trail = None
    note(c, border_break(s))
    note(c, swallowed(s))
    dupe(c, x.id)
    each_block(c, x.body)
    note(c, too_deep(s))
    note(c, deep_setext(s))
    note(c, barren(s))
    note(c, unmarked(s))
    note(c, gapped_item(s))
    // 中身の尻の水平線は、見出しでも項目でも次の骨格を境界にする。子が項目だけなら
    // 部分木の後ろに書かれる（`trails`）ので、部分木の次の骨格へ持ち回る。Implicit は
    // 行が無いので中身を書けない（`Unmarked`）— 綴られてから咎める
    let trail = if x.mark is Some(_) { trailing(x.body) } else { None }
    c.trail = if trails(x) { None } else { trail }
    // 項目の中は、その項目の深さを 0 とした文書。側は見出しの根も項目の根も持つ
    let inner = if sign_of(x) is Some(Item) { depth } else { base }
    walk(
      c,
      x.children,
      depth + 1,
      inner,
      kids(i),
      _ => [],
      mid=middle(x).map(h => h.id),
    )
    if trails(x) {
      c.trail = trail
    }
  }
}

///|
/// 中身の列を見る。**id はノードと同じ列**なので、ここでも数える。
fn each_block(c : Check, bs : Array[Block]) -> Unit {
  for b in bs {
    dupe(c, b.id)
    note(c, wordless(b))
  }
}

///|
/// その中身の列が尻に置いた水平線。
fn trailing(bs : Array[Block]) -> Int? {
  match bs.last() {
    Some({ id, content: Some(ThematicBreak), .. }) => Some(id)
    _ => None
  }
}

///|
/// 中身の尻の水平線を、子の後ろに書くか — **子が項目だけのとき**。子の手前に書けば
/// 続く骨格の行が境界に読むが、項目の列を閉じた後ろの塊は持ち主が自分に戻る
/// （docs/spec.md「水平線」）。見出しの子は後ろの塊を自分の中身にするので戻らない
fn trails(x : Node) -> Bool {
  trailing(x.body) is Some(_) &&
  x.children is [_, ..] &&
  x.children.iter().all(k => k.mark is Some(Item(..)))
}

///|
/// 中身を、項目の子の列と見出しの子の間に書くか。**項目の列の尻が水平線で終わり**（`ends`）、
/// 続く見出しの子がそれを境界にしてしまうとき、中身を挟めば線は飾りのまま
/// （`# a / - b / (b) --- / text / ## c`）。中身の尻が水平線なら挟んでも境界になるので挟まない。
/// 返すのは中身の後ろに書く最初の見出しの子。**書く側（`strokes`）も同じ答えを引く**
fn middle(x : Node) -> Node? {
  guard x.body.last() is Some(b) && !(b.content is Some(ThematicBreak)) else {
    return None
  }
  guard x.children.search_by(k => k.mark is Some(Heading(..))) is Some(split) &&
    split > 0 &&
    x.children[:split].iter().all(k => k.mark is Some(Item(..))) &&
    ends(x.children[split - 1]) else {
    return None
  }
  Some(x.children[split])
}

///|
/// 部分木を書いたとき、最後の塊が水平線か（書く側の順 — 尻に続く線は子が項目だけなら子の後ろ）。
/// 畳みは閉じが最後に来る
fn ends(n : Node) -> Bool {
  guard n.fold is None else { return false }
  guard !trails(n) else { return true }
  match n.children.last() {
    Some(k) => ends(k)
    None => trailing(n.body) is Some(_)
  }
}

///|
/// 破れが在れば控える。
fn note(c : Check, flaw : Flaw?) -> Unit {
  match flaw {
    Some(f) => c.flaws.push(f)
    None => ()
  }
}

// ══════════════════════════════════════════════════════════════════
// 規則 — 1 つにつき 1 つ。破れが無ければ None
// ══════════════════════════════════════════════════════════════════

///|
/// 同じ id が 2 度出た。文書ぜんぶで 1 つの列なので、歩きが覚えている。
fn dupe(c : Check, id : Int) -> Unit {
  if !c.seen.add_and_check(id) {
    c.flaws.push(DupeId(id))
  }
}

///|
/// 書き戻す字が無い中身。意味から綴れるのは絵の 4 つと水平線だけで、
/// 読み解かなかったものと畳めなかった領域は原文でしか書けない。
fn wordless(b : Block) -> Flaw? {
  guard b.source is None &&
    (b.content is None || b.content is Some(Details(..))) else {
    return None
  }
  Some(Wordless(b.id))
}

///|
/// 側の本数が根の子と合わない。
fn side_count(r : Root) -> Flaw? {
  let kids = r.node.children.length()
  guard r.sides.length() != kids else { return None }
  Some(SideCount(root=r.node.id, sides=r.sides.length(), children=kids))
}

///|
/// 行の無い根の最初の子が左。境界の `---` はその子の手前の文書の段に書かれ、持ち主が
/// 文書になるので境界にならない（docs/spec.md「水平線」の `--- / ## a`）。
fn ownerless(r : Root) -> Flaw? {
  guard r.node.mark is None && r.sides.get(0) is Some(Left) else { return None }
  Some(Ownerless(r.node.id))
}

///|
/// ノードの中身の尻の水平線に、同じ木の骨格の行が続く。次の骨格の行で境界
/// （側の変わり目）に読まれて、中身に残らない。
/// 側が変わる所には境界の `---` がもう 1 本書かれるので、中身の水平線は残る
/// （読みは 1 本目を中身に落とし、2 本目を境界にする）。
fn border_break(s : Site) -> Flaw? {
  guard !s.bordered else { return None }
  s.trail.map(b => BorderBreak(b))
}

///|
/// 見出し（綴られた・綴られない）に続く項目、境界なしで続く Implicit。その見出しに
/// 飲み込まれる — 項目は子に読まれ、飛びはその見出しの深さから測られる。
/// **境界で逃げられるのは Implicit だけ** — `---` の後ろの見出しは `#` の数で深さが決まるが、
/// 項目の深さは書かれた入れ物から測るので、`## a / --- / - b` の b は a の兄弟にならず、
/// 境界の後ろの Implicit の下に読まれる（docs/spec.md「水平線」）。
/// **畳まれた見出しも飲み込まない** — `</details>` がその部分木の終わりを言うので、
/// 閉じの後ろに書かれたものは外（docs/core.md「畳み」）。
fn swallowed(s : Site) -> Flaw? {
  guard s.prev is Some(prev) else { return None }
  guard !(sign_of(prev) is Some(Item)) &&
    prev.fold is None &&
    !(s.bordered && s.node.mark is None) &&
    !(sign_of(s.node) is Some(Heading)) else {
    return None
  }
  Some(Swallowed(s.node.id))
}

///|
/// 深さ 7 以上の見出し。`#` は `deepest` 本までで、7 本目からは段落に読まれる。
fn too_deep(s : Site) -> Flaw? {
  guard sign_of(s.node) is Some(Heading) && s.depth - s.base > deepest else {
    return None
  }
  Some(TooDeep(s.node.id))
}

///|
/// 深さ 3 以上で名前に改行。setext は深さ 2 までしか無く、ATX は 1 行しか持てない。
fn deep_setext(s : Site) -> Flaw? {
  guard sign_of(s.node) is Some(Heading) &&
    s.depth - s.base > 2 &&
    s.node.label.contains("\n") else {
    return None
  }
  Some(DeepSetext(s.node.id))
}

///|
/// 子を持たない Implicit。飛びを埋める理由が無く、書き出す文字も無い。
fn barren(s : Site) -> Flaw? {
  guard sign_of(s.node) is None && s.node.children.is_empty() else {
    return None
  }
  Some(BarrenImplicit(s.node.id))
}

///|
/// 綴りの無いノード（Implicit）が、行の要るもの（名前・畳み・中身）を持つ。
/// 行を省いた空の見出しなので、綴ってからでないと当てられない。
fn unmarked(s : Site) -> Flaw? {
  guard sign_of(s.node) is None else { return None }
  guard s.node.label != "" || s.node.fold is Some(_) || !s.node.body.is_empty() else {
    return None
  }
  Some(Unmarked(s.node.id))
}

///|
/// Implicit の先頭の子が項目。項目の深さは書かれた入れ物から測られ、Implicit に
/// 行は無いので 1 つ浅く読まれる（2 つ目からは直前の兄弟が深さを留める）。
/// **境界の直後なら、書いた所の入れ物がこの Implicit と同じ深さのとき書ける**（`containers`）—
/// 項目の深さはその行から測られて保たれる。
fn gapped_item(s : Site) -> Flaw? {
  guard sign_of(s.node) is None else { return None }
  guard s.node.children is [first, ..] && sign_of(first) is Some(Item) else {
    return None
  }
  guard s.container != Some(s.depth) else { return None }
  Some(GappedItem(first.id))
}

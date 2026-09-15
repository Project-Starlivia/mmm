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
  /// ノードの中身の尻の水平線に、同じ木の骨格の行が続く。境界（側の変わり目）に
  /// 読まれて中身に残らない
  BorderBreak(Int)
  /// 見出し（綴られた・綴られない）に境界なしで続く項目・Implicit。その見出しに
  /// 飲み込まれる — 項目は子に読まれ、飛びはその見出しの深さから測られる
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
  let c : Check = { flaws: [], seen: Set([]), border: None, }
  for r in doc.roots {
    note(c, side_count(r))
  }
  // 文書の中身の水平線は境界にならない（持ち主がノードでない）ので持ち回らない
  each_block(c, doc.body)
  walk(c, doc.roots.map(r => r.node), 1, 0, [], i => doc.roots[i].sides)
  c.flaws
}

///|
/// 検めの途中。**状態は 2 つだけ** — id は文書ぜんぶで 1 つの列なので覚え、
/// 中身の尻の水平線は次の骨格まで文書順に持ち回る。
priv struct Check {
  flaws : Array[Flaw]
  seen : Set[Int]
  /// 文書順で 1 つ前の骨格が、中身の尻に置いた水平線
  mut border : Int?
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
  border : Int?
  /// 境界の直後に立った Implicit の先頭の鎖に居るなら、境界の手前の兄弟の
  /// 部分木の尻の鎖で、書かれた行が居る深さ。その深さの行の中に書き足せる
  lead : Set[Int]?
}

///|
/// 同じ列の兄弟を順に見る。`sides` はこの列の側（根の子だけが持つ）、
/// `kids` は i 番目の子の列の側（根なら `Root.sides`、深ければ無い）、
/// `lead` は列の頭が境界の直後の Implicit の鎖を継ぐときの `Site.lead`。
fn walk(
  c : Check,
  xs : Array[Node],
  depth : Int,
  base : Int,
  sides : Array[Side],
  kids : (Int) -> Array[Side],
  lead? : Set[Int]? = None,
) -> Unit {
  for i, x in xs {
    // 新しい木の手前の水平線は境界にならない
    if depth == 1 {
      c.border = None
    }
    // 手前に境界の `---` が書かれるか。**書く側（unbuild の `nodes`）と同じ見方** —
    // 側は Right から始まるので、先頭の子が Left なら手前にも 1 本書かれる
    let bordered = i < sides.length() &&
      sides[i] != (if i > 0 { sides[i - 1] } else { Right })
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
      border: c.border,
      lead: if bordered && i > 0 {
        Some(tail(xs[i - 1], depth, Set([])))
      } else if i == 0 {
        lead
      } else {
        None
      },
    }
    c.border = None
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
    c.border = if trails(x) { None } else { trail }
    let under = if x.mark is None { s.lead } else { None }
    // 項目の中は、その項目の深さを 0 とした文書。側は見出しの根も項目の根も持つ
    let inner = if sign_of(x) is Some(Item) { depth } else { base }
    walk(c, x.children, depth + 1, inner, kids(i), _ => [], lead=under)
    if trails(x) {
      c.border = trail
    }
  }
}

///|
/// 部分木の尻の鎖（最後の子を辿る）で、書かれた行が居る深さ。`n` は深さ `depth`。
fn tail(n : Node, depth : Int, out : Set[Int]) -> Set[Int] {
  if n.mark is Some(_) {
    out.add(depth)
  }
  match n.children.last() {
    Some(k) => tail(k, depth + 1, out)
    None => out
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
/// ノードの中身の尻の水平線に、同じ木の骨格の行が続く。次の骨格の行で境界
/// （側の変わり目）に読まれて、中身に残らない。
/// 側が変わる所には境界の `---` がもう 1 本書かれるので、中身の水平線は残る
/// （読みは 1 本目を中身に落とし、2 本目を境界にする）。
fn border_break(s : Site) -> Flaw? {
  guard !s.bordered else { return None }
  s.border.map(b => BorderBreak(b))
}

///|
/// 見出し（綴られた・綴られない）に境界なしで続く項目・Implicit。その見出しに
/// 飲み込まれる — 項目は子に読まれ、飛びはその見出しの深さから測られる。
/// 側が変わる所には `---` が書かれるので飲み込まれない。
/// **畳まれた見出しも飲み込まない** — `</details>` がその部分木の終わりを言うので、
/// 閉じの後ろに書かれたものは外（docs/core.md「畳み」）。
fn swallowed(s : Site) -> Flaw? {
  guard s.prev is Some(prev) else { return None }
  guard !(sign_of(prev) is Some(Item)) &&
    prev.fold is None &&
    !s.bordered &&
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
/// **境界の直後なら書ける** — 境界の手前の兄弟の尻に、この Implicit と同じ深さの
/// 書かれた行が居れば、その行の中に `---` と項目を書けば深さが保たれる。
fn gapped_item(s : Site) -> Flaw? {
  guard sign_of(s.node) is None else { return None }
  guard s.node.children is [first, ..] && sign_of(first) is Some(Item) else {
    return None
  }
  guard !(s.lead is Some(t) && t.contains(s.depth)) else { return None }
  Some(GappedItem(first.id))
}

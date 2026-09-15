// 書く形 — 木を書く前に、側を境界の水平線として行に添え（`turns`）、境界の直後の
// Implicit を手前の兄弟の尻へ移す（`laid` / `tuck`）。書く歩き（unbuild.mbt）は側を知らず、
// 行に添えた綴りを手前に置くだけ。貼る断片の側を中身の線に戻すのも同じ表（`bordered`）。

///|
/// 書く形の枠 1 つ。木のノードに、手前に書く境界の水平線を添えたもの。
/// 子は `kids` が持つ — 境界の直後の Implicit の子は、手前の兄弟の尻へ移っている（`after`）
priv struct Laid {
  node : Node
  /// この行の手前に書く境界の綴り。無ければ None
  rule : String?
  kids : Array[Laid]
  /// 境界の後ろから移ってきた行（`tuck`）。**中身の尻より後ろ**に書く
  after : Array[Laid]
}

///|
/// 境界を持たない部分木の書く形。
fn Laid::of(n : Node) -> Laid {
  { node: n, rule: None, kids: n.children.map(Laid::of), after: [], }
}

///|
/// この部分木の中で最後に書かれる部分木 — 移ってきた行が在ればその尻、無ければ子の尻。
fn Laid::last(self : Laid) -> Laid? {
  match self.after.last() {
    Some(l) => Some(l)
    None => self.kids.last()
  }
}

///|
/// 根の子ごとの、手前に書く境界の綴り。**側が直前の兄弟と変わる子だけ**（先頭の子は
/// Right から比べる）。綴りは読んだ字、無ければ `---`。書く形（`laid`）と合流
/// （`turned`）が同じ表を引く
fn turns(r : Root) -> Array[String?] {
  let out : Array[String?] = []
  let mut prev = Right
  for i, _ in r.node.children {
    let side = r.sides.get(i).unwrap_or(prev)
    if side == prev {
      out.push(None)
      continue
    }
    prev = side
    out.push(
      match r.rules.get(i) {
        Some(s) if s != "" => Some(s)
        _ => Some("---")
      },
    )
  }
  out
}

///|
/// 根の側を、中身の水平線に戻した文書。**側の変わり目ごとに、書けば md がその子の手前の
/// 境界と読む所へ線を置く** — その子の行の直前に中身の尻が書かれる行（`rule_owner`）。
/// 綴りは書く側と同じ表（`turns`）。置ける行が無い変わり目は落とす — 行の無い根の最初の子や、
/// 手前の部分木の尻が畳みの中にしか無いとき（畳みの中に置けば畳みが崩れる）。
/// 側そのものは触らない。貼る断片は根でない席に差され、側は読み直しが決める（docs/spec.md「水平線」）
pub fn bordered(doc : Doc) -> Doc {
  let at : Map[Int, Array[Block]] = Map([])
  let next : Ref[Int] = { val: top_id(doc) + 1, }
  for r in doc.roots {
    for i, turn in turns(r) {
      guard turn is Some(rule) && rule_owner(r, i) is Some(owner) else {
        continue
      }
      let rule : Block = {
        id: next.val,
        content: Some(ThematicBreak),
        source: Some(rule),
      }
      next.val = next.val + 1
      at[owner] = [..at.get(owner).unwrap_or([]), rule]
    }
  }
  fn append(n : Node) -> Node {
    {
      ..n,
      body: [..n.body, ..at.get(n.id).unwrap_or([])],
      children: n.children.map(append),
    }
  }

  { ..doc, roots: doc.roots.map(r => { ..r, node: append(r.node), }), }
}

///|
/// 根 `r` の i 番目の子の手前に置く線の持ち主 — **書く順で、その子の行の直前に中身の尻が
/// 書かれる行**。先頭の子なら根（中身が子の手前に書かれるとき — 子が項目だけなら尻の線は
/// 子の後ろ `trails`）、でなければ手前の兄弟の部分木の尻（`tail_line`）。無ければ None
fn rule_owner(r : Root, i : Int) -> Int? {
  match r.node.children.get(i - 1) {
    Some(prev) => tail_line(prev)
    None =>
      if r.node.mark is Some(_) &&
        !r.node.children.iter().all(k => k.mark is Some(Item(..))) {
        Some(r.node.id)
      } else {
        None
      }
  }
}

///|
/// 部分木 `n` を書いたとき、**中身の尻が最後に書かれる行**。尻の水平線をもう子の後ろに書く行
/// （`trails`）ならその行、葉ならその行、子を持てば子の部分木の尻、そこに無ければ子が項目だけの
/// 行（足した線は子の後ろに書かれる）。畳みは閉じが最後に来るので、中には置けない
fn tail_line(n : Node) -> Int? {
  guard n.fold is None else { return None }
  guard !trails(n) else { return Some(n.id) }
  guard n.children.last() is Some(k) else {
    return if n.mark is Some(_) { Some(n.id) } else { None }
  }
  match tail_line(k) {
    Some(id) => Some(id)
    None =>
      if n.mark is Some(_) &&
        n.children.iter().all(c => c.mark is Some(Item(..))) {
        Some(n.id)
      } else {
        None
      }
  }
}

///|
/// 文書で使っている一番大きい id（ノードも中身も）。無ければ文書の id。
fn top_id(doc : Doc) -> Int {
  let top : Ref[Int] = { val: doc_id, }
  fn blocks(bs : Array[Block]) {
    for b in bs {
      if b.id > top.val {
        top.val = b.id
      }
    }
  }

  fn node(n : Node) {
    if n.id > top.val {
      top.val = n.id
    }
    blocks(n.body)
    for k in n.children {
      node(k)
    }
  }

  blocks(doc.body)
  for r in doc.roots {
    node(r.node)
  }
  top.val
}

///|
/// 根の書く形。**側の変わり目は、変わる子の行の手前に書く境界**（`turns`）。
///
/// **境界の直後の Implicit は、手前の兄弟の尻へ移す。** Implicit は深さを保って
/// 置き直された行の足場で、行が無いので、手前の兄弟の尻の同じ深さの行の中に
/// 書くしか深さを保つ道が無い（docs/spec.md「水平線」）。移せなければそのまま書き、
/// 読み直しが形を決める
fn laid(r : Root) -> Laid {
  let rules = turns(r)
  let out : Array[Laid] = []
  for i, k in r.node.children {
    match rules[i] {
      None => out.push(Laid::of(k))
      Some(rule) =>
        if k.mark is None &&
          out.last() is Some(p) &&
          tuck(p, k, rule) is Some(q) {
          out[out.length() - 1] = q
        } else {
          out.push({ ..Laid::of(k), rule: Some(rule), })
        }
    }
  }
  { node: r.node, rule: None, kids: out, after: [], }
}

///|
/// Implicit `gap` の子を、同じ深さの書かれた行 `host` の尻へ移し、移した先頭の行の
/// 手前に境界 `rule` を添える。**移した行は host の中身の尻より後ろ**（`after`）— 子の後ろに
/// 書く尻の水平線（`front`）より前に置けば、その線が移した行の手前の境界になる。
/// `gap` の先頭の子も Implicit なら、host の中で最後に書かれる行の尻へさらに降りる
/// （降りるだけなら行の無い host も通る — 書き足すのは降りた先の書かれた行）。
/// **項目は、host より深い見出しの節が開いていれば移せない**（`open_section`）— 項目の
/// 深さは書かれた入れ物から測るので、その節に入ってしまう。移せなければ None
fn tuck(host : Laid, gap : Node, rule : String) -> Laid? {
  guard gap.children is [first, .. rest] else { return None }
  let more : Array[Laid] = rest.iter().map(Laid::of).collect()
  if first.mark is None {
    let kids = host.kids.copy()
    let after = host.after.copy()
    match after.last() {
      Some(tail) => {
        guard tuck(tail, first, rule) is Some(moved) else { return None }
        after[after.length() - 1] = moved
      }
      // 子の後ろに尻の水平線を書く host の子へは降りない — 移した行の後ろにその線が来る
      None => {
        guard front(host) == host.node.body.length() &&
          kids.last() is Some(tail) &&
          tuck(tail, first, rule) is Some(moved) else {
          return None
        }
        kids[kids.length() - 1] = moved
      }
    }
    return Some({ ..host, kids, after: [..after, ..more], })
  }
  guard host.node.mark is Some(_) &&
    !(first.mark is Some(Item(..)) && open_section(host)) else {
    return None
  }
  Some({
    ..host,
    after: [..host.after, { ..Laid::of(first), rule: Some(rule), }, ..more],
  })
}

///|
/// host の部分木の尻で、host より深い見出しの節が開いたままか。host の段に書く行は、
/// 深い項目を字下げの戻りで閉じるが、見出しの節は閉じない。畳みは閉じの後ろで閉じている
fn open_section(host : Laid) -> Bool {
  guard host.last() is Some(k) && k.node.fold is None else { return false }
  match k.node.mark {
    Some(Heading(..)) => true
    Some(Item(..)) => false
    None => open_section(k)
  }
}

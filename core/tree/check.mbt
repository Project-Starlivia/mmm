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
/// 見つかった破れ。直せるものと直せないものを分けない — 直すのは normalize。
pub(all) enum Flaw {
  /// 同じ id が 2 度出た
  DupeId(Int)
  /// 子を持たない Implicit。飛びを埋める理由が無く、書き出す文字も無い
  BarrenImplicit(Int)
  /// 側の本数が根の子と合わない
  SideCount(root~ : Int, sides~ : Int, children~ : Int)
  /// 畳みの名前が `<summary>` に書けない。読み戻すと別のものになる
  UnwritableName(Int)
  /// 中身の尻の水平線に骨格が続く。境界（側の変わり目）に読まれて中身に残らない
  BorderBreak(Int)
  /// 見出し（綴られた・綴られない）に境界なしで続く項目・Implicit。その見出しに
  /// 飲み込まれる — 項目は子に読まれ、飛びはその見出しの深さから測られる
  Swallowed(Int)
  /// 項目の根の子に Left。項目の中の `---` は中身なので側を書けない
  ListSide(Int)
  /// Implicit の直下の項目。項目は相対記法で深さが飛ばないので、飛びを綴れない
  GappedItem(Int)
} derive(Eq, ToJson)

///|
/// 文書ぜんぶを見る。破れが無ければ空。
pub fn check(doc : Doc) -> Array[Flaw] {
  let flaws = []
  let seen : Set[Int] = Set([])
  fn id(n : Int) -> Unit {
    if !seen.add_and_check(n) {
      flaws.push(DupeId(n))
    }
  }

  fn blocks(bs : Array[Block]) -> Unit {
    for x in bs {
      id(x.id)
    }
  }

  /// 「畳んでいないのに open」は型が殺しているので、ここには来ない。
  fn named(n : Int, fold : Fold?) -> Unit {
    guard fold is Some({ summary: Some(s), .. }) else { return }
    if !writable(s) {
      flaws.push(UnwritableName(n))
    }
  }

  // 中身の尻に水平線があれば、次の骨格の行で境界に読まれる。
  // 項目の中の水平線は中身なので保留しない
  let border : Ref[Int?] = { val: None }
  fn trailing(bs : Array[Block]) -> Int? {
    match bs.last() {
      Some({ id, content: ThematicBreak }) => Some(id)
      _ => None
    }
  }

  fn skeleton() -> Unit {
    match border.val {
      Some(b) => flaws.push(BorderBreak(b))
      None => ()
    }
    border.val = None
  }

  fn items(xs : Array[ListNode]) -> Unit {
    for x in xs {
      id(x.id)
      named(x.id, x.fold)
      blocks(x.body)
      items(x.children)
    }
  }

  /// 同じ列の兄弟。並びの規則もここで見る。`sides` はこの列の側（根の子だけが
  /// 持つ）で、側が変わる所には境界（`---`）が書かれるので、そこでは飲み込まれない。
  /// `kids` は i 番目の子の列の側（根なら `Root.sides`、深ければ無い）
  fn nodes(
    xs : Array[Node],
    sides : Array[Side],
    kids : (Int) -> Array[Side],
  ) -> Unit {
    for i, x in xs {
      skeleton()
      let after_heading = i > 0 && !(xs[i - 1] is ListNode(_))
      let bordered = i > 0 && i < sides.length() && sides[i] != sides[i - 1]
      if after_heading && !bordered && !(x is HeadingNode(_)) {
        flaws.push(Swallowed(id_of(x)))
      }
      match x {
        HeadingNode(h) => {
          id(h.id)
          named(h.id, h.fold)
          blocks(h.body)
          border.val = trailing(h.body)
          nodes(h.children, kids(i), _ => [])
        }
        ListNode(l) => {
          id(l.id)
          named(l.id, l.fold)
          blocks(l.body)
          items(l.children)
        }
        ImplicitNode(g) => {
          id(g.id)
          if g.children.is_empty() {
            flaws.push(BarrenImplicit(g.id))
          }
          for k in g.children {
            if k is ListNode(l) {
              flaws.push(GappedItem(l.id))
            }
          }
          nodes(g.children, kids(i), _ => [])
        }
      }
    }
  }

  for r in doc.roots {
    let kids = match r.node {
      HeadingNode(h) => h.children.length()
      ImplicitNode(g) => g.children.length()
      ListNode(l) => l.children.length()
    }
    if r.sides.length() != kids {
      flaws.push(
        SideCount(root=root_id(r), sides=r.sides.length(), children=kids),
      )
    }
    if r.node is ListNode(_) && r.sides.contains(Left) {
      flaws.push(ListSide(root_id(r)))
    }
  }
  blocks(doc.body)
  border.val = trailing(doc.body)
  nodes(doc.roots.map(r => r.node), [], i => doc.roots[i].sides)
  flaws
}

///|
/// 畳みの名前として `<summary>` に書けるか。**塊が割れる字並びは書けない** —
/// `<summary>` の中身は最初の `</summary>` までで、生の HTML の塊は空行で終わる。
/// 畳む操作もこれで見て、書けなければ名前を付けずに畳む。
pub fn writable(s : String) -> Bool {
  !(s.contains("</summary>") || blank_line(s))
}

///|
/// 空行が混じっているか。行いっぱいが空白の行は、生の HTML の塊を終わらせる。
fn blank_line(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    guard s[i] == '\n' else {
      i = i + 1
      continue
    }
    let mut k = i + 1
    while k < s.length() && (s[k] == ' ' || s[k] == '\t' || s[k] == '\r') {
      k = k + 1
    }
    if k < s.length() && s[k] == '\n' {
      return true
    }
    i = k
  }
  false
}

///|
fn root_id(r : Root) -> Int {
  id_of(r.node)
}

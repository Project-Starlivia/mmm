// 型で言えない不変条件を見る。
//
// 型は「あり得ない形」だけを殺す。関係の規則— id の一意さ、Implicit の
// 存在条件、側の本数 —は静的に書けないので、ここが見る。
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

  fn items(xs : Array[ListNode]) -> Unit {
    for x in xs {
      id(x.id)
      named(x.id, x.fold)
      blocks(x.body)
      items(x.children)
    }
  }

  fn nodes(xs : Array[Node]) -> Unit {
    for x in xs {
      match x {
        HeadingNode(h) => {
          id(h.id)
          named(h.id, h.fold)
          blocks(h.body)
          nodes(h.children)
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
          nodes(g.children)
        }
      }
    }
  }

  blocks(doc.body)
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
    nodes([r.node])
  }
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
  match r.node {
    HeadingNode(h) => h.id
    ListNode(l) => l.id
    ImplicitNode(g) => g.id
  }
}

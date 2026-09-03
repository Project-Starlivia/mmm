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
  /// 畳んでいないのに `open` が立っている。書き出す `<details>` が無い
  OpenWithoutDetails(Int)
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
      if x is Details(id=i, ..) {
        id(i)
      }
    }
  }

  fn shut(n : Int, details : Bool, open : Bool) -> Unit {
    if open && !details {
      flaws.push(OpenWithoutDetails(n))
    }
  }

  fn items(xs : Array[ListNode]) -> Unit {
    for x in xs {
      id(x.id)
      shut(x.id, x.details, x.open)
      blocks(x.body)
      items(x.children)
    }
  }

  fn nodes(xs : Array[Node]) -> Unit {
    for x in xs {
      match x {
        HeadingNode(h) => {
          id(h.id)
          shut(h.id, h.details, h.open)
          blocks(h.body)
          nodes(h.children)
        }
        ListNode(l) => {
          id(l.id)
          shut(l.id, l.details, l.open)
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
fn root_id(r : Root) -> Int {
  match r.node {
    HeadingNode(h) => h.id
    ListNode(l) => l.id
    ImplicitNode(g) => g.id
  }
}

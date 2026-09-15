// 門 — 操作の結果を、md に書ける木にして返す。見出しの天井（`cap`）を綴り替え、
// Implicit を綴れば直る破れを繕い（`mend`）、残れば断る。何が書けないかは check の 1 つ。

///|
/// **md に書ける木しか返さない。** 何が書けないかは check が 1 つで言う
/// （骨格の直前の水平線・見出しに飲み込まれる項目・行の無い Implicit の下の項目）ので、
/// 操作ごとに規則を写さず、組んだ結果を check に通す。見出しの深さは cap が
/// 綴り替え、Implicit を綴れば直る破れは mend が繕い、残れば断る。
/// cap が先 — 天井を越えた見出しは mend には直せない。
/// 例外は境界（`BorderBreak`）だけ — 書けば md が境界と読むので、形は読み直しが決める。
fn apply(doc : @tree.Doc, op : Op) -> Done? {
  guard attempt(doc, op) is Some(d) else { return None }
  guard mend(cap(d.doc)) is Some(doc) else { return None }
  Some({ doc, focus: d.focus.filter(f => has(doc, f)), })
}

///|
/// 部分木をその綴りで書き直す。形（ラベル・中身・子・畳み・飛び）は保ち、綴りだけ替える —
/// **読んだ綴りは保ち**、種類が変わるものだけ新しく作る綴りで書く。
/// 項目にするとき、飛び（Implicit）は行を省けないので空の項目として綴る（`- - b`）。
/// 見出しにするとき、Implicit はそのまま — 省いたままで読めない席かは check と mend が見る。
/// 決めは docs/superpowers/specs/2026-09-06-paste-design.md
fn respell(n : @tree.Node, sign : @tree.Sign) -> @tree.Node {
  let mark : @tree.Mark? = match (sign, n.mark) {
    (Item, Some(Item(..))) | (Heading, Some(Heading(..))) => n.mark
    (Item, _) => Some(@tree.bullet)
    (Heading, None) => None
    (Heading, _) => Some(@tree.atx)
  }
  { ..n, mark, children: n.children.map(c => respell(c, sign)), }
}

///|
/// 見出しの天井。`@tree.deepest` より深くに着いた見出しは部分木ごと項目に
/// 綴り替える — 手で書くときも `######` の下は `- ` でしか続けられない。
/// 天井より深い Implicit は空の項目として綴る（飛びは形なので運ぶ。`- - b`）。
/// 天井の Implicit は行を省いた空の見出しなので残す
/// （子が項目になれば `GappedItem` — 綴れば読める）。上の段には触らないので、
/// parse の出力には何もしない。
fn cap(doc : @tree.Doc) -> @tree.Doc {
  // `base` はその列を抱える項目の深さ。**`#` の本数はそこから測る**
  // （項目の中は、その項目の深さを 0 とした文書）。項目の外は 0
  fn node(
    n : @tree.Node,
    depth : Int,
    base : Int,
    out : Array[@tree.Node],
  ) -> Unit {
    fn under(xs : Array[@tree.Node], base : Int) -> Array[@tree.Node] {
      let children = []
      for c in xs {
        node(c, depth + 1, base, children)
      }
      children
    }

    if @tree.sign_of(n) is Some(Item) {
      out.push({ ..n, children: under(n.children, depth), })
    } else if depth - base <= @tree.deepest {
      out.push({ ..n, children: under(n.children, base), })
    } else {
      out.push(respell(n, Item))
    }
  }

  // 根は深さ 1 なので必ず 1 つ残り、根の子の数も変わらない（sides はそのまま）
  {
    ..doc,
    roots: doc.roots.map(r => {
      let out = []
      node(r.node, 1, 0, out)
      { ..r, node: out[0], }
    }),
  }
}

///|
/// check の破れのうち、Implicit で直るものを直して通し直す。子が尽きた Implicit
/// （`BarrenImplicit`）は消す — 道具は途中で席が消えないように残しておくので、
/// 掃除はここ。見出しの直後に来た Implicit（`Swallowed`）と、先頭の子が項目の
/// Implicit（`GappedItem` の親）と、最初の子が左の行の無い根（`Ownerless`）は綴る。
/// 消すものは綴らないので、消す回は綴らない。行の要るものを持った Implicit（`Unmarked`）は
/// 来ない — 名前・畳み・中身を持たせる道具は、先に綴ってから当てる（`rename` / `fold` / `body`）。
/// 一回ごとに Implicit は減るので止まる。残った破れは None。
fn mend(doc : @tree.Doc) -> @tree.Doc? {
  let mut cur = doc
  for ;; {
    let flaws = @tree.check(cur)
    if flaws.is_empty() {
      return Some(cur)
    }
    let barren = []
    let ids = []
    for f in flaws {
      match f {
        BarrenImplicit(id) => barren.push(id)
        Swallowed(id) => ids.push(id)
        Ownerless(id) => ids.push(id)
        GappedItem(id) => ids.push(parent(cur, id).unwrap())
        _ => ()
      }
    }
    let mut fixed = false
    for id in barren {
      guard splice(cur, id, _ => []) is Some(d) else { return None }
      cur = d
      fixed = true
    }
    if barren.is_empty() {
      for id in ids {
        guard find(cur, id) is Some(g) else { continue }
        guard g.mark is None else { continue }
        guard splice(cur, id, _ => [spell(g, "")]) is Some(d) else {
          return None
        }
        cur = d
        fixed = true
      }
    }
    if !fixed {
      // 中身の尻の水平線に骨格が続く形（`BorderBreak`）だけは通す — 書けば md が
      // 境界と読む（根の子なら側の反転、深ければ深さを保って根の反対側へ置き直す）。
      // 形は読み直しが決めるので、そのとき edit は focus を持たない
      return if flaws.iter().all(f => f is BorderBreak(_)) {
        Some(cur)
      } else {
        None
      }
    }
  }
}

///|
/// Implicit を綴る。行を省いた空の見出しなので、名を付ければ見出しそのもの。
fn spell(g : @tree.Node, label : String) -> @tree.Node {
  { ..g, label, mark: Some(@tree.atx), }
}

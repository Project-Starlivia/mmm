// 貼る — md の断片を形として読み、席の綴りで差す（`graft`）。断片が持ち込むのは形で、
// 綴りは席が決める。決めは docs/superpowers/specs/2026-09-06-paste-design.md

///|
/// 部分木の id をまとめてずらす。parse が振った番号を、いまの木に無い番号へ。
fn shift(n : @tree.Node, by : Int) -> @tree.Node {
  fn blocks(bs : Array[@tree.Block]) -> Array[@tree.Block] {
    bs.map(b => { id: b.id + by, content: b.content, source: b.source, })
  }

  {
    ..n,
    id: n.id + by,
    body: blocks(n.body),
    children: n.children.map(c => shift(c, by)),
  }
}

///|
/// md を読んで形にし、席の綴りで差す。断片が持ち込むのは形（ラベル・中身・子・畳み・
/// 飛び）だけで、`#` の本数・マーカー・先頭の飛びは書き方なので捨てる。
/// 一番外は順に読み、段落は行ごとにノード、それ以外の中身は直前に生えたノードの
/// 中身へ（無ければ行き先の親の body 末尾へ）。`---` は md と同じ意味 — 断片の側は
/// 境界として運び、書けば md が境界と読む（形は読み直しが決める）。
///
/// **行の字下げは形。** 桁が深ければ手前の行の子になる（`grow` の梯子）。断片の
/// 左余白は切り出した先の容器なので落とす（`@tree.dedent`）。md を読む側は改行を
/// 段落の中の折り返しと見るが、**貼る側は行で切る** — マップへ貼るのは字を構造に
/// したいからで、そこは読みと違っていい（#118）
/// （行き先が文書なら文書の散文へ。マップには出ないが、手で頭に書いたのと同じ）。
/// 断片が `##` から始まると parse は根を Implicit で包む（深さ 1 の飛び）。
/// それは切り出した場所の名残でしかないので剥がし、相対の形で差す。
/// 決めは docs/superpowers/specs/2026-09-06-paste-design.md
fn graft(doc : @tree.Doc, at : NodePlace, md : String) -> Done? {
  // 断片の左余白は切り出した先の容器なので落とす（`@tree.dedent`）。
  // 落とさないと 4 桁以上入った枝の写しが字下げコードとして読まれ、ノードが
  // 1 つも生えない。桁を原文から測るので、読むのは地番付きの `build`
  let md = @tree.dedent(md)
  let (sub, spots) = @tree.build(md)
  guard !(sub.roots.is_empty() && sub.body.is_empty()) else { return None }
  let host = match at {
    In(node~, ..) => node
    _ => {
      guard parent(doc, at.id()) is Some(p) else { return None }
      p
    }
  }
  // 断片の側は境界の水平線に戻す。側は根のものなので席へ差せば消えるが、
  // 字として運べば書き戻したときに md が境界と読む（置き場は書く側と同じ表 `@tree.bordered`）
  let sub = @tree.bordered(sub)
  let cut = pieces(md, spots, sub.body)
  // 行のノードは文書に無い番号から、断片の id はその先へ寄せる
  let first = fresh(doc)
  let by = first + count_lines(cut) - (@tree.doc_id + 1)
  // 一番外は順に読む。中身は直前に生えたノードのもの（文書の読みと同じ —
  // 骨格の行の後ろの中身はその行のもの）で、手前にノードが無ければ貼り先の中身
  let (heads, prose) = grow(cut, first, by)
  let nodes = [
    ..heads,
    ..peel(sub.roots.map(r => r.node)).map(n => shift(n, by)),
  ]
  let mut cur = doc
  if !prose.is_empty() {
    guard body(cur, node=host, bs => [..bs, ..prose]) is Some(d) else {
      return None
    }
    cur = d
  }
  if nodes.is_empty() {
    return Some({ doc: cur, focus: Some(prose[0].id), })
  }
  done(implant(cur, at, nodes), Some(nodes[0].id))
}

///|
/// 貼る断片の一番外の 1 切れ。**行のノードになる字**か、**中身のまま行くもの**。
/// 行になりうるのは読み解かなかった中身の原文（段落）だけで、1 行が 1 ノード。
priv enum Piece {
  Lines(Array[@tree.Rung])
  Card(@tree.Block)
}

///|
/// 一番外の中身を、順のまま切る。桁は原文と地番から測る（`@tree.rungs`）。
/// 地番の無い塊（`bordered` が足した水平線は根の中身に入るので、ここには来ない）は
/// 中身として通す
fn pieces(
  md : String,
  spots : Map[Int, @tree.Spot],
  body : Array[@tree.Block],
) -> Array[Piece] {
  body.map(b => {
    // 読み解かなかった字（段落）と、字下げコードだけが行になりうる。
    // どちらかは `rungs` が原文を読み直して決める（囲んだコードは中身のまま）
    let asks = b.content is None || b.content is Some(Code(..))
    let rs = if asks {
      spots.get(b.id).bind(spot => @tree.rungs(md, spot))
    } else {
      None
    }
    match rs {
      Some(rs) => Lines(rs)
      None => Card(b)
    }
  })
}

///|
fn count_lines(cut : Array[Piece]) -> Int {
  cut.fold(init=0, (n, p) => {
    match p {
      Lines(ls) => n + ls.length()
      Card(_) => n
    }
  })
}

///|
/// 開いている段 — まだ子と中身を取れる行。`col` は貼った字の桁
priv struct Rung {
  col : Int
  node : @tree.Node
}

///|
/// 切れの列を木に育てる。**桁が深ければ手前の行の子、同じか浅ければ一番近い
/// 手前の段の隣。** 空行は段を作らず、開いている段も閉じないので、梯子は空行を
/// またいで立ったまま（#118）。
///
/// 中身は**一番深い開いている段**の中身になる。これは「直前に生えたノードのもの」
/// を木にした形で、手前にノードが無ければ貼り先のものとして返す
fn grow(
  cut : Array[Piece],
  first : Int,
  by : Int,
) -> (Array[@tree.Node], Array[@tree.Block]) {
  let out : Array[@tree.Node] = []
  let open : Array[Rung] = []
  let prose : Array[@tree.Block] = []
  let mut grown = 0
  for p in cut {
    match p {
      Lines(rs) =>
        for r in rs {
          while open.last() is Some(top) && top.col >= r.col {
            open.pop() |> ignore
          }
          let node = make(first + grown, r.label)
          grown = grown + 1
          match open.last() {
            Some(top) => top.node.children.push(node)
            None => out.push(node)
          }
          open.push({ col: r.col, node, })
        }
      Card(b) => {
        let blk : @tree.Block = {
          id: b.id + by,
          content: b.content,
          source: b.source,
        }
        match open.last() {
          Some(top) => top.node.body.push(blk)
          None => prose.push(blk)
        }
      }
    }
  }
  (out, prose)
}

///|
/// 根が Implicit 1 つだけなら、その子たちを根にする。飛びが何段でも剥がす。
/// 途中の飛び（子の中の Implicit）は綴りなので触らない。
fn peel(roots : Array[@tree.Node]) -> Array[@tree.Node] {
  match roots {
    [g] if g.mark is None => peel(g.children)
    _ => roots
  }
}

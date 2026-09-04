// 反映 — 前後の木を比べ、変わった所だけを原文 md に映す。
//
// 受け取るのは原文・前の Doc とその地番・後の Doc の 4 つで、返すのは編集列だけ。
// 後の Doc が誰にどう作られたか（操作・undo のスナップショット）は知らない。
//
// 前後の木を id で突き合わせ、変わったノード（dirty）の地番を断片で置き換える。
// 子の増減は容器を書かず、消えた子の範囲を消し、増えた子を隣に差す。
// 出来た文章を読み直して後の木と形が一致しなければ全文を正規形に落とす —
// **正しさはこの検証が持つ**ので、比較がどれだけ雑でも壊れない。
// 決めは docs/core.md「反映」。

///|
/// 編集 1 つ。from..to を insert に置き換える（CodeMirror の changes と同じ形）。
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug, ToJson)

///|
/// 後の木を映す編集列。from 順で、範囲は重ならない
/// （同じ位置の差し込みと置き換えは、差し込みが先）。
pub fn reflect(
  md : String,
  before : Doc,
  spans : Map[Int, @markdown.Span],
  after : Doc,
) -> Array[Edit] {
  match plan(md, before, spans, after) {
    Some(edits) if shape(parse(apply(md, edits))) == shape(after) => edits
    _ => [{ from: 0, to: md.length(), insert: serialize(after) }]
  }
}

///|
/// 編集列を md に当てる。後ろから当てれば座標がずれない。
pub fn apply(md : String, edits : Array[Edit]) -> String {
  let mut out = md
  for i = edits.length() - 1; i >= 0; i = i - 1 {
    let e = edits[i]
    out = slice(out, 0, e.from) + e.insert + slice(out, e.to, out.length())
  }
  out
}

///|
/// 比較の途中。
priv struct Reflect {
  md : String
  spans : Map[Int, @markdown.Span]
  eol : Eol
  /// 前の木のノードを id で引く
  old : Map[Int, Node]
  out : Array[Edit]
}

///|
/// 触った所だけの編集列。断片で書けない変化（frontmatter・改行・根の並べ替え）
/// は None — 全文へ落ちる。
fn plan(
  md : String,
  before : Doc,
  spans : Map[Int, @markdown.Span],
  after : Doc,
) -> Array[Edit]? {
  guard before.frontmatter == after.frontmatter && before.eol == after.eol else {
    return None
  }
  let r : Reflect = { md, spans, eol: before.eol, old: Map([]), out: [] }
  for root in before.roots {
    index(r.old, root.node)
  }
  if before.body != after.body {
    r.out.push(edit(r, doc_id, prose(after.body, r.eol)))
  }
  // 側は根のもの。変われば根が丸ごと（子の増減で長さが変わるだけ — 全部 Right — は同じ）
  let olds = Map::from_array(before.roots.map(x => (id_of(x.node), x.sides)))
  let sides = Map::from_array(after.roots.map(x => (id_of(x.node), x.sides)))
  for x in after.roots {
    match olds.get(id_of(x.node)) {
      Some(was) if !(was == x.sides || (plain(was) && plain(x.sides))) =>
        r.old.remove(id_of(x.node))
      _ => ()
    }
  }
  let olds_n = before.roots.map(x => x.node)
  let news_n = after.roots.map(x => x.node)
  guard aligned(olds_n, news_n) else { return None }
  kids(r, spans.get(doc_id).unwrap().to, 0, olds_n, news_n, 1, sides)
  r.out.sort_by((a, b) => {
    if a.from != b.from {
      a.from - b.from
    } else {
      a.to - b.to
    }
  })
  Some(r.out)
}

///|
fn plain(sides : Array[Side]) -> Bool {
  sides.iter().all(s => s is Right)
}

///|
/// 前の木の同じ id と比べる。種類・畳み・子の並びが変わっていれば部分木ごと書く。
/// そうでなければ、自分（行と中身）が違うときだけ自分の範囲を書き、子は子列の差分に任せる。
fn walk(r : Reflect, x : Node, depth : Int, sides : Array[Side]) -> Unit {
  match r.old.get(id_of(x)) {
    // 畳みは `<details>` が部分木を包むので、自分か子列が変わればそこから丸ごと
    Some(old) if kind(old) == kind(x) &&
      aligned(children_of(old), children_of(x)) &&
      (
        !(folded(old) || folded(x)) ||
        (same(old, x) && ids(children_of(old)) == ids(children_of(x)))
      ) => {
      let s = r.spans.get(id_of(x)).unwrap()
      let mine = children_of(x)
      if !same(old, x) {
        // 自分の行と中身だけ。最初の子の行頭まで（項目の子の字下げは残す）
        let head = match mine.get(0) {
          Some(k) if r.old.contains(id_of(k)) => {
            let ks = r.spans.get(id_of(k)).unwrap()
            ks.from - column(r.md, ks.from)
          }
          _ => s.to
        }
        let alone = with_children(x, [])
        r.out.push({
          from: s.from,
          to: head,
          insert: indent(
            fragment(alone, depth, [], r.eol),
            column(r.md, s.from),
          ),
        })
      }
      // 項目の子は容器の中身の桁（マーカーの 2 つ右）に居る
      let col = match x {
        ListNode(_) => column(r.md, s.from) + 2
        _ => 0
      }
      kids(r, s.to, col, children_of(old), mine, depth + 1, Map([]))
    }
    _ => replace(r, x, depth, sides)
  }
}

///|
/// 残る子の順が前後で同じか。違えば並べ替えで、容器ごと書く。
fn aligned(olds : Array[Node], news : Array[Node]) -> Bool {
  let was = Map::from_array(olds.map(x => (id_of(x), x)))
  let now = Map::from_array(news.map(x => (id_of(x), x)))
  ids(olds.filter(x => now.contains(id_of(x)))) ==
  ids(news.filter(x => was.contains(id_of(x))))
}

///|
/// 子列の差分。残った子は組にして降り、消えた子は範囲ごと消し、増えた子は
/// 次に残る子の手前か、最後に残る子の後ろか、容器の尻（`end`・桁 `col`）に差す。
/// 残った子の順は同じ（`aligned`）が前提。
fn kids(
  r : Reflect,
  end : Int,
  col : Int,
  olds : Array[Node],
  news : Array[Node],
  depth : Int,
  sides : Map[Int, Array[Side]],
) -> Unit {
  let was = Map::from_array(olds.map(x => (id_of(x), x)))
  let now = Map::from_array(news.map(x => (id_of(x), x)))
  let stay = news.filter(x => was.contains(id_of(x)))
  for x in olds {
    if !now.contains(id_of(x)) {
      let s = r.spans.get(id_of(x)).unwrap()
      // 容器の字下げも道連れ。残すと次の行に 2 重に掛かる
      r.out.push({ from: s.from - column(r.md, s.from), to: s.to, insert: "" })
    }
  }
  // 増えた子は、次に残る子までまとめて 1 つの差し込みにする
  let pend = StringBuilder::new()
  for x in news {
    let id = id_of(x)
    if was.contains(id) {
      let s = r.spans.get(id).unwrap()
      if !pend.is_empty() {
        // 残る子のマーカーの手前。差した後ろにその子の字下げを戻す
        let c = column(r.md, s.from)
        r.out.push(insert(r, s.from, indent(pend.to_string(), c) + pad(c)))
        pend.reset()
      }
      walk(r, x, depth, sides.get(id).unwrap_or([]))
    } else {
      pend.write_string(fragment(x, depth, sides.get(id).unwrap_or([]), r.eol))
    }
  }
  if !pend.is_empty() {
    // 最後に残った子の後ろ。残らなければ消えた子の桁で容器の尻へ
    let (pos, c) = match stay.last() {
      Some(x) => {
        let s = r.spans.get(id_of(x)).unwrap()
        (s.to, column(r.md, s.from))
      }
      None =>
        match olds.get(0) {
          Some(o) => (end, column(r.md, r.spans.get(id_of(o)).unwrap().from))
          None => (end, col)
        }
    }
    r.out.push(insert(r, pos, pad(c) + indent(pend.to_string(), c)))
  }
}

///|
fn pad(n : Int) -> String {
  String::make(n, ' ')
}

///|
/// 位置 pos に text を差す編集。行の途中（改行の無い末尾）なら改行してから。
/// 行頭の字下げの後ろは行頭と同じ（項目のマーカーの手前がそこ）。
fn insert(r : Reflect, pos : Int, text : String) -> Edit {
  let text = if skip_blank(r.md, pos - column(r.md, pos), pos) < pos {
    "\n" + text
  } else {
    text
  }
  { from: pos, to: pos, insert: text }
}

///|
/// 部分木ごと断片にして、地番に差す。
fn replace(r : Reflect, x : Node, depth : Int, sides : Array[Side]) -> Unit {
  r.out.push(edit(r, id_of(x), fragment(x, depth, sides, r.eol)))
}

///|
/// 地番 id の範囲を text で置き換える編集。項目の入れ子は列 0 で出るので、
/// 容器の桁に揃える（1 行目はもう容器が字下げしている）。
fn edit(r : Reflect, id : Int, text : String) -> Edit {
  // 前の木に無い id はここへ来ない — 親の子 id 列が違うので親が書かれる
  let s = r.spans.get(id).unwrap()
  { from: s.from, to: s.to, insert: indent(text, column(r.md, s.from)) }
}

///|
/// 2 行目以降を n 桁字下げする。空行はそのまま。
fn indent(text : String, n : Int) -> String {
  if n == 0 {
    return text
  }
  let pad = pad(n)
  let out = StringBuilder::new()
  let mut head = false
  for c in text {
    if head && c != '\n' && c != '\r' {
      out.write_string(pad)
    }
    out.write_char(c)
    head = c == '\n'
  }
  out.to_string()
}

///|
/// ノード自身が同じか — ラベル・中身・畳み。子は見ない。
fn same(a : Node, b : Node) -> Bool {
  match (a, b) {
    (HeadingNode(p), HeadingNode(q)) =>
      p.label == q.label && p.fold == q.fold && p.body == q.body
    (ListNode(p), ListNode(q)) =>
      p.label == q.label && p.fold == q.fold && p.body == q.body
    (ImplicitNode(_), ImplicitNode(_)) => true
    _ => false
  }
}

///|
fn index(into : Map[Int, Node], x : Node) -> Unit {
  into[id_of(x)] = x
  for k in children_of(x) {
    index(into, k)
  }
}

///|
fn id_of(x : Node) -> Int {
  match x {
    HeadingNode(h) => h.id
    ListNode(l) => l.id
    ImplicitNode(g) => g.id
  }
}

///|
/// 種類。構築子の名前そのもの
fn kind(x : Node) -> Int {
  match x {
    HeadingNode(_) => 0
    ListNode(_) => 1
    ImplicitNode(_) => 2
  }
}

///|
fn with_children(x : Node, kids : Array[Node]) -> Node {
  match x {
    HeadingNode(h) => HeadingNode({ ..h, children: kids })
    ImplicitNode(g) => ImplicitNode({ ..g, children: kids })
    ListNode(l) =>
      ListNode({
        ..l,
        children: kids.map(k => {
          match k {
            ListNode(c) => c
            _ => abort("項目の子は項目")
          }
        }),
      })
  }
}

///|
fn folded(x : Node) -> Bool {
  match x {
    HeadingNode(h) => h.fold is Some(_)
    ListNode(l) => l.fold is Some(_)
    ImplicitNode(_) => false
  }
}

///|
fn children_of(x : Node) -> Array[Node] {
  match x {
    HeadingNode(h) => h.children
    ListNode(l) => l.children.map(c => ListNode(c))
    ImplicitNode(g) => g.children
  }
}

///|
fn ids(xs : Array[Node]) -> Array[Int] {
  xs.map(id_of)
}

///|
/// 木の形。id と改行を消したもの — 読みは id を振り直し、後の木の新しい
/// ノードは別の id を持つ。改行は原文から推し量るもので、空になった文書には
/// 流儀が無い。
pub fn shape(doc : Doc) -> Doc {
  {
    ..doc,
    eol: Lf,
    body: faceless(doc.body),
    roots: doc.roots.map(r => { node: faceless_node(r.node), sides: r.sides }),
  }
}

///|
fn faceless_node(x : Node) -> Node {
  match x {
    HeadingNode(h) =>
      HeadingNode({
        ..h,
        id: 0,
        body: faceless(h.body),
        children: h.children.map(faceless_node),
      })
    ListNode(l) => ListNode(faceless_list(l))
    ImplicitNode(g) =>
      ImplicitNode({ id: 0, children: g.children.map(faceless_node) })
  }
}

///|
fn faceless_list(l : ListNode) -> ListNode {
  {
    ..l,
    id: 0,
    body: faceless(l.body),
    children: l.children.map(faceless_list),
  }
}

///|
fn faceless(body : Array[Block]) -> Array[Block] {
  body.map(b => {
    match b {
      Details(text~, ..) => Details(id=0, text~)
      other => other
    }
  })
}

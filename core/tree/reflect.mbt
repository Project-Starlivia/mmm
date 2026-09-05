// 反映 — 前後の木を比べ、変わった所だけを原文 md に映す。
//
// 受け取るのは原文・前の Doc とその地番・後の Doc の 4 つで、返すのは編集列だけ。
// 後の Doc が誰にどう作られたか（操作・undo のスナップショット）は知らない。
//
// 前後の木を id で突き合わせ、ノード 1 つを行（ラベル）・中身・子の 3 つの列に
// 分けて、それぞれ変わった所だけを書く。列の差分は子も中身も同じ 1 つ（`diff`）で、
// 消えた並びは隙間ごと消し、増えた並びは容器が兄弟の間に使っている隙間を挟んで差す。
// 行が同じなら行には触らない — そこに選択の目印が在る（follow.mbt）。
// 出来た文章を読み直して後の木と形が一致しなければ全文を正規形に落とす —
// **正しさはこの検証が持つ**ので、比較がどれだけ雑でも壊れない。
// 決めは docs/core.md「反映」。

///|
/// 編集 1 つ。from..to を insert に置き換える（CodeMirror の changes と同じ形）。
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 後の木を映す編集列。from 順で、範囲は重ならない
/// （同じ位置の差し込みと置き換えは、差し込みが先）。
pub fn reflect(
  md : String,
  before : Doc,
  spans : Map[Int, Spot],
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
  spans : Map[Int, Spot]
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
  spans : Map[Int, Spot],
  after : Doc,
) -> Array[Edit]? {
  guard before.frontmatter == after.frontmatter && before.eol == after.eol else {
    return None
  }
  let r : Reflect = { md, spans, eol: before.eol, old: Map([]), out: [] }
  for root in before.roots {
    index(r.old, root.node)
  }
  // 文書の散文。容器の自分の尻は散文の頭（frontmatter の尻）
  body(r, before.body, after.body, spans.get(doc_id).unwrap().from, 0)
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
  guard aligned(ids(olds_n), ids(news_n)) else { return None }
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
/// そうでなければ、行（ラベル）・中身・子の 3 つの列をそれぞれ差分にする —
/// 行が同じなら行には触らない（そこに選択の目印が在る）。
fn walk(r : Reflect, x : Node, depth : Int, sides : Array[Side]) -> Unit {
  match r.old.get(id_of(x)) {
    // 畳みは `<details>` が部分木を包むので、自分か子列が変わればそこから丸ごと
    Some(old) if kind(old) == kind(x) &&
      aligned(ids(children_of(old)), ids(children_of(x))) &&
      (
        !(folded(old) || folded(x)) ||
        (same(old, x) && ids(children_of(old)) == ids(children_of(x)))
      ) => {
      let s = r.spans.get(id_of(x)).unwrap()
      // 項目の中身と子は容器の中身の桁（マーカーの 2 つ右）に居る
      let col = if x is ListNode(_) { column(r.md, s.from) + 2 } else { 0 }
      // Implicit は行も中身も持たない（範囲は子の和）
      match x {
        ImplicitNode(_) => ()
        _ => {
          let line_to = line_end(r.md, s.from)
          if !same_line(old, x) {
            r.out.push({
              from: s.from,
              to: line_to,
              insert: indent(
                fragment(with_children(with_body(x, []), []), depth, [], r.eol),
                column(r.md, s.from),
              ),
            })
          }
          body(r, body_of(old), body_of(x), line_to, col)
        }
      }
      kids(
        r,
        own_end(r, old),
        col,
        children_of(old),
        children_of(x),
        depth + 1,
        Map([]),
      )
    }
    _ => replace(r, x, depth, sides)
  }
}

///|
/// 残る物の順が前後で同じか。違えば並べ替えで、容器（列）ごと書く。
fn aligned(olds : Array[Int], news : Array[Int]) -> Bool {
  let now = Map::from_array(news.map(id => (id, ())))
  let was = Map::from_array(olds.map(id => (id, ())))
  olds.filter(id => now.contains(id)) == news.filter(id => was.contains(id))
}

///|
/// 列が納まる容器。列が空のとき消す起点であり差す位置（自分の尻）、列の桁、
/// 兄弟の間の隙間、そして前に何も無いか（文書の頭 — 隙間は後ろにしか付けられない）。
priv struct Container {
  own : Int
  col : Int
  sep : String
  head : Bool
}

///|
fn container(own : Int, col : Int, sep : String) -> Container {
  { own, col, sep, head: own == 0 }
}

///|
/// 列の差分。子の列と中身の列で共用する。
/// 残った物は `keep` に任せ、消えた並びは隙間ごと消し、増えた並びは隙間を挟んで差す。
///
/// 消える並び（連続して消える物は 1 つの並び）は、次に残る物が居ればその頭まで、
/// 居なければ前に残る物の尻から、前も居なければ容器の自分の尻から消す —
/// 隙間は必ずどちらかに道連れになり、残った物の間の隙間だけが残る。
/// 増える並びは、次に残る物の手前なら `断片 ⋯ + sep`、そうでなければ `sep + 断片 ⋯`。
fn diff(
  r : Reflect,
  c : Container,
  olds : Array[Int],
  news : Array[Int],
  keep : (Int) -> Unit,
  make : (Int) -> String,
) -> Unit {
  let now = Map::from_array(news.map(id => (id, ())))
  let was = Map::from_array(olds.map(id => (id, ())))
  let at = (id : Int) => r.spans.get(id).unwrap()
  let mut i = 0
  let mut prev : Int? = None
  while i < olds.length() {
    if now.contains(olds[i]) {
      prev = Some(at(olds[i]).to)
      i = i + 1
      continue
    }
    let start = i
    while i < olds.length() && !now.contains(olds[i]) {
      i = i + 1
    }
    let last = at(olds[i - 1]).to
    let (from, to) = if i < olds.length() {
      (
        line_start(r.md, at(olds[start]).from),
        line_start(r.md, at(olds[i]).from),
      )
    } else {
      match prev {
        Some(p) => (p, last)
        // 文書の頭から消すなら、後ろの隙間も道連れ（頭に空行を残さない）
        None => (c.own, if c.head { skip_newlines(r.md, last) } else { last })
      }
    }
    r.out.push({ from, to, insert: "" })
  }
  let pend : Array[String] = []
  let mut kept : Int? = None
  for id in news {
    if was.contains(id) {
      if !pend.is_empty() {
        // 残る物のマーカーの手前。差した後ろにその物の字下げを戻す
        let s = at(id)
        let col = column(r.md, s.from)
        r.out.push(
          insert(r, s.from, indent(pend.join(c.sep), col) + c.sep + pad(col)),
        )
        pend.clear()
      }
      keep(id)
      kept = Some(id)
    } else {
      pend.push(make(id))
    }
  }
  if !pend.is_empty() {
    match kept {
      Some(id) => r.out.push(insert(r, at(id).to, behind(c, pend)))
      None => {
        // 空になった列（元の尻は最後に消えた物の尻）か、元から空の列
        let tail = match olds.last() {
          Some(id) => at(id).to
          None => c.own
        }
        r.out.push(insert(r, c.own, first(r, c, pend, tail)))
      }
    }
  }
}

///|
/// 残る物の後ろに置く並び。隙間を挟んで、容器の桁に揃える
fn behind(c : Container, parts : Array[String]) -> String {
  c.sep + pad(c.col) + indent(parts.join(c.sep), c.col)
}

///|
/// 空の容器に置く並び。文書の頭には前が無いので、隙間は後ろ — それも続きが有るときだけ
/// （`tail` は列の尻。その先に字が無ければ文書の尻）。
fn first(
  r : Reflect,
  c : Container,
  parts : Array[String],
  tail : Int,
) -> String {
  if !c.head {
    return behind(c, parts)
  }
  let follows = skip_newlines(r.md, tail) < r.md.length()
  indent(parts.join(c.sep), c.col) + (if follows { c.sep } else { "" })
}

///|
/// 子列の差分。残った子には降りる。
fn kids(
  r : Reflect,
  own : Int,
  col : Int,
  olds : Array[Node],
  news : Array[Node],
  depth : Int,
  sides : Map[Int, Array[Side]],
) -> Unit {
  let now = Map::from_array(news.map(x => (id_of(x), x)))
  let item = match news.get(0) {
    Some(ListNode(_)) => true
    _ => false
  }
  diff(
    r,
    container(own, col, sep(r, item, ids(olds))),
    ids(olds),
    ids(news),
    id => walk(r, now.get(id).unwrap(), depth, sides.get(id).unwrap_or([])),
    id => {
      fragment(now.get(id).unwrap(), depth, sides.get(id).unwrap_or([]), r.eol)
    },
  )
}

///|
/// 中身の列の差分。内容だけ変わった中身はその範囲を置き換える。
/// 並びが変われば列ごと — 全部消して全部差す（同じ規則で隙間が付く）。
/// 中身の間は常に空行 1 つ — 項目の中でも、段落がラベルの続きに読まれないように
/// （書き手が項目の中身をそう書くのと同じ）。
fn body(
  r : Reflect,
  olds : Array[Block],
  news : Array[Block],
  own : Int,
  col : Int,
) -> Unit {
  if olds == news {
    return
  }
  let was = Map::from_array(olds.map(b => (b.id, b)))
  let now = Map::from_array(news.map(b => (b.id, b)))
  let old_ids = olds.map(b => b.id)
  let new_ids = news.map(b => b.id)
  let c = container(own, col, eol(r))
  let make = (id : Int) => prose([now.get(id).unwrap()], r.eol)
  if !aligned(old_ids, new_ids) {
    diff(r, c, old_ids, [], _ => (), make)
    let tail = match olds.last() {
      Some(b) => r.spans.get(b.id).unwrap().to
      None => own
    }
    r.out.push(insert(r, own, first(r, c, [prose(news, r.eol)], tail)))
    return
  }
  diff(
    r,
    c,
    old_ids,
    new_ids,
    id => {
      let b = now.get(id).unwrap()
      if was.get(id).unwrap().content != b.content {
        let s = r.spans.get(id).unwrap()
        r.out.push({
          from: s.from,
          to: s.to,
          insert: indent(make(id), column(r.md, s.from)),
        })
      }
    },
    make,
  )
}

///|
/// 兄弟の間の隙間。容器に元から 2 つ以上居ればその間を写し、居なければ
/// 項目の列は詰め、見出しと文書の直下は空行 1 つ。
fn sep(r : Reflect, item : Bool, olds : Array[Int]) -> String {
  if olds.length() >= 2 {
    let a = r.spans.get(olds[0]).unwrap()
    let b = r.spans.get(olds[1]).unwrap()
    return if slice(r.md, a.to, line_start(r.md, b.from)).contains("\n") {
      eol(r)
    } else {
      ""
    }
  }
  if item {
    ""
  } else {
    eol(r)
  }
}

///|
fn eol(r : Reflect) -> String {
  match r.eol {
    Lf => "\n"
    Crlf => "\r\n"
  }
}

///|
/// 前の木のノードの、自分の尻 — 最後の中身の尻、中身が無ければ行の尻。
/// Implicit は行を持たないので最初の子の頭（範囲の頭）。地番を引くので前の木のものに限る。
fn own_end(r : Reflect, old : Node) -> Int {
  let s = r.spans.get(id_of(old)).unwrap()
  match old {
    ImplicitNode(_) => s.from
    _ =>
      match body_of(old).last() {
        Some(b) => r.spans.get(b.id).unwrap().to
        None => line_end(r.md, s.from)
      }
  }
}

///|
/// 改行だけを読み飛ばした位置。
fn skip_newlines(md : String, at : Int) -> Int {
  let mut i = at
  while i < md.length() && (md[i] == '\n' || md[i] == '\r') {
    i = i + 1
  }
  i
}

///|
fn pad(n : Int) -> String {
  String::make(n, ' ')
}

///|
/// 位置 pos に text を差す編集。行の途中（改行の無い末尾）なら改行してから。
/// 行頭の字下げの後ろは行頭と同じ（項目のマーカーの手前がそこ）。
fn insert(r : Reflect, pos : Int, text : String) -> Edit {
  let text = if skip_blank(r.md, line_start(r.md, pos), pos) < pos {
    eol(r) + text
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
/// 行が同じか — ラベルと畳み。中身と子は見ない。
fn same_line(a : Node, b : Node) -> Bool {
  match (a, b) {
    (HeadingNode(p), HeadingNode(q)) => p.label == q.label && p.fold == q.fold
    (ListNode(p), ListNode(q)) => p.label == q.label && p.fold == q.fold
    (ImplicitNode(_), ImplicitNode(_)) => true
    _ => false
  }
}

///|
fn body_of(x : Node) -> Array[Block] {
  match x {
    HeadingNode(h) => h.body
    ListNode(l) => l.body
    ImplicitNode(_) => []
  }
}

///|
fn with_body(x : Node, body : Array[Block]) -> Node {
  match x {
    HeadingNode(h) => HeadingNode({ ..h, body, })
    ListNode(l) => ListNode({ ..l, body, })
    ImplicitNode(_) => x
  }
}

///|
/// ノード自身が同じか — 行（ラベル・畳み）と中身。子は見ない。
fn same(a : Node, b : Node) -> Bool {
  same_line(a, b) && body_of(a) == body_of(b)
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
  body.map(b => { id: 0, content: b.content })
}

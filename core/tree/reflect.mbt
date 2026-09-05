// 反映 — 前後の木を比べ、変わった所だけを原文 md に映す。
//
// 受け取るのは原文・前の Doc とその地番・後の Doc の 4 つで、返すのは編集列だけ。
// 後の Doc が誰にどう作られたか（操作・undo のスナップショット）は知らない。
//
// 形は**正規形を base にした 3-way merge**（recast と同じ）:
//
//   ours   = 原文（ユーザーの流儀）   要素ごとに [手前の隙間, 本体] の範囲（地番）
//   base   = 前の木の正規形            要素ごとに、手前に空行が有るか
//   theirs = 後の木の正規形            同上
//
// base → theirs の差（操作の差）だけを ours に写す。base と ours の差（流儀の差）は
// 写さないので、触っていない所の書き方は残る。要素はノードの行（ラベル）と中身 1 枚で、
// 位置合わせは id。**要素は手前の隙間（空行）を持つ** — 消えるときは隙間ごと消え、
// 増えるときは theirs の隙間を連れてきて、残る要素の隙間は theirs で変わったときだけ
// 書き換える。隙間そのものは原文の字で測る（空白だけの行 = 空行。読みと同じ）。
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
/// 後の木を映す編集列。from 順で、範囲は重ならない。
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
  /// ours — 要素の手前の隙間の頭（空行が無ければ行頭）。前の木の id で引く
  gap : Map[Int, Int]
  /// base — 正規形（前）で手前に空行が有るか。前の木の id で引く
  base : Map[Int, Bool]
  /// theirs — 正規形（後）で手前に空行が有るか。後の木の id で引く
  theirs : Map[Int, Bool]
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
  // 木だけで分かる落ちは先に（正規形を書いて読み直す前に）
  let olds_n = before.roots.map(x => x.node)
  let news_n = after.roots.map(x => x.node)
  guard aligned(ids(olds_n), ids(news_n)) else { return None }
  guard gaps_of(before) is Some(base) && gaps_of(after) is Some(theirs) else {
    return None
  }
  let r : Reflect = {
    md,
    spans,
    eol: before.eol,
    old: Map([]),
    gap: gaps_in(md, spans),
    base,
    theirs,
    out: [],
  }
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
  kids(r, spans.get(doc_id).unwrap().to, 0, olds_n, news_n, 1, sides)
  Some(settle(r))
}

///|
fn plain(sides : Array[Side]) -> Bool {
  sides.iter().all(s => s is Right)
}

///|
/// 要素（Implicit でないノードと中身）の id を文書順に。
fn elements(doc : Doc) -> Array[Int] {
  let out : Array[Int] = []
  fn node(x : Node) {
    match x {
      ImplicitNode(_) => ()
      _ => out.push(id_of(x))
    }
    for b in body_of(x) {
      out.push(b.id)
    }
    for k in children_of(x) {
      node(k)
    }
  }

  for b in doc.body {
    out.push(b.id)
  }
  for r in doc.roots {
    node(r.node)
  }
  out
}

///|
/// 部分木の最初の要素。Implicit を下って最初の行を持つノード
fn head_element(x : Node) -> Int? {
  match x {
    ImplicitNode(g) =>
      match g.children.get(0) {
        Some(k) => head_element(k)
        None => None
      }
    _ => Some(id_of(x))
  }
}

///|
/// ours の隙間 — 地番を持つものごとに、手前に続く空行の頭。Implicit の範囲の頭は
/// 最初の子の頭なので、Implicit の隙間はその子の隙間。
fn gaps_in(md : String, spans : Map[Int, Spot]) -> Map[Int, Int] {
  let out : Map[Int, Int] = Map([])
  for id, s in spans {
    out[id] = blank_start(md, line_start(md, s.from))
  }
  out
}

///|
/// 正規形の隙間 — 木を正規形に書いて読み直し、要素ごとに手前に空行が有るかを見る。
/// 要素は文書順に 1 対 1 で並ぶので、順に組にする。並ばなければ None（全文へ落ちる）。
fn gaps_of(doc : Doc) -> Map[Int, Bool]? {
  let canon = serialize(doc)
  let (read, spans) = survey(canon)
  let mine = elements(doc)
  let theirs = elements(read)
  guard mine.length() == theirs.length() else { return None }
  let out : Map[Int, Bool] = Map([])
  for i, id in mine {
    let s = spans.get(theirs[i]).unwrap()
    let head = line_start(canon, s.from)
    out[id] = blank_start(canon, head) < head
  }
  // Implicit は行を持たないので、その隙間は最初の要素の隙間
  fn implicit(x : Node) {
    match x {
      ImplicitNode(g) => {
        match head_element(x) {
          Some(first) => out[g.id] = out.get(first).unwrap_or(true)
          None => ()
        }
        for k in g.children {
          implicit(k)
        }
      }
      _ =>
        for k in children_of(x) {
          implicit(k)
        }
    }
  }

  for r in doc.roots {
    implicit(r.node)
  }
  Some(out)
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
/// 列 1 つの差分に要るもの。
priv struct Seq {
  olds : Array[Int]
  news : Array[Int]
  /// 元から空の列に差す位置 — 容器の自分の尻
  own : Int
  /// 列の桁
  col : Int
  /// 増える物の手前に空行を置くか。theirs の答え（項目の列は ours の兄弟の流儀が先）
  gap : (Int) -> Bool
  /// 残る物に降りる
  keep : (Int) -> Unit
  /// 増える物の断片
  make : (Int) -> String
}

///|
/// 列の差分。子の列と中身の列で共用する。
///
/// 列の頭の境目（列の手前の隙間）は要素でなく**列のもの** — 頭の要素が消えても、
/// 頭に要素が増えても、境目の字は原文のまま残る。頭より後ろの隙間は要素のもの。
///
/// - 消える並び（連続して消える物は 1 つ）は、手前の隙間から最後の尻まで消す。
///   列の頭の並びで後ろに残る物が居れば、境目を残してその物の行頭まで消す
///   （theirs がその物を文書の頭と言うなら、境目ごと）
/// - 残る物には降りる。手前の隙間が base と theirs で違えば（文書の頭になった /
///   頭でなくなった、列が詰まった / 空いた）、隙間だけ書き換える。列の頭で消し差しが
///   あった物は境目を引き継いでいるので触らない
/// - 増える並びは、次に残る物の隙間の頭か、前に残る物の尻か、容器の自分の尻に差し、
///   1 つずつ theirs の隙間を連れてくる。列の頭に差すなら境目の後ろに置き、隙間は
///   次に残る物との間に付ける
fn diff(r : Reflect, q : Seq) -> Unit {
  let now = Map::from_array(q.news.map(id => (id, ())))
  let was = Map::from_array(q.olds.map(id => (id, ())))
  let at = (id : Int) => r.spans.get(id).unwrap()
  let gap_text = (id : Int) => if (q.gap)(id) { eol(r) } else { "" }
  // 列の頭に新しい物が来るか（頭の並びを消すとき、境目を残すかに要る）
  let head_born = q.news.get(0) is Some(id) && !was.contains(id)
  // 境目を引き継いだ物（隙間の書き換えを飛ばす）
  let mut inherited : Int? = None
  let mut i = 0
  let mut kept_before = false
  while i < q.olds.length() {
    if now.contains(q.olds[i]) {
      kept_before = true
      i = i + 1
      continue
    }
    let start = i
    while i < q.olds.length() && !now.contains(q.olds[i]) {
      i = i + 1
    }
    let first = q.olds[start]
    let last = at(q.olds[i - 1]).to
    let head = !kept_before
    let edge = if head && i < q.olds.length() {
      let next = q.olds[i]
      inherited = Some(next)
      (
        if r.theirs.get(next).unwrap_or(true) {
          line_start(r.md, at(first).from)
        } else {
          r.gap.get(first).unwrap()
        },
        line_start(r.md, at(next).from),
      )
    } else if head && head_born {
      (line_start(r.md, at(first).from), last)
    } else {
      (r.gap.get(first).unwrap(), last)
    }
    r.out.push({ from: edge.0, to: edge.1, insert: "" })
  }
  let body = (id : Int) => pad(q.col) + indent((q.make)(id), q.col)
  let pend : Array[Int] = []
  let mut kept : Int? = None
  for id in q.news {
    if was.contains(id) {
      if !pend.is_empty() {
        if kept is None {
          // 列の頭。境目の後ろに置き、隙間は次に残る物との間に
          let text = pend
            .mapi((k, x) => (if k == 0 { "" } else { gap_text(x) }) + body(x))
            .join("") +
            gap_text(id)
          let pos = line_start(r.md, at(id).from)
          r.out.push({ from: pos, to: pos, insert: text })
          inherited = Some(id)
        } else {
          let pos = r.gap.get(id).unwrap()
          r.out.push({
            from: pos,
            to: pos,
            insert: pend.map(x => gap_text(x) + body(x)).join(""),
          })
        }
        pend.clear()
      }
      if inherited != Some(id) {
        let had = r.base.get(id).unwrap_or(false)
        let has = r.theirs.get(id).unwrap_or(had)
        if had != has {
          r.out.push({
            from: r.gap.get(id).unwrap(),
            to: line_start(r.md, at(id).from),
            insert: if has {
              eol(r)
            } else {
              ""
            },
          })
        }
      }
      (q.keep)(id)
      kept = Some(id)
    } else {
      pend.push(id)
    }
  }
  if !pend.is_empty() {
    match (kept, q.olds.get(0)) {
      (Some(k), _) => {
        let pos = at(k).to
        r.out.push({
          from: pos,
          to: pos,
          insert: pend.map(x => gap_text(x) + body(x)).join(""),
        })
      }
      // 列ごと消えて生まれ直す。境目は残してあるので頭の隙間は要らない
      (None, Some(first)) => {
        let pos = line_start(r.md, at(first).from)
        r.out.push({
          from: pos,
          to: pos,
          insert: pend
          .mapi((k, x) => (if k == 0 { "" } else { gap_text(x) }) + body(x))
          .join(""),
        })
      }
      // 元から空の列。境目は無いので theirs の隙間から
      (None, None) =>
        r.out.push({
          from: q.own,
          to: q.own,
          insert: pend.map(x => gap_text(x) + body(x)).join(""),
        })
    }
  }
}

///|
/// 子列の差分。残った子には降りる。項目の列は ours の兄弟の流儀（詰まっているか）を
/// 増える物にも写す — 正規形は流儀を知らないので、ここだけは ours が先。
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
  let item = news.get(0) is Some(ListNode(_))
  let old_ids = ids(olds)
  let style : Bool? = if item && old_ids.length() >= 2 {
    // 2 つ目からの兄弟の隙間が、この列の流儀（先頭の隙間は列の手前のもの）
    Some(
      old_ids[1:]
      .iter()
      .any(id => {
        r.gap.get(id).unwrap() < line_start(r.md, r.spans.get(id).unwrap().from)
      }),
    )
  } else {
    None
  }
  diff(r, {
    olds: old_ids,
    news: ids(news),
    own,
    col,
    gap: id => {
      match style {
        Some(loose) => loose
        None => r.theirs.get(id).unwrap_or(true)
      }
    },
    keep: id => {
      walk(r, now.get(id).unwrap(), depth, sides.get(id).unwrap_or([]))
    },
    make: id => {
      fragment(now.get(id).unwrap(), depth, sides.get(id).unwrap_or([]), r.eol)
    },
  })
}

///|
/// 中身の列の差分。内容だけ変わった中身はその範囲を置き換える。
/// 並びが変われば列ごと — 全部消して全部差す（同じ規則で隙間が付く）。
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
  let make = (id : Int) => prose([now.get(id).unwrap()], r.eol)
  let gap = (id : Int) => r.theirs.get(id).unwrap_or(true)
  if !aligned(old_ids, new_ids) {
    diff(r, { olds: old_ids, news: [], own, col, gap, keep: _ => (), make })
    diff(r, {
      olds: [],
      news: new_ids,
      own: r.gap.get(old_ids[0]).unwrap(),
      col,
      gap,
      keep: _ => (),
      make,
    })
    return
  }
  diff(r, {
    olds: old_ids,
    news: new_ids,
    own,
    col,
    gap,
    keep: id => {
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
  })
}

///|
fn eol(r : Reflect) -> String {
  match r.eol {
    Lf => "\n"
    Crlf => "\r\n"
  }
}

///|
/// 前の木のノードの、自分の尻。元から子の無い容器に差すときだけ使い、そのとき
/// 地番の尻は自分の尻そのもの（setext の 2 行目も含む）。
fn own_end(r : Reflect, old : Node) -> Int {
  r.spans.get(id_of(old)).unwrap().to
}

///|
/// 行頭 `at` の手前に続く空行の頭。空行が無ければその位置のまま。
/// 空行は「改行までが空白だけの行」— 読みが空行と見るのと同じ。改行は `\n`（CRLF の
/// `\r` は行の中身ではない）。
fn blank_start(md : String, at : Int) -> Int {
  let mut p = at
  while p > 0 && md[p - 1] == '\n' {
    let nl = if p >= 2 && md[p - 2] == '\r' { p - 2 } else { p - 1 }
    let head = line_start(md, nl)
    guard skip_blank(md, head, nl) == nl else { break }
    p = head
  }
  p
}

///|
fn pad(n : Int) -> String {
  String::make(n, ' ')
}

///|
/// 編集列を整える。from 順（同じ from なら幅の狭い順 — 差し込みが置き換えより先、
/// 同じなら出た順）に並べ、隣り合う編集は 1 つに繋ぎ、行の途中（改行の無い末尾）に
/// 字を書く編集は改行から始める。繋いでから見るので、消した後に何が残るかで決まる。
fn settle(r : Reflect) -> Array[Edit] {
  let order = Array::makei(r.out.length(), i => i)
  order.sort_by((a, b) => {
    let (x, y) = (r.out[a], r.out[b])
    if x.from != y.from {
      x.from - y.from
    } else if x.to != y.to {
      x.to - y.to
    } else {
      a - b
    }
  })
  let out : Array[Edit] = []
  for i in order {
    let e = r.out[i]
    match out.last() {
      Some(p) if p.to == e.from =>
        out[out.length() - 1] = { ..p, to: e.to, insert: p.insert + e.insert }
      _ => out.push(e)
    }
  }
  out.map(e => {
    if e.insert != "" && mid_line(r.md, e.from) {
      { ..e, insert: eol(r) + e.insert }
    } else {
      e
    }
  })
}

///|
/// その位置が行の途中か（行頭の字下げの後ろは行頭と同じ — 項目のマーカーの手前がそこ）。
fn mid_line(md : String, at : Int) -> Bool {
  skip_blank(md, line_start(md, at), at) < at
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

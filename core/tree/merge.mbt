// 合流 — 前後の木を比べ、変わった所だけを原文 md に映す。
//
// 受け取るのは原文・前の Doc とその地番・後の Doc の 4 つで、返すのは編集列と
// その検証の答え。後の Doc が誰にどう作られたか（操作・undo のスナップショット）は知らない。
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
// **正しさはこの検証が持つ**ので、比較がどれだけ雑でも壊れない。答えは返り値に
// 載せる（`same`）— 呼ぶ側も同じことを知りたいので、二度読み直さない。
// 決めは docs/core.md「合流」。

///|
/// 編集 1 つ。from..to を insert に置き換える（CodeMirror の changes と同じ形）。
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 編集列（前の座標・from 順・重ならない）を md に当てた後の全文。
/// 続けて操作を映すとき、次の操作が読む md はこれ
pub fn patched(md : String, edits : Array[Edit]) -> String {
  let out = StringBuilder()
  let mut at = 0
  for e in edits {
    out.write_string(String::unsafe_substring(md, start=at, end=e.from))
    out.write_string(e.insert)
    at = e.to
  }
  out.write_string(String::unsafe_substring(md, start=at, end=md.length()))
  out.to_string()
}

///|
/// 合流の結果。
pub(all) struct Merged {
  /// 後の木を映す編集列。from 順で、範囲は重ならない
  edits : Array[Edit]
  /// 当てて読み直した形が後の木と同じか。書けない木のときだけ偽で、
  /// そのとき文書順の番号（focus）は別のものを指す
  same : Bool
} derive(Eq, Debug, ToJson)

///|
/// 後の木を映す編集列と、その検証。断片で書けなければ全文を正規形に落とす。
pub fn merge(
  md : String,
  before : Doc,
  spans : Map[Int, Spot],
  after : Doc,
) -> Merged {
  let planned = if before == after {
    Some([])
  } else {
    plan(md, before, spans, after)
  }
  match planned {
    Some(edits) if verified(md, edits, after) => { edits, same: true, }
    // 全文の正規形は断片と字が違うので、検証もやり直す
    _ => {
      let edits = [{ from: 0, to: md.length(), insert: serialize(after), }]
      { edits, same: verified(md, edits, after), }
    }
  }
}

///|
/// 編集を当てて読み直した形が、後の木と同じか。**合流の正しさはこれが持つ。**
fn verified(md : String, edits : Array[Edit], after : Doc) -> Bool {
  shape(parse(patched(md, edits))) == shape(after)
}

///|
/// 比較の途中。
priv struct Merge {
  md : String
  spans : Map[Int, Spot]
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
/// 触った所だけの編集列。断片で書けない変化（frontmatter・根の並べ替え）
/// は None — 全文へ落ちる。
fn plan(
  md : String,
  before : Doc,
  spans : Map[Int, Spot],
  after : Doc,
) -> Array[Edit]? {
  guard before.frontmatter == after.frontmatter else { return None }
  // 木だけで分かる落ちは先に（正規形を書いて読み直す前に）
  let olds_n = before.roots.map(x => x.node)
  let news_n = after.roots.map(x => x.node)
  guard aligned(ids(olds_n), ids(news_n)) else { return None }
  guard canon_gaps(before) is Some(base) && canon_gaps(after) is Some(theirs) else {
    return None
  }
  let r : Merge = {
    md,
    spans,
    old: Map([]),
    gap: gaps(md, spans),
    base,
    theirs,
    out: [],
  }
  for root in before.roots {
    index(r.old, root.node)
  }
  // 文書の散文。容器の自分の尻は散文の頭（frontmatter の尻）
  merge_body(r, before.body, after.body, spans.get(doc_id).unwrap().from, 0)
  let olds = Map::from_array(before.roots.map(x => (x.node.id, x.sides)))
  let sides = Map::from_array(after.roots.map(x => (x.node.id, x.sides)))
  let rules = Map::from_array(after.roots.map(x => (x.node.id, x.rules)))
  // 側が変われば根が丸ごとなので、突き合わせから外す
  for x in after.roots {
    if olds.get(x.node.id) is Some(was) && !sided(was, x.sides) {
      r.old.remove(x.node.id)
    }
  }
  merge_children(
    r,
    spans.get(doc_id).unwrap().to,
    0,
    olds_n,
    news_n,
    1,
    sides,
    rules,
  )
  Some(settle(r))
}

///|
/// 側が前後で同じか。**側は根のもの**で `---` は隙間に書かれるので、変われば
/// 根ごと書き直す。子の増減で長さが変わるだけ（前後とも全部 Right）は同じと見る。
fn sided(olds : Array[Side], news : Array[Side]) -> Bool {
  olds == news || (plain(olds) && plain(news))
}

///|
/// 側が 1 つも変わらない列（`---` が 1 本も書かれない）。
fn plain(sides : Array[Side]) -> Bool {
  sides.iter().all(s => s is Right)
}

///|
/// 要素（Implicit でないノードと中身）の id を文書順に。
fn elements(doc : Doc) -> Array[Int] {
  let out : Array[Int] = []
  fn node(x : Node) {
    if x.mark is Some(_) {
      out.push(x.id)
    }
    for b in x.body {
      out.push(b.id)
    }
    for k in x.children {
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
/// 部分木の最初の要素。Implicit を下って最初の行を持つノード。子の無い Implicit は
/// 在り得ない（check が言う）ので None は来ないが、来れば theirs の既定に落ちて
/// 検証が全文へ落とす
fn head_element(x : Node) -> Int? {
  if x.mark is Some(_) {
    return Some(x.id)
  }
  match x.children.get(0) {
    Some(k) => head_element(k)
    None => None
  }
}

///|
/// ours の隙間 — 地番を持つものごとに、手前に続く空行の頭。Implicit の範囲の頭は
/// 最初の子の頭なので、Implicit の隙間はその子の隙間。
fn gaps(md : String, spans : Map[Int, Spot]) -> Map[Int, Int] {
  let out : Map[Int, Int] = Map([])
  for id, s in spans {
    out[id] = blank_start(md, line_start(md, s.from))
  }
  out
}

///|
/// 正規形の隙間 — 木を正規形に書いて読み直し、要素ごとに手前に空行が有るかを見る。
/// 要素は文書順に 1 対 1 で並ぶので、順に組にする。並ばなければ None（全文へ落ちる）。
fn canon_gaps(doc : Doc) -> Map[Int, Bool]? {
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
    if x.mark is None {
      match head_element(x) {
        Some(first) => out[x.id] = out.get(first).unwrap_or(true)
        None => ()
      }
    }
    for k in x.children {
      implicit(k)
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
fn merge_node(
  r : Merge,
  x : Node,
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> Unit {
  match r.old.get(x.id) {
    // 畳みは `<details>` が部分木を包むので、自分か子列が変わればそこから丸ごと
    Some(old) if kind(old) == kind(x) &&
      aligned(ids(old.children), ids(x.children)) &&
      (
        !(old.fold is Some(_) || x.fold is Some(_)) ||
        (same(old, x) && ids(old.children) == ids(x.children))
      ) => {
      let s = r.spans.get(x.id).unwrap()
      // 項目の中身と子は容器のラベルの桁（読んだ字下げ幅の右）に居る
      let col = match x.mark {
        Some(Item(offset~, ..)) => column(r.md, s.from) + offset
        _ => 0
      }
      // Implicit は行も中身も持たない（範囲は子の和）
      match x.mark {
        None => ()
        Some(_) => {
          let line_to = line_end(r.md, s.from)
          if !same_line(old, x) {
            r.out.push({
              from: s.from,
              to: line_to,
              insert: indent(
                fragment({ ..x, body: [], children: [], }, depth, [], []),
                column(r.md, s.from),
              ),
            })
          }
          merge_body(r, old.body, x.body, line_to, col)
        }
      }
      merge_children(
        r,
        own_end(r, old),
        col,
        old.children,
        x.children,
        depth + 1,
        Map([]),
        Map([]),
      )
    }
    _ => replace(r, x, depth, sides, rules)
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
fn merge_seq(r : Merge, q : Seq) -> Unit {
  filled(r, q, dropped(r, q))
}

///|
/// 消える並びを消す。連続して消える物は 1 つにまとめ、**手前の隙間から最後の尻まで**。
/// 列の頭の並びで後ろに残る物が居れば、境目を残してその物の行頭まで消す
/// （theirs がその物を文書の頭と言うなら、境目ごと）。
/// 返すのは**境目を引き継いだ物** — その隙間は `filled` が書き換えない。
fn dropped(r : Merge, q : Seq) -> Int? {
  let now = Map::from_array(q.news.map(id => (id, ())))
  // 列の頭に新しい物が来るか（頭の並びを消すとき、境目を残すかに要る）
  // 列ごと消えるとき、生まれ直すなら境目を残す（全部消えたなら news の頭は必ず新しい）
  let head_born = !q.news.is_empty()
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
    let last = spot(r, q.olds[i - 1]).to
    let head = !kept_before
    let (from, to) = if head && i < q.olds.length() {
      let next = q.olds[i]
      inherited = Some(next)
      // 後ろに残る物が後の列の頭で、しかも文書の頭なら境目ごと。そうでなければ境目は残す
      let bare = q.news.get(0) == Some(next) && headless(r, next)
      (
        if bare {
          r.gap.get(first).unwrap()
        } else {
          line_start(r.md, spot(r, first).from)
        },
        line_start(r.md, spot(r, next).from),
      )
    } else if head && head_born {
      (line_start(r.md, spot(r, first).from), last)
    } else {
      (r.gap.get(first).unwrap(), last)
    }
    r.out.push({ from, to, insert: "", })
  }
  inherited
}

///|
/// 残る物と増える物を並べる。残る物には降りて、手前の隙間が base と theirs で
/// 違えば（`gapped`）隙間だけ書き換える。増える並びは**次に残る物の隙間の頭か、
/// 前に残る物の尻か、容器の自分の尻**に差す。列の頭に差すなら境目の後ろに置き、
/// 隙間は次に残る物との間に付ける。
fn filled(r : Merge, q : Seq, inherited : Int?) -> Unit {
  let was = Map::from_array(q.olds.map(id => (id, ())))
  let pend : Array[Int] = []
  let mut inherited = inherited
  let mut kept : Int? = None
  for id in q.news {
    guard was.contains(id) else {
      pend.push(id)
      continue
    }
    if !pend.is_empty() {
      match kept {
        // 列の頭。境目の後ろに置き、隙間は次に残る物との間に。
        // 差す物が文書の頭なら（手前に何も残らない）、境目ごと置き換える
        None => {
          let head = line_start(r.md, spot(r, id).from)
          r.out.push({
            from: if headless(r, pend[0]) {
              r.gap.get(id).unwrap()
            } else {
              head
            },
            to: head,
            insert: grown(q, pend, lead=false) + gap_text(q, id),
          })
          inherited = Some(id)
        }
        Some(_) => {
          let pos = r.gap.get(id).unwrap()
          r.out.push({ from: pos, to: pos, insert: grown(q, pend, lead=true), })
        }
      }
      pend.clear()
    }
    if inherited != Some(id) {
      gapped(r, id)
    }
    (q.keep)(id)
    kept = Some(id)
  }
  guard !pend.is_empty() else { return }
  let (pos, lead) = match (kept, q.olds.get(0)) {
    (Some(k), _) => (spot(r, k).to, true)
    // 列ごと消えて生まれ直す。境目は残してあるので頭の隙間は要らない
    (None, Some(first)) => (line_start(r.md, spot(r, first).from), false)
    // 元から空の列。境目は無いので theirs の隙間から
    (None, None) => (q.own, true)
  }
  r.out.push({ from: pos, to: pos, insert: grown(q, pend, lead~), })
}

///|
/// 残る物の手前の隙間。base と theirs で違えば（文書の頭になった / 頭でなくなった、
/// 列が詰まった / 空いた）、**隙間だけ**書き換える。
fn gapped(r : Merge, id : Int) -> Unit {
  let had = r.base.get(id).unwrap_or(false)
  let has = r.theirs.get(id).unwrap_or(had)
  guard had != has else { return }
  r.out.push({
    from: r.gap.get(id).unwrap(),
    to: line_start(r.md, spot(r, id).from),
    insert: if has {
      "\n"
    } else {
      ""
    },
  })
}

///|
/// 増える並びの字。**1 つずつ theirs の隙間を連れてくる。**
/// `lead` が偽なら先頭の隙間は付けない（列の頭の境目は原文のまま残る）。
fn grown(q : Seq, pend : Array[Int], lead~ : Bool) -> String {
  pend
  .mapi((k, x) => {
    (if k == 0 && !lead { "" } else { gap_text(q, x) }) +
    pad(q.col) +
    indent((q.make)(x), q.col)
  })
  .join("")
}

///|
/// 増える物の手前の隙間の字。
fn gap_text(q : Seq, id : Int) -> String {
  if (q.gap)(id) {
    "\n"
  } else {
    ""
  }
}

///|
/// 文書の頭に来る要素（theirs が「手前に隙間は無い」と言う）。その手前の境目は消す。
fn headless(r : Merge, id : Int) -> Bool {
  !r.theirs.get(id).unwrap_or(true)
}

///|
/// その要素の地番。
fn spot(r : Merge, id : Int) -> Spot {
  r.spans.get(id).unwrap()
}

///|
/// 子列の差分。残った子には降りる。項目の列は ours の兄弟の流儀（詰まっているか）を
/// 増える物にも写す — 正規形は流儀を知らないので、ここだけは ours が先。
fn merge_children(
  r : Merge,
  own : Int,
  col : Int,
  olds : Array[Node],
  news : Array[Node],
  depth : Int,
  sides : Map[Int, Array[Side]],
  rules : Map[Int, Array[String]],
) -> Unit {
  let now = Map::from_array(news.map(x => (x.id, x)))
  let old_ids = ids(olds)
  let style = loosened(r, news, old_ids)
  merge_seq(r, {
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
      merge_node(
        r,
        now.get(id).unwrap(),
        depth,
        sides.get(id).unwrap_or([]),
        rules.get(id).unwrap_or([]),
      )
    },
    make: id => {
      fragment(
        now.get(id).unwrap(),
        depth,
        sides.get(id).unwrap_or([]),
        rules.get(id).unwrap_or([]),
      )
    },
  })
}

///|
/// 読んだ列の流儀 — 項目の間が空いているか。**正規形は流儀を知らない**ので、
/// 項目の列だけは増える物にも ours の兄弟の流儀を写す。2 つ目からの兄弟の隙間で
/// 測る（先頭の隙間は列の手前のもの）。項目でない列と、兄弟が 1 つしかない列は
/// 流儀を持たないので None — そのときは theirs に従う。
fn loosened(r : Merge, news : Array[Node], olds : Array[Int]) -> Bool? {
  guard news.get(0).map(sign_of) is Some(Some(Item)) && olds.length() >= 2 else {
    return None
  }
  Some(
    olds[1:]
    .iter()
    .any(id => r.gap.get(id).unwrap() < line_start(r.md, spot(r, id).from)),
  )
}

///|
/// 中身の列の差分。内容だけ変わった中身はその範囲を置き換える。
/// 並びが変われば列ごと — 全部消して全部差す（同じ規則で隙間が付く）。
fn merge_body(
  r : Merge,
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
  let make = (id : Int) => prose([now.get(id).unwrap()])
  let gap = (id : Int) => r.theirs.get(id).unwrap_or(true)
  if !aligned(old_ids, new_ids) {
    merge_seq(r, {
      olds: old_ids,
      news: [],
      own,
      col,
      gap,
      keep: _ => (),
      make,
    })
    merge_seq(r, {
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
  merge_seq(r, {
    olds: old_ids,
    news: new_ids,
    own,
    col,
    gap,
    keep: id => {
      let b = now.get(id).unwrap()
      let old = was.get(id).unwrap()
      // 書き戻す字は意味と原文の両方で決まるので、両方を見る
      if old.content != b.content || old.source != b.source {
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
/// 前の木のノードの、自分の尻。元から子の無い容器に差すときだけ使い、そのとき
/// 地番の尻は自分の尻そのもの（setext の 2 行目も含む）。
fn own_end(r : Merge, old : Node) -> Int {
  r.spans.get(old.id).unwrap().to
}

///|
fn pad(n : Int) -> String {
  String::make(n, ' ')
}

///|
/// 編集列を整える。from 順（同じ from なら幅の狭い順 — 差し込みが置き換えより先、
/// 同じなら出た順）に並べ、隣り合う編集は 1 つに繋ぎ、行の途中（改行の無い末尾）に
/// 字を書く編集は改行から始める。繋いでから見るので、消した後に何が残るかで決まる。
fn settle(r : Merge) -> Array[Edit] {
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
        out[out.length() - 1] = { ..p, to: e.to, insert: p.insert + e.insert, }
      _ => out.push(e)
    }
  }
  out.map(e => {
    if e.insert != "" && mid_line(r.md, e.from) {
      { ..e, insert: "\n" + e.insert, }
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
fn replace(
  r : Merge,
  x : Node,
  depth : Int,
  sides : Array[Side],
  rules : Array[String],
) -> Unit {
  r.out.push(patch(r, x.id, fragment(x, depth, sides, rules)))
}

///|
/// 地番 id の範囲を text で置き換える編集。項目の入れ子は列 0 で出るので、
/// 容器の桁に揃える（1 行目はもう容器が字下げしている）。
fn patch(r : Merge, id : Int, text : String) -> Edit {
  // 前の木に無い id はここへ来ない — 親の子 id 列が違うので親が書かれる
  let s = r.spans.get(id).unwrap()
  { from: s.from, to: s.to, insert: indent(text, column(r.md, s.from)), }
}

///|
/// 2 行目以降を n 桁字下げする。空行はそのまま。
fn indent(text : String, n : Int) -> String {
  if n == 0 {
    return text
  }
  let pad = pad(n)
  let out = StringBuilder()
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
  kind(a) == kind(b) && a.label == b.label && a.fold == b.fold
}

///|
/// ノード自身が同じか — 行（ラベル・畳み）と中身。子は見ない。
fn same(a : Node, b : Node) -> Bool {
  same_line(a, b) && a.body == b.body
}

///|
fn index(into : Map[Int, Node], x : Node) -> Unit {
  into[x.id] = x
  for k in x.children {
    index(into, k)
  }
}

///|
/// 種類。綴りの書き方は見ない
fn kind(x : Node) -> Int {
  match sign_of(x) {
    Some(Heading) => 0
    Some(Item) => 1
    None => 2
  }
}

///|
fn ids(xs : Array[Node]) -> Array[Int] {
  xs.map(x => x.id)
}

///|
/// 木の形。id と綴りを消したもの — 読みは id を振り直し、後の木の新しい
/// ノードは別の id を持つ。境界の綴り（`rules`）は原文から来るもので、
/// 操作が作った境界は綴りを持たない（書けば `---` として読み直される）。
/// edit が focus の要否を見るのにも使う。
pub fn shape(doc : Doc) -> Doc {
  {
    ..doc,
    body: faceless(doc.body),
    roots: doc.roots.map(r => {
      node: faceless_node(r.node),
      sides: r.sides,
      rules: [],
    }),
  }
}

///|
/// 綴りの書き方（setext・閉じの `#`・マーカー・字下げ幅・詰め）は原文から来る
/// もので、席が変われば綴り直される。**形は種類だけを見る。**
fn faceless_node(x : Node) -> Node {
  {
    ..x,
    id: 0,
    body: faceless(x.body),
    children: x.children.map(faceless_node),
    mark: match sign_of(x) {
      Some(Heading) => Some(atx)
      Some(Item) => Some(bullet)
      None => None
    },
  }
}

///|
/// **形の比較は原文を見ない** — 書いた原文と読み直した原文は、改行の剥ぎ方で
/// 違い得る。意味が同じなら同じ形。
fn faceless(body : Array[Block]) -> Array[Block] {
  body.map(b => { id: 0, content: b.content, source: None, })
}

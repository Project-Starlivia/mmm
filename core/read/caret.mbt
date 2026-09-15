// md のカーソル、または地図の選択の位置が、どのノード（かカード）に掛かっているか。
// DOM も文書の意味も知らない、区間の重なりだけの層。選択の規則はここにしか無い。
//
// 自身の文 = 地番の頭から最初の子の頭まで、**と子の後ろに書かれた中身**（列 0 の
// 塊は開いている項目を閉じるので、子より後ろに書かれることがある。#204）。地番は
// 入れ子なので、これで「最も深いノード」が出る。子孫まで含む `to` で見ると、
// カーソル 1 つでも根までの祖先が全部光り、選択と見分けが付かない（spec.md
// 「選択の持ち主」）。

///|
/// md 側のカーソル 1 つ、または選択 1 つぶん（`from == to` なら点）
pub(all) struct Range {
  from : Int
  to : Int
} derive(Eq, Debug, ToJson)

///|
/// md のカーソルぜんぶ。head は主カーソルの頭（anchor になる）
pub(all) struct Caret {
  ranges : Array[Range]
  head : Int
} derive(Eq, Debug)

///|
/// 選択を持っている側。フォーカスが最後に入ったペイン
pub(all) enum Holder {
  Md
  Map
} derive(Eq, Debug)

///|
/// 地図の選択の位置。ノードはラベルの頭、カードは中身の原文の頭。CodeMirror が編集で写す
pub(all) enum Anchors {
  NodeAt(at~ : Array[Int], anchor~ : Int?)
  CardAt(at~ : Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 何を選んでいるか — ノードの並びか、カード 1 枚か。片方だけ（spec.md「C カード」）
pub(all) enum Choice {
  Nodes(sel~ : @map.Selection)
  Card(id~ : Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub let nothing : Choice = Nodes(sel=@map.none)

///|
/// ノードの自身の文 `[from, to)`。**1 ノードが何本も持てる** — 子の後ろに
/// 書かれた中身はその子の領分を跨がないので、区間が割れる（#204）。
/// Implicit は空なので入らない
priv struct Own {
  id : Int
  from : Int
  to : Int
}

///|
fn owns(s : Survey) -> Array[Own] {
  let starts = starts_of(s)
  let out = []
  each_node(s.doc, n => {
    guard s.spots.get(n.id) is Some(sp) else { return }
    // **自身の文の尻は、次に始まるノードの頭。** ふつうは最初の子だが、境界で置き直された
    // 行のこともある — 境界は中身の持ち主を変えないので、その行の下に自分の中身が続く
    let mut to = sp.to
    if n.children.get(0).bind(k => s.spots.get(k.id)) is Some(first) &&
      first.from < to {
      to = first.from
    }
    if after(starts, sp.from) is Some(next) && next < to {
      to = next
    }
    if to > sp.from {
      out.push({ id: n.id, from: sp.from, to, })
    }
    // **子や置き直された行の後ろに書かれた中身も自分の文。** 列 0 の塊は開いている
    // 項目を閉じるので、見出しの中身が子より後ろに書かれていることがある（#204）。
    // 1 本の区間では言えないので、そういう塊は 1 つずつ足す
    for b in n.body {
      guard s.spots.get(b.id) is Some(at) else { continue }
      if at.from >= to && at.to > at.from {
        out.push({ id: n.id, from: at.from, to: at.to, })
      }
    }
  })
  out.sort_by_key(o => o.from)
  out
}

///|
/// 書かれたノードの頭、昇順。
fn starts_of(s : Survey) -> Array[Int] {
  let out = []
  each_node(s.doc, n => {
    if n.mark is Some(_) && s.spots.get(n.id) is Some(sp) {
      out.push(sp.from)
    }
  })
  out.sort()
  out
}

///|
/// 昇順の並びで、`p` より後ろの最初の値。
fn after(xs : Array[Int], p : Int) -> Int? {
  let mut lo = 0
  let mut hi = xs.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if xs[mid] <= p {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  xs.get(lo)
}

///|
/// 点に掛かる自身の文。掛からなければ None。
///
/// **`owns` は from の昇順で、重なりが無い** — 親の文は最初の子の手前で終わり、
/// 次の兄弟はその子孫の後ろから始まる。子の後ろに書かれた中身は子の領分を
/// 跨がないので、そこも重ならない。だから **`from` が `p` 以下の最後のもの
/// 1 つ**を見れば足りる。それが `p` を含まなければ、`p` はどの文にも掛からない
/// （子の領分の中）。継ぎ目ちょうどの点では、その位置から始まるほうが最後になる
/// ので、「始まる側 1 つ」がそのまま出る。
///
/// **走らずに探す。** 矩形選択は選んだ点ぜんぶを打鍵ごとに解き直すので、1 点ごとに
/// 全ノードを走ると O(ノード数 × 点の数) になる — 5000 ノードで 144 個選んだとき
/// 1 打鍵 12.6ms を実測した（#55）。順が崩れれば二分探索は誤るので、
/// `caret_wbtest.mbt` が見本ぜんぶで昇順・重なり無しを押さえる
fn hit_at(all : Array[Own], p : Int) -> Own? {
  let mut lo = 0
  let mut hi = all.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if all[mid].from <= p {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  guard lo > 0 else { return None }
  let o = all[lo - 1]
  if o.to >= p {
    Some(o)
  } else {
    None
  }
}

///|
/// 1 つの範囲に掛かる自身の文。**閉じ際は中と見なす** — 区間は半開だが、カーソルは
/// その位置に立てる。半開で読むと文書の末尾では何にも掛からず、追記しているあいだ
/// 印が出ない。**点が継ぎ目ちょうどなら始まる側 1 つ**（`hit_at`）— 両側を返すと、
/// 地図へ移った直後の Delete が 2 つ消す。範囲なら掛かる全部
fn hits(all : Array[Own], r : Range) -> Array[Own] {
  guard r.from == r.to else {
    return all.filter(o => o.from <= r.to && o.to >= r.from)
  }
  match hit_at(all, r.from) {
    Some(o) => [o]
    None => []
  }
}

///|
/// その範囲たちが掛かるノードの id、原文の順。無ければ空。**1 つずつ** —
/// 自身の文は 1 ノードで何本にも割れる（`Own`）。
/// **`all` は呼ぶ側が 1 回だけ作る**（`owns`）— 点の数だけ作り直すと、それだけで
/// ノード数に比例した仕事が点の数ぶん増える（#55）
fn ids_at(all : Array[Own], ranges : Array[Range]) -> Array[Int] {
  guard ranges.length() > 0 else { return [] }
  let picked : Set[Int] = Set([])
  for r in ranges {
    for o in hits(all, r) {
      picked.add(o.id)
    }
  }
  let seen : Set[Int] = Set([])
  all
  .filter(o => picked.contains(o.id) && seen.add_and_check(o.id))
  .map(o => o.id)
}

///|
/// 畳まれて埋もれたノード（fold のあるノードの子孫）。箱を持たないので選択に居られない
fn buried(doc : @tree.Doc) -> Set[Int] {
  let out : Set[Int] = Set([])
  fn walk(n : @tree.Node, under : Bool) -> Unit {
    if under {
      out.add(n.id)
    }
    for k in n.children {
      walk(k, under || n.fold is Some(_))
    }
  }

  for t in doc.roots {
    walk(t.node, false)
  }
  out
}

///|
/// その位置を原文に含む中身の id。持ち主が畳まれている・埋もれていれば無い —
/// どちらもカードの行を持たないので、選んでも地図に印の出しようがない
fn block_at(s : Survey, p : Int, gone : Set[Int]) -> Int? {
  let mut found : Int? = None
  each_node(s.doc, n => {
    if !gone.contains(n.id) && n.fold is None {
      for b in meant(n.body) {
        match s.spots.get(b.id) {
          Some(sp) => if sp.from <= p && p < sp.to { found = Some(b.id) }
          None => ()
        }
      }
    }
  })
  found
}

///|
/// 選択。**持ち主が決める** — md が持つ間はカーソルから、地図が持つ間は位置から。
/// 選択に居るのは箱のあるものだけ（埋もれたノードは落とす）。anchor が落ちれば末尾
pub fn chosen(
  s : Survey,
  holder : Holder,
  caret : Caret,
  anchors : Anchors?,
) -> Choice {
  let gone = buried(s.doc)
  // **自身の文の並びは 1 回だけ作る。** 下の `point` は選んだ点ぜんぶに当たる（#55）
  let all = owns(s)
  let point = (p : Int) => hit_at(all, p).map(o => o.id)
  let nodes = (ids : Array[Int], anchor : Int?) => {
    let set : Set[Int] = Set::from_array(ids)
    let kept = set.iter().filter(id => !gone.contains(id)).collect()
    kept.sort()
    let a = match anchor {
      Some(a) if kept.contains(a) => Some(a)
      _ => kept.last()
    }
    Nodes(sel={ ids: kept, anchor: a, })
  }
  if holder is Md {
    return nodes(ids_at(all, caret.ranges), point(caret.head))
  }
  match anchors {
    None => nothing
    Some(CardAt(at~)) =>
      match block_at(s, at, gone) {
        Some(id) => Card(id~)
        None => nothing
      }
    Some(NodeAt(at~, anchor~)) => {
      let ids = at.map(point).filter(x => x is Some(_)).map(x => x.unwrap())
      nodes(ids, anchor.bind(point))
    }
  }
}

///|
/// 位置を編集で写す。点の写し（CodeMirror の `changes.mapPos`）は呼ぶ側の閉包
pub fn carry(a : Anchors, at : (Int) -> Int) -> Anchors {
  match a {
    CardAt(at=p) => CardAt(at=at(p))
    NodeAt(at=ps, anchor~) => NodeAt(at=ps.map(at), anchor=anchor.map(at))
  }
}

///|
/// focus の id をその木の地番で位置に。ノードならラベルの頭、中身なら原文の頭。無ければ None
pub fn anchors_of(s : Survey, id : Int?) -> Anchors? {
  guard id is Some(id) else { return None }
  guard s.spots.get(id) is Some(sp) else { return None }
  guard s.is_node(id) else { return Some(CardAt(at=sp.from)) }
  sp.label.map(l => NodeAt(at=[l], anchor=Some(l)))
}

///|
/// 選択（id）をその木の地番で位置に。地図で選んだときの setAnchors の値。Implicit は行が無いので入らない
pub fn anchors_for(s : Survey, c : Choice) -> Anchors? {
  match c {
    Card(id~) => s.spots.get(id).map(sp => CardAt(at=sp.from))
    Nodes(sel~) => {
      let label = (id : Int) => s.spots.get(id).bind(sp => sp.label)
      let at = sel.ids.map(label).filter(x => x is Some(_)).map(x => x.unwrap())
      Some(NodeAt(at~, anchor=sel.anchor.bind(label)))
    }
  }
}

///|
/// md 側で薄く塗る範囲。ノードは部分木の原文（`Survey::cover`）、カードは中身の原文。
/// 無い地番は落とす。「地図が持つ間だけ」は呼ぶ側（state.ts）が見る
pub fn ranges(s : Survey, c : Choice) -> Array[Range] {
  match c {
    Card(id~) =>
      match s.spots.get(id) {
        Some(sp) => [{ from: sp.from, to: sp.to, }]
        None => []
      }
    Nodes(sel~) => {
      let out = []
      for id in sel.ids {
        out.push_iter(s.cover(id).iter())
      }
      out
    }
  }
}

///|
/// ノードの部分木が原文に書かれた範囲、原文の順。ふつうは地番 1 本。
///
/// **部分木の外の行を跨げば、そこを抜いて割る。** 境界は中身の持ち主を変えないので、
/// 持ち主の中身が、境界で置き直された行より下に書かれていることがある
/// （`- 野菜` / `(野菜) ---` / `(野菜) - 肉` / `(野菜) メモ` の、野菜と メモ の間の肉。
/// docs/spec.md「水平線」）。抜くのは跨いだ書かれた行の範囲と、その手前の境界の水平線。
/// Implicit の地番は子の和なので、跨いだ持ち主の中身まで覆う — 抜く物には数えない
pub fn Survey::cover(self : Survey, id : Int) -> Array[Range] {
  guard self.spots.get(id) is Some(sp) else { return [] }
  let inside : Set[Int] = Set([])
  fn mark(n : @tree.Node) -> Unit {
    inside.add(n.id)
    for k in n.children {
      mark(k)
    }
  }

  each_node(self.doc, n => if n.id == id { mark(n) })
  let holes : Array[Range] = []
  each_node(self.doc, n => {
    guard n.mark is Some(_) &&
      !inside.contains(n.id) &&
      self.spots.get(n.id) is Some(o) &&
      o.from > sp.from &&
      o.from < sp.to else {
      return
    }
    holes.push({ from: hole_start(self.md, o.from), to: o.to, })
  })
  holes.sort_by_key(h => h.from)
  let out : Array[Range] = []
  let mut at = sp.from
  for h in holes {
    if h.from > at {
      out.push({ from: at, to: h.from, })
    }
    if h.to > at {
      at = h.to
    }
  }
  if sp.to > at {
    out.push({ from: at, to: sp.to, })
  }
  out
}

///|
/// 跨いだ行 `at` を抜くときの頭。行の頭から、手前の空行を越えて**境界の水平線が在れば
/// その行の頭**まで — 置き直された行の手前の水平線は、その行の側の綴りで、持ち主の中身ではない
fn hole_start(md : String, at : Int) -> Int {
  let head = line_head(md, at)
  let mut p = head
  while p > 0 {
    let prev = line_head(md, p - 1)
    guard blank(md, prev, p) else {
      return if ruled(md, prev, p) { prev } else { head }
    }
    p = prev
  }
  head
}

///|
/// `at` を含む行の頭。
fn line_head(md : String, at : Int) -> Int {
  let mut p = if at < md.length() { at } else { md.length() }
  while p > 0 && md[p - 1] != '\n' {
    p = p - 1
  }
  p
}

///|
/// `[from, to)` が空白だけか。
fn blank(md : String, from : Int, to : Int) -> Bool {
  for i in from..<(if to < md.length() { to } else { md.length() }) {
    let c = md[i]
    if c != ' ' && c != '\t' && c != '\r' && c != '\n' {
      return false
    }
  }
  true
}

///|
/// `[from, to)` の行が水平線か。空白を除いて `-` `_` `*` のどれか 1 種が 3 つ以上だけ並ぶ
fn ruled(md : String, from : Int, to : Int) -> Bool {
  let mut mark : UInt16 = 0
  let mut count = 0
  for i in from..<(if to < md.length() { to } else { md.length() }) {
    let c = md[i]
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      continue
    }
    if c != '-' && c != '_' && c != '*' {
      return false
    }
    if count == 0 {
      mark = c
    } else if c != mark {
      return false
    }
    count = count + 1
  }
  count >= 3
}

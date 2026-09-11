// 操作を木に当てる。Op は道具の組み合わせで、型の異種性には触らない。
//
// None は「できない操作」。ts は spec どおり押す前に沈めるので、core は静かに断る。
// 途中で失敗しても元の doc は変わらない（道具が純粋なので）。

///|
/// **md に書ける木しか返さない。** 何が書けないかは check が 1 つで言う
/// （骨格の直前の水平線・見出しに飲み込まれる項目・項目の根の側）ので、
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
/// Implicit（`GappedItem` の親）と、行の要るものを持った Implicit（`Unmarked`）は
/// 綴る。消すものは綴らないので、消す回は綴らない。
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
        Unmarked(id) => ids.push(id)
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
      // 境界と読む（深さ 2 なら側の反転、深ければ深さ 2 へ引き出して反対側）。
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

///|
fn attempt(doc : @tree.Doc, op : Op) -> Done? {
  match op {
    Rename(id~, label~) => rename(doc, id, label)
    Fold(id~, open~) => fold(doc, id, open)
    Unfold(id~) => unfold(doc, id)
    Delete(ids~) => delete(doc, ids)
    AddNode(at~, label~) => add_node(doc, at, label)
    Wrap(id~, label~) => wrap(doc, id, label)
    MoveNode(ids~, at~) => move_node(doc, ids, at)
    FlipSide(id~) => flip(doc, id)
    AddBlock(at~, content~) => add_block(doc, at, content)
    SetBlock(id~, content~, source~) => set_block(doc, id, content, source)
    MoveBlock(ids~, at~) => move_block(doc, ids, at)
    Graft(at~, md~) => graft(doc, at, md)
  }
}

///|
/// 道具の結果を Done に包む。
fn done(doc : @tree.Doc?, focus : Int?) -> Done? {
  match doc {
    Some(d) => Some({ doc: d, focus, })
    None => None
  }
}

///|
/// ラベルを替える。Implicit は見出しとして綴られる。
/// 畳まれたノードの名前は summary（地図が出す字）なので、summary も同じ字にする —
/// 手書きで食い違っていた 2 つの名前も、名を付け直せば 1 つに揃う
fn rename(doc : @tree.Doc, id : Int, label : String) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  // Implicit は行を省いた空の見出しなので、名を付ければ見出しそのもの
  // （畳みは持てないので summary も無い）
  let m = if n.mark is None {
    spell(n, label)
  } else {
    {
      ..n,
      label,
      fold: n.fold.map(f => ({ ..f, summary: Some(label), } : @tree.Fold)),
    }
  }
  done(splice(doc, id, _ => [m]), Some(id))
}

///|
/// 定義ごと畳む。名前はラベルそのもの。畳み済みなら open だけ替わる。
/// Implicit は綴ってから畳む。
fn fold(doc : @tree.Doc, id : Int, open : Bool) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  fn next(fold : @tree.Fold?, label : String) -> @tree.Fold {
    match fold {
      Some(f) => { ..f, open, }
      None => { open, summary: Some(label), }
    }
  }

  // Implicit は綴ってから畳む
  if n.mark is None {
    guard splice(doc, id, _ => [spell(n, "")]) is Some(d) else { return None }
    return fold(d, id, open)
  }
  let m = { ..n, fold: Some(next(n.fold, n.label)), }
  done(splice(doc, id, _ => [m]), Some(id))
}

///|
/// 畳みを外す。中身はその場で普通の md として読み直される（読みのサイクルの仕事）。
fn unfold(doc : @tree.Doc, id : Int) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  guard n.fold is Some(_) else { return None }
  let m = { ..n, fold: None, }
  done(splice(doc, id, _ => [m]), Some(id))
}

///|
/// 1 つ消す。ノードは部分木ごと、中身は 1 枚。
fn erase(doc : @tree.Doc, id : Int) -> @tree.Doc? {
  match owner(doc, block=id) {
    Some(o) => body(doc, node=o, bs => bs.filter(b => b.id != id))
    None => splice(doc, id, _ => [])
  }
}

///|
/// 消した後に選ぶ候補、近いほうから。中身なら持ち主とその祖先。ノードなら
/// 次の兄弟たち → 前の兄弟たち（近い順）→ 祖先。消えるものは呼ぶ側が落とす。
/// 兄弟と親は、消したノードが見えていれば見えている（畳まれるのは子孫）ので、
/// 埋もれたノードには落ちない。
fn heirs(doc : @tree.Doc, id : Int) -> Array[Int] {
  let out : Array[Int] = []
  // 中身は `siblings` が空を返す（兄弟を持つのはノードだけ）
  let sibs = siblings(doc, id)
  match sibs.search(id) {
    Some(i) => {
      for k in (i + 1)..<sibs.length() {
        out.push(sibs[k])
      }
      for k in 0..<i {
        out.push(sibs[i - 1 - k])
      }
    }
    None => ()
  }
  for a in ancestors(doc, id) {
    out.push(a)
  }
  out
}

///|
/// 選んだものを文書順に消す。知らない id が 1 つでもあれば None。
/// focus は先頭（文書順）の消したものの隣 — 中身なら持ち主、ノードなら次の兄弟 →
/// 前の兄弟 → 親。消えるものは飛ばす。何も残らなければ None（最後の根、文書の散文）。
/// 「消した後に何を選ぶか」の答えはこの focus 1 本（ts は隣を決めない）。
fn delete(doc : @tree.Doc, ids : Array[Int]) -> Done? {
  guard !ids.is_empty() && ids.all(id => has(doc, id)) else { return None }
  let gone = pick(doc, ids)
  let wants = heirs(doc, gone[0])
  let mut cur = doc
  for id in gone {
    guard erase(cur, id) is Some(d) else { return None }
    cur = d
  }
  // 子が尽きた Implicit を選ばないように、掃除してから選ぶ
  guard mend(cur) is Some(swept) else { return None }
  let mut focus = None
  for w in wants {
    if focus is None && has(swept, w) {
      focus = Some(w)
    }
  }
  Some({ doc: swept, focus, })
}

///|
/// 新しいノード。持ち込むのは形（ラベル）だけで、綴りは席が決める（`implant`）。
fn make(id : Int, label : String) -> @tree.Node {
  { id, label, fold: None, body: [], children: [], mark: Some(@tree.atx), }
}

///|
/// その綴りの種類。飛び（Implicit）は行を省いた空の見出しなので見出し。
fn sign_or_heading(n : @tree.Node) -> @tree.Sign {
  match @tree.sign_of(n) {
    Some(s) => s
    None => Heading
  }
}

///|
/// 席の隣 — 差すもの・運ぶものが綴りを継ぐ相手。Before / After は隣そのもの、
/// In は末尾の子、In(doc_id) は最後の根。居なければ None（席が無い・子が無い・根が無い）。
fn neighbor(doc : @tree.Doc, at : NodePlace) -> @tree.Node? {
  match at {
    Before(node~) | After(node~) => find(doc, node)
    In(node~, ..) if node == @tree.doc_id => doc.roots.last().map(r => r.node)
    In(node~, ..) => find(doc, node).bind(n => n.children.last())
  }
}

///|
/// 席の綴りの種類。隣に従い、隣が居なければ親に従う（項目の下は項目、それ以外は
/// 見出し。根が無い文書は見出し）。席が無ければ None。
fn sign_at(doc : @tree.Doc, at : NodePlace) -> @tree.Sign? {
  match neighbor(doc, at) {
    Some(n) => Some(sign_or_heading(n))
    None =>
      match at {
        In(node~, ..) if node == @tree.doc_id => Some(Heading)
        In(node~, ..) => find(doc, node).map(sign_or_heading)
        _ => None
      }
  }
}

///|
/// 席の項目の綴り（マーカー・字下げ幅・詰め）。隣が項目でなければ `@tree.bullet` —
/// 種類と違い、親には従わない。
fn spell_at(doc : @tree.Doc, at : NodePlace) -> @tree.Mark {
  match neighbor(doc, at).bind(n => n.mark) {
    Some(Item(..) as m) => m
    _ => @tree.bullet
  }
}

///|
/// マーカーを n だけ進める。番号付きなら数字を足し（`3.` の 1 つ先は `4.`）、
/// 箇条の字はそのまま。
fn step(marker : String, n : Int) -> String {
  let mut d = 0
  let mut num = 0
  while d < marker.length() && marker[d] >= '0' && marker[d] <= '9' {
    num = num * 10 + (marker[d].to_int() - '0'.to_int())
    d = d + 1
  }
  if d == 0 {
    return marker
  }
  (num + n).to_string() + marker[d:].to_owned()
}

///|
/// その席に座る項目の綴り。k 番目の新入りは番号を k + 1 だけ進める。
fn spelled(n : @tree.Node, mark : @tree.Mark, k : Int) -> @tree.Node {
  match (n.mark, mark) {
    (Some(Item(..)), Item(marker~, offset~, loose~)) =>
      { ..n, mark: Some(Item(marker=step(marker, k + 1), offset~, loose~)), }
    _ => n
  }
}

///|
/// 席が指している id。
fn NodePlace::id(self : NodePlace) -> Int {
  match self {
    Before(node~) | After(node~) | In(node~, ..) => node
  }
}

///|
/// 席の綴りで差す。差すもの・運ぶものは形だけを持ち込み、種類（`sign_at`）も
/// マーカーと桁（`spell_at`）も席が決める。席が無ければ None。
fn implant(
  doc : @tree.Doc,
  at : NodePlace,
  nodes : Array[@tree.Node],
) -> @tree.Doc? {
  guard sign_at(doc, at) is Some(sign) else { return None }
  let mark = spell_at(doc, at)
  place(doc, at, nodes.mapi((k, n) => spelled(respell(n, sign), mark, k)))
}

///|
/// 新しいノードを差す。
fn add_node(doc : @tree.Doc, at : NodePlace, label : String) -> Done? {
  let id = fresh(doc)
  done(implant(doc, at, [make(id, label)]), Some(id))
}

///|
/// 新しいノードが id の席に座り、id はその唯一の子になる。綴りは id と同じ。
fn wrap(doc : @tree.Doc, id : Int, label : String) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  let nid = fresh(doc)
  // id の席に座るので、項目なら綴りも id のもの。見出しは新しく作る綴り
  // （読んだ setext や閉じの `#` は運ばない。飛びは行が無いので見出しで綴る）
  let mark = match n.mark {
    Some(Item(..)) as m => m.unwrap()
    _ => @tree.atx
  }
  let w : @tree.Node = {
    id: nid,
    label,
    fold: None,
    body: [],
    children: [n],
    mark: Some(mark),
  }
  done(splice(doc, id, _ => [w]), Some(nid))
}

///|
/// 文書順に抜き取る。抜いたものは taken に、残りの木を返す。
fn take(
  doc : @tree.Doc,
  ids : Array[Int],
  taken : Array[@tree.Node],
) -> @tree.Doc? {
  let mut cur = doc
  for id in ids {
    let pulled = splice(cur, id, fn(n) {
      taken.push(n)
      []
    })
    match pulled {
      Some(d) => cur = d
      None => return None
    }
  }
  Some(cur)
}

///|
/// 中身を文書順に抜き取る。抜いたものは taken に、残りの木を返す。
fn take_blocks(
  doc : @tree.Doc,
  ids : Array[Int],
  taken : Array[@tree.Block],
) -> @tree.Doc? {
  let mut cur = doc
  for id in ids {
    guard owner(cur, block=id) is Some(o) else { return None }
    let pulled = body(cur, node=o, fn(bs) {
      let out = []
      for b in bs {
        if b.id == id {
          taken.push(b)
        } else {
          out.push(b)
        }
      }
      out
    })
    match pulled {
      Some(d) => cur = d
      None => return None
    }
  }
  Some(cur)
}

///|
/// 席に差す。
fn place(
  doc : @tree.Doc,
  at : NodePlace,
  nodes : Array[@tree.Node],
) -> @tree.Doc? {
  match at {
    Before(node~) => splice(doc, node, x => [..nodes, x])
    After(node~) => splice(doc, node, x => [x, ..nodes])
    In(node~, side~) => append(doc, node~, side?, nodes)
  }
}

///|
/// 動かす。文書順を保って抜き、席に差す。側は行き先が決め、綴りも席が決める（`respell`）。
fn move_node(doc : @tree.Doc, ids : Array[Int], at : NodePlace) -> Done? {
  guard !ids.is_empty() else { return None }
  for id in ids {
    guard find(doc, id) is Some(_) else { return None }
  }
  let picked = pick(doc, ids)
  guard !within(doc, at.id(), picked) else { return None }
  let taken = []
  guard take(doc, picked, taken) is Some(rest) else { return None }
  done(implant(rest, at, taken), Some(picked[0]))
}

///|
fn flipped(s : @tree.Side) -> @tree.Side {
  match s {
    Right => Left
    Left => Right
  }
}

///|
/// 側を裏返す。根は sides を一括反転（鏡像）、根の子はその 1 つ、深いノードは
/// 反対側の末尾へ引き出す（深さは保つので、間を Implicit が埋める）。
fn flip(doc : @tree.Doc, id : Int) -> Done? {
  guard seat(doc, id) is Some(path) else { return None }
  let r = doc.roots[path[0]]
  let turned = match path.length() {
    1 => Some(reside(doc, path[0], r.sides.map(flipped)))
    2 => {
      let sides = r.sides.copy()
      sides[path[1]] = flipped(side_at(r, path[1]))
      Some(reside(doc, path[0], sides))
    }
    depth => haul(doc, r, id, side=flipped(side_at(r, path[1])), depth~)
  }
  done(turned, Some(id))
}

///|
/// 根の側を置き換える。**側は根のもの**なので、書き換わるのは `sides` だけ。
fn reside(doc : @tree.Doc, at : Int, sides : Array[@tree.Side]) -> @tree.Doc {
  let roots = doc.roots.copy()
  roots[at] = { ..roots[at], sides, }
  { ..doc, roots, }
}

///|
/// 深いノードを反対側の末尾へ引き出す。**深さは保つ**ので、間を Implicit が埋める。
/// 項目は相対記法で深さを持たず飛びを綴れないので、直に深さ 2 へ。
fn haul(
  doc : @tree.Doc,
  r : @tree.Root,
  id : Int,
  side~ : @tree.Side,
  depth~ : Int,
) -> @tree.Doc? {
  let taken = []
  guard take(doc, [id], taken) is Some(rest) else { return None }
  let mut next = fresh(doc)
  let mut wrapped = taken[0]
  if !(@tree.sign_of(wrapped) is Some(Item)) {
    for _ in 0..<(depth - 2) {
      wrapped = {
        id: next,
        label: "",
        fold: None,
        body: [],
        children: [wrapped],
        mark: None,
      }
      next = next + 1
    }
  }
  append(rest, node=r.node.id, side~, [wrapped])
}

///|
/// 中身の列の中に差す。Before / After は隣の id で、In は末尾。
fn put(
  bs : Array[@tree.Block],
  at : BlockPlace,
  more : Array[@tree.Block],
) -> Array[@tree.Block] {
  match at {
    In(..) => [..bs, ..more]
    Before(block~) => {
      let out = []
      for b in bs {
        if b.id == block {
          out.push_iter(more.iter())
        }
        out.push(b)
      }
      out
    }
    After(block~) => {
      let out = []
      for b in bs {
        out.push(b)
        if b.id == block {
          out.push_iter(more.iter())
        }
      }
      out
    }
  }
}

///|
/// 席の持ち主。Before / After は隣の持ち主、In はそのノード。
fn owner_at(doc : @tree.Doc, at : BlockPlace) -> Int? {
  match at {
    Before(block~) | After(block~) => owner(doc, block~)
    In(node~) => Some(node)
  }
}

///|
fn add_block(
  doc : @tree.Doc,
  at : BlockPlace,
  content : @tree.Content?,
) -> Done? {
  guard owner_at(doc, at) is Some(o) else { return None }
  let b : @tree.Block = { id: fresh(doc), content, source: None, }
  done(body(doc, node=o, bs => put(bs, at, [b])), Some(b.id))
}

///|
/// 中身を入れ替える。**前の字は残さない** — 意味を渡せば種類ごとに綴られ、
/// 原文を渡せばその字がそのまま書き戻る（カードのその場編集）。
fn set_block(
  doc : @tree.Doc,
  id : Int,
  content : @tree.Content?,
  source : String?,
) -> Done? {
  guard owner(doc, block=id) is Some(o) else { return None }
  done(
    body(doc, node=o, bs => {
      bs.map(b => if b.id == id { { id, content, source, } } else { b })
    }),
    Some(id),
  )
}

///|
/// 席が指している id。
fn BlockPlace::id(self : BlockPlace) -> Int {
  match self {
    Before(block~) | After(block~) => block
    In(node~) => node
  }
}

///|
/// 中身を動かす。文書順を保って抜き、席に差す。
fn move_block(doc : @tree.Doc, ids : Array[Int], at : BlockPlace) -> Done? {
  guard !ids.is_empty() else { return None }
  for id in ids {
    guard owner(doc, block=id) is Some(_) else { return None }
  }
  let picked = pick(doc, ids)
  guard !picked.contains(at.id()) else { return None }
  let taken = []
  guard take_blocks(doc, picked, taken) is Some(rest) else { return None }
  guard owner_at(rest, at) is Some(o) else { return None }
  done(body(rest, node=o, bs => put(bs, at, taken)), Some(picked[0]))
}

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
  // 字として運べば書き戻したときに md が境界と読む
  let sub = bordered(sub)
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
/// 断片の側を、境界の水平線に戻す。側が変わる子の**手前の子の部分木の最後の行**
/// （文書順で境界の直前に書かれていた行）の中身の尻に置く。読んだ字（`rules`）は
/// そのまま運ぶ。行が綴りを持たない（Implicit）なら中身を持てないので置けない。
fn bordered(sub : @tree.Doc) -> @tree.Doc {
  let mut cur = sub
  let mut next = fresh(sub)
  for r in sub.roots {
    let kids = r.node.children
    for i in 1..<kids.length() {
      guard i < r.sides.length() && r.sides[i] != r.sides[i - 1] else {
        continue
      }
      let source = match r.rules.get(i) {
        Some(line) if line != "" => Some(line)
        _ => None
      }
      let rule : @tree.Block = {
        id: next,
        content: Some(ThematicBreak),
        source,
      }
      next = next + 1
      if body(cur, node=last_line(kids[i - 1]), bs => [..bs, rule]) is Some(d) {
        cur = d
      }
    }
  }
  cur
}

///|
/// 部分木の中で文書順が最後の骨格の行。
fn last_line(n : @tree.Node) -> Int {
  match n.children.last() {
    Some(k) => last_line(k)
    None => n.id
  }
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

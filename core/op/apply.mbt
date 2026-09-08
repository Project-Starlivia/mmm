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
pub fn apply(doc : @tree.Doc, op : Op) -> Done? {
  guard attempt(doc, op) is Some(d) else { return None }
  guard mend(cap(d.doc)) is Some(doc) else { return None }
  Some({ doc, focus: d.focus.filter(f => has(doc, f)), })
}

///|
/// 部分木をその綴りで書き直す。形（ラベル・中身・子・畳み・飛び）は保ち、綴りだけ替える。
/// 項目にするとき、飛び（Implicit）は行を省けないので空の項目として綴る（`- - b`）。
/// 見出しにするとき、Implicit はそのまま — 省いたままで読めない席かは check と mend が見る。
/// 決めは docs/superpowers/specs/2026-09-06-paste-design.md
fn respell(n : @tree.Node, sign : @tree.Sign) -> @tree.Node {
  // **読んだ綴りは保つ。** 種類が変わるものだけ、新しく作る綴りで書く。
  // 飛び（Implicit）は行を省けないので項目にするときだけ空の項目として綴り、
  // 見出しにするときはそのまま（省いたままで読めない席かは check と mend が見る）
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
      return None
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
    AddNode(at~, labels~) => add_node(doc, at, labels)
    Wrap(id~, label~) => wrap(doc, id, label)
    MoveNode(ids~, at~) => move_node(doc, ids, at)
    FlipSide(id~) => flip(doc, id)
    AddBlock(at~, content~, source~) => add_block(doc, at, content, source)
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
fn rename(doc : @tree.Doc, id : Int, label : String) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  // Implicit は行を省いた空の見出しなので、名を付ければ見出しそのもの
  let m = if n.mark is None { spell(n, label) } else { { ..n, label, } }
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
  if owner(doc, block=id) is None {
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
/// その綴りで空のノードを作る。項目の綴りは既定で、席のものは `spelled` が当てる。
fn make(sign : @tree.Sign, id : Int, label : String) -> @tree.Node {
  let mark = match sign {
    Heading => @tree.atx
    Item => @tree.bullet
  }
  { id, label, fold: None, body: [], children: [], mark: Some(mark), }
}

///|
/// その綴りの種類。飛び（Implicit）は行を省いた空の見出しなので見出し。
fn sign_of(n : @tree.Node) -> @tree.Sign {
  match @tree.sign_of(n) {
    Some(s) => s
    None => Heading
  }
}

///|
/// この下に足すときの綴り。末尾の子がいればそれに、いなければ親に従う
/// （項目の下は項目、それ以外は見出し）。
fn sign_in(n : @tree.Node) -> @tree.Sign {
  match n.children.last() {
    Some(c) => sign_of(c)
    None => sign_of(n)
  }
}

///|
/// 席の綴り。新しく差すもの・運ぶものはこれに従う（「綴りは席が決める」）。
/// Before / After は隣の綴り、In は末尾の子の綴り、子が無ければ親（項目なら項目、
/// それ以外は見出し）、In(doc_id) は最後の根（無ければ見出し）。席が無ければ None。
fn sign_at(doc : @tree.Doc, at : NodePlace) -> @tree.Sign? {
  match at {
    Before(node~) => find(doc, node).map(sign_of)
    After(node~) => find(doc, node).map(sign_of)
    In(node~, ..) =>
      if node == @tree.doc_id {
        Some(
          match doc.roots.last() {
            Some(r) => sign_of(r.node)
            None => @tree.Heading
          },
        )
      } else {
        find(doc, node).map(sign_in)
      }
  }
}

///|
/// 席の項目の綴り（マーカー・字下げ幅・詰め）。`sign_at` と同じ席の見方で、
/// Before / After は隣、In は末尾の子、In(doc_id) は最後の根。
/// 項目が居なければ既定（`-` / 2 / 詰まった列）。
fn spell_at(doc : @tree.Doc, at : NodePlace) -> (String, Int, Bool) {
  let near = match at {
    Before(node~) | After(node~) => find(doc, node)
    In(node~, ..) =>
      if node == @tree.doc_id {
        doc.roots.last().map(r => r.node)
      } else {
        find(doc, node).bind(n => n.children.last())
      }
  }
  match near.map(x => x.mark) {
    Some(Some(Item(marker~, offset~, loose~))) => (marker, offset, loose)
    _ => ("-", 2, false)
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
fn spelled(n : @tree.Node, spell : (String, Int, Bool), k : Int) -> @tree.Node {
  guard n.mark is Some(Item(..)) else { return n }
  {
    ..n,
    mark: Some(Item(marker=step(spell.0, k + 1), offset=spell.1, loose=spell.2)),
  }
}

///|
/// 席が指している id。
fn anchor(at : NodePlace) -> Int {
  match at {
    Before(node~) => node
    After(node~) => node
    In(node~, ..) => node
  }
}

///|
/// 新しいノードを差す。綴りは席が決める（`sign_at` / `spell_at`）。
fn add_node(doc : @tree.Doc, at : NodePlace, labels : Array[String]) -> Done? {
  guard !labels.is_empty() else { return None }
  guard sign_at(doc, at) is Some(sign) else { return None }
  let spell = spell_at(doc, at)
  let first = fresh(doc)
  let news = labels.mapi((k, label) => {
    spelled(make(sign, first + k, label), spell, k)
  })
  done(place(doc, at, news), Some(first))
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
  guard !within(doc, anchor(at), picked) else { return None }
  let taken = []
  guard take(doc, picked, taken) is Some(rest) else { return None }
  guard sign_at(rest, at) is Some(sign) else { return None }
  let spell = spell_at(rest, at)
  done(
    place(rest, at, taken.mapi((k, n) => spelled(respell(n, sign), spell, k))),
    Some(picked[0]),
  )
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
  match path.length() {
    1 => reside(doc, path[0], r.sides.map(flipped), id)
    2 => {
      let sides = r.sides.copy()
      sides[path[1]] = flipped(side_of(r, path[1]))
      reside(doc, path[0], sides, id)
    }
    depth => haul(doc, r, id, side=flipped(side_of(r, path[1])), depth~)
  }
}

///|
/// 根の子の側。書かれていない所は Right（`sides` は子と並走するが、
/// 短くても足りない所は `---` が書かれていないということ）。
fn side_of(r : @tree.Root, j : Int) -> @tree.Side {
  if j < r.sides.length() {
    r.sides[j]
  } else {
    @tree.Right
  }
}

///|
/// 根の側を置き換える。**側は根のもの**なので、書き換わるのは `sides` だけ。
fn reside(
  doc : @tree.Doc,
  at : Int,
  sides : Array[@tree.Side],
  focus : Int,
) -> Done? {
  let roots = doc.roots.copy()
  roots[at] = { ..roots[at], sides, }
  Some({ doc: { ..doc, roots, }, focus: Some(focus), })
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
) -> Done? {
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
  done(append(rest, node=r.node.id, side~, [wrapped]), Some(id))
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
fn holder(doc : @tree.Doc, at : BlockPlace) -> Int? {
  match at {
    Before(block~) => owner(doc, block~)
    After(block~) => owner(doc, block~)
    In(node~) => Some(node)
  }
}

///|
fn add_block(
  doc : @tree.Doc,
  at : BlockPlace,
  content : @tree.Content?,
  source : String?,
) -> Done? {
  guard holder(doc, at) is Some(o) else { return None }
  let b : @tree.Block = { id: fresh(doc), content, source, }
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
/// 中身を動かす。文書順を保って持ち主ごとに抜き、席に差す。
fn move_block(doc : @tree.Doc, ids : Array[Int], at : BlockPlace) -> Done? {
  guard !ids.is_empty() else { return None }
  for id in ids {
    guard owner(doc, block=id) is Some(_) else { return None }
  }
  let picked = pick(doc, ids)
  guard !picked.contains(anchor_block(at)) else { return None }
  let taken = []
  let mut cur = doc
  for id in picked {
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
  guard holder(cur, at) is Some(o) else { return None }
  done(body(cur, node=o, bs => put(bs, at, taken)), Some(picked[0]))
}

///|
/// 席が指している id。
fn anchor_block(at : BlockPlace) -> Int {
  match at {
    Before(block~) => block
    After(block~) => block
    In(node~) => node
  }
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
/// 飛び）だけで、`#` の本数・マーカー・字下げ・先頭の飛びは書き方なので捨てる。
/// 一番外の段落は行ごとにノード、それ以外の中身は行き先の親の body 末尾へ
/// （行き先が文書なら断る — 文書の散文はマップに出ない）。
/// 断片が `##` から始まると parse は根を Implicit で包む（深さ 1 の飛び）。
/// それは切り出した場所の名残でしかないので剥がし、相対の形で差す。
/// 決めは docs/superpowers/specs/2026-09-06-paste-design.md
fn graft(doc : @tree.Doc, at : NodePlace, md : String) -> Done? {
  let sub = @tree.parse(md)
  guard !(sub.roots.is_empty() && sub.body.is_empty()) else { return None }
  guard sign_at(doc, at) is Some(sign) else { return None }
  let host = match at {
    In(node~, ..) => node
    _ => {
      guard parent(doc, anchor(at)) is Some(p) else { return None }
      p
    }
  }
  let (labels, rest) = split_prose(sub.body)
  // 行のノードは文書に無い番号から、断片の id はその先へ寄せる
  let first = fresh(doc)
  let by = first + labels.length() - (@tree.doc_id + 1)
  let spell = spell_at(doc, at)
  let heads = labels.mapi((k, label) => make(sign, first + k, label))
  let prose = rest.map(b => {
    ({ id: b.id + by, content: b.content, source: b.source, } : @tree.Block)
  })
  let subs = peel(sub.roots.map(r => r.node)).map(n => {
    respell(shift(n, by), sign)
  })
  let nodes = [..heads, ..subs].mapi((k, n) => spelled(n, spell, k))
  let mut cur = doc
  if !prose.is_empty() {
    guard host != @tree.doc_id else { return None }
    guard body(cur, node=host, bs => [..bs, ..prose]) is Some(d) else {
      return None
    }
    cur = d
  }
  if nodes.is_empty() {
    return Some({ doc: cur, focus: Some(prose[0].id), })
  }
  done(place(cur, at, nodes), Some(nodes[0].id))
}

///|
/// 貼る断片の一番外の中身を、**行のノードになる字**と**中身のまま行くもの**に分ける。
/// 行になりうるのは読み解かなかった中身の原文（段落）だけで、1 行が 1 ノード。
fn split_prose(
  body : Array[@tree.Block],
) -> (Array[String], Array[@tree.Block]) {
  let labels : Array[String] = []
  let rest : Array[@tree.Block] = []
  for b in body {
    let ls = if b.content is None { b.source.bind(@tree.lines) } else { None }
    match ls {
      Some(ls) => labels.append(ls)
      None => rest.push(b)
    }
  }
  (labels, rest)
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

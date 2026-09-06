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
  Some({ doc, focus: d.focus.filter(f => has(doc, f)) })
}

///|
/// 部分木をその綴りで書き直す。形（ラベル・中身・子・畳み・飛び）は保ち、綴りだけ替える。
/// 項目にするとき、飛び（Implicit）は行を省けないので空の項目として綴る（`- - b`）。
/// 見出しにするとき、Implicit はそのまま — 省いたままで読めない席かは check と mend が見る。
/// 決めは docs/superpowers/specs/2026-09-06-paste-design.md
fn respell(n : @tree.Node, sign : @tree.Sign) -> @tree.Node {
  match sign {
    Item => @tree.ListNode(as_item(n))
    Heading =>
      match n {
        HeadingNode(h) =>
          @tree.HeadingNode({
            ..h,
            children: h.children.map(c => respell(c, Heading)),
          })
        ImplicitNode(g) =>
          @tree.ImplicitNode({
            ..g,
            children: g.children.map(c => respell(c, Heading)),
          })
        ListNode(l) =>
          @tree.HeadingNode({
            id: l.id,
            label: l.label,
            fold: l.fold,
            body: l.body,
            children: l.children.map(c => respell(@tree.ListNode(c), Heading)),
          })
      }
  }
}

///|
/// 部分木を項目で書く。型が「項目の子孫は項目」なので、下は全部項目になる。
fn as_item(n : @tree.Node) -> @tree.ListNode {
  match n {
    ListNode(l) => l
    HeadingNode(h) =>
      {
        id: h.id,
        label: h.label,
        fold: h.fold,
        body: h.body,
        children: h.children.map(as_item),
      }
    ImplicitNode(g) =>
      {
        id: g.id,
        label: "",
        fold: None,
        body: [],
        children: g.children.map(as_item),
      }
  }
}

///|
/// 見出しの天井。`@tree.deepest` より深くに着いた見出しは部分木ごと項目に
/// 綴り替える — 手で書くときも `######` の下は `- ` でしか続けられない。
/// 天井より深い Implicit は空の項目として綴る（飛びは形なので運ぶ。`- - b`）。
/// 天井の Implicit は行を省いた空の見出しなので残す
/// （子が項目になれば `GappedItem` — 綴れば読める）。上の段には触らないので、
/// parse の出力には何もしない。
fn cap(doc : @tree.Doc) -> @tree.Doc {
  fn node(n : @tree.Node, depth : Int, out : Array[@tree.Node]) -> Unit {
    fn under(xs : Array[@tree.Node]) -> Array[@tree.Node] {
      let children = []
      for c in xs {
        node(c, depth + 1, children)
      }
      children
    }

    match n {
      HeadingNode(h) if depth <= @tree.deepest =>
        out.push(@tree.HeadingNode({ ..h, children: under(h.children) }))
      ImplicitNode(g) if depth <= @tree.deepest =>
        out.push(@tree.ImplicitNode({ ..g, children: under(g.children) }))
      ListNode(_) => out.push(n)
      _ => out.push(respell(n, Item))
    }
  }

  // 根は深さ 1 なので必ず 1 つ残り、根の子の数も変わらない（sides はそのまま）
  {
    ..doc,
    roots: doc.roots.map(r => {
      let out = []
      node(r.node, 1, out)
      { ..r, node: out[0] }
    }),
  }
}

///|
/// check の破れのうち、Implicit で直るものを直して通し直す。子が尽きた Implicit
/// （`BarrenImplicit`）は消す — 道具は途中で席が消えないように残しておくので、
/// 掃除はここ。見出しの直後に来た Implicit（`Swallowed`）と、項目を子に持った
/// Implicit（`GappedItem` の親）は綴る。消すものは綴らないので、消す回は綴らない。
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
        guard find(cur, id) is Some(ImplicitNode(g)) else { continue }
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
fn spell(g : @tree.ImplicitNode, label : String) -> @tree.Node {
  @tree.HeadingNode({
    id: g.id,
    label,
    fold: None,
    body: [],
    children: g.children,
  })
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
    AddBlock(at~, content~) => add_block(doc, at, content)
    SetBlock(id~, content~) => set_block(doc, id, content)
    MoveBlock(ids~, at~) => move_block(doc, ids, at)
    Graft(at~, md~) => graft(doc, at, md)
  }
}

///|
/// 道具の結果を Done に包む。
fn done(doc : @tree.Doc?, focus : Int?) -> Done? {
  match doc {
    Some(d) => Some({ doc: d, focus })
    None => None
  }
}

///|
/// ラベルを替える。Implicit は見出しとして綴られる。
fn rename(doc : @tree.Doc, id : Int, label : String) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  let m = match n {
    HeadingNode(h) => @tree.HeadingNode({ ..h, label, })
    ListNode(l) => @tree.ListNode({ ..l, label, })
    ImplicitNode(g) => spell(g, label)
  }
  done(splice(doc, id, _ => [m]), Some(id))
}

///|
/// 定義ごと畳む。名前はラベル（書けなければ名無し）。畳み済みなら open だけ替わる。
/// Implicit は綴ってから畳む。
fn fold(doc : @tree.Doc, id : Int, open : Bool) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  fn folding(label : String) -> @tree.Fold {
    { open, summary: if @tree.writable(label) { Some(label) } else { None } }
  }

  fn next(fold : @tree.Fold?, label : String) -> @tree.Fold {
    match fold {
      Some(f) => { ..f, open, }
      None => folding(label)
    }
  }

  let m = match n {
    HeadingNode(h) =>
      @tree.HeadingNode({ ..h, fold: Some(next(h.fold, h.label)) })
    ListNode(l) => @tree.ListNode({ ..l, fold: Some(next(l.fold, l.label)) })
    ImplicitNode(g) => {
      guard splice(doc, id, _ => [spell(g, "")]) is Some(d) else { return None }
      return fold(d, id, open)
    }
  }
  done(splice(doc, id, _ => [m]), Some(id))
}

///|
/// 畳みを外す。中身はその場で普通の md として読み直される（読みのサイクルの仕事）。
fn unfold(doc : @tree.Doc, id : Int) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  let m = match n {
    HeadingNode(h) => {
      guard h.fold is Some(_) else { return None }
      @tree.HeadingNode({ ..h, fold: None })
    }
    ListNode(l) => {
      guard l.fold is Some(_) else { return None }
      @tree.ListNode({ ..l, fold: None })
    }
    ImplicitNode(_) => return None
  }
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
  Some({ doc: swept, focus })
}

///|
/// その綴りで空のノードを作る。
fn make(sign : @tree.Sign, id : Int, label : String) -> @tree.Node {
  match sign {
    Heading =>
      @tree.HeadingNode({ id, label, fold: None, body: [], children: [] })
    Item => @tree.ListNode({ id, label, fold: None, body: [], children: [] })
  }
}

///|
fn sign_of(n : @tree.Node) -> @tree.Sign {
  match n {
    ListNode(_) => Item
    _ => Heading
  }
}

///|
/// この下に足すときの綴り。末尾の子がいればそれに、いなければ親に従う
/// （項目の下は項目、それ以外は見出し）。
fn sign_in(n : @tree.Node) -> @tree.Sign {
  match kids(n).last() {
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
/// 席が指している id。
fn anchor(at : NodePlace) -> Int {
  match at {
    Before(node~) => node
    After(node~) => node
    In(node~, ..) => node
  }
}

///|
/// 新しいノードを差す。綴りは席が決める（`sign_at`）。
fn add_node(doc : @tree.Doc, at : NodePlace, labels : Array[String]) -> Done? {
  guard !labels.is_empty() else { return None }
  guard sign_at(doc, at) is Some(sign) else { return None }
  let first = fresh(doc)
  let news = labels.mapi((k, label) => make(sign, first + k, label))
  done(place(doc, at, news), Some(first))
}

///|
/// 新しいノードが id の席に座り、id はその唯一の子になる。綴りは id と同じ。
fn wrap(doc : @tree.Doc, id : Int, label : String) -> Done? {
  guard find(doc, id) is Some(n) else { return None }
  let nid = fresh(doc)
  let w = match n {
    ListNode(l) =>
      @tree.ListNode({ id: nid, label, fold: None, body: [], children: [l] })
    _ =>
      @tree.HeadingNode({ id: nid, label, fold: None, body: [], children: [n] })
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
/// 動かす。文書順を保って抜き、席に差す。側は行き先が決め、綴りは保つ。
fn move_node(doc : @tree.Doc, ids : Array[Int], at : NodePlace) -> Done? {
  guard !ids.is_empty() else { return None }
  for id in ids {
    guard find(doc, id) is Some(_) else { return None }
  }
  let picked = pick(doc, ids)
  guard !within(doc, anchor(at), picked) else { return None }
  let taken = []
  guard take(doc, picked, taken) is Some(rest) else { return None }
  done(place(rest, at, taken), Some(picked[0]))
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
  let roots = doc.roots.copy()
  let r = roots[path[0]]
  fn side_at(j : Int) -> @tree.Side {
    if j < r.sides.length() {
      r.sides[j]
    } else {
      @tree.Right
    }
  }

  match path.length() {
    1 => {
      roots[path[0]] = { ..r, sides: r.sides.map(flipped) }
      Some({ doc: { ..doc, roots, }, focus: Some(id) })
    }
    2 => {
      let sides = r.sides.copy()
      sides[path[1]] = flipped(side_at(path[1]))
      roots[path[0]] = { ..r, sides, }
      Some({ doc: { ..doc, roots, }, focus: Some(id) })
    }
    depth => {
      let side = flipped(side_at(path[1]))
      let mut next = fresh(doc)
      let taken = []
      guard take(doc, [id], taken) is Some(rest) else { return None }
      let mut wrapped = taken[0]
      // 項目は相対記法で深さを持たないので、飛びを綴れない。直に深さ 2 へ
      if !(wrapped is ListNode(_)) {
        for _ in 0..<(depth - 2) {
          wrapped = @tree.ImplicitNode({ id: next, children: [wrapped] })
          next = next + 1
        }
      }
      done(append(rest, node=id_of(r.node), side~, [wrapped]), Some(id))
    }
  }
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
  content : @tree.Content,
) -> Done? {
  guard holder(doc, at) is Some(o) else { return None }
  let b : @tree.Block = { id: fresh(doc), content }
  done(body(doc, node=o, bs => put(bs, at, [b])), Some(b.id))
}

///|
fn set_block(doc : @tree.Doc, id : Int, content : @tree.Content) -> Done? {
  guard owner(doc, block=id) is Some(o) else { return None }
  done(
    body(doc, node=o, bs => {
      bs.map(b => if b.id == id { { id, content } } else { b })
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
    bs.map(b => { id: b.id + by, content: b.content })
  }

  fn list(l : @tree.ListNode) -> @tree.ListNode {
    { ..l, id: l.id + by, body: blocks(l.body), children: l.children.map(list) }
  }

  match n {
    HeadingNode(h) =>
      @tree.HeadingNode({
        ..h,
        id: h.id + by,
        body: blocks(h.body),
        children: h.children.map(c => shift(c, by)),
      })
    ListNode(l) => @tree.ListNode(list(l))
    ImplicitNode(g) =>
      @tree.ImplicitNode({
        id: g.id + by,
        children: g.children.map(c => shift(c, by)),
      })
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
  // 一番外の中身を、行のノードになる段落と、body へ行く中身に分ける
  let labels : Array[String] = []
  let rest : Array[@tree.Block] = []
  for b in sub.body {
    let ls = match b.content {
      Opaque(text) => @tree.lines(text)
      _ => None
    }
    match ls {
      Some(ls) => labels.append(ls)
      None => rest.push(b)
    }
  }
  // 行のノードは文書に無い番号から、断片の id はその先へ寄せる
  let first = fresh(doc)
  let by = first + labels.length() - (@tree.doc_id + 1)
  let heads = labels.mapi((k, label) => make(sign, first + k, label))
  let prose = rest.map(b => {
    ({ id: b.id + by, content: b.content } : @tree.Block)
  })
  let subs = peel(sub.roots.map(r => r.node)).map(n => {
    respell(shift(n, by), sign)
  })
  let nodes = [..heads, ..subs]
  let mut cur = doc
  if !prose.is_empty() {
    guard host != @tree.doc_id else { return None }
    guard body(cur, node=host, bs => [..bs, ..prose]) is Some(d) else {
      return None
    }
    cur = d
  }
  if nodes.is_empty() {
    return Some({ doc: cur, focus: Some(prose[0].id) })
  }
  done(place(cur, at, nodes), Some(id_of(nodes[0])))
}

///|
/// 根が Implicit 1 つだけなら、その子たちを根にする。飛びが何段でも剥がす。
/// 途中の飛び（子の中の Implicit）は綴りなので触らない。
fn peel(roots : Array[@tree.Node]) -> Array[@tree.Node] {
  match roots {
    [ImplicitNode(g)] => peel(g.children)
    _ => roots
  }
}

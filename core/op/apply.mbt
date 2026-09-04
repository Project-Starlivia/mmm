// 操作を木に当てる。Op は道具の組み合わせで、型の異種性には触らない。
//
// None は「できない操作」。ts は spec どおり押す前に沈めるので、core は静かに断る。
// 途中で失敗しても元の doc は変わらない（道具が純粋なので）。

///|
/// **md に書ける木しか返さない。** 何が書けないかは check が 1 つで言う
/// （骨格の直前の水平線・見出しに飲み込まれる項目・項目の根の側）ので、
/// 操作ごとに規則を写さず、組んだ結果を check に通して断る。
pub fn apply(doc : @tree.Doc, op : Op) -> Done? {
  match attempt(doc, op) {
    Some(d) if @tree.check(d.doc).is_empty() => Some(d)
    _ => None
  }
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
    ImplicitNode(g) =>
      @tree.HeadingNode({
        id: g.id,
        label,
        fold: None,
        body: [],
        children: g.children,
      })
  }
  done(splice(doc, id, _ => [m]), Some(id))
}

///|
/// 定義ごと畳む。名前はラベル（書けなければ名無し）。畳み済みなら open だけ替わる。
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
    ImplicitNode(_) => return None
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
/// 選んだものを文書順に消す。知らない id が 1 つでもあれば None。
/// 中身を消したら、その持ち主が focus（消した後に選ぶべきもの）。ノードを消した
/// 後に選ぶものは無い — 隣を選ぶのは UI の仕事（目印で追う）
fn delete(doc : @tree.Doc, ids : Array[Int]) -> Done? {
  guard !ids.is_empty() && ids.all(id => has(doc, id)) else { return None }
  let mut cur = doc
  let mut focus = None
  for id in pick(doc, ids) {
    if owner(cur, block=id) is Some(o) {
      focus = Some(o)
    }
    guard erase(cur, id) is Some(d) else { return None }
    cur = d
  }
  // 持ち主ごと消えていれば、選ぶものは無い
  Some({ doc: cur, focus: focus.filter(o => has(cur, o)) })
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
/// 席が指している id。
fn anchor(at : NodePlace) -> Int {
  match at {
    Before(node~) => node
    After(node~) => node
    In(node~, ..) => node
  }
}

///|
/// 新しいノードを差す。綴りは隣に従う。根の隣（`In(doc_id)`）は最後の根に従う。
fn add_node(doc : @tree.Doc, at : NodePlace, labels : Array[String]) -> Done? {
  guard !labels.is_empty() else { return None }
  let first = fresh(doc)
  fn news(sign : @tree.Sign) -> Array[@tree.Node] {
    labels.mapi((k, label) => make(sign, first + k, label))
  }

  let sign = match at {
    Before(node~) => {
      guard find(doc, node) is Some(n) else { return None }
      sign_of(n)
    }
    After(node~) => {
      guard find(doc, node) is Some(n) else { return None }
      sign_of(n)
    }
    In(node~, ..) =>
      if node == @tree.doc_id {
        match doc.roots.last() {
          Some(r) => sign_of(r.node)
          None => @tree.Heading
        }
      } else {
        guard find(doc, node) is Some(n) else { return None }
        sign_in(n)
      }
  }
  done(place(doc, at, news(sign)), Some(first))
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
      let root_id = id_of(r.node)
      // 根の Implicit は引き出す相手しか持たないことがある。掃除で消えた根は、
      // 引き出したものを子に置き直す。
      match find(rest, root_id) {
        Some(_) => done(append(rest, node=root_id, side~, [wrapped]), Some(id))
        None => {
          let roots = rest.roots.copy()
          roots.insert(path[0], {
            node: @tree.ImplicitNode({ id: root_id, children: [wrapped] }),
            sides: [side],
          })
          Some({ doc: { ..rest, roots, }, focus: Some(id) })
        }
      }
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
/// md を読んで、根たちを席に差す。側は捨て、綴りは読んだまま。
/// 先頭の散文は行き先の親の body 末尾へ（In なら node 自身、根の間なら doc の散文）。
fn graft(doc : @tree.Doc, at : NodePlace, md : String) -> Done? {
  let sub = @tree.parse(md)
  guard !(sub.roots.is_empty() && sub.body.is_empty()) else { return None }
  let by = fresh(doc) - (@tree.doc_id + 1)
  let prose = sub.body.map(b => {
    ({ id: b.id + by, content: b.content } : @tree.Block)
  })
  let subs = sub.roots.map(r => shift(r.node, by))
  let host = match at {
    In(node~, ..) => node
    _ => {
      guard parent(doc, anchor(at)) is Some(p) else { return None }
      p
    }
  }
  let mut cur = doc
  if !prose.is_empty() {
    guard body(cur, node=host, bs => [..bs, ..prose]) is Some(d) else {
      return None
    }
    cur = d
  }
  if subs.is_empty() {
    return Some({ doc: cur, focus: None })
  }
  done(place(cur, at, subs), Some(id_of(subs[0])))
}

// 操作を木に当てる。Op は道具の組み合わせで、型の異種性には触らない。
//
// None は「できない操作」。ts は spec どおり押す前に沈めるので、core は静かに断る。
// 途中で失敗しても元の doc は変わらない（道具が純粋なので）。

///|
pub fn apply(doc : @tree.Doc, op : Op) -> Done? {
  match op {
    Rename(id~, label~) => rename(doc, id, label)
    Fold(id~, open~) => fold(doc, id, open)
    Unfold(id~) => unfold(doc, id)
    Delete(ids~) => delete(doc, ids)
    Add(at~, labels~) => add(doc, at, labels)
    Wrap(id~, label~) => wrap(doc, id, label)
    Move(ids~, at~) => move_nodes(doc, ids, at)
    FlipSide(id~) => flip(doc, id)
    _ => None
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

  let m = match n {
    HeadingNode(h) => @tree.HeadingNode({ ..h, fold: Some(folding(h.label)) })
    ListNode(l) => @tree.ListNode({ ..l, fold: Some(folding(l.label)) })
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
fn delete(doc : @tree.Doc, ids : Array[Int]) -> Done? {
  guard !ids.is_empty() && ids.all(id => has(doc, id)) else { return None }
  let mut cur = doc
  for id in pick(doc, ids) {
    guard erase(cur, id) is Some(d) else { return None }
    cur = d
  }
  Some({ doc: cur, focus: None })
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
/// 新しいノードを差す。綴りは隣に従う。
fn add(doc : @tree.Doc, at : NodePlace, labels : Array[String]) -> Done? {
  guard !labels.is_empty() else { return None }
  let first = fresh(doc)
  fn news(sign : @tree.Sign) -> Array[@tree.Node] {
    labels.mapi((k, label) => make(sign, first + k, label))
  }

  let out = match at {
    Before(node~) => {
      guard find(doc, node) is Some(n) else { return None }
      splice(doc, node, x => [..news(sign_of(n)), x])
    }
    After(node~) => {
      guard find(doc, node) is Some(n) else { return None }
      splice(doc, node, x => [x, ..news(sign_of(n))])
    }
    In(node~, side~) => {
      let sign = if node == @tree.doc_id {
        @tree.Heading
      } else {
        guard find(doc, node) is Some(n) else { return None }
        sign_in(n)
      }
      append(doc, node~, side?, news(sign))
    }
  }
  done(out, Some(first))
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
fn move_nodes(doc : @tree.Doc, ids : Array[Int], at : NodePlace) -> Done? {
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
      for _ in 0..<(depth - 2) {
        wrapped = @tree.ImplicitNode({ id: next, children: [wrapped] })
        next = next + 1
      }
      done(append(rest, node=id_of(r.node), side~, [wrapped]), Some(id))
    }
  }
}

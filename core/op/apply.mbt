// 操作を木に当てる。Op は道具の組み合わせで、型の異種性には触らない。
//
// None は「できない操作」。ts は spec どおり押す前に沈めるので、core は静かに断る。
// 途中で失敗しても元の doc は変わらない（道具が純粋なので）。

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
/// **席が綴りを借りる相手。** 隣が居れば隣、居なければ In の先（親）。
///
/// 落ち方を 1 つにしてある — 種類（`sign_at`）と綴り（`spell_at`）が別々に落ちると、
/// 子の居ない `* a` の下で**種類だけ親を継ぎ、マーカーは既定に落ちて** `- b` が
/// `* a` の子として書かれる。同じ列にマーカーが混ざる（#243）。
///
/// 文書（`doc_id`）は綴りを持たないので、根が 1 つも無ければ None
fn follows(doc : @tree.Doc, at : NodePlace) -> @tree.Node? {
  match neighbor(doc, at) {
    Some(n) => Some(n)
    None =>
      match at {
        In(node~, ..) if node != @tree.doc_id => find(doc, node)
        _ => None
      }
  }
}

///|
/// 席の綴りの種類。借りる相手に従う（項目の下は項目、それ以外は見出し。
/// 根が無い文書は見出し）。席が無ければ None。
fn sign_at(doc : @tree.Doc, at : NodePlace) -> @tree.Sign? {
  match follows(doc, at) {
    Some(n) => Some(sign_or_heading(n))
    None =>
      if at is In(node~, ..) && node == @tree.doc_id {
        Some(Heading)
      } else {
        None
      }
  }
}

///|
/// 席の項目の綴り（マーカー・字下げ幅・詰め）。借りる相手が項目でなければ
/// `@tree.bullet`。**種類と同じ相手から借りる**（`follows`。#243）
fn spell_at(doc : @tree.Doc, at : NodePlace) -> @tree.Mark {
  match follows(doc, at).bind(n => n.mark) {
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
/// 深さを保って反対側の末尾へ置き直す（`haul`）。
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
    depth => haul(doc, path[0], id, side=flipped(side_at(r, path[1])), depth~)
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
/// 深いノードを反対側の末尾へ置き直す。**動くのは選んだノードだけで、深さは保つ**
/// （読みの境界と同じ形。docs/spec.md「水平線」）。
///
/// - 行き先の側の最後の子が同じ側なら、間に境界は書かれない。その子の部分木の尻へ
///   深さのまま入る — md に書けば読みが置く親（`sink`）。戻すときも同じ規則なので、
///   元の親が右の最後の枝でなければ元の木にはならない（元の位置へは D&D か undo）
/// - そうでなければ境界が書かれるので、根の子の席から Implicit が深さを埋める
///
/// 元の側に残った Implicit は子が尽きていれば門（`mend`）が消す
/// `at` は根の添字。抜くのは深さ 3 以上なので、抜いた後も根の並びは変わらない
fn haul(
  doc : @tree.Doc,
  at : Int,
  id : Int,
  side~ : @tree.Side,
  depth~ : Int,
) -> @tree.Doc? {
  let taken = []
  guard take(doc, [id], taken) is Some(rest) else { return None }
  let x = taken[0]
  let next : Ref[Int] = { val: fresh(doc), }
  let t = rest.roots[at]
  if last_filled(t.node) is Some(j) && side_at(t, j) == side {
    let kids = t.node.children.copy()
    kids[j] = sink(kids[j], 2, x, depth, next)
    let roots = rest.roots.copy()
    roots[at] = { ..t, node: { ..t.node, children: kids, }, }
    return Some({ ..rest, roots, })
  }
  append(rest, node=t.node.id, side~, [gaps(x, depth - 2, next)])
}

///|
/// 子を持つ最後の子の添字。抜き取りで空になった Implicit の鎖（`hollow`）は数えない —
/// 門が消すので、行き先の隣にはならない
fn last_filled(n : @tree.Node) -> Int? {
  for i = n.children.length() - 1; i >= 0; i = i - 1 {
    if !hollow(n.children[i]) {
      return Some(i)
    }
  }
  None
}

///|
/// 行が 1 つも無い Implicit の鎖か。
fn hollow(n : @tree.Node) -> Bool {
  n.mark is None && n.children.iter().all(hollow)
}

///|
/// 深さ `at` のノード `n` の部分木の尻へ、深さ `depth` のまま `x` を入れる。md に
/// 書けば読みが置く親 — 尻の鎖で深さ `depth - 1` の行。鎖が浅く尽きれば、見出しは
/// 足りない段を Implicit が埋め、項目は尽きた所の子になる（項目の深さは入れ物が決める）
fn sink(
  n : @tree.Node,
  at : Int,
  x : @tree.Node,
  depth : Int,
  next : Ref[Int],
) -> @tree.Node {
  if at >= depth - 1 {
    return { ..n, children: [..n.children, x], }
  }
  match n.children.last() {
    Some(k) => {
      let kids = n.children.copy()
      kids[kids.length() - 1] = sink(k, at + 1, x, depth, next)
      { ..n, children: kids, }
    }
    None if @tree.sign_of(x) is Some(Item) => { ..n, children: [x], }
    None => { ..n, children: [gaps(x, depth - 1 - at, next)], }
  }
}

///|
/// `x` を `count` 枚の Implicit で包む（深さを保つ足場）。
fn gaps(x : @tree.Node, count : Int, next : Ref[Int]) -> @tree.Node {
  let mut wrapped = x
  for _ in 0..<count {
    wrapped = {
      id: next.val,
      label: "",
      fold: None,
      body: [],
      children: [wrapped],
      mark: None,
    }
    next.val = next.val + 1
  }
  wrapped
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

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

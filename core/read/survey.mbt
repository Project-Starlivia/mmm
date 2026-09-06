// md を読んだもの — 木（View）と地番（Spot）と原文。打鍵 1 回ぶんの読みの結果で、
// ts はこれを持ち手として持ち、問い合わせで読む。木も地番も core から出ない。

///|
pub(all) struct Survey {
  md : String
  view : @view.View
  spots : Map[Int, @tree.Spot]
}

///|
/// 打鍵 1 回ぶんの読み。読みは打鍵ごとに 1 回に保つ
pub fn survey(md : String) -> Survey {
  let (doc, spots) = @tree.survey(md)
  { md, view: @view.project(doc), spots, }
}

///|
/// 木のノードを文書順に（親が先）
pub fn each_node(view : @view.View, f : (@view.Node) -> Unit) -> Unit {
  fn walk(n : @view.Node) -> Unit {
    f(n)
    for k in n.children {
      walk(k)
    }
  }

  for t in view.roots {
    walk(t.node)
  }
}

///|
/// id がノードのものか（中身の id なら false）。木を辿って確かめる —
/// ノードと中身は同じ通し番号を分け合うので、種類は木の形からしか読めない
pub fn Survey::is_node(self : Survey, id : Int) -> Bool {
  let mut found = false
  each_node(self.view, n => if n.id == id { found = true })
  found
}

///|
/// 木が 1 つも無い（白紙）
pub fn Survey::empty(self : Survey) -> Bool {
  self.view.roots.length() == 0
}

///|
/// その字のノード（文書順で最初）。見本の md から id を引くため
pub fn Survey::find(self : Survey, label : String) -> Int? {
  let mut hit : Int? = None
  each_node(self.view, n => {
    if hit is None && n.label == Some(label) {
      hit = Some(n.id)
    }
  })
  hit
}

///|
/// そのノードの中身の id、文書順
pub fn Survey::blocks(self : Survey, id : Int) -> Array[Int] {
  let mut out : Array[Int] = []
  each_node(self.view, n => if n.id == id { out = n.blocks.map(b => b.id) })
  out
}

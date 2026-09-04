// 反映を試す道具。木を決まった形で少し変え、反映を通す。
//
// 操作そのものではない（操作は別の段）。lab が「このノードをこう変えたら
// md はどこが変わるか」を見るのと、総当たりの法則テストが同じ変え方を回すのに使う。

///|
/// 変え方。
pub enum Change {
  /// ラベルの尻に `!` を足す
  Relabel
  /// ノードを部分木ごと消す
  Delete
  /// 子を 1 つ足す（項目の子は項目）
  Adopt
} derive(Eq, Debug)

///|
/// 名前から変え方へ。lab の select の値がそのまま来る。
pub fn change_of(name : String) -> Change? {
  match name {
    "relabel" => Some(Relabel)
    "delete" => Some(Delete)
    "adopt" => Some(Adopt)
    _ => None
  }
}

///|
/// 試した結果。編集列と、当てた後の md。
pub(all) struct Trial {
  edits : Array[Edit]
  out : String
} derive(ToJson)

///|
pub fn trial(md : String, id : Int, how : Change) -> Trial {
  let (before, spans) = survey(md)
  let edits = reflect(md, before, spans, changed(before, id, how))
  { edits, out: apply(md, edits) }
}

///|
/// id のノードを how で変えた木。
pub fn changed(doc : Doc, id : Int, how : Change) -> Doc {
  morph(doc, id, x => {
    match how {
      Relabel =>
        Some(
          match x {
            HeadingNode(h) => HeadingNode({ ..h, label: h.label + "!" })
            ListNode(l) => ListNode({ ..l, label: l.label + "!" })
            other => other
          },
        )
      Delete => None
      Adopt =>
        Some(with_children(x, children_of(x) + [newborn(x is ListNode(_))]))
    }
  })
}

///|
/// 新しいノード（id は読みが振る番号と被らない）。項目の子は項目。
pub fn newborn(item : Bool) -> Node {
  if item {
    ListNode({ id: 999, label: "new", fold: None, body: [], children: [] })
  } else {
    HeadingNode({ id: 999, label: "new", fold: None, body: [], children: [] })
  }
}

///|
/// 木の全ノードの id（文書順）。
pub fn all_ids(doc : Doc) -> Array[Int] {
  let out = []
  fn go(x : Node) {
    out.push(id_of(x))
    for k in children_of(x) {
      go(k)
    }
  }

  for r in doc.roots {
    go(r.node)
  }
  out
}

///|
/// id のノードを f で置き換えた Doc。None なら消す。根の側は子と並走を保ち、
/// 子を失った Implicit は在り得ない（check が言う）ので一緒に消える。
pub fn morph(doc : Doc, id : Int, f : (Node) -> Node?) -> Doc {
  let roots = []
  for r in doc.roots {
    if id_of(r.node) == id {
      match f(r.node) {
        Some(n) => roots.push(({ node: n, sides: fit(r.sides, n) } : Root))
        None => ()
      }
    } else {
      let (kids, sides) = morph_kids(children_of(r.node), r.sides, id, f)
      if r.node is ImplicitNode(_) && kids.is_empty() {
        continue
      }
      roots.push(({ node: with_children(r.node, kids), sides } : Root))
    }
  }
  { ..doc, roots, }
}

///|
fn morph_kids(
  kids : Array[Node],
  sides : Array[Side],
  id : Int,
  f : (Node) -> Node?,
) -> (Array[Node], Array[Side]) {
  let out = []
  let out_sides = []
  for i, k in kids {
    let side = if i < sides.length() { sides[i] } else { Right }
    if id_of(k) == id {
      match f(k) {
        Some(n) => {
          out.push(n)
          out_sides.push(side)
        }
        None => ()
      }
    } else {
      let (kk, _) = morph_kids(children_of(k), [], id, f)
      if k is ImplicitNode(_) && kk.is_empty() {
        continue
      }
      out.push(with_children(k, kk))
      out_sides.push(side)
    }
  }
  (out, out_sides)
}

///|
fn fit(sides : Array[Side], node : Node) -> Array[Side] {
  let n = children_of(node).length()
  Array::makei(n, i => if i < sides.length() { sides[i] } else { Right })
}

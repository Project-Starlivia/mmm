// 印。選択の塗り・輪・針・落とし先の線。値は host が持ち、ここは塗るだけ

///|
/// 選択を塗る。md が持つ間は**輪**（箱の内側）、地図が持つ間は **selected**（枠）。
/// 輪と枠は「誰が持っているか」の印（spec.md「選択の持ち主」）
fn Mindmap::paint_choice(self : Mindmap) -> Unit {
  let ids = (self.host.selection)().ids
  let md = (self.host.holder)() is Md
  self.renderer.paint(if md { [] } else { ids })
  self.ring(if md { ids } else { [] })
}

///|
/// 輪を、掛かっているノードの**内側**へ重ねる。箱の無い（畳まれて埋もれた）ノードには
/// 出さない。本数が変わったときだけ作り足す / 捨てる
fn Mindmap::ring(self : Mindmap, ids : Array[Int]) -> Unit {
  let boxes = self.rects_of(ids)
  while self.caret_rings.length() > boxes.length() {
    match self.caret_rings.pop() {
      Some(r) => r.remove()
      None => ()
    }
  }
  while self.caret_rings.length() < boxes.length() {
    let doc = self.renderer.doc
    let ring = @web.el(doc, "rect", [("class", "caret-ring")])
    self.caret_layer.append(ring.as_node())
    self.caret_rings.push(ring)
  }
  for i, b in boxes {
    let ring = self.caret_rings[i]
    ring.setAttribute("x", @web.num(b.x + ring_inset))
    ring.setAttribute("y", @web.num(b.y + ring_inset))
    ring.setAttribute("width", @web.num(b.w - ring_inset * 2.0))
    ring.setAttribute("height", @web.num(b.h - ring_inset * 2.0))
  }
}

///|
/// 見失った選択（無ければ根）を控えめな針で指す。決めは map/indicator.mbt が持つ
fn Mindmap::update_indicator(self : Mindmap) -> Unit {
  let pane = self.pane_size()
  let sel = self.rects_of((self.host.selection)().ids)
  // 見失ったかは、選択があれば選択の話。無ければ文書の話
  let watched = if sel.length() > 0 { sel } else { self.all_rects() }
  // 指す先は、選択ならいちばん近いやつ。無ければ根 — 帰る場所は 1 つでいい
  let target = if !@map.is_lost(watched, self.camera, pane) {
    None
  } else if sel.length() > 0 {
    @map.nearest(sel, self.camera, pane)
  } else {
    @map.root_box(self.layout).map(b => b.rect())
  }
  guard target is Some(r) else {
    @web.show(self.indicator_el, "block", false)
    return
  }
  let i = @map.indicator_for(r, self.camera, pane)
  @web.show(self.indicator_el, "block", true)
  @web.set_style(self.indicator_el, "left", @web.px(i.x))
  @web.set_style(self.indicator_el, "top", @web.px(i.y))
  @web.set_style(
    self.indicator_el,
    "transform",
    "translate(-50%, -50%) rotate(\{@web.num(i.angle)}deg)",
  )
}

///|
/// 落とし先の印を今の drop に合わせる。前の印は消してから塗り直す
fn Mindmap::paint_drop(self : Mindmap) -> Unit {
  self.clear_drop_mark()
  match self.drop {
    None => ()
    Some(Side(root~, ..)) => self.mark_drop_parent(root)
    Some(Node(id~, pos~)) =>
      if pos == 0 {
        self.mark_drop_parent(id)
      } else {
        guard self.layout.boxes.get(id) is Some(b) else { return }
        let y = if pos == 1 { b.y } else { b.y + b.h }
        self.drop_line.setAttribute("x1", @web.num(b.x))
        self.drop_line.setAttribute("x2", @web.num(b.x + b.w))
        self.drop_line.setAttribute("y1", @web.num(y))
        self.drop_line.setAttribute("y2", @web.num(y))
        self.drop_line.setAttribute("visibility", "visible")
      }
  }
}

///|
fn Mindmap::mark_drop_parent(self : Mindmap, id : Int) -> Unit {
  match self.renderer.node_el(id) {
    Some(g) => @web.toggle_class(g, "drop-parent", true)
    None => ()
  }
  self.drop_parent = Some(id)
}

///|
/// 予告の印（drop-parent と drop-line）を消す
fn Mindmap::clear_drop_mark(self : Mindmap) -> Unit {
  match self.drop_parent {
    Some(id) => {
      match self.renderer.node_el(id) {
        Some(g) => @web.toggle_class(g, "drop-parent", false)
        None => ()
      }
      self.drop_parent = None
    }
    None => ()
  }
  self.drop_line.setAttribute("visibility", "hidden")
}

///|
/// ファイルのドラッグ中、その画面の点に落ちる先を予告する（app/disk/drop.mbt）。
/// None は予告を消す合図。当たった先のノードの id（無ければ None）を返す —
/// ドラッグ中はノードの部分木を弾く理由が無いので、落とし先の判定は使わず
/// `node_at` だけで決める
pub fn Mindmap::mark_file_drop(self : Mindmap, at : @map.Pt?) -> Int? {
  self.clear_drop_mark()
  guard at is Some(p) else { return None }
  let id = self.node_at(p.x, p.y)
  match id {
    Some(id) => self.mark_drop_parent(id)
    None => ()
  }
  id
}

// 入ってくるもの。ホイール・ポインタ（押す・動かす・離す、掴んで落とす）・クリック・長押し・
// キー・右クリック。出来事を受けて判断（core/map）に繋ぐところまでで、意味はここに無い。
// 何をするかは act.mbt、印は marks.mbt

///|
/// 押したまま離すのを待つノード（指、または選んでいる箱をマウスで）。動かさずに離せば選ぶ
pub struct Press {
  id : Int
  x : Double
  y : Double
}

///|
/// パンの始まり。押した画面の点と、そのときの視点
pub struct Panning {
  px : Double
  py : Double
  ox : Double
  oy : Double
}

///|
/// 動かしているノード。ids は選んだ全部（文書順）、subtree はその子孫込み（落とし先から外す）
pub struct Dragging {
  ids : Array[Int]
  subtree : Array[Int]
}

///|
/// 見え方を変える入力（ホイールのズームとスクロール）。動かし方そのものは map/camera.mbt
fn Mindmap::bind_wheel(self : Mindmap) -> Unit {
  @web.listen(self.pane.as_element(), "wheel", e => {
    @web.prevent(e)
    let m = @web.mouse(e)
    let (dx, dy) = @web.delta(e)
    if m.ctrlKey || m.metaKey {
      let p = self.at(m.clientX, m.clientY)
      self.set_camera(@map.zoom_at(self.camera, p.x, p.y, dy))
    } else if m.shiftKey {
      // Shift+ホイールは横スクロール（縦の目盛りしか出さないマウス用）
      self.set_camera(
        @map.pan_by(self.camera, -(if dy != 0 { dy } else { dx }), 0),
      )
    } else {
      self.set_camera(@map.pan_by(self.camera, -dx, -dy))
    }
  })
}

///|
fn far(x : Double, y : Double, p : Press) -> Bool {
  @math.hypot(x - p.x, y - p.y) > slop
}

///|
fn Mindmap::cursor(self : Mindmap, v : String) -> Unit {
  @web.set_style(self.pane.as_element(), "cursor", v)
}

///|
/// 背景の左ドラッグは矩形選択、パンは中クリック / Space+ドラッグ / 指の 1 本。
/// **指は 1 本でも 2 本でも台帳に載せる** — 載らなかった指の pointermove が
/// 「1 本ぶん」の流れへ落ちると、別の指の始点との差で地図が跳ぶ。capture で
/// 取るのは、リンクの ↗ が pointerdown を止めるため
fn Mindmap::bind_pointer(self : Mindmap) -> Unit {
  let pane = self.pane.as_element()
  @web.listen(
    pane,
    "pointerdown",
    e => {
      guard @web.is_touch(e) else { return }
      let m = @web.mouse(e)
      let p = self.at(m.clientX, m.clientY)
      self.fingers.down(@web.pointer_id(e), p.x, p.y)
      // 2 本目が乗った時点で 1 本ぶんのパンは畳む。tapped も畳む —
      // 畳まなければピンチ中ずっと最初の指の場所に居座り、離したときに選んでしまう
      if self.fingers.pinching() {
        self.panning = None
        self.tapped = None
      }
    },
    capture=true,
  )
  @web.listen(pane, "pointerdown", e => self.pointer_down(e))
  @web.listen(pane, "pointermove", e => self.pointer_move(e))
  @web.listen(pane, "pointerup", e => self.pointer_end(e))
  @web.listen(pane, "pointercancel", e => self.pointer_end(e))
}

///|
fn Mindmap::pointer_down(self : Mindmap, e : @core.Any) -> Unit {
  guard @web.target_in(
      e, ".link-open, .image-connect, .pane-tool, .label-editor, .card-editor",
    )
    is None else {
    return
  }
  let touch = @web.is_touch(e)
  if touch && self.fingers.pinching() {
    return
  }
  // 長押しの印は次の押下で用済み（contextmenu を合成しない環境で残らないように）
  self.menu_by_hold = false
  let m = @web.mouse(e)
  guard m.button == 0 || m.button == 1 else { return }
  self.pane.focus()
  // カードと × の上の押下は、そのクリック（bind_click）のもの。ここで
  // ノードを選び直すと、pointerup が選択を作り直して picked を落とす
  guard @web.target_in(e, "[data-card], [data-delete]") is None else { return }
  let id = self.node_at(m.clientX, m.clientY)
  let pointer = @web.pointer_id(e)
  // パンは 3 つ入り口を持つ: 中クリック / Space+ドラッグ / 指で背景をなぞる。
  // 担当する手が違うので、どれか 1 つでは塞がる場面がある
  if m.button == 1 || self.space_held || (touch && id is None) {
    self.panning = Some({
      px: m.clientX,
      py: m.clientY,
      ox: self.camera.tx,
      oy: self.camera.ty,
    })
    self.cursor("grabbing")
    @web.capture(self.pane.as_element(), pointer)
    @web.prevent(e)
    return
  }
  if touch {
    // 指は離したときに選ぶ（なぞったら選ばない）
    self.tapped = id.map(id => ({ id, x: m.clientX, y: m.clientY, } : Press))
    // 長押しは右クリックの代わり。動かさずに hold_ms 待てばメニューを開く
    let at : @map.Pt = { x: m.clientX, y: m.clientY, }
    self.hold_at = Some(at)
    self.hold = Some(
      @global.set_timeout(
        () => {
          let at = self.hold_at
          self.drop_hold()
          guard at is Some(at) else { return }
          self.tapped = None
          self.menu_by_hold = true
          self.open_menu(at.x, at.y)
        },
        hold_ms,
      ),
    )
    return
  }
  match id {
    Some(id) => {
      let mod : @map.Modifier = if m.shiftKey {
        Shift
      } else if m.ctrlKey || m.metaKey {
        Mod
      } else {
        Plain
      }
      let sel = (self.host.selection)()
      // 選んでいる箱をそのまま押したなら、1 つに畳むのは離したとき（指と同じ）。
      // 押した瞬間に畳むと、複数選択を掴んで動かす手が無くなる
      if mod is Plain && sel.ids.contains(id) {
        self.tapped = Some({ id, x: m.clientX, y: m.clientY, })
      } else {
        (self.host.set_selection)(
          @map.click(sel, id, mod, self.layout.order),
          true,
        )
        self.drag_cand = Some({ id, x: m.clientX, y: m.clientY, })
      }
      @web.capture(self.pane.as_element(), pointer)
      @web.prevent(e)
    }
    None => {
      // 背景。ドラッグすれば矩形選択、動かさずに離せば選択を解く
      self.rubber_start = Some(self.at(m.clientX, m.clientY))
      self.rubber_size = (0, 0)
      @web.capture(self.pane.as_element(), pointer)
      @web.prevent(e)
    }
  }
}

///|
fn Mindmap::pointer_move(self : Mindmap, e : @core.Any) -> Unit {
  let m = @web.mouse(e)
  if @web.is_touch(e) {
    let p = self.at(m.clientX, m.clientY)
    match self.fingers.moved(@web.pointer_id(e), p.x, p.y) {
      Some((from, to)) => {
        self.set_camera(@map.pinch(self.camera, from, to))
        return
      }
      None => ()
    }
    // 2 本乗っているあいだは、1 本ぶんの続きを進めない
    if self.fingers.pinching() {
      return
    }
  }
  match self.tapped {
    Some(t) if far(m.clientX, m.clientY, t) => {
      // 長押しが先にメニューを開いていれば tapped はもう無い（ここまで来ない）
      self.start_drag(t.id, m.clientX, m.clientY)
      self.tapped = None
    }
    _ => ()
  }
  match self.hold_at {
    Some(at) if @math.hypot(m.clientX - at.x, m.clientY - at.y) > slop =>
      self.drop_hold()
    _ => ()
  }
  match self.drag_cand {
    Some(c) if far(m.clientX, m.clientY, c) => {
      self.start_drag(c.id, m.clientX, m.clientY)
      self.drag_cand = None
    }
    _ => ()
  }
  if self.dragging is Some(_) {
    self.update_drop(m.clientX, m.clientY)
    return
  }
  match self.rubber_start {
    Some(s) => {
      let p = self.at(m.clientX, m.clientY)
      let x = @cmp.minimum(s.x, p.x)
      let y = @cmp.minimum(s.y, p.y)
      let w = (p.x - s.x).abs()
      let h = (p.y - s.y).abs()
      @web.show(self.rubber, "block", true)
      @web.set_style(self.rubber, "left", @web.px(x))
      @web.set_style(self.rubber, "top", @web.px(y))
      @web.set_style(self.rubber, "width", @web.px(w))
      @web.set_style(self.rubber, "height", @web.px(h))
      self.rubber_size = (w, h)
      let a = @map.to_world(self.camera, x, y)
      let b = @map.to_world(self.camera, x + w, y + h)
      (self.host.set_selection)(
        @map.rubber(self.layout, { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y, }),
        false,
      )
      return
    }
    None => ()
  }
  guard self.panning is Some(pan) else { return }
  self.set_camera({
    k: self.camera.k,
    tx: pan.ox + (m.clientX - pan.px),
    ty: pan.oy + (m.clientY - pan.py),
  })
}

///|
fn Mindmap::pointer_end(self : Mindmap, e : @core.Any) -> Unit {
  self.drop_hold()
  let up = @web.event_type(e) == "pointerup"
  match self.dragging {
    Some(d) => {
      // cancel は取り消しなので、印だけ消して Op は投げない
      match self.drop {
        Some(drop) if up =>
          (self.host.apply)(@map.drop_op(drop, d.ids), false) |> ignore
        _ => ()
      }
      self.end_drag()
    }
    None => {
      self.drag_cand = None
      // 選ぶのは離したとき（pointerup）だけ。cancel は取り消しなので選ばずに捨てる
      match self.tapped {
        Some(t) if up =>
          (self.host.set_selection)(
            @map.click((self.host.selection)(), t.id, Plain, self.layout.order),
            true,
          )
        _ => ()
      }
      self.tapped = None
      if self.rubber_start is Some(_) {
        let (w, h) = self.rubber_size
        let dragged = w > 3 || h > 3
        @web.show(self.rubber, "block", false)
        self.rubber_start = None
        if !dragged {
          (self.host.set_selection)(@map.none, false)
        }
      }
    }
  }
  if @web.is_touch(e) {
    self.lift_finger(@web.pointer_id(e))
    // 組が壊れて残った指でパンを立て直したなら、その up ではない
    if self.panning is Some(_) && self.fingers.only() is Some(_) {
      return
    }
  }
  self.panning = None
  self.cursor(if self.space_held { "grab" } else { "" })
}

///|
/// 指が離れた。組が壊れて 1 本に戻ったら、その指から 1 本パンを立て直す
fn Mindmap::lift_finger(self : Mindmap, id : Int) -> Unit {
  let was_pinching = self.fingers.pinching()
  self.fingers.up(id)
  guard was_pinching else { return }
  match self.fingers.only() {
    Some(solo) if !self.fingers.pinching() => {
      let r = self.pane_rect()
      self.panning = Some({
        px: solo.x + r.left,
        py: solo.y + r.top,
        ox: self.camera.tx,
        oy: self.camera.ty,
      })
    }
    _ => ()
  }
}

///|
/// 選んだものとその子孫（文書順）。落とし先から外す部分木
fn Mindmap::subtree(self : Mindmap, ids : Array[Int]) -> Array[Int] {
  let l = self.layout
  let set : Set[Int] = Set::from_array(ids)
  // order は親が子より先なので、前から 1 回なめれば「親が部分木に居るか」で決まる
  for id in l.order {
    guard l.boxes.get(id) is Some(b) else { continue }
    if b.parent is Some(p) && set.contains(p.id) {
      set.add(id)
    }
  }
  l.order.filter(id => set.contains(id))
}

///|
/// 掴んで動かし始める。掴んだのが選択の中ならその全部（文書順）、外なら
/// 単独で選び直してそれ。落とし先から外す部分木は、選んだもの自身とその子孫
fn Mindmap::start_drag(
  self : Mindmap,
  id : Int,
  x : Double,
  y : Double,
) -> Unit {
  let mut sel = (self.host.selection)()
  if !sel.ids.contains(id) {
    sel = { ids: [id], anchor: Some(id), }
    (self.host.set_selection)(sel, false)
  }
  self.dragging = Some({ ids: sel.ids, subtree: self.subtree(sel.ids), })
  for nid in sel.ids {
    match self.renderer.node_el(nid) {
      Some(g) => @web.toggle_class(g, "dragging", true)
      None => ()
    }
  }
  self.update_drop(x, y)
}

///|
/// ポインタの今の場所から落とし先を計算し直し、予告を塗り直す
fn Mindmap::update_drop(self : Mindmap, x : Double, y : Double) -> Unit {
  guard self.dragging is Some(d) else { return }
  let p = self.at(x, y)
  let at = @map.to_world(self.camera, p.x, p.y)
  self.drop = @map.resolve(self.layout, at, d.subtree)
  self.paint_drop()
}

///|
/// ドラッグを終える。Op を投げるかどうかは呼び出し側が先に決めておく
fn Mindmap::end_drag(self : Mindmap) -> Unit {
  match self.dragging {
    Some(d) =>
      for id in d.ids {
        match self.renderer.node_el(id) {
          Some(g) => @web.toggle_class(g, "dragging", false)
          None => ()
        }
      }
    None => ()
  }
  self.dragging = None
  self.drop = None
  self.clear_drop_mark()
}

///|
/// リンクの ↗ と、読めていない画像の「繋ぐ」の字、カードと ×、ダブルクリックの編集
fn Mindmap::bind_click(self : Mindmap) -> Unit {
  let pane = self.pane.as_element()
  @web.listen(pane, "click", e => {
    match @web.attr_in(e, "[data-delete]", "data-delete") {
      Some(del) => {
        match int_of(del) {
          Some(id) => (self.host.apply)(Delete(ids=[id]), false) |> ignore
          None => ()
        }
        return
      }
      None => ()
    }
    if @web.target_in(e, ".image-connect") is Some(_) {
      (self.host.connect_assets)()
      return
    }
    match @web.attr_in(e, "[data-card]", "data-card") {
      Some(spot) => {
        match int_of(spot) {
          Some(id) =>
            (self.host.set_picked)(
              if (self.host.picked)() == Some(id) {
                None
              } else {
                Some(id)
              },
            )
          None => ()
        }
        return
      }
      None => ()
    }
    match @web.attr_in(e, ".link-open", "data-url") {
      Some(url) if url != "" => @web.open_url(url)
      _ => ()
    }
  })
  @web.listen(self.renderer.node_layer, "pointerdown", e => {
    if @web.target_in(e, ".link-open, .image-connect") is Some(_) {
      @web.stop(e)
    }
  })
  @web.listen(pane, "dblclick", e => {
    guard @web.target_in(
        e, ".link-open, .image-connect, .label-editor, .card-editor",
      )
      is None else {
      return
    }
    match @web.attr_in(e, "[data-card]", "data-card") {
      Some(spot) => {
        match int_of(spot) {
          Some(id) => {
            @web.prevent(e)
            self.edit_card(id)
          }
          None => ()
        }
        return
      }
      None => ()
    }
    let m = @web.mouse(e)
    guard self.node_at(m.clientX, m.clientY) is Some(id) else { return }
    @web.prevent(e)
    self.begin_edit(id, None) |> ignore
  })
}

///|
/// 長押しの待ち時計を止める。次に押すまで、待っていたことを覚えておかない
fn Mindmap::drop_hold(self : Mindmap) -> Unit {
  match self.hold {
    Some(t) => @global.clear_timeout(t)
    None => ()
  }
  self.hold = None
  self.hold_at = None
}

///|
/// 右クリック。触った箱が選ばれていなければそれへ選び直してから開く。長押しが
/// 開いた直後の（触った指が上げるときに走る）contextmenu は握り潰す — 二重に開かせない
fn Mindmap::bind_context_menu(self : Mindmap) -> Unit {
  @web.listen(self.pane.as_element(), "contextmenu", e => {
    @web.prevent(e)
    if self.menu_by_hold {
      self.menu_by_hold = false
      return
    }
    self.drop_hold()
    let m = @web.mouse(e)
    self.open_menu(m.clientX, m.clientY)
  })
}

///|
/// 地図の中だけで効くキー。全体のキーは app/shortcuts.mbt
fn Mindmap::bind_keys(self : Mindmap) -> Unit {
  let pane = self.pane.as_element()
  @web.listen(pane, "keydown", e => {
    let k = @web.keyboard(e)
    if k.isComposing || k.keyCode == 229 {
      return
    }
    if self.dragging is Some(_) && k.key == "Escape" {
      self.end_drag()
      @web.prevent(e)
      return
    }
    if k.key == " " {
      self.space_held = true
      self.cursor("grab")
      @web.prevent(e)
      return
    }
    let key : @map.Key = {
      key: k.key,
      shift: k.shiftKey,
      mod: k.ctrlKey || k.metaKey,
      alt: k.altKey,
    }
    let intent = match (self.host.picked)() {
      Some(picked) => @map.keyed_card(self.layout, picked, key)
      None => @map.keyed(self.layout, (self.host.selection)(), key)
    }
    guard intent is Some(i) else {
      // 表が断った Tab（選んでいない・前の兄弟が無い）でも、地図から焦点を逃がさない
      if k.key == "Tab" {
        @web.prevent(e)
      }
      return
    }
    @web.prevent(e)
    self.act(i)
  })
  @web.listen(pane, "keyup", e => {
    if @web.keyboard(e).key == " " {
      self.space_held = false
      if self.panning is None {
        self.cursor("")
      }
    }
  })
  // Space を押したままペインの外へフォーカスが抜けると keyup が来ない。
  // 持ったままになるとカーソルが grab に貼り付き、背景の左ドラッグが
  // ずっと矩形選択でなくパンになる
  @web.listen(pane, "focusout", _ => {
    self.space_held = false
    if self.panning is None {
      self.cursor("")
    }
  })
}

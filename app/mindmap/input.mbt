// 入ってくるもの。ホイール・ポインタ（押す・動かす・離す、掴んで落とす）・クリック・長押し・
// キー・右クリック。出来事を受けて判断（core/map）に繋ぐところまでで、意味はここに無い。
// 何をするかは act.mbt、印は marks.mbt

///|
/// 押しても地図の手が始まらないもの。自分で出来事を受ける — リンクの ↗、
/// 読めていない画像の「繋ぐ」、隅の道具、開いている欄
let interactive = ".link-open, .image-connect, .pane-tool, .label-editor, .card-editor"

///|
/// `interactive` のうち、ノードの層の中に在るもの。pointerdown をここで止め、
/// ペインの手（パン・矩形・掴み）に渡さない — 欄と道具は HTML で、SVG の外に居る
let card_links = ".link-open, .image-connect"

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
fn Mindmap::cursor(self : Mindmap, v : String) -> Unit {
  @web.set_style(self.pane.as_element(), "cursor", v)
}

///|
/// 手を離したときのカーソル。Space を持っていれば掴む手のまま
fn Mindmap::rest_cursor(self : Mindmap) -> Unit {
  self.cursor(if self.space_held { "grab" } else { "" })
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
      // 2 本目が乗った時点で 1 本ぶんの手は畳む — 畳まなければピンチ中ずっと
      // 最初の指の場所に居座り、離したときに選んでしまう
      if self.fingers.pinching() {
        match self.mode {
          Panning(_) => self.mode = Idle
          Holding(_, _) => self.drop_hold()
          _ => ()
        }
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
  guard @web.target_in(e, interactive) is None else { return }
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
  guard @web.target_in(e, "[\{data_card}], [\{data_delete}]") is None else {
    return
  }
  let id = self.node_at(m.clientX, m.clientY)
  let pointer = @web.pointer_id(e)
  // パンは 3 つ入り口を持つ: 中クリック / Space+ドラッグ / 指で背景をなぞる。
  // 担当する手が違うので、どれか 1 つでは塞がる場面がある
  if m.button == 1 || self.space_held || (touch && id is None) {
    self.mode = Panning({
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
  let at : @map.Pt = { x: m.clientX, y: m.clientY, }
  match id {
    Some(id) if touch => {
      // 指は離したときに選ぶ（なぞったら選ばない）。動かさず hold_ms 待てばメニュー
      let press : Press = { id, at, }
      self.mode = Holding(
        press,
        @global.set_timeout(
          () => {
            guard self.mode is Holding(_, _) else { return }
            self.mode = Idle
            self.menu_by_hold = true
            self.open_menu(at.x, at.y)
          },
          @map.hold_ms,
        ),
      )
      return
    }
    Some(id) => {
      let mod : @map.Modifier = if m.shiftKey {
        Shift
      } else if m.ctrlKey || m.metaKey {
        Mod
      } else {
        Plain
      }
      let sel = (self.host.selection)()
      // 選んでいる箱をそのまま押したなら、1 つに畳むのは離したとき（指と同じ）
      let tap = mod is Plain && sel.ids.contains(id)
      if !tap {
        (self.host.set_selection)(
          @map.click(sel, id, mod, self.layout.order),
          true,
        )
      }
      self.mode = Pressed({ id, at, }, tap~)
    }
    None =>
      // 背景。ドラッグすれば矩形選択、動かさずに離せば選択を解く
      self.mode = Rubber(start=self.at(m.clientX, m.clientY), size=(0, 0))
  }
  @web.capture(self.pane.as_element(), pointer)
  @web.prevent(e)
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
  let (x, y) = (m.clientX, m.clientY)
  match self.mode {
    Pressed(p, ..) if @map.far(p.at, x, y) => self.start_drag(p.id, x, y)
    Holding(p, t) if @map.far(p.at, x, y) => {
      @global.clear_timeout(t)
      self.start_drag(p.id, x, y)
    }
    Dragging(_) => self.update_drop(x, y)
    Rubber(start=s, ..) => {
      let p = self.at(x, y)
      let left = @cmp.minimum(s.x, p.x)
      let top = @cmp.minimum(s.y, p.y)
      let w = (p.x - s.x).abs()
      let h = (p.y - s.y).abs()
      @web.show(self.rubber, "block", true)
      @web.set_style(self.rubber, "left", @web.px(left))
      @web.set_style(self.rubber, "top", @web.px(top))
      @web.set_style(self.rubber, "width", @web.px(w))
      @web.set_style(self.rubber, "height", @web.px(h))
      self.mode = Rubber(start=s, size=(w, h))
      let a = @map.to_world(self.camera, left, top)
      let b = @map.to_world(self.camera, left + w, top + h)
      (self.host.set_selection)(
        @map.rubber(self.layout, { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y, }),
        false,
      )
    }
    Panning(pan) =>
      self.set_camera({
        k: self.camera.k,
        tx: pan.ox + (x - pan.px),
        ty: pan.oy + (y - pan.py),
      })
    _ => ()
  }
}

///|
fn Mindmap::pointer_end(self : Mindmap, e : @core.Any) -> Unit {
  // 選ぶのは離したとき（pointerup）だけ。cancel は取り消しなので選ばずに捨てる
  let up = @web.event_type(e) == "pointerup"
  let pick = (id : Int) => {
    (self.host.set_selection)(
      @map.click((self.host.selection)(), id, Plain, self.layout.order),
      true,
    )
  }
  match self.mode {
    Dragging(d) => {
      // cancel は取り消しなので、印だけ消して Op は投げない
      match d.drop {
        Some(drop) if up =>
          (self.host.apply)(@map.drop_op(drop, d.ids), false) |> ignore
        _ => ()
      }
      self.end_drag()
    }
    Pressed(p, tap~) => if tap && up { pick(p.id) }
    Holding(p, t) => {
      @global.clear_timeout(t)
      if up {
        pick(p.id)
      }
    }
    Rubber(size=(w, h), ..) => {
      @web.show(self.rubber, "block", false)
      if !(w > 3 || h > 3) {
        (self.host.set_selection)(@map.none, false)
      }
    }
    Panning(_) | Idle => ()
  }
  if @web.is_touch(e) {
    self.lift_finger(@web.pointer_id(e))
    // 組が壊れて残った指でパンを立て直したなら、その up ではない
    if self.mode is Panning(_) && self.fingers.only() is Some(_) {
      return
    }
  }
  self.mode = Idle
  self.rest_cursor()
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
      self.mode = Panning({
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
    sel = @map.Selection::only(id)
    (self.host.set_selection)(sel, false)
  }
  self.mode = Dragging({
    ids: sel.ids,
    subtree: @map.subtree(self.layout, sel.ids),
    drop: None,
  })
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
  guard self.mode is Dragging(d) else { return }
  let p = self.at(x, y)
  let at = @map.to_world(self.camera, p.x, p.y)
  d.drop = @map.resolve(self.layout, at, d.subtree)
  self.paint_drop(d.drop)
}

///|
/// ドラッグを終える。Op を投げるかどうかは呼び出し側が先に決めておく
fn Mindmap::end_drag(self : Mindmap) -> Unit {
  guard self.mode is Dragging(d) else { return }
  for id in d.ids {
    match self.renderer.node_el(id) {
      Some(g) => @web.toggle_class(g, "dragging", false)
      None => ()
    }
  }
  self.mode = Idle
  self.clear_drop_mark()
}

///|
/// 長押しの待ち時計を止める。次に押すまで、待っていたことを覚えておかない
fn Mindmap::drop_hold(self : Mindmap) -> Unit {
  guard self.mode is Holding(_, t) else { return }
  @global.clear_timeout(t)
  self.mode = Idle
}

///|
/// 的（かその中）の `attr` を数として読む。的がその属性を持つ要素の中でなければ None
fn id_in(e : @core.Any, attr : String) -> Int? {
  @web.attr_in(e, "[\{attr}]", attr).bind(s => {
    try @string.parse_int(s) catch {
      _ => None
    } noraise {
      v => Some(v)
    }
  })
}

///|
/// リンクの ↗ と、読めていない画像の「繋ぐ」の字、カードと ×、ダブルクリックの編集
fn Mindmap::bind_click(self : Mindmap) -> Unit {
  let pane = self.pane.as_element()
  @web.listen(pane, "click", e => {
    match id_in(e, data_delete) {
      Some(id) => {
        (self.host.apply)(Delete(ids=[id]), false) |> ignore
        return
      }
      None => ()
    }
    if @web.target_in(e, ".image-connect") is Some(_) {
      (self.host.connect_assets)()
      return
    }
    match id_in(e, data_card) {
      Some(id) => {
        (self.host.set_picked)(
          if (self.host.picked)() == Some(id) {
            None
          } else {
            Some(id)
          },
        )
        return
      }
      None => ()
    }
    match @web.attr_in(e, ".link-open", "data-url") {
      Some(url) if url != "" =>
        @web.open_url(self.pane.ownerDocument().unwrap(), url)
      _ => ()
    }
  })
  @web.listen(self.renderer.node_layer, "pointerdown", e => {
    if @web.target_in(e, card_links) is Some(_) {
      @web.stop(e)
    }
  })
  @web.listen(pane, "dblclick", e => {
    guard @web.target_in(e, interactive) is None else { return }
    match id_in(e, data_card) {
      Some(id) => {
        @web.prevent(e)
        self.edit_card(id)
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
    if self.mode is Dragging(_) && k.key == "Escape" {
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
    let answer = match (self.host.picked)() {
      Some(picked) => @map.keyed_card(self.layout, picked, key)
      None => @map.keyed(self.layout, (self.host.selection)(), key)
    }
    match answer {
      Do(i) => {
        @web.prevent(e)
        self.act(i)
      }
      // 拾ったが、いまはできない — ブラウザにも渡さない（端の ↓ でページが動かない。#244）
      Stop => @web.prevent(e)
      // 表が断った Tab でも、地図から焦点を逃がさない
      Pass => if k.key == "Tab" { @web.prevent(e) }
    }
  })
  @web.listen(pane, "keyup", e => {
    if @web.keyboard(e).key == " " {
      self.space_held = false
      if !(self.mode is Panning(_)) {
        self.cursor("")
      }
    }
  })
  // Space を押したままペインの外へフォーカスが抜けると keyup が来ない。
  // 持ったままになるとカーソルが grab に貼り付き、背景の左ドラッグが
  // ずっと矩形選択でなくパンになる
  @web.listen(pane, "focusout", _ => {
    self.space_held = false
    if !(self.mode is Panning(_)) {
      self.cursor("")
    }
  })
}

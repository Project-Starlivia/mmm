// マップのペイン。core が置いて描き、入力を受けて判断し、答えを host へ返す。
//
// 持っているのは視点（Camera）と、それを動かす入力（ホイール・ドラッグ・ピンチ・
// クリック・矩形・矢印・右クリック・長押し）と、見失った先を指す針だけ。
// **選択の値は持たない** — 入力を選択の値にして host へ渡し、host の値を塗るだけ。
// 値は EditorState の field（ts の state.ts）。判断（当たり・落とし先・キーの表・矢印・
// 寄せ・針）は全部 map/。ここはそれを DOM の出来事に繋ぐ。

///|
/// 全体を収めるときの余白（画面 px）
let fit_margin = 60.0

///|
/// 矢印で辿るとき、選んだ箱が縁から離れている距離（画面 px）
let show_margin = 40.0

///|
/// 長押しが右クリックメニューに化けるまでの間（ms）
let hold_ms = 500

///|
/// 押した点からこれだけ動けば「なぞった」（画面 px）
let slop = 8.0

///|
/// 輪を箱の内側へ入れる量
let ring_inset = 3.0

///|
/// 背景の格子 1 目盛り（world）
let grid = 18.0

///|
pub struct Mindmap {
  pane : @dom.HTMLElement
  host : Host
  /// world 座標の層。Camera の変換はこれに掛ける
  world : @dom.Element
  renderer : Renderer
  /// 白紙の言い出し（器は ts の app/hint.ts）
  hint : @dom.Element
  indicator_el : @dom.Element
  mut camera : @map.Camera
  mut layout : @map.Layout
  fingers : @map.Fingers
  mut panning : Panning?
  mut fit_pending : Bool
  /// ペインの画面上の矩形。None なら次に読む。resize でしか変わらない（アプリは
  /// スクロールしない）ので ResizeObserver が捨てる。毎イベント読み直すと、直前に
  /// world へ書いた scale のぶん SVG 全体のレイアウトを同期で走らせる —
  /// 5000 ノードで 1 ホイール 30ms（読むだけで）
  mut rect : @dom.DOMRect?
  /// カーソルの輪の層。world に浮かぶ別の印（ノードの子にすると、動くたびに中身が作り直される）
  caret_layer : @dom.Element
  caret_rings : Array[@dom.Element]
  /// 矩形選択の面（画面 px）。始点は pane の左上から
  rubber : @dom.Element
  mut rubber_start : @map.Pt?
  /// 矩形選択で引いた大きさ（画面 px）。離したとき「なぞったか」を見る
  mut rubber_size : (Double, Double)
  mut tapped : Press?
  mut grab : Bool
  /// Space を押している間、左ドラッグはパン
  mut space_held : Bool
  label : LabelField
  card : CardField
  /// 選んでいるカードに被せる枠と ×。world に浮かぶ 1 個の印
  pick : CardPick
  /// 長押しの待ち時計。無ければ待っていない
  mut hold : @global.Timer?
  /// 長押しを起こした指の押した場所。動かせば捨てる
  mut hold_at : @map.Pt?
  /// 直前に開いたメニューが長押しから来たか。続く contextmenu を握り潰すため
  mut menu_by_hold : Bool
  /// マウスで掴んだ候補。slop を越えたら start_drag へ化ける
  mut drag_cand : Press?
  mut dragging : Dragging?
  /// 今の落とし先の予告。無ければ離しても何もしない
  mut drop : @map.Drop?
  /// 予告で drop-parent を付けている箱の id。次の予告や後片付けで外す
  mut drop_parent : Int?
  /// 兄弟へ挿入する予告の線。world に浮かぶ
  drop_line : @dom.Element
  /// 右クリック（と長押し）のメニュー
  menu : @parts.Menu
}

///|
fn place_layout(host : Host) -> @map.Layout {
  @map.layout((host.survey)().doc.roots, @map.node_size(host.measure))
}

///|
/// ペインを地図の器にする
pub fn Mindmap::new(pane : @dom.HTMLElement, host : Host) -> Mindmap {
  let doc = pane.ownerDocument().unwrap()
  // この pane はマップの器になった。見た目（style.css の `.map-pane`）はここで付く
  @web.toggle_class(pane.as_element(), "map-pane", true)
  let svg = @web.el(doc, "svg", [("class", "map-svg")])
  let world = @web.el(doc, "g", [])
  let caret_layer = @web.el(doc, "g", [])
  let drop_line = @web.el(doc, "line", [
    ("class", "drop-line"),
    ("visibility", "hidden"),
  ])
  let renderer = Renderer::new(doc)
  let pick = CardPick::new(doc)
  world.append(renderer.edge_layer.as_node())
  world.append(renderer.node_layer.as_node())
  world.append(pick.el.as_node())
  world.append(caret_layer.as_node())
  world.append(drop_line.as_node())
  svg.append(world.as_node())
  pane.append(svg.as_node())
  let rubber = @web.html(doc, "div", "rubber").as_element()
  pane.append(rubber.as_node())
  let label = LabelField::new(doc, pane, host.measure, (id, label) => {
    (host.apply)(Rename(id~, label~), false) |> ignore
  })
  let card = CardField::new(doc, pane, host.measure, host.tokens_block, (
    id,
    text,
  ) => {
    (host.apply)(SetBlock(id~, content=None, source=Some(text)), false)
    |> ignore
  })
  // md からの始め方は md ペイン自身が同じ器で言う
  let hint = @parts.pane_hint(doc, "map")
  @web.show(hint, "flex", false)
  pane.append(hint.as_node())
  let indicator_el = @web.html(doc, "div", "map-indicator").as_element()
  @web.show(indicator_el, "block", false)
  pane.append(indicator_el.as_node())
  let tool = @parts.pane_tool(doc, "map-center")
  let center = doc.createElement("button")
  center.setAttribute("type", "button")
  center.setAttribute("title", "Center the view — Home")
  center.setAttribute("aria-label", "Center the view")
  center.append(@parts.icon(doc, "crosshair").as_node())
  tool.append(center.as_node())
  pane.append(tool.as_node())
  let m : Mindmap = {
    pane,
    host,
    world,
    renderer,
    hint,
    indicator_el,
    camera: { k: 1, tx: 60, ty: 60, },
    layout: place_layout(host),
    fingers: @map.Fingers::new(),
    panning: None,
    fit_pending: false,
    rect: None,
    caret_layer,
    caret_rings: [],
    rubber,
    rubber_start: None,
    rubber_size: (0, 0),
    tapped: None,
    grab: false,
    space_held: false,
    label,
    card,
    pick,
    hold: None,
    hold_at: None,
    menu_by_hold: false,
    drag_cand: None,
    dragging: None,
    drop: None,
    drop_parent: None,
    drop_line,
    menu: @parts.Menu::new(doc),
  }
  @web.listen(center, "click", _ => m.center_on_target())
  m.bind_wheel()
  m.bind_pointer()
  m.bind_click()
  m.bind_context_menu()
  m.bind_keys()
  m.apply_camera()
  // 大きさが無いうちに頼まれた fit は、付いてから 1 度走る
  @web.observe_resize(pane.as_element(), () => {
    m.rect = None
    if m.fit_pending {
      m.fit_view()
    }
  })
  m
}

///|
fn Mindmap::pane_rect(self : Mindmap) -> @dom.DOMRect {
  match self.rect {
    Some(r) => r
    None => {
      let r = @web.client_rect(self.pane.as_element())
      self.rect = Some(r)
      r
    }
  }
}

///|
/// ペインの左上から測った画面 px（core の視点が使う座標系）
fn Mindmap::at(self : Mindmap, x : Double, y : Double) -> @map.Pt {
  let r = self.pane_rect()
  { x: x - r.left, y: y - r.top, }
}

///|
fn Mindmap::pane_size(self : Mindmap) -> @map.Pane {
  let r = self.pane_rect()
  { width: r.width, height: r.height, }
}

///|
fn Mindmap::set_camera(self : Mindmap, c : @map.Camera) -> Unit {
  self.camera = c
  self.apply_camera()
  self.follow_label()
  self.follow_card()
  self.update_indicator()
}

///|
/// 編集中の欄を箱に追従させる。書くたび・視点を動かすたびに呼ぶ。
/// 箱が消えていれば（畳まれて埋もれた）欄が自分で閉じる
fn Mindmap::follow_label(self : Mindmap) -> Unit {
  self.label.place(self.layout, self.camera)
}

///|
/// 選んでいるカードの印と、開いている入力欄を今のレイアウト・視点に合わせる
fn Mindmap::follow_card(self : Mindmap) -> Unit {
  // 持ち主が畳まれて箱を失えば外す — 見えないカードを選んだままにしない
  let picked = (self.host.picked)()
  let at = picked.bind(id => card_rect_of(self.layout, id))
  match (picked, at) {
    (Some(id), Some(r)) => self.pick.show(id, r)
    (Some(_), None) => {
      (self.host.set_picked)(None)
      self.pick.hide()
    }
    _ => self.pick.hide()
  }
  self.card.place(self.layout, self.camera)
}

///|
/// 属性の数字。読めなければ None
fn int_of(s : String) -> Int? {
  try @string.parse_int(s) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
}

///|
fn Mindmap::apply_camera(self : Mindmap) -> Unit {
  let { k, tx, ty, } = self.camera
  self.world.setAttribute(
    "transform",
    "translate(\{@web.num(tx)} \{@web.num(ty)}) scale(\{@web.num(k)})",
  )
  let pane = self.pane.as_element()
  @web.set_style(pane, "background-position", "\{@web.px(tx)} \{@web.px(ty)}")
  let cell = @web.px(grid * k)
  @web.set_style(pane, "background-size", "\{cell} \{cell}")
}

///|
pub fn Mindmap::render(self : Mindmap) -> Unit {
  let s = (self.host.survey)()
  @web.show(self.hint, "flex", s.empty())
  self.layout = place_layout(self.host)
  self.renderer.draw({
    layout: self.layout,
    measure: self.host.measure,
    image_url: self.host.image_url,
    image_hint: (self.host.image_hint)(),
    tokens: self.host.tokens,
    epoch: (self.host.epoch)(),
  })
  self.paint_choice()
  self.follow_label()
  self.follow_card()
  self.update_indicator()
}

///|
fn Mindmap::all_rects(self : Mindmap) -> Array[@map.Rect] {
  self.rects_of(self.layout.order)
}

///|
/// 在る箱の矩形（world）。無い id は飛ばす
fn Mindmap::rects_of(self : Mindmap, ids : Array[Int]) -> Array[@map.Rect] {
  let out = []
  for id in ids {
    match self.layout.boxes.get(id) {
      Some(b) => out.push(b.rect())
      None => ()
    }
  }
  out
}

///|
pub fn Mindmap::fit_view(self : Mindmap) -> Unit {
  let pane = self.pane_size()
  // まだ大きさが無い（隠れている / 起動直後）なら、付いてから改めて
  if pane.width < 80 || pane.height < 80 {
    self.fit_pending = true
    return
  }
  self.fit_pending = false
  match @map.fit(self.all_rects(), pane, fit_margin) {
    Some(c) => self.set_camera(c)
    None => ()
  }
}

///|
/// 選択（無ければ根）を画面の中心へ。拡大率は変えない
pub fn Mindmap::center_on_target(self : Mindmap) -> Unit {
  let target = match @map.union(self.rects_of((self.host.selection)().ids)) {
    Some(r) => Some(r)
    None => @map.root_box(self.layout).map(b => b.rect())
  }
  match target {
    Some(r) => self.set_camera(@map.center_on(self.camera, r, self.pane_size()))
    None => ()
  }
}

///|
/// その箱が画面に入るまでだけ寄せる（矢印で選び直したとき）
fn Mindmap::ensure_visible(self : Mindmap, id : Int) -> Unit {
  match self.layout.boxes.get(id) {
    Some(b) =>
      self.set_camera(
        @map.pan_to_show(self.camera, b.rect(), self.pane_size(), show_margin),
      )
    None => ()
  }
}

///|
/// 選択の塗り直し。レイアウトは見直さない
pub fn Mindmap::refresh_selection(self : Mindmap) -> Unit {
  self.paint_choice()
  self.follow_card()
  self.update_indicator() // 針は選択を指す — 視点が動かなくても指し直す
}

///|
/// その場編集に入る。seed は最初の字。箱が無い（畳まれて埋もれた）ノードは開けない —
/// 戻り値はそれを呼び出し側（main.ts の apply）に言うためのもの
pub fn Mindmap::begin_edit(self : Mindmap, id : Int, seed : String?) -> Bool {
  guard self.layout.boxes.get(id) is Some(b) else { return false }
  self.label.open(id, self.layout, self.camera, b.node.label, seed)
  true
}

///|
/// カードをその場で開く。畳まれて埋もれている（箱が無い）ときは断る。
/// `text` は欄に載せる字（無ければ md の原文）— 変えずに閉じれば書かない
pub fn Mindmap::edit_card(
  self : Mindmap,
  id : Int,
  from? : Int? = None,
  to? : Int? = None,
  text? : String? = None,
) -> Unit {
  guard card_rect_of(self.layout, id) is Some(_) else {
    (self.host.failed)("Couldn't open that card")
    return
  }
  let body = match text {
    Some(t) => t
    None => {
      let raw = (self.host.block_text)(id)
      if raw.has_suffix("\n") {
        String::unsafe_substring(raw, start=0, end=raw.length() - 1)
      } else {
        raw
      }
    }
  }
  (self.host.set_picked)(Some(id))
  self.card.open(id, self.layout, self.camera, body, from, to)
}

///|
/// 画面の点がどの箱に居るか。Easy grab なら箱の外まで当たる（map の hit）。無ければ None
fn Mindmap::node_at(self : Mindmap, x : Double, y : Double) -> Int? {
  let p = self.at(x, y)
  let w = @map.to_world(self.camera, p.x, p.y)
  @map.hit(
    self.layout,
    w.x,
    w.y,
    if self.grab {
      @map.grab
    } else {
      @map.exact
    },
  )
}

///|
/// 掴みやすさ（⋯ の Easy grab）。見た目は変えず、叩ける範囲だけ広げる
pub fn Mindmap::set_grab(self : Mindmap, on : Bool) -> Unit {
  self.grab = on
}

///|
/// 書き出しに写すもの。文書順の箱と、その線・ノードの要素。空なら箱が無い
pub fn Mindmap::svg_parts(
  self : Mindmap,
) -> (Array[@map.Rect], Array[@dom.Element], Array[@dom.Element]) {
  let edges = []
  let nodes = []
  for id in self.layout.order {
    match self.renderer.node_el(id) {
      Some(e) => nodes.push(e)
      None => ()
    }
    match self.renderer.edge_el(id) {
      Some(e) => edges.push(e)
      None => ()
    }
  }
  (self.all_rects(), edges, nodes)
}

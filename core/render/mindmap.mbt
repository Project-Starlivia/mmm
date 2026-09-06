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
  @map.layout((host.survey)().view.roots, @map.node_size(host.measure))
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
  ) => (host.apply)(SetBlock(id~, content=Opaque(text)), false) |> ignore)
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

// ---------- 視点 ----------

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
/// data-card の「ノードの id, 何枚目」から中身の id
fn Mindmap::block_at(self : Mindmap, spot : String) -> Int? {
  let parts = spot.split(",").map(s => s.to_owned()).collect()
  guard parts.length() == 2 else { return None }
  guard int_of(parts[0]) is Some(node) && int_of(parts[1]) is Some(index) else {
    return None
  }
  guard self.layout.boxes.get(node) is Some(b) else { return None }
  b.node.blocks.get(index).map(blk => blk.id)
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

// ---------- 置く・描く ----------

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
  self.label.open(id, self.layout, self.camera, @map.label_of(b.node), seed)
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
/// `https?://` で始まり、空白を含まない
fn is_url(s : String) -> Bool {
  guard s.has_prefix("http://") || s.has_prefix("https://") else {
    return false
  }
  let scheme = if s.has_prefix("https://") { 8 } else { 7 }
  guard s.length() > scheme else { return false }
  for i in 0..<s.length() {
    let c = s[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      return false
    }
  }
  true
}

///|
/// クリップボードの URL をリンクカードにして足し、題（`[]` の中）を打つ。
/// URL として読めなければ `failed`（core にも聞かない — Mod+V は raw を core に
/// 読ませるが、ここは「URL か否か」だけを見て、違えば言う）
fn Mindmap::add_link(self : Mindmap, id : Int) -> Unit {
  (self.host.read_clipboard)(raw => {
    let url = raw.trim(chars=" \t\r\n").to_owned()
    guard is_url(url) else {
      (self.host.failed)("Couldn't read that as a link")
      return
    }
    let f = (self.host.apply)(
      AddBlock(at=In(node=id), content=Link(text="", href=url, title="")),
      false,
    )
    match f {
      Some(block) => self.edit_card(block, from=Some(1), to=Some(1))
      None => ()
    }
  })
}

///|
/// 空のコードカードを足して、本文の行を打つ。core は空のコードを開きと閉じの
/// 2 行で書くので、欄には空行を 1 つ挟んだ形で載せ、そこに頭を置く（打たなければ書かない）
fn Mindmap::add_code(self : Mindmap, id : Int) -> Unit {
  let f = (self.host.apply)(
    AddBlock(at=In(node=id), content=Code(info="", text="")),
    false,
  )
  match f {
    Some(block) =>
      self.edit_card(block, from=Some(4), to=Some(4), text=Some("```\n\n```"))
    None => ()
  }
}

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

// ---------- 入力 ----------

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
/// ファイルのドラッグ中、その画面の点に落ちる先を予告する（app/dnd.ts）。
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
        match self.block_at(spot) {
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
        match self.block_at(spot) {
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
/// その画面の点でメニューを開く。箱の外なら閉じるだけ。触った箱がまだ選ばれて
/// いなければ、それ 1 つに選び直してから並びを組む — 右クリックは選ぶ動作も兼ねる
fn Mindmap::open_menu(self : Mindmap, x : Double, y : Double) -> Unit {
  // メニューも地図の入力。まず地図に持たせてから選ぶ（focusin → 持ち主 → 選択）—
  // 右押下でペインに焦点が入らない環境があり、持たないままだと選び直しが届かない
  self.pane.focus()
  // 開いている欄は閉じてから。メニューは選択を据え直すので、欄の下で id が動かないように
  self.label.close()
  self.card.close()
  guard self.node_at(x, y) is Some(id) else {
    self.menu.hide(false)
    return
  }
  let sel = (self.host.selection)()
  if !sel.ids.contains(id) {
    (self.host.set_selection)({ ids: [id], anchor: Some(id), }, false)
  }
  self.menu.show(x, y, () => {
    items_of(@map.items(self.layout, (self.host.selection)()), i => self.act(i))
  })
}

///|
/// 右クリックの行（map/context.mbt）をメニューの器の行に写す。押せば `act` へ渡すだけで、
/// 意味はここに増やさない。沈む行は `why` を押せない理由として持ち、無ければただ沈む。
/// 絵の名は表（parts/icons.mbt）に無ければ落とす
pub fn items_of(
  es : Array[@map.Entry],
  act : (@map.Intent) -> Unit,
) -> Array[@parts.Entry] {
  fn one(it : @map.Item) -> @parts.Entry {
    let row = @parts.row(
      it.label,
      key=it.key,
      mark=it.mark.filter(@parts.is_icon),
      disabled=match (it.intent, it.why) {
        (Some(_), _) => No
        (None, Some(why)) => Why(why)
        (None, None) => Yes
      },
    )
    let run = it.intent.map(i => () => act(i))
    match it.items {
      Some(items) => Sub(row, items.map(one), run)
      None => Run(row, run.unwrap_or(() => ()))
    }
  }

  es.map(e => {
    match e {
      Sep => @parts.Sep
      Item(it) => one(it)
    }
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
/// 「何をするか」を実行する。意味は map/keys.mbt と map/context.mbt が持ち、ここは配線だけ
pub fn Mindmap::act(self : Mindmap, intent : @map.Intent) -> Unit {
  match intent {
    Op(op~, edit~) => (self.host.apply)(op, edit) |> ignore
    Edit(id~, seed~) => self.begin_edit(id, seed) |> ignore
    Select(sel~, reveal~) => {
      (self.host.set_selection)(sel, reveal)
      // 矢印で辿るときだけ寄せる（Mod+A / Esc は reveal が偽）
      match sel.anchor {
        Some(a) if reveal => self.ensure_visible(a)
        _ => ()
      }
    }
    Center => self.center_on_target()
    Pick(id~) => (self.host.set_picked)(id)
    EditCard(id~) => self.edit_card(id)
    AddLink(id~) => self.add_link(id)
    AddCode(id~) => self.add_code(id)
    Draw(id~) => (self.host.draw)(id)
    Paste => (self.host.paste)()
    Copy(cut~) =>
      // 消すのは写せてから。写せなければ（クリップボードが断った）何も失わない
      (self.host.copy)(ok => {
        match cut {
          Some(c) if ok => self.act(c)
          _ => ()
        }
      })
  }
}

///|
/// 地図の中だけで効くキー。全体のキーは app/shortcuts.ts
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

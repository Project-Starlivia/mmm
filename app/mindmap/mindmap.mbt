// マップのペイン。core が置いて描き、入力を受けて判断し、答えを host へ返す。
//
// 持っているのは視点（Camera）と、それを動かす入力（ホイール・ドラッグ・ピンチ・
// クリック・矩形・矢印・右クリック・長押し）と、見失った先を指す針だけ。
// **選択の値は持たない** — 入力を選択の値にして host へ渡し、host の値を塗るだけ。
// 値は EditorState の field（ts の state.ts）。判断（当たり・落とし先・キーの表・矢印・
// 寄せ・針・押した点からの遠さ）は全部 map/。ここはそれを DOM の出来事に繋ぐ。

///|
/// 輪を箱の内側へ入れる量
let ring_inset = 3.0

///|
/// 背景の格子 1 目盛り（world）
let grid = 18.0

///|
/// ポインタの手。**互いに両立しない 5 つを 1 つの値で持つ** — 押しながら矩形選択、
/// のような組み合わせは書けない。Space と長押しの印は手ではなく「次の出来事をどう
/// 読むか」なので、ここには入れない（`space_held` / `menu_by_hold`）
priv enum Mode {
  Idle
  /// マウスで箱を押した。動かせば Dragging。`tap` なら動かさず離せば選ぶ —
  /// 選んでいる箱をそのまま押したとき（押した瞬間に畳むと、複数選択を掴んで動かす手が無くなる）
  Pressed(Press, tap~ : Bool)
  /// 指で箱を押した。動かせば Dragging、動かさず離せば選ぶ、待てばメニュー（右クリックの代わり）
  Holding(Press, @global.Timer)
  Panning(Panning)
  /// 背景をなぞっている。`size` は引いた大きさ（画面 px）— 離したとき「なぞったか」を見る
  Rubber(start~ : @map.Pt, size~ : (Double, Double))
  Dragging(Dragging)
}

///|
/// 押したノードと、押した画面の点
priv struct Press {
  id : Int
  at : @map.Pt
}

///|
/// パンの始まり。押した画面の点と、そのときの視点
priv struct Panning {
  px : Double
  py : Double
  ox : Double
  oy : Double
}

///|
/// 動かしているノード。ids は選んだ全部（文書順）、subtree はその子孫込み（落とし先から外す）
priv struct Dragging {
  ids : Array[Int]
  subtree : Array[Int]
  /// 今の落とし先の予告。無ければ離しても何もしない
  mut drop : @map.Drop?
}

///|
pub struct Mindmap {
  pane : @dom.HTMLElement
  host : Host
  /// world 座標の層。Camera の変換はこれに掛ける
  world : @dom.Element
  renderer : Renderer
  /// 白紙の言い出し（器は app/parts/hint.mbt）
  hint : @dom.Element
  indicator_el : @dom.Element
  /// 針がいま指している箱（world）。**押したとき頑張るのはこれ 1 つ** —
  /// `Home` / 十字は選択ぜんぶの外接を寄せるので、手によって中心へ来るものが違う（#129）
  mut pointed : @map.Rect?
  /// 直前に針を当てた条件（視点・選択・ペイン）。同じなら当て直さない —
  /// 矩形選択は pointermove ごとに選択を書き、そのたび refresh_selection が来る（#249）
  mut aimed : (@map.Camera, Array[Int], @map.Pane)?
  mut camera : @map.Camera
  mut layout : @map.Layout
  /// 在る箱ぜんぶの矩形（world）。針が見張るのに要り、集めるのは O(ノード) なので
  /// レイアウトを置いたときに 1 度だけ
  mut all : Array[@map.Rect]
  fingers : @map.Fingers
  priv mut mode : Mode
  mut fit_pending : Bool
  /// ペインの画面上の矩形。None なら次に読む。resize でしか変わらない（アプリは
  /// スクロールしない）ので ResizeObserver が捨てる。毎イベント読み直すと、直前に
  /// world へ書いた scale のぶん SVG 全体のレイアウトを同期で走らせる —
  /// 5000 ノードで 1 ホイール 30ms（読むだけで）
  mut rect : @dom.DOMRect?
  /// カーソルの輪の層。world に浮かぶ別の印（ノードの子にすると、動くたびに中身が作り直される）
  caret_layer : @dom.Element
  caret_rings : Array[@dom.Element]
  /// 直前に輪を置いた矩形。同じなら書かない
  mut ringed : Array[@map.Rect]
  /// 矩形選択の面（画面 px）。始点は pane の左上から
  rubber : @dom.Element
  mut grab : Bool
  /// Space を押している間、左ドラッグはパン
  mut space_held : Bool
  label : LabelField
  card : CardField
  /// 選んでいるカードに被せる枠と ×。world に浮かぶ 1 個の印
  pick : CardPick
  /// 直前に開いたメニューが長押しから来たか。続く contextmenu を握り潰すため
  mut menu_by_hold : Bool
  /// 予告で drop-parent を付けている箱の id。次の予告や後片付けで外す
  /// （ノードのドラッグと、ファイルのドラッグの両方が付ける）
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
/// 在る箱の矩形（world）。無い id は飛ばす
fn rects_in(l : @map.Layout, ids : Array[Int]) -> Array[@map.Rect] {
  ids.filter_map(id => l.boxes.get(id).map(b => b.rect))
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
  let drop_line = @web.el(doc, "line", [("class", "drop-line")])
  @web.svg_show(drop_line, false)
  let renderer = Renderer::new(doc)
  let pick = CardPick::new(doc)
  world.append(renderer.edge_layer.as_node())
  world.append(renderer.node_layer.as_node())
  world.append(pick.el.as_node())
  world.append(caret_layer.as_node())
  world.append(drop_line.as_node())
  svg.append(world.as_node())
  pane.append(svg.as_node())
  let rubber = @web.html(doc, "div", "rubber")
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
  let hint = @parts.pane_hint(doc, Map)
  @web.show(hint, "flex", false)
  pane.append(hint.as_node())
  let indicator_el = @web.html(doc, "div", "map-indicator")
  indicator_el.setAttribute("role", "button")
  indicator_el.setAttribute("title", "Bring it into view")
  indicator_el.setAttribute("aria-label", "Bring the selection into view")
  @web.show(indicator_el, "block", false)
  pane.append(indicator_el.as_node())
  let tool = @parts.pane_tool(doc, "map-center")
  let center = @parts.icon_button(
    doc,
    "crosshair",
    title="Center the view — Home",
    label="Center the view",
  )
  tool.append(center.as_node())
  pane.append(tool.as_node())
  let layout = place_layout(host)
  let m : Mindmap = {
    pane,
    host,
    world,
    renderer,
    hint,
    indicator_el,
    pointed: None,
    aimed: None,
    camera: { k: 1, tx: 60, ty: 60, },
    layout,
    all: rects_in(layout, layout.order),
    fingers: @map.Fingers::new(),
    mode: Idle,
    fit_pending: false,
    rect: None,
    caret_layer,
    caret_rings: [],
    ringed: [],
    rubber,
    grab: false,
    space_held: false,
    label,
    card,
    pick,
    menu_by_hold: false,
    drop_parent: None,
    drop_line,
    menu: @parts.Menu::new(doc),
  }
  @web.listen(center, "click", _ => m.center_on_target())
  // 針は押せる。**指している 1 つ**へ行く（隅の十字は選択ぜんぶの外接。#129）
  @web.listen(m.indicator_el, "click", e => {
    @web.stop(e)
    m.goto_pointed()
  })
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
  self.all = rects_in(self.layout, self.layout.order)
  self.aimed = None // 箱が動いたので、針は当て直す
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
pub fn Mindmap::fit_view(self : Mindmap) -> Unit {
  let pane = self.pane_size()
  // まだ大きさが無い（隠れている / 起動直後）なら、付いてから改めて
  if pane.width < 80 || pane.height < 80 {
    self.fit_pending = true
    return
  }
  self.fit_pending = false
  match @map.fit(self.all, pane) {
    Some(c) => self.set_camera(c)
    None => ()
  }
}

///|
/// 選択（無ければ根）を画面の中心へ。拡大率は変えない
fn Mindmap::center_on_target(self : Mindmap) -> Unit {
  let target = match
    @map.union(rects_in(self.layout, (self.host.selection)().ids)) {
    Some(r) => Some(r)
    None => @map.root_box(self.layout).map(b => b.rect)
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
      self.set_camera(@map.pan_to_show(self.camera, b.rect, self.pane_size()))
    None => ()
  }
}

///|
/// 選択の塗り直し。レイアウトは見直さない
pub fn Mindmap::refresh_selection(self : Mindmap) -> Unit {
  self.paint_choice()
  self.follow_card()
  self.follow_holder()
  self.update_indicator() // 針は選択を指す — 視点が動かなくても指し直す
}

///|
/// **md が持つ間は、地図がカーソルを追う。** 追従は元は地図 → md の片側だけで、
/// md を打ち進めると選択は画面外へ出たまま戻らず、針だけが縁を回っていた（#131）。
///
/// 寄せ方は `ensure_visible` と同じ「余白を持って入るまで」 — 中心へ置くと打鍵の
/// たびに地図が跳ねて読めない。**入っているあいだは 1 ピクセルも動かない。**
/// 追うのは anchor 1 つ（選択ぜんぶを入れると、広い選択で倍率の話になる）
fn Mindmap::follow_holder(self : Mindmap) -> Unit {
  guard (self.host.holder)() is Md else { return }
  guard (self.host.selection)().anchor is Some(anchor) else { return }
  self.ensure_visible(anchor)
}

///|
/// その場編集に入る。seed は最初の字。箱が無い（畳まれて埋もれた）ノードは開けない —
/// 戻り値はそれを呼び出し側（App の apply）に言うためのもの
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
fn Mindmap::svg_parts(
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
  (self.all, edges, nodes)
}

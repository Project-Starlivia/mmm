// ペインの表示 / 非表示（md とマップ）とスプリッタ。
//
// **見え方は「分割線の居場所」ひとつで言い切れる。** 「両方消えた」は
// 作らないので、辿り着ける形はたかだか 3 つ（狭ければ 2 つ）で、左から
// 順に並べるとそのまま分割線を左右に動かす話になる（`spots_for`）。
//
// だから**矢印は向きを変えない**。`‹` はいつでも「分割線を左へ 1 つ」、
// `›` はいつでも「右へ 1 つ」で、いま押せるかどうかだけが変わる（端では止まる）。
//
// **居場所は覚える**（`prefs` の `panes`）。書くのは人が動かしたときだけで
// （`go`）、幅が境目をまたいだときの射影は覚えた姿を上書きしない — あれは
// 環境の都合であって、選んだ結果ではない。覚えが無ければ両方から始まる。
//
// **狭いときは「両方」が居場所から消える。** 並べられない幅で「両方」を
// 残すと、CSS が片方を隠して**状態が 2 つになり食い違う** — 矢印は行けない
// 場所を指し、`disabled` は画面に無い世界を説明する。

///|
/// 見えているペイン。**「両方消えた」は作らない**
pub(all) struct Vis {
  md : Bool
  map : Bool
} derive(Eq, Debug)

///|
/// その姿の綴り。CSS へ降ろす 1 属性（`#panes[data-show]`）と、覚える綴りは
/// 同じ 3 つ — 居場所の数と揃う
fn Vis::show(self : Vis) -> String {
  if self.md && self.map {
    "both"
  } else if self.md {
    "md"
  } else {
    "map"
  }
}

///|
/// 綴りから読み戻す。知らない綴りは None（覚えていないのと同じ）
fn vis_of(show : String?) -> Vis? {
  match show {
    Some("both") => Some({ md: true, map: true, })
    Some("md") => Some({ md: true, map: false, })
    Some("map") => Some({ md: false, map: true, })
    _ => None
  }
}

///|
/// ペインの名指し
pub(all) enum Pane {
  Md
  Map
} derive(Eq, Debug)

///|
/// 分割線の居場所。左端 = md が無い / 真ん中 = 両方 / 右端 = マップが無い。
/// **狭いときは真ん中が消えて 2 つになる** — 左から右へ並ぶ順は変わらない
/// ので、`‹` は狭くても「分割線を左へ 1 つ」のまま
fn spots_for(narrow : Bool) -> Array[Vis] {
  let map_only : Vis = { md: false, map: true, }
  let md_only : Vis = { md: true, map: false, }
  if narrow {
    [map_only, md_only]
  } else {
    [map_only, { md: true, map: true, }, md_only]
  }
}

///|
/// 要求された見え方を、いまの居場所へ射影する。**居場所に無い形は 2 つだけ** —
/// 「両方消えた」と、狭いときの「両方」。どちらも**マップを必ず残し、md は
/// 残せるなら残す**（この道具がマップのために在るから）
fn project(v : Vis, list : Array[Vis]) -> Vis {
  for s in list {
    if s == v {
      return s
    }
  }
  for s in list {
    if s.md && s.map {
      return s
    }
  }
  list[0]
}

///|
fn spot_of(list : Array[Vis], v : Vis) -> Int {
  for i, s in list {
    if s == v {
      return i
    }
  }
  -1
}

///|
/// `which` を出す / 引っ込める一手の行き先。**`project` のフォールバックには
/// 任せない** — あちらは「行き先を言っていない要求」（境目をまたいだ・
/// 両方消えた）専用で、常にマップへ丸めてしまうので、「md を出したい」
/// のような名指しの要求に使うと要求そのものが無視される。
///
/// 決め方は 2 つだけ:
/// - **引っ込める。** 最後の 1 枚（もう片方が既に消えている）なら
///   「両方消えた」は作らないので、「もう片方を出す」一手として読む —
///   幅に関係なく、消される側の逆が残る。もう片方も出ていれば、ただ
///   その 1 枚だけを消す。
/// - **出す。** 居場所が 2 つ（狭い）なら「両方」という置き場が無いので、
///   そのペイン 1 枚だけになる。3 つ（広い）なら相方はそのまま、その
///   ペインを足すだけ
fn toggled(v : Vis, which : Pane, list : Array[Vis]) -> Vis {
  let (on, other) = match which {
    Md => (v.md, v.map)
    Map => (v.map, v.md)
  }
  let only = (p : Pane) => {
    match p {
      Md => ({ md: true, map: false, } : Vis)
      Map => { md: false, map: true, }
    }
  }
  if on {
    if !other {
      return only(
        match which {
          Md => Map
          Map => Md
        },
      )
    }
    return match which {
      Md => { md: false, map: v.map, }
      Map => { md: v.md, map: false, }
    }
  }
  if list.length() == 3 {
    match which {
      Md => { md: true, map: v.map, }
      Map => { md: v.md, map: true, }
    }
  } else {
    only(which)
  }
}

///|
/// その姿の名前。**「その一手」ではなく「着く先」を言う。**
///
/// 出す/隠すの動詞で言うと、同じ数か所を行き来する話が何通りにも散り、
/// 呼び名まで揃わなくなる。姿に名前を付ければ、居場所の数だけで足りる。
///
/// **画面に `pane` とは書かない。** 見えているものの名前は Markdown と
/// Mindmap の 2 つで、`pane` は器の呼び名（＝こちらの都合）でしかない
fn name_of(v : Vis?) -> String {
  match v {
    None => ""
    Some({ md: true, map: true, }) => "Markdown + Mindmap"
    Some({ md: true, .. }) => "Markdown only"
    Some(_) => "Mindmap only"
  }
}

///|
/// 絵は下向きの chevron 1 つだけ。左右は回して作る（線を増やさない）
fn arrow_button(doc : @dom.Document, left : Bool) -> @dom.Element {
  let button = @parts.icon_button(doc, "chevron-down")
  @web.toggle_class(
    button.firstElementChild().unwrap(),
    if left {
      "point-left"
    } else {
      "point-right"
    },
    true,
  )
  button
}

///|
/// **`720px` を 2 か所に置かない。** メディアクエリでは CSS 変数を使えないので、
/// 唯一の源をここに置き、CSS は `<html class="narrow">` を見る
let narrow_query = "(max-width: 720px)"

///|
pub struct Panes {
  doc : @dom.Document
  md_pane : @dom.Element
  map_pane : @dom.Element
  panes_el : @dom.Element
  focus_editor : () -> Unit
  narrow : @dom.MediaQueryList
  go_left : @dom.Element
  go_right : @dom.Element
  mut vis : Vis
  /// 分割線を掴んでいる（幅を変えている）あいだ
  mut dragging : Bool
}

///|
fn Panes::narrow(self : Panes) -> Bool {
  @web.matches(self.narrow)
}

///|
fn Panes::spots(self : Panes) -> Array[Vis] {
  spots_for(self.narrow())
}

///|
fn Panes::apply(self : Panes, want : Vis) -> Unit {
  let list = self.spots()
  let v = project(want, list)
  self.vis = v
  @web.toggle_class(self.doc.documentElement(), "narrow", self.narrow())
  // 見え方は CSS へ 1 属性で降ろす（`#panes[data-show]`）。居場所と同じ 3 つ
  self.panes_el.setAttribute("data-show", v.show())
  // 端では、その先が無いので押せない
  let spot = spot_of(list, v)
  @web.set_disabled(self.go_left, spot <= 0)
  @web.set_disabled(self.go_right, spot >= list.length() - 1)
  // 絵しか持たない矢印。名前は動くたび変わる — 押した先の姿を言い切る
  // 文言が、そのままアクセシブルネームにもなる
  let left = name_of(if spot > 0 { Some(list[spot - 1]) } else { None })
  self.go_left.setAttribute("title", left)
  self.go_left.setAttribute("aria-label", left)
  let right = name_of(list.get(spot + 1))
  self.go_right.setAttribute("title", right)
  self.go_right.setAttribute("aria-label", right)
  // 隠れたペインに焦点を残さない
  let active : @dom.Element? = @core.identity_option(
    self.doc.activeElement().as_any(),
  )
  match active {
    Some(a) => {
      if !v.md && self.md_pane.contains(Some(a.as_node())) {
        @web.focus(self.map_pane)
      }
      if !v.map && self.map_pane.contains(Some(a.as_node())) {
        (self.focus_editor)()
      }
    }
    None => ()
  }
}

///|
/// 人が動かした一手。落ち着いた姿をそのまま覚える（狭くて「両方」に
/// なれなかったなら、見えているほうを覚える）
fn Panes::go(self : Panes, want : Vis) -> Unit {
  self.apply(want)
  @prefs.store(self.doc, "panes", self.vis.show())
}

///|
/// 分割線を 1 つ動かす。端は動かない
fn Panes::slide(self : Panes, step : Int) -> Unit {
  let list = self.spots()
  match list.get(spot_of(list, self.vis) + step) {
    Some(next) => self.go(next)
    None => ()
  }
}

///|
/// そのペインの表示 / 非表示
fn Panes::toggle_vis(self : Panes, which : Pane) -> Unit {
  self.go(toggled(self.vis, which, self.spots()))
}

///|
/// Mod+/: もう片方のペインへ。隠れていれば出す
fn Panes::toggle(self : Panes) -> Unit {
  let active : @dom.Element? = @core.identity_option(
    self.doc.activeElement().as_any(),
  )
  let in_md = match active {
    Some(a) => self.md_pane.contains(Some(a.as_node()))
    None => false
  }
  if in_md {
    if !self.vis.map {
      self.go(toggled(self.vis, Map, self.spots()))
    }
    @web.focus(self.map_pane)
  } else {
    if !self.vis.md {
      self.go(toggled(self.vis, Md, self.spots()))
    }
    (self.focus_editor)()
  }
}

///|
/// 分割線の矢印を付け、スプリッタを掴めるようにする。**md 側のフォーカスは
/// CodeMirror が持つので注入**
fn Panes::new(
  md_pane : @dom.Element,
  map_pane : @dom.Element,
  panes_el : @dom.Element,
  splitter : @dom.Element,
  focus_editor : () -> Unit,
) -> Panes {
  let doc = md_pane.ownerDocument().unwrap()
  let arrows = @parts.pane_tool(doc, "pane-switch")
  let go_left = arrow_button(doc, true)
  let go_right = arrow_button(doc, false)
  arrows.append(go_left.as_node())
  arrows.append(go_right.as_node())
  splitter.append(arrows.as_node())
  let p : Panes = {
    doc,
    md_pane,
    map_pane,
    panes_el,
    focus_editor,
    narrow: @web.match_media(doc, narrow_query),
    go_left,
    go_right,
    vis: vis_of(@prefs.load(doc, "panes")).unwrap_or({ md: true, map: true, }),
    dragging: false,
  }
  @web.listen(go_left, "click", _ => p.slide(-1))
  @web.listen(go_right, "click", _ => p.slide(1))
  // ---- スプリッタ ----
  // 両方出ているときは幅を変えるだけ。開閉は境目の矢印と Alt+1 / Alt+2、
  // Mod+/ が持つ。
  //
  // **片方だけのときは、押せば分割へ戻る。** 動かす幅が無いので掴んでも
  // 何もできないが、縁に寄った分割線はそこに見えている — 戻すための
  // 取っ手として使えるほうが、細い矢印 1 つを狙わせるより易しい
  @web.listen(splitter, "pointerdown", e => {
    // 狭いときは分割そのものが無い。掴む先も、戻る先も無い
    if p.narrow() {
      return
    }
    if !p.vis.md || !p.vis.map {
      p.go({ md: true, map: true, })
      return
    }
    @web.toggle_class(splitter, "dragging", true)
    @web.capture(splitter, @web.pointer_id(e))
    p.dragging = true
  })
  @web.listen(splitter, "pointermove", e => {
    guard p.dragging else { return }
    let total = @web.client_rect(panes_el)
    let m = @web.mouse(e)
    let pct = @cmp.minimum(
      80.0,
      @cmp.maximum(15.0, (m.clientX - total.left) / total.width * 100.0),
    )
    @web.set_style(doc.documentElement(), "--md-width", "\{@web.num(pct)}%")
  })
  let up = (_ : @core.Any) => {
    guard p.dragging else { return }
    p.dragging = false
    @web.toggle_class(splitter, "dragging", false)
  }
  @web.listen(splitter, "pointerup", up)
  @web.listen(splitter, "pointercancel", up)
  // 幅が境目をまたいだら、いまの見え方を新しい居場所へ射影し直す
  p.narrow.addChangeListener(_ => p.apply(p.vis))
  // 覚えた姿を今の居場所へ射影し、押せる / 押せないをそろえる。
  // **ここでは覚え直さない** — まだ誰も動かしていない
  p.apply(p.vis)
  p
}

// メニューの器。**何を並べるかは持たない** — 並びは呼ぶ側が決めて渡す。
// ここが引き受けるのは、作る・置く・画面からはみ出させない・**外を押されたら
// 閉じる**、だけ。閉じる条件はメニューであることの一部であって、
// マップであることの一部ではない。
//
// **1 個しか作れない器にはしない**（id ではなく class）。マップの右クリックと、
// 帯の Files / ⋯ / 書き出しの出し方選びが、同じ器を別々に持つ。
//
// 入れ子も同じ器で作る — 子メニューは `Menu` そのもので、置く場所が
// 親の行の隣になるだけ。**別の器を書き足さない。**
//
// 行の形と敷き方は entry.mbt（`Entry` / `fill`）

///|
/// 画面の縁からこれだけは離す
let margin = 8.0

///|
/// 子メニューは親の行にこれだけ重ねて出す（縁の線をまたぐ量）
let overlap = 4.0

///|
pub struct Menu {
  doc : @dom.Document
  el : @dom.Element
  /// 開いている子メニュー。要るまで作らない（大半のメニューに入れ子は無い）
  mut sub : Menu?
  /// 自分が誰の子か。子から選んだとき、親ごと閉じるために辿る
  mut parent : Menu?
  /// 子を開いた行。閉じたとき、そこへ焦点を戻す（← キー）
  mut opener_row : @dom.Element?
  /// 開いたときに焦点があった要素。トップレベルだけが持つ — 閉じたら戻る先
  mut opener : @dom.Element?
  /// 入れ子を持つ行の「開く」動作（`fill` が返す）。ArrowRight が引く
  mut openers : Array[(@dom.Element, () -> Unit)]
  /// 並びの作り方。**開くたび・綴り直すたびに引く** — いまの状態に合わせるため
  mut items : () -> Array[Entry]
  /// 頼まれた場所。**無ければ画面の真ん中** — 押されて出たのではないものには
  /// 出どころの座標が無い（立ち上がりに覚えているものを並べる。#277）。
  /// 綴り直しで大きさが変わっても、寄せ直せるように覚えておく
  mut at : (Double, Double)?
}

///|
pub fn Menu::new(doc : @dom.Document) -> Menu {
  let el = @web.html(doc, "div", "menu")
  @web.show(el, "block", false)
  el.setAttribute("role", "menu")
  el.setAttribute("tabindex", "-1")
  match doc.body() {
    Some(body) => body.append(el.as_node())
    None => ()
  }
  let m : Menu = {
    doc,
    el,
    sub: None,
    parent: None,
    opener_row: None,
    opener: None,
    openers: [],
    items: () => [],
    at: Some((0.0, 0.0)),
  }
  // 開いているあいだだけ付け外しする手もあるが、`hide` は何度呼んでも
  // 同じなので、付けっぱなしのほうが短い
  let root = doc.documentElement()
  @web.listen(root, "pointerdown", e => {
    if !m.contains(@web.event_target(e)) {
      m.hide(false)
    }
  })
  // トップレベルだけ、閉じたときに呼んだ場所へ焦点を戻す。子から選んで
  // 閉じるときも同じ道を通る（close → 一番上の hide(true)）
  @web.listen(root, "keydown", e => {
    if @web.keyboard(e).key == "Escape" {
      m.hide(m.parent is None)
    }
  })
  @web.on_window(doc, "blur", _ => m.hide(false))
  // **開いているあいだに窓の大きさが変われば置き直す。** 押して出る器では
  // 起きないが、立ち上がりに出る一覧は**窓がまだ大きさを持たないうちに**
  // 置かれることがある — そこでは真ん中が画面の外になる（実測した）
  @web.on_window(doc, "resize", _ => if m.is_open() { m.respell() })
  @web.listen(el, "keydown", e => m.on_keydown(e))
  m
}

///|
/// 開いた直後に呼ぶ。**先頭の行へ焦点を移す。** トップレベルなら、閉じた
/// ときに戻る先（そのとき焦点があった要素）もここで覚える — 呼ぶ側に
/// 「開ける前の焦点を覚えておいて」と言わせない
fn Menu::focus_first(self : Menu, on_row : Bool) -> Unit {
  if self.parent is None {
    self.opener = @core.identity_option(self.doc.activeElement().as_any())
  }
  // 行に乗せないときも**焦点はメニューが持つ** — 手放すと Escape も
  // Tab も届かず、閉じた後に戻る先も分からなくなる
  if on_row {
    match self.el.querySelector(".item") {
      Some(row) => @web.focus(row)
      None => ()
    }
  } else {
    @web.focus(self.el)
  }
}

///|
/// 今どの行に焦点があるか。行でなければ None（絞り込んで確かめる）
fn Menu::active_row(self : Menu) -> @dom.Element? {
  let el : @dom.Element? = @core.identity_option(
    self.doc.activeElement().as_any(),
  )
  el.filter(e => @web.has_class(e, "item"))
}

///|
/// 焦点のある行が上から何番目か。行に無ければ -1
fn Menu::row_index(self : Menu) -> Int {
  let rows = self.el.querySelectorAll(".item")
  let mut at = -1
  match self.active_row() {
    Some(a) =>
      for i, r in rows {
        if @web.same(r, a) {
          at = i
        }
      }
    None => ()
  }
  at
}

///|
fn Menu::top(self : Menu) -> Menu {
  match self.parent {
    Some(p) => p.top()
    None => self
  }
}

///|
fn Menu::on_keydown(self : Menu, e : @core.Any) -> Unit {
  let rows = self.el.querySelectorAll(".item")
  guard rows.length() > 0 else { return }
  let active = self.active_row()
  let at = self.row_index()
  let step = (next : Int) => {
    @web.focus(rows[(next % rows.length() + rows.length()) % rows.length()])
  }
  match @web.keyboard(e).key {
    "ArrowDown" => {
      @web.prevent(e)
      step(at + 1)
    }
    "ArrowUp" => {
      @web.prevent(e)
      step(at - 1)
    }
    "Home" => {
      @web.prevent(e)
      @web.focus(rows[0])
    }
    "End" => {
      @web.prevent(e)
      @web.focus(rows[rows.length() - 1])
    }
    "ArrowRight" => {
      // 入れ子でない行では何もしない（横に伸びる先が無い）
      guard active is Some(a) else { return }
      for o in self.openers {
        if @web.same(o.0, a) {
          @web.prevent(e)
          (o.1)()
          match self.sub {
            Some(s) => s.focus_first(true)
            None => ()
          }
        }
      }
    }
    "ArrowLeft" =>
      // 自分が子のときだけ意味を持つ。**親の `close_sub` を経由する** —
      // 直に `hide` すると、開いた行の `aria-expanded` を戻す係が
      // 素通りされる（そこは親しか持っていない）
      match self.parent {
        Some(p) => {
          @web.prevent(e)
          let row = self.opener_row
          p.close_sub()
          match row {
            Some(r) => @web.focus(r)
            None => ()
          }
        }
        None => ()
      }
    "Enter" | " " => {
      @web.prevent(e)
      // 押せなさもキーの並びも、click 側が既に持っている判断をそのまま使う
      match active {
        Some(a) => @dom.HTMLElement::cast_from_element(a).click()
        None => ()
      }
    }
    // 抜けるところまで持っていかない — Tab の既定の移動に任せ、
    // 浮いたままにならないよう畳むだけ
    "Tab" => self.top().hide(false)
    _ => ()
  }
}

///|
/// その座標に開く。**並びは作り方で受ける** — 開くたびに引くので、押した瞬間の
/// 状態に合う（綴り直し（`Flip`）も同じ口から引く）
pub fn Menu::show(
  self : Menu,
  x : Double,
  y : Double,
  items : () -> Array[Entry],
) -> Unit {
  self.items = items
  self.at = Some((x, y))
  self.draw()
}

///|
/// 画面の真ん中に開く。**押されて出たのではないもの**のための口で、閉じ方は
/// 同じ（外を押す・Escape・窓を離れる）
pub fn Menu::show_middle(self : Menu, items : () -> Array[Entry]) -> Unit {
  self.items = items
  self.at = None
  self.draw()
}

///|
/// いまの並びを組んで置く。画面外へはみ出すときは内側へ寄せる
fn Menu::draw(self : Menu) -> Unit {
  self.close_sub()
  self.openers = fill(self.el, (self.items)(), {
    open_sub: (row, items) => self.open_sub(row, items),
    close_sub: () => self.close_sub(),
    close: () => self.close(true),
    respell: () => self.top().respell(),
  })
  // 大きさは出してからでないと測れない
  @web.show(self.el, "block", true)
  let (w, h) = @web.offset_size(self.el)
  let (iw, ih) = @web.inner_size(self.doc)
  // **画面の内側へ寄せる。** 押した所なら縁より内へ、真ん中なら半分の所へ。
  // どちらも縁から `margin` は離す — 器が画面より大きいとき、真ん中は
  // 負の桁になって左上が画面の外へ出る（窓の大きさが 0 で立ち上がることもある）
  let inside = (v : Double, room : Double) => {
    @cmp.maximum(margin, @cmp.minimum(v, room - margin))
  }
  let (x, y) = match self.at {
    Some((x, y)) => (inside(x, iw - w), inside(y, ih - h))
    None => (inside((iw - w) / 2.0, iw - w), inside((ih - h) / 2.0, ih - h))
  }
  @web.set_style(self.el, "left", @web.px(x))
  @web.set_style(self.el, "top", @web.px(y))
}

///|
/// **開いたまま、いまの状態から並びを引き直す。** 行は作り直されるので、
/// 焦点は同じ位置の行へ戻す — キーで辿っている途中に切り替えても、
/// 手が置いてある場所は動かない
fn Menu::respell(self : Menu) -> Unit {
  let at = self.row_index()
  self.draw()
  guard at >= 0 else { return }
  let rows = self.el.querySelectorAll(".item")
  if at < rows.length() {
    @web.focus(rows[at])
  }
}

///|
/// `restore_focus` はトップレベルが閉じるときだけ意味を持つ — 選んで閉じた
/// とき（`close`）と Escape で閉じたときは呼んだ場所へ戻り、外を押した・
/// 窓が背後へ回った・Tab で抜けたときは戻さない（戻すと、その操作を
/// わざわざやり直させることになる）
pub fn Menu::hide(self : Menu, restore_focus : Bool) -> Unit {
  self.close_sub()
  @web.show(self.el, "block", false)
  if restore_focus {
    match self.opener {
      Some(o) => @web.focus(o)
      None => ()
    }
    self.opener = None
  }
}

///|
/// いま開いているか。同じボタンを押し直して閉じたい呼び出し側のため
pub fn Menu::is_open(self : Menu) -> Bool {
  @web.is_shown(self.el)
}

///|
/// メニューの中で起きた出来事か（外を押したときだけ閉じるため）。
/// **子メニューの中も自分の中**として数える — そうしないと、子を押した
/// 瞬間に親が閉じ、閉じるついでに子まで畳まれて選べない
fn Menu::contains(self : Menu, target : @core.Any) -> Bool {
  let node : @dom.Node? = @core.identity_option(target)
  if self.el.contains(node) {
    return true
  }
  match self.sub {
    Some(s) => s.contains(target)
    None => false
  }
}

///|
/// 親の行の右隣へ子を開く。器は使い回す（開くたびに作らない）
fn Menu::open_sub(
  self : Menu,
  row : @dom.Element,
  items : Array[Entry],
) -> Unit {
  let sub = match self.sub {
    Some(s) => s
    None => {
      let s = Menu::new(self.doc)
      s.parent = Some(self)
      self.sub = Some(s)
      s
    }
  }
  row.setAttribute("aria-expanded", "true")
  sub.opener_row = Some(row)
  let r = @web.client_rect(row)
  sub.show(r.right - overlap, r.top - overlap, () => items)
  // 右に入らないときは**親の左へ回す**。`show` の寄せは画面の中へ入れる
  // だけなので、そのままだと親に重なって文字を隠す
  let (w, _) = @web.offset_size(sub.el)
  if r.right - overlap + w > @web.inner_size(self.doc).0 - margin {
    let left = @web.client_rect(self.el).left - w + overlap
    @web.set_style(sub.el, "left", @web.px(@cmp.maximum(margin, left)))
  }
}

///|
/// いちばん上まで辿って閉じる。子から選んだら親も畳む。
/// `restore_focus` は `hide` と同じ意味 — 選んで閉じるときは戻す
/// （キー操作でも選んだ後は呼んだ場所へ）
fn Menu::close(self : Menu, restore_focus : Bool) -> Unit {
  self.top().hide(restore_focus)
}

///|
fn Menu::close_sub(self : Menu) -> Unit {
  match self.sub {
    Some(s) => {
      match s.opener_row {
        Some(r) => r.setAttribute("aria-expanded", "false")
        None => ()
      }
      s.hide(false)
    }
    None => ()
  }
}

///|
/// そのボタンでメニューを開く。**押し直したら閉じる** — 閉じるのは document 側の
/// `pointerdown` が済ませるので、押した時点で開いていたかだけを覚えて開き直さない
/// （ボタン自身の `pointerdown` は document より先に届く）。
///
/// 並びは開くたびに作る。押した瞬間の文書に合わせるため。
///
/// **開けたのがキーなら先頭の行へ、マウスならメニューそのものへ。**
/// マウスで開いた瞬間に行が光ると、指してもいないところを「ここ」だと
/// 言うことになる（右クリックで開くメニューが誰も光らせないのと同じ）。
/// 焦点はメニューが持ったままなので、矢印を押せばそこから先頭に着く。
/// キーで押した click は `detail` が 0（マウスは押した回数が入る）
pub fn open_on_click(button : @dom.Element, items : () -> Array[Entry]) -> Unit {
  guard button.ownerDocument() is Some(doc) else { return }
  let menu = Menu::new(doc)
  let was_open : Ref[Bool] = { val: false, }
  @web.listen(button, "pointerdown", _ => was_open.val = menu.is_open())
  @web.listen(button, "click", e => {
    if was_open.val {
      return
    }
    let r = @web.client_rect(button)
    menu.show(r.left, r.bottom + 4.0, items)
    menu.focus_first(@web.detail(e) == 0)
  })
}

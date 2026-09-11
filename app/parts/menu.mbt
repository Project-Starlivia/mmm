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

///|
/// 押せない理由。**言葉を持てば、それが押せない理由として hover に出る。**
/// 真偽と 1 つに畳んであるので、「無効なのに理由が無い」と「理由があるのに押せる」が
/// 食い違いようがない。理由を書くのは、見ただけでは分からないときだけ —
/// 「選んでいない」「複数選んでいる」は行の並びと選択そのものが既に言っている
pub(all) enum Disabled {
  No
  Yes
  Why(String)
} derive(Eq, Debug)

///|
/// 行に共通の見た目。押したときの振る舞いは `Entry` が持つ。
///
/// `note` は**押す前に知っておくとよいこと**。押せなくはしない（押せないなら
/// `disabled` の側）。**1 つにつき印 1 つ**を右端に並べ、中身は触れば**すぐ**読める
/// （`title` はブラウザ任せで一拍待たされるので、吹き出しは自前で出す）。
/// 続きで受けるのは、届くのに一手かかるもの（リンクの長さは gzip してからでないと
/// 分からない）を、開くのを遅らせずに言うため — メニューは**待たずに開き**、
/// 届いた時点でその行だけに印が付く。空なら何も出さない
pub(all) struct Row {
  label : String
  key : String?
  /// 行の頭の絵。無ければ字だけ
  mark : String?
  note : (((Array[String]) -> Unit) -> Unit)?
  disabled : Disabled
}

///|
/// 1 行。
///
/// `Run` は閉じて走る — 結果が画面のどこかに出るもの。
/// `Done` は**閉じずに走り、済んだらその行の絵がチェックになる** —
/// 手元から何も見えないもの（コピー）を、押した場所で答えるため。
/// **できたかを続きで返す** — しくじりに頷いてしまわないように。
/// `Flip` は**閉じずに走り、並びを綴り直す** — 行そのものが次の状態を名乗るもの
/// （`Dark theme` を押すと行が `Light theme` になる）。閉じないのは、変わったのが
/// 画面の見え方そのもので、押した場所から確かめられるため。**綴り直すのは並び全部** —
/// 行が自分だけを書き換えると、同じ状態を 2 か所（並びを組む表と行）が持つことになる。
/// `Sub` は入れ子。**入れ子の行も走れる** — 触れば開き、押せばその場で走る
/// （`Add ▸` を押すと子ノードが増え、開けば下や上や親も選べる）。走るものの無い
/// 入れ子は開くだけ。
/// `Caption` は**続く行たちが何に効くか**を言う、押せない見出し。`mark` は
/// **主語を絵で言う**（値の無い状態 `not saved yet` では、何の話か絵が言う）
pub(all) enum Entry {
  Run(Row, () -> Unit)
  Done(Row, ((Bool) -> Unit) -> Unit)
  Flip(Row, () -> Unit)
  Sub(Row, Array[Entry], (() -> Unit)?)
  Caption(String, String?)
  Sep
}

///|
/// 押せる行（Caption / Sep でない）
pub fn row(
  label : String,
  key? : String? = None,
  mark? : String? = None,
  note? : (((Array[String]) -> Unit) -> Unit)? = None,
  disabled? : Disabled = No,
) -> Row {
  { label, key, mark, note, disabled, }
}

///|
/// 画面の縁からこれだけは離す
let margin = 8.0

///|
/// 子メニューは親の行にこれだけ重ねて出す（縁の線をまたぐ量）
let overlap = 4.0

///|
/// 行が器へ返すもの。位置・開閉・焦点は器（`Menu`）の持ち物で、行は
/// 「入れ子を開いて」「選んだから閉じて」と言うだけ
pub(all) struct Ways {
  /// 入れ子をその行の隣に開く
  open_sub : (@dom.Element, Array[Entry]) -> Unit
  /// 開いている入れ子を閉じる（別の行へ移った）
  close_sub : () -> Unit
  /// 選んだので器ごと閉じる
  close : () -> Unit
  /// 状態が変わったので、いまの状態から並びを引き直す（閉じない）
  respell : () -> Unit
}

///|
/// 絵の無い行に置く、同じ大きさの空欄。中身が無いだけの `.icon`
fn empty_mark(doc : @dom.Document) -> @dom.Element {
  let span = doc.createElement("span")
  span.setAttribute("class", "icon")
  span
}

///|
fn Entry::row_of(self : Entry) -> Row? {
  match self {
    Run(r, _) | Done(r, _) | Flip(r, _) | Sub(r, _, _) => Some(r)
    _ => None
  }
}

///|
/// 但し書きの印と吹き出し。**印は 1 つ。** その行についての但し書きが何本あっても、
/// 「この一手には気に留めることがある」という同じ 1 つの話なので、印を数だけ
/// 並べると別々の物に見える。数は吹き出しの中で言う
fn note_box(doc : @dom.Document, texts : Array[String]) -> @dom.Element {
  let mark = icon(doc, "triangle-alert")
  @web.toggle_class(mark, "note", true)
  // 印そのものが読み上げの対象になる。行の名前に但し書きを足すので
  // はなく、印に名前を持たせる（label は label のまま）
  mark.removeAttribute("aria-hidden")
  mark.setAttribute("role", "img")
  mark.setAttribute("aria-label", texts.join(". "))
  // 吹き出しは自前。`title` はブラウザ任せで一拍待たされる
  let tip = doc.createElement("div")
  tip.setAttribute("class", "tip")
  for text in texts {
    let line = doc.createElement("div")
    line.setTextContent(text)
    tip.append(line.as_node())
  }
  // `<span>` にしない — 行は「`.key` でも絵でもない `<span>` は
  // 字だ」と見て `flex: 1` を当てるので、印の器が横幅を全部
  // 持っていってしまう
  let box = doc.createElement("div")
  box.setAttribute("class", "note-box")
  box.append(mark.as_node())
  box.append(tip.as_node())
  box
}

///|
/// `.menu` の器に行を並べる。**中身だけ** — どこに出すか・いつ閉じるかは
/// 持たない。返るのは、入れ子を持つ行の「開く」動作（ArrowRight とホバーの
/// 両方がこれを引く。2 つの入口が同じ判断をばらばらに持たない）
fn fill(
  el : @dom.Element,
  items : Array[Entry],
  ways : Ways,
) -> Array[(@dom.Element, () -> Unit)] {
  guard el.ownerDocument() is Some(doc) else { return [] }
  el.replaceChildren([])
  let openers : Array[(@dom.Element, () -> Unit)] = []
  // 空欄で頭出しを揃えるのは、**このメニューの中に絵を持つ行が 1 つでも
  // あるとき**だけ。1 つも無いなら（Add の子など）揃える相手が無いので、
  // 全部の行を左端まで詰める — 空欄ぶんの余白だけが浮いて見えていた
  let any_mark = items.any(it => it.row_of() is Some({ mark: Some(_), .. }))
  for it in items {
    match it {
      Sep => {
        el.append(doc.createElement("hr").as_node())
        continue
      }
      Caption(text, mark) => {
        let cap = doc.createElement("div")
        cap.setAttribute("class", "caption")
        // 字は span に入れる — 長い名前を省略するのは字だけで、絵は縮めない
        let span = doc.createElement("span")
        span.setTextContent(text)
        match mark {
          Some(m) => cap.append(icon(doc, m).as_node())
          None => ()
        }
        cap.append(span.as_node())
        el.append(cap.as_node())
        continue
      }
      _ => ()
    }
    guard it.row_of() is Some(r) else { continue }
    let row = doc.createElement("div")
    row.setAttribute("class", "item")
    row.setAttribute("role", "menuitem")
    // 矢印キーで辿れる。触っても効かない行だけが機能しないので、
    // トップレベルには常に参加させる（見えるが効かない、が Tab と同じ形）
    row.setAttribute("tabindex", "-1")
    // 理由を持つなら、触れば読める。アクセシブルネームも同じ理由を言う —
    // hover できない読み上げでも「なぜ」がその場で分かる
    let off = !(r.disabled is No)
    if off {
      row.setAttribute("aria-disabled", "true")
    }
    match r.disabled {
      Why(why) => {
        row.setAttribute("title", why)
        row.setAttribute("aria-label", "\{r.label}, \{why}")
      }
      _ => ()
    }
    // 絵の有る行と無い行で字の頭出しがずれないよう、無い行にも同じ幅の
    // 空欄を置く（絵は行ごとの都合、字の頭は並びの都合 — 別の話）
    match r.mark {
      Some(m) => row.append(icon(doc, m).as_node())
      None => if any_mark { row.append(empty_mark(doc).as_node()) }
    }
    let label = doc.createElement("span")
    label.setTextContent(r.label)
    row.append(label.as_node())
    let nested = it is Sub(_, _, _)
    if nested {
      row.setAttribute("aria-haspopup", "menu")
      row.setAttribute("aria-expanded", "false")
    }
    // 但し書きは**印だけ**を右端に出し、中身は触れば読める。
    // **待たずに開いて、届いたら付ける** — 閉じた後に届いても、器ごと
    // 捨てられているだけなので何も起きない
    match r.note {
      Some(note) =>
        note(texts => {
          if texts.length() > 0 {
            row.append(note_box(doc, texts).as_node())
          }
        })
      None => ()
    }
    // 押して走る行のキーと、開ける印は同居しうる（`Tab ▸`）
    let hint = [r.key.unwrap_or(""), if nested { "▸" } else { "" }]
      .filter(s => s != "")
      .join(" ")
    if hint != "" {
      let key = doc.createElement("span")
      key.setAttribute("class", "key")
      key.setTextContent(hint)
      row.append(key.as_node())
    }
    // 「開く」判断は 1 か所。ホバーと ArrowRight の両方がこれを呼ぶ
    match it {
      Sub(_, items, _) if !off =>
        openers.push((row, () => (ways.open_sub)(row, items)))
      _ => ()
    }
    // どの行へ移っても、開いていた子は閉じる。入れ子の行なら開き直す
    @web.listen(row, "pointerenter", _ => {
      (ways.close_sub)()
      for o in openers {
        if @web.same(o.0, row) {
          (o.1)()
        }
      }
    })
    @web.listen(row, "click", _ => {
      // **押せなさは、ここが持つ。** CSS の `pointer-events: none` で
      // 止めていた頃は、同じ指定が hover まで殺していて理由が読めなかった
      if off {
        return
      }
      match it {
        // 走るものが無い入れ子は「開く」だけ。触るとすぐ閉じては選べない
        Sub(_, items, None) => (ways.open_sub)(row, items)
        // **`Done` の行は閉じない。** 済んだことはその場で絵が言うので、
        // 閉じて別の場所に出すより近いし、続けてもう 1 つ選べる
        Done(_, work) =>
          nod(
            work,
            mark => {
              // 行の頭の絵だけを差し替える（`:scope >` が無いと、但し書きの
              // 印まで拾いうる）。差し替えるたび引き直すので、そのつど探す
              match row.querySelector(":scope > .icon") {
                Some(old) => old.replaceWith([icon(doc, mark).as_node()])
                None => ()
              }
            },
            _ => (),
          )
        // **`Flip` の行も閉じない。** 走らせてから並びを引き直すので、
        // 押した行がその場で次の状態を名乗る
        Flip(_, run) => {
          run()
          (ways.respell)()
        }
        Sub(_, _, Some(run)) | Run(_, run) => {
          (ways.close)()
          run()
        }
        _ => ()
      }
    })
    el.append(row.as_node())
  }
  openers
}

///|
/// 行だけのメニュー。位置も開閉も持たない — 並べて見るためのもの
pub fn rows(doc : @dom.Document, items : Array[Entry]) -> @dom.Element {
  let el = doc.createElement("div")
  el.setAttribute("class", "menu")
  el.setAttribute("role", "menu")
  fill(el, items, {
    open_sub: (_, _) => (),
    close_sub: () => (),
    close: () => (),
    respell: () => (),
  })
  |> ignore
  el
}

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
  /// 頼まれた場所。綴り直しで大きさが変わっても、寄せ直せるように覚えておく
  mut at : (Double, Double)
}

///|
pub fn Menu::new(doc : @dom.Document) -> Menu {
  let el = doc.createElement("div")
  el.setAttribute("class", "menu")
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
    at: (0.0, 0.0),
  }
  // 開いているあいだだけ付け外しする手もあるが、`hide` は何度呼んでも
  // 同じなので、付けっぱなしのほうが短い
  let root = doc.documentElement()
  @web.listen(root, "pointerdown", e => {
    if !m.contains(e._get("target")) {
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
  self.at = (x, y)
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
  @web.set_style(
    self.el,
    "left",
    @web.px(@cmp.minimum(self.at.0, iw - w - margin)),
  )
  @web.set_style(
    self.el,
    "top",
    @web.px(@cmp.minimum(self.at.1, ih - h - margin)),
  )
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
  @dom.css_style_from_val(self.el.as_any()._get("style")).get_property_value(
    "display",
  ) ==
  "block"
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

// その場編集の欄。SVG の中では IME を走らせられないので、箱の上に HTML の欄を重ねる。
//
// ラベルは**打つたびに md へ書く**（キャンセルは存在しない。打った字はもう md に在る —
// spec.md「Mindmap 側」）。IME の変換中は待ち、確定で書く。
// カードは**閉じるときに 1 回**書く（コードは打っている途中の中間状態が md に流れると、
// フェンスが割れて木が壊れる。spec.md「C カード」）。
//
// 欄をどこに置くかは map/place.mbt が数え、ここは style に入れるだけ。

///|
/// 欄の置き方を style に入れる。border は拡大しない
fn put(
  e : @dom.Element,
  p : @map.Placement,
  border : Double,
  line_height : Double?,
) -> Unit {
  @web.set_style(e, "left", @web.px(p.left))
  @web.set_style(e, "top", @web.px(p.top))
  @web.set_style(e, "width", @web.px(p.width))
  @web.set_style(e, "height", @web.px(p.height))
  @web.set_style(e, "font-size", @web.px(p.font_size))
  @web.set_style(e, "border-width", @web.px(border))
  match line_height {
    Some(lh) => {
      @web.set_style(e, "line-height", @web.px(lh))
      @web.set_style(e, "padding", @web.px(p.padding))
    }
    None => {
      @web.set_style(e, "padding-left", @web.px(p.padding))
      @web.set_style(e, "padding-right", @web.px(p.padding))
    }
  }
}

///|
/// ラベルの欄。開く / 打つたびに rename / 閉じる。値の意味は持たない
pub struct LabelField {
  input : @dom.Element
  pane : @dom.HTMLElement
  measure : @map.Measure
  rename : (Int, String) -> Unit
  /// 読みのサイクルを越えて id を持つ唯一の場所。Rename は木の形を変えず番号を
  /// 振り直さないので安全。形を変える操作が編集中に走ることは無い（欄が開いている間は
  /// keydown が地図へ届かない）
  mut id : Int?
  mut composing : Bool
  /// 最後に place へ渡された配置と視点。打鍵のたびに欄を今の値へ合わせ直すのに使う
  /// （変換中は md へ書かず render も走らないので、ここから自分で place する）
  mut last : (@map.Layout, @map.Camera)?
}

///|
fn LabelField::new(
  doc : @dom.Document,
  pane : @dom.HTMLElement,
  measure : @map.Measure,
  rename : (Int, String) -> Unit,
) -> LabelField {
  let input = doc.createElement("input")
  input.setAttribute("class", "label-editor")
  input.setAttribute("spellcheck", "false")
  pane.append(input.as_node())
  let f : LabelField = {
    input,
    pane,
    measure,
    rename,
    id: None,
    composing: false,
    last: None,
  }
  @web.listen(input, "compositionstart", _ => f.composing = true)
  @web.listen(input, "compositionend", _ => {
    f.composing = false
    f.write()
  })
  @web.listen(input, "input", e => {
    // 欄は打った字の分だけ先に育つ。md へ書くかは別の話
    match f.last {
      Some((l, c)) => f.place(l, c)
      None => ()
    }
    if f.composing || @web.is_composing(e) {
      return
    }
    f.write()
  })
  @web.listen(input, "keydown", e => {
    let k = @web.keyboard(e)
    if k.isComposing || k.keyCode == 229 {
      return
    }
    // 地図のキーへ流さない（Enter が「兄弟を足す」に化ける）
    @web.stop(e)
    if k.key == "Escape" || k.key == "Enter" {
      @web.prevent(e)
      // キー由来の close だけ、地図へフォーカスを戻す。blur は既にフォーカスが
      // 行き先を持っている最中なので奪わない
      f.close()
      pane.focus()
    } else if k.key == "Tab" {
      // 編集中の Tab は無効（spec.md）
      @web.prevent(e)
    }
  })
  // 欄の外を押す・md 側に触る・Mod+/ で移る — フォーカスが抜けたら閉じる
  @web.listen(input, "blur", _ => f.close())
  f
}

///|
pub fn LabelField::editing(self : LabelField) -> Int? {
  self.id
}

///|
/// 開く。カーソルは末尾（全選択しない）。seed があればそれが最初の字
fn LabelField::open(
  self : LabelField,
  id : Int,
  l : @map.Layout,
  cam : @map.Camera,
  label : String,
  seed : String?,
) -> Unit {
  self.id = Some(id)
  @web.set_value(self.input, seed.unwrap_or(label))
  @web.show(self.input, "block", true)
  self.place(l, cam)
  @web.focus(self.input)
  let end = @web.value(self.input).length()
  @web.select_range(self.input, end, end)
  // 最初の字はもう欄に在るので、いまの値を md へ
  if seed is Some(_) {
    self.write()
  }
}

///|
/// 箱に追従する。書くたびに箱が変わるので、描き直しの後に呼ぶ。
/// 箱が消えていれば（畳まれて埋もれた）閉じる
fn LabelField::place(
  self : LabelField,
  l : @map.Layout,
  cam : @map.Camera,
) -> Unit {
  guard self.id is Some(id) else { return }
  guard l.boxes.get(id) is Some(b) else {
    self.close()
    return
  }
  self.last = Some((l, cam))
  let w = (self.measure)(
    @map.label_font(@map.row_of(b.node)),
    @web.value(self.input),
  )
  put(self.input, @map.label_place(b, cam, w), @map.label_border, None)
}

///|
/// 閉じる。書くものは無い（もう書いてある）。二重に閉じても何も起きない
fn LabelField::close(self : LabelField) -> Unit {
  guard self.id is Some(_) else { return }
  // 変換中にフォーカスが抜けたなら、未確定ぶんを取りこぼさない
  // （keydown は isComposing で早期リターンするので、ここに来るのは blur だけ）
  if self.composing {
    self.composing = false
    self.write()
  }
  self.id = None
  self.last = None
  @web.show(self.input, "block", false)
}

///|
fn LabelField::write(self : LabelField) -> Unit {
  match self.id {
    Some(id) => (self.rename)(id, @web.value(self.input))
    None => ()
  }
}

///|
/// その中身から起きたカードの矩形（world）。カードにならない中身と、
/// 持ち主が畳まれた中身は None
fn card_rect_of(l : @map.Layout, block : Int) -> @map.Rect? {
  guard @map.owner_of(l, block) is Some((b, i)) else { return None }
  guard @map.card_rect(b, i) is Some(r) else { return None }
  Some({ x: b.rect.x + r.x, y: b.rect.y + r.y, w: r.w, h: r.h, })
}

///|
/// カードの欄。ラベルと違って**閉じるときに 1 回だけ**書く
pub struct CardField {
  box : @dom.Element
  highlight : @dom.Element
  textarea : @dom.Element
  pane : @dom.HTMLElement
  measure : @map.Measure
  /// コードの色分け。実体は ts の highlight（CodeMirror の言語表）
  tokens : (String) -> Array[Array[Token]]
  commit : (Int, String) -> Unit
  /// 開いたときの値。閉じるとき、これと違えば書く（同じなら書かない）
  mut opened : String
  mut id : Int?
  mut last : (@map.Layout, @map.Camera)?
}

///|
fn CardField::new(
  doc : @dom.Document,
  pane : @dom.HTMLElement,
  measure : @map.Measure,
  tokens : (String) -> Array[Array[Token]],
  commit : (Int, String) -> Unit,
) -> CardField {
  let box = doc.createElement("div")
  box.setAttribute("class", "card-editor")
  @web.show(box, "block", false)
  let highlight = doc.createElement("pre")
  highlight.setAttribute("class", "highlight")
  let textarea = doc.createElement("textarea")
  textarea.setAttribute("spellcheck", "false")
  box.append(highlight.as_node())
  box.append(textarea.as_node())
  pane.append(box.as_node())
  let f : CardField = {
    box,
    highlight,
    textarea,
    pane,
    measure,
    tokens,
    commit,
    opened: "",
    id: None,
    last: None,
  }
  @web.listen(textarea, "input", _ => {
    f.paint()
    match f.last {
      Some((l, c)) => f.place(l, c)
      None => ()
    }
  })
  @web.listen(textarea, "keydown", e => {
    // 地図のキーへ流さない（Delete がカードを消すに化ける）
    @web.stop(e)
    let k = @web.keyboard(e)
    // 変換中の Esc / Enter は IME のもの
    if k.isComposing || k.keyCode == 229 {
      return
    }
    if k.key == "Escape" || (k.key == "Enter" && (k.ctrlKey || k.metaKey)) {
      @web.prevent(e)
      f.close()
      pane.focus()
    } else if k.key == "Tab" {
      @web.prevent(e)
    }
  })
  @web.listen(textarea, "blur", _ => f.close())
  f
}

///|
pub fn CardField::editing(self : CardField) -> Int? {
  self.id
}

///|
/// 開く。`from` / `to` は最初に選んでおく範囲（無ければ末尾にカーソル）
fn CardField::open(
  self : CardField,
  id : Int,
  l : @map.Layout,
  cam : @map.Camera,
  text : String,
  from : Int?,
  to : Int?,
) -> Unit {
  self.id = Some(id)
  self.opened = text
  @web.set_value(self.textarea, text)
  @web.show(self.box, "block", true)
  self.paint()
  self.place(l, cam)
  @web.focus(self.textarea)
  let end = text.length()
  let a = from.unwrap_or(end)
  @web.select_range(self.textarea, a, to.unwrap_or(a))
}

///|
/// カードに追従する。書くたび・視点を動かすたびに呼ぶ。持ち主が畳まれてカードが無ければ閉じる
fn CardField::place(
  self : CardField,
  l : @map.Layout,
  cam : @map.Camera,
) -> Unit {
  guard self.id is Some(id) else { return }
  guard card_rect_of(l, id) is Some(rect) else {
    self.close()
    return
  }
  self.last = Some((l, cam))
  let lines = @web.value(self.textarea)
    .split("\n")
    .map(x => x.to_owned())
    .collect()
  let font = @map.mono_font
  let mut widest = 0.0
  for line in lines {
    widest = @cmp.maximum(widest, (self.measure)(font, line))
  }
  put(
    self.box,
    @map.card_place(rect, cam, lines.length(), widest),
    @map.card_border,
    Some(@map.code_line * cam.k),
  )
}

///|
/// 色付き層を今の中身で塗り直す
fn CardField::paint(self : CardField) -> Unit {
  guard self.highlight.ownerDocument() is Some(doc) else { return }
  self.highlight.replaceChildren([])
  for line in (self.tokens)(@web.value(self.textarea)) {
    for t in line {
      let span = doc.createElement("span")
      if t.cls != "" {
        span.setAttribute("class", t.cls)
      }
      span.setTextContent(t.text)
      self.highlight.append(span.as_node())
    }
    // 空行でも高さを持たせる（改行だけの行がある文書で行がずれる）
    self.highlight.append(doc.createTextNode("\n").as_node())
  }
}

///|
/// 閉じる。値が開いたときと違えば `commit` を 1 回。二重に閉じても何も起きない
fn CardField::close(self : CardField) -> Unit {
  guard self.id is Some(id) else { return }
  let v = @web.value(self.textarea)
  self.id = None
  self.last = None
  @web.show(self.box, "block", false)
  if v != self.opened {
    (self.commit)(id, v)
  }
}

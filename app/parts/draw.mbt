// その場で描いて、画像として貼る。
//
// mmm の中に描く道は他に無い（外の道具で描いて貼ることはできるが、それは
// mmm を離れる）。**保存の道は増やさない** — 描いたものは貼り付けや
// ドロップとまったく同じ `Images::save_to_disk` を通るので、WebP への変換も
// 名前の確認も画像フォルダの結び付けも、そこ 1 か所が持ち続ける。
//
// 紙は**描いた順の並びの写像**（sheet.mbt の `Sheet`）。ここが持つのは、それを
// canvas に載せる道具立て（`Board`）と窓（`show_drawing`）。
//
// **道具は選ばせるのではなく、絞って並べる。** OS のカラーピッカーと生の
// スライダーは「何でも選べます」としか言っておらず、選ぶ手間だけを渡して
// くる。出すのは黒とアクセントカラーと消しゴム、そして 3 段の太さだけ。
// ピッカーは**主役にはしない**が、筆の丸をダブルクリックか右クリックすれば
// 出て、その筆の色を差し替えられる — 並びは 2 本のまま、色だけ好きに。

///|
let width = 720.0

///|
let height = 440.0

///|
/// 紙の色。消しゴムはこの色で描く（出来上がりは透過を持たない WebP）
let paper = "#ffffff"

///|
/// 拡大しても粗くならない範囲。上げすぎると重くなるだけ
let max_dpr = 2.0

///|
/// 紙の上で字と同じに読める黒。既定の筆
let black = "#111111"

///|
/// アクセントカラーが読めないときの筆。**style.css の `--accent` の既定と
/// 同じ値**を写してある — 読めないのは style.css そのものが来ていないときで、
/// そこで筆を 1 本減らすより、既定の色で出しておくほうが揃う
let default_accent = "#5932ff"

///|
/// 太さは細・中・太の 3 段。**その段が何 px になるかはインクが決める** —
/// 消しゴムはペンと同じ太さでは細すぎて使えない。掛け算を隠さず表で持ち、
/// ボタンの点も選んだインクに合わせて太る（見えている点が、出てくる太さ）
let pen_nibs : Array[Double] = [2.0, 4.0, 8.0]

///|
let eraser_nibs : Array[Double] = [8.0, 16.0, 24.0]

///|
/// 既定は真ん中
let default_step = 1

///|
/// 筆。色は差し替えられる（ピッカー）
pub struct Pen {
  mut color : String
}

///|
/// 描くもの。**消しゴムは紙の色のインク**でしかない（`pointerdown` は
/// 実際、色と太さを差し替えているだけ）。同じ並びの中に置けば「消しながら
/// 色を選ぶ」のような、意味の無い組み合わせが最初から作れない — 別の
/// 切り替えとして持つと、そこは自分で塞ぐことになる
pub enum Ink {
  Pen(Pen)
  Eraser
}

///|
fn nibs_of(ink : Ink) -> Array[Double] {
  match ink {
    Eraser => eraser_nibs
    Pen(_) => pen_nibs
  }
}

///|
/// canvas の 2d に載せる
fn canvas_paint(ctx : @core.Any) -> Paint {
  {
    fill: () => @web.fill_rect(ctx, paper, width, height),
    line: (color, w, points) => {
      let xy = FixedArray::make(points.length() * 2, 0.0)
      for i, p in points {
        xy[i * 2] = p.x
        xy[i * 2 + 1] = p.y
      }
      @web.stroke_line(ctx, color, w, xy)
    },
  }
}

///|
/// 押しても送らないボタン（form の中に居る）。字は無くてもよい（太さの点）
fn button(doc : @dom.Document, class : String, label : String) -> @dom.Element {
  let b = @web.html_text(doc, "button", class, label)
  b.setAttribute("type", "button")
  b
}

///|
/// 小さな集合から 1 つだけ選ぶ並び。**インクも太さも同じ形**なので器は 1 つ。
/// 選ばれているものに `on` が付き、選び直せば前の印は外れる
fn[T] picker(
  values : Array[T],
  face : (T) -> @dom.Element,
  chosen : Int,
  on_pick : (T, Int) -> Unit,
) -> Array[@dom.Element] {
  let buttons = values.map(face)
  for i, b in buttons {
    @web.toggle_class(b, "on", i == chosen)
    @web.listen(b, "click", _ => {
      for other in buttons {
        @web.toggle_class(other, "on", false)
      }
      @web.toggle_class(b, "on", true)
      on_pick(values[i], i)
    })
  }
  buttons
}

///|
/// インク 1 つぶんの見た目。**どれも同じ大きさの丸** — 消しゴムは色を持てない
/// ので、中に絵を入れる（紙の色で塗った丸は、明るいテーマで器と同じ色になって
/// 消える）
fn ink_face(doc : @dom.Document, ink : Ink) -> @dom.Element {
  match ink {
    Eraser => {
      let b = icon_button(doc, "eraser", title="Eraser")
      b.setAttribute("class", "ink eraser")
      b
    }
    Pen(pen) => {
      let b = button(doc, "ink", "")
      // 色そのものは道具の持ち物。CSS には形だけを置く
      let paint = () => {
        @web.set_style(b, "--swatch", pen.color)
        b.setAttribute("title", pen.color + " — double-click to change")
        b.setAttribute("aria-label", "Color " + pen.color)
      }
      paint()
      // 色の差し替え。ダブルクリックでも右クリックでも同じピッカー（見えない
      // `<input type="color">` を押す。ロゴのアクセントカラーと同じ手）。
      // 筆の値そのものを書き換えるので、選んでいる筆ならそのまま次の一手から効く。
      // **入力は丸に重ねて置く** — OS のピッカーは入力の箱の位置に出るので、
      // 箱が無い（`hidden`）と窓の隅に出る。見た目と押下は丸のもの（`.pick`）
      let pick = @web.html(doc, "input", "pick")
      pick.setAttribute("type", "color")
      pick.setAttribute("tabindex", "-1")
      @web.listen(pick, "input", _ => {
        pen.color = @web.value(pick)
        paint()
      })
      let open = (e : @core.Any) => {
        @web.prevent(e)
        @web.set_value(pick, pen.color)
        @web.click(pick)
      }
      @web.listen(b, "dblclick", open)
      @web.listen(b, "contextmenu", open)
      b.append(pick.as_node())
      b
    }
  }
}

///|
/// 太さ 1 つぶんの見た目。**その太さの点そのもの**を出す
/// （字で "2px" と書くより、出てくる線の太さが直に分かる）。
/// 実際の大きさは選んでいるインクで変わるので、`--nib` は後から入れる
fn nib_face(doc : @dom.Document) -> @dom.Element {
  button(doc, "nib", "")
}

///|
/// 描く道具と紙。`.draw` の中身そのもので、窓（`show_drawing`）はこれを載せる
pub struct Board {
  el : @dom.Element
  canvas : @dom.Element
  sheet : Sheet
}

///|
/// 紙の canvas に 2d を開く（既定の載せ先）
fn paper_of(doc : @dom.Document, canvas : @dom.Element) -> Paint {
  canvas_paint(
    @web.paper_2d(canvas, @cmp.minimum(@web.device_pixel_ratio(doc), max_dpr)),
  )
}

///|
/// 道具と紙を組む。**置くのは呼ぶ側** — アプリは窓に載せ、並べて見る道具は
/// そのまま置く。`paint` は紙の載せ先（試験は記録に差し替える）
fn Board::new(
  doc : @dom.Document,
  paint? : (@dom.Element) -> Paint = canvas => paper_of(doc, canvas),
) -> Board {
  let body = @web.html(doc, "div", "draw")

  // ---- 道具立て ----
  //
  // 並びは 3 つの塊 — **何で描くか**（インク）と**どのくらいで**（太さ）を
  // 左に置き、**やり直すもの**（Undo / Clear）だけを右へ離す。描くために
  // 選ぶものと、描いたものを取り消すものは種類が違う。
  //
  // 筆の並びは**窓を開くたびに組む** — アクセントカラーはその間に変わりうる。
  // アクセントカラーも 1 本の筆にする（綴りは持たず、ロゴと同じ `--accent` を
  // 読む。読めなければ既定の色で出す）。黒の**後ろ**に置くのは、既定に
  // すると淡いアクセントカラーのときに紙の上で消えるため — 選べば使えるが、
  // 黙って選ばれてはいない
  let inks : Array[Ink] = [
    Pen({ color: black, }),
    Pen({ color: accent(doc).unwrap_or(default_accent), }),
    Eraser,
  ]
  let ink : Ref[Ink] = { val: inks[0], }
  let step : Ref[Int] = { val: default_step, }
  let bar = @web.html(doc, "div", "tools")
  let nib_buttons = picker(pen_nibs, _ => nib_face(doc), default_step, (_, i) => {
    step.val = i
  })
  // ボタンの点を、いま選んでいるインクの太さに合わせる
  let sync_nibs = () => {
    let table = nibs_of(ink.val)
    for i, b in nib_buttons {
      let size = @web.px(table[i])
      @web.set_style(b, "--nib", size)
      b.setAttribute("title", size)
      b.setAttribute("aria-label", size)
    }
  }
  let ink_row = @web.html(doc, "div", "inks")
  for
    b in picker(inks, i => ink_face(doc, i), 0, (value, _) => {
      ink.val = value
      sync_nibs()
    }) {
    ink_row.append(b.as_node())
  }
  let nibs = @web.html(doc, "div", "nibs")
  for b in nib_buttons {
    nibs.append(b.as_node())
  }
  sync_nibs()
  let undo = button(doc, "", "Undo")
  undo.setAttribute("title", "Mod+Z")
  let clear = button(doc, "", "Clear")
  let actions = @web.html(doc, "div", "group")
  actions.append(undo.as_node())
  actions.append(clear.as_node())
  bar.append(ink_row.as_node())
  bar.append(nibs.as_node())
  bar.append(actions.as_node())

  // ---- 紙 ----
  // 絵の比は常に width:height（画素は dpr 倍）。表示だけは窓に入る大きさまで縮む
  // （CSS の max-width。高さは canvas 自身の比から決まる）
  let dpr = @cmp.minimum(@web.device_pixel_ratio(doc), max_dpr)
  let canvas = @web.html(doc, "canvas", "paper")
  canvas.setAttribute("width", @web.num(width * dpr))
  canvas.setAttribute("height", @web.num(height * dpr))
  @web.set_style(canvas, "width", @web.px(width))
  let sheet = Sheet::new(paint(canvas))

  // ---- 描く ----
  // 画面の点を紙の座標へ。**表示が縮んでいても紙の上では同じ場所**に
  // 描けるよう、実際に表示されている大きさで割り戻す
  let at = (e : @core.Any) => {
    let m = @web.mouse(e)
    let r = @web.client_rect(canvas)
    {
      x: (m.clientX - r.left) * width / r.width,
      y: (m.clientY - r.top) * height / r.height,
    }
  }
  @web.listen(canvas, "pointerdown", e => {
    // 押した瞬間にフォーカスが body へ逃げると Esc / Mod+Enter が死ぬ
    @web.prevent(e)
    @web.capture(canvas, @web.pointer_id(e))
    let color = match ink.val {
      Eraser => paper
      Pen(pen) => pen.color
    }
    sheet.begin(at(e), color, nibs_of(ink.val)[step.val])
  })
  @web.listen(canvas, "pointermove", e => sheet.draw_to(at(e)))
  @web.listen(canvas, "pointerup", _ => sheet.end())
  @web.listen(canvas, "pointercancel", _ => sheet.end())

  // ---- やり直す ----
  @web.listen(undo, "click", _ => sheet.undo())
  @web.listen(clear, "click", _ => sheet.clear())
  body.append(bar.as_node())
  body.append(canvas.as_node())
  { el: body, canvas, sheet, }
}

///|
/// 最後の一手を戻す（Mod+Z）
fn Board::undo(self : Board) -> Unit {
  self.sheet.undo()
}

///|
/// いまの絵。WebP が作れない環境では PNG へ落ちる（type が空になる）。作れなければ None
async fn Board::picture(self : Board) -> @core.Any? {
  @core.identity_option(
    @web.canvas_blob(self.canvas, "image/webp", 0.92).wait(),
  )
}

///|
/// 窓に載せる form。題・道具と紙・足元のボタン。`insert` には板を渡す（絵は板から取る）
pub fn draw_form(
  doc : @dom.Document,
  cancel : () -> Unit,
  insert : (Board) -> Unit,
  paint? : ((@dom.Element) -> Paint)? = None,
) -> (@dom.Element, Board) {
  let form = doc.createElement("form")
  form.setAttribute("method", "dialog")
  form.append(@web.html_text(doc, "p", "title", "Draw").as_node())
  form.append(
    @web.html_text(doc, "p", "note", "Mod+Enter to insert, Esc to discard").as_node(),
  )
  let board = match paint {
    Some(paint) => Board::new(doc, paint~)
    None => Board::new(doc)
  }
  // 足元はたずねと同じ並び。進む側は送信ではなく、押せば板を渡す
  let (row, go) = footer(doc, "Insert", "Cancel", cancel)
  go.setAttribute("type", "button")
  @web.listen(go, "click", _ => insert(board))
  form.append(board.el.as_node())
  form.append(row.as_node())
  (form, board)
}

///|
/// 描いてもらって、その絵を返す。キャンセルなら None。
///
/// 確定は `Mod+Enter` か確定ボタン、破棄は `Esc` かキャンセルボタン。
/// **マップの入力欄と違って破棄がある** — あちらは既に文書に在るものを直す
/// ので「確定のみ」でよいが、こちらは確定するまで文書に何も無く、
/// 引き返せないと逃げ場が無い
pub async fn show_drawing(doc : @dom.Document) -> @core.Any? {
  // 器はたずねと同じ `<dialog class="ask">`。焦点の閉じ込め・Esc・後ろの幕は
  // ブラウザが持つので、ここでは書かない
  let dlg = @web.html(doc, "dialog", "ask")
  // 閉じ方は `<dialog>` の 1 つ — Esc も Cancel も `close()` で、進んだとき
  // だけ `"ok"` を添える。絵を待つ間に Esc を押されても close は
  // 1 度しか起きないので、二重に返らない
  let picture : Ref[@core.Any?] = { val: None, }
  let insert = (board : Board) => {
    @js_async.Promise::from_async(async fn() {
      picture.val = board.picture()
      @web.close_with(dlg, "ok")
    })
    |> ignore
  }
  let (form, board) = draw_form(doc, () => @web.close_dialog(dlg), insert)
  // Esc は dialog が持つ。全体のショートカット（shortcuts.mbt）は窓の中では
  // 黙るので、ここで拾うのは窓だけのキー
  @web.listen(dlg, "keydown", e => {
    let k = @web.keyboard(e)
    guard k.ctrlKey || k.metaKey else { return }
    if k.key == "Enter" {
      @web.prevent(e)
      insert(board)
    } else if k.key == "z" || k.key == "Z" {
      @web.prevent(e)
      board.undo()
    }
  })
  dlg.append(form.as_node())
  match doc.body() {
    Some(b) => b.append(dlg.as_node())
    None => ()
  }
  let closed = @web.promise_of(k => @web.listen(dlg, "close", k))
  @web.show_modal(dlg)
  closed.wait() |> ignore
  let ok = @web.return_value(dlg) == "ok"
  dlg.remove()
  if ok {
    picture.val
  } else {
    None
  }
}

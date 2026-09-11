// カード 1 枚を SVG にする。
//
// `map/card.mbt` が**分類**（Block → Card。DOM を知らない）で、こちらが
// **見せ方**（Card → SVG）。種類ごとに形・クラス・埋め方が縦に並ぶので、
// リンクカードを直したい人はこのファイルの `link` だけを見ればよい。
//
// 置き場所は自分では数えない — `@map.card_rect` が唯一の出所で、選んだ枠も
// 入力欄も同じ数を使う。字の大きさも `@map` の字（card_font / note_font / tiny_font /
// mono_font）を属性で入れ、CSS に同じ数字を持たせない（metric.mbt の決め）。
// class と data-* は ts の style.css とハンドラとの契約 — 変えない。
// `data-card` はカードが出た**中身の id** 1 つ（枚目は入れない）。

///|
/// カードが出た中身の id を出す属性。input.mbt が読み、style.css が当たり判定に使う契約
let data_card = "data-card"

///|
/// カード 1 枚を置く場所
pub(all) struct Spot {
  /// 中身を置く矩形（箱の左上から見た座標）
  rect : @map.Rect
  /// 行の枠の上端。中身より上にあり、差は `card_inset` ぶん
  row_y : Double
  /// ノードの箱の幅。仕切り線だけは中身ではなく箱に合わせて引く
  box_w : Double
  /// `data-card` に入れる、そのカードが出た中身の id
  id : Int
}

///|
/// `data-card` の属性。押せばこの中身が選ばれる
fn Spot::mark(self : Spot) -> (String, String) {
  (data_card, self.id.to_string())
}

///|
/// コードの色分けの 1 塊。`cls` が空なら色の付かない地の文
pub(all) struct Token {
  text : String
  cls : String
}

// ---- 矩形と線を書く。数は core の Rect のまま、SVG の属性にするのはここだけ ----

///|
/// 要素をその矩形にぴったり被せる（x / y / width / height）
fn cover(e : @dom.Element, r : @map.Rect) -> Unit {
  @web.set_rect(e, r.x, r.y, r.w, r.h)
}

///|
/// 矩形を持つ要素（rect / image）を、その矩形に置いて作る
fn rect_el(
  doc : @dom.Document,
  tag : String,
  attrs : Array[(String, String)],
  r : @map.Rect,
) -> @dom.Element {
  let e = @web.el(doc, tag, attrs)
  cover(e, r)
  e
}

///|
/// 線を引いて作る
fn line_el(
  doc : @dom.Document,
  attrs : Array[(String, String)],
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> @dom.Element {
  let e = @web.el(doc, "line", attrs)
  @web.set_line(e, x1, y1, x2, y2)
  e
}

///|
/// 字の要素。大きさは core の字で決まり、属性で入れる
fn text_el(
  doc : @dom.Document,
  attrs : Array[(String, String)],
  font : @map.Font,
  x : Double,
  y : Double,
  text : String,
) -> @dom.Element {
  let e = @web.el(doc, "text", attrs)
  e.setAttribute("font-size", font.px.to_string())
  e.setAttribute("x", @web.num(x))
  e.setAttribute("y", @web.num(y))
  e.setTextContent(text)
  e
}

///|
/// 行と行のあいだの仕切り。種類によらず引く
fn separator(doc : @dom.Document, at : Spot) -> @dom.Element {
  line_el(
    doc,
    [("class", "sep")],
    @map.normal.pad - 4.0,
    at.row_y,
    at.box_w - @map.normal.pad + 4.0,
    at.row_y,
  )
}

///|
/// 当たり判定の面。**字しか描かないカードに敷く** — 絵や背景を持つ 3 種（画像・
/// コード・SVG）はそれ自身が面になるが、リンクと `<details>` は文字だけなので、
/// カードいっぱいの透明な面が要る。SVG の `text` はインクにしか当たらないので、
/// 敷かないと字の隙間を押したときに何も選べない。
fn hit_face(doc : @dom.Document, at : Spot) -> @dom.Element {
  rect_el(doc, "rect", [("class", "card-hit"), at.mark()], at.rect)
}

///|
fn link(
  doc : @dom.Document,
  title : String,
  url : String,
  at : Spot,
) -> Array[@dom.Element] {
  let { x, y, w, h, } = at.rect
  let hit = hit_face(doc, at)
  let text = text_el(
    doc,
    [("class", "link-row")],
    @map.card_font,
    x,
    y + h / 2.0,
    title,
  )
  let tip = @web.el(doc, "title", [])
  tip.setTextContent(url)
  let open = @web.el(doc, "text", [
    ("class", "link-open"),
    // 枠の内側に収める。外へ出すと、選択の枠が本体より小さく見える
    ("x", @web.num(x + w)),
    ("y", @web.num(y + h / 2.0)),
    ("text-anchor", "end"),
    ("data-url", url),
  ])
  open.setTextContent("↗")
  [hit, text, tip, open]
}

///|
/// 絵を 1 枚。インライン SVG もローカル画像も、貼り方はここだけ
fn picture(doc : @dom.Document, href : String, at : Spot) -> @dom.Element {
  rect_el(
    doc,
    "image",
    [at.mark(), ("preserveAspectRatio", "xMidYMid meet"), ("href", href)],
    at.rect,
  )
}

///|
fn inline_svg(
  doc : @dom.Document,
  markup : String,
  at : Spot,
) -> Array[@dom.Element] {
  let href = "data:image/svg+xml;charset=utf-8," +
    @global.encode_uri_component(markup)
  [picture(doc, href, at)]
}

///|
fn image(
  doc : @dom.Document,
  path : String,
  name : String,
  at : Spot,
  scene : Scene,
) -> Array[@dom.Element] {
  match (scene.image_url)(path) {
    Some(url) => return [picture(doc, url, at)]
    None => ()
  }
  // まだ読めていない（握っていない / ファイルが無い）。読めたときに配置が
  // 飛ばないよう、同じ大きさの場所取りを置く
  let { x, y, w, h, } = at.rect
  let box = rect_el(
    doc,
    "rect",
    [("class", "image-placeholder"), at.mark()],
    at.rect,
  )
  // **黙って空にしない。** 読めない理由は 4 通りあるのに症状は 1 つなので、
  // 場所取りが自分で言う。握っていないだけなら、ここが入口も兼ねる
  let mid = y + h / 2.0
  let label = text_el(
    doc,
    [("class", "image-name"), at.mark(), ("text-anchor", "middle")],
    @map.note_font,
    x + w / 2.0,
    if scene.image_hint is None {
      mid
    } else {
      mid - 7.0
    },
    name,
  )
  guard scene.image_hint is Some(hint) else { return [box, label] }
  // 入口は**この字だけ**。場所取りそのものは選択のままにしておく
  // （2 つの意味を 1 つの当たり判定に乗せない）
  let connect = text_el(
    doc,
    [
      ("class", "image-connect"),
      ("data-connect", "1"),
      ("text-anchor", "middle"),
    ],
    @map.tiny_font,
    x + w / 2.0,
    mid + 8.0,
    hint,
  )
  [box, label, connect]
}

///|
fn code(
  doc : @dom.Document,
  lang : String,
  lines : Array[String],
  at : Spot,
  scene : Scene,
) -> Array[@dom.Element] {
  // 背景は左右にも張り出す（コードは箱の縁まで塗る）。張り出しは矩形に
  // 織り込み済みなので、ここで足し直さない
  let bg = rect_el(doc, "rect", [("class", "code-bg"), at.mark()], at.rect)
  if lang != "" {
    let tip = @web.el(doc, "title", [])
    tip.setTextContent(lang)
    bg.append(tip.as_node())
  }
  let out = [bg]
  let tokens = (scene.tokens)(lines, lang)
  for i, _ in lines {
    let line = text_el(
      doc,
      [("class", "code-line"), at.mark()],
      @map.mono_font,
      @map.normal.pad + 1.0,
      at.row_y +
      @map.code_pad +
      i.to_double() * @map.code_line +
      @map.code_line / 2.0,
      "",
    )
    // 幅の判断は素の文字列で行い、色の付いた塊をそこへ合わせる
    for t in tokens[i] {
      let span = @web.el(
        doc,
        "tspan",
        if t.cls == "" {
          []
        } else {
          [("class", t.cls)]
        },
      )
      span.setTextContent(t.text)
      line.append(span.as_node())
    }
    out.push(line)
  }
  out
}

///|
/// 装飾の水平線。中身の幅いっぱいに 1 本
fn rule(doc : @dom.Document, at : Spot) -> Array[@dom.Element] {
  let { x, y, w, h, } = at.rect
  [
    line_el(
      doc,
      [("class", "break"), at.mark()],
      x,
      y + h / 2.0,
      x + w,
      y + h / 2.0,
    ),
  ]
}

///|
/// `<details>`。GitHub と同じ見え方 — 三角と summary（無ければ Details）、
/// 開いていればその下に中身の字。開閉は md の `open` が決めるので、押しても動かない
fn details(
  doc : @dom.Document,
  open : Bool,
  summary : String?,
  lines : Array[String],
  at : Spot,
) -> Array[@dom.Element] {
  let x = at.rect.x
  let row_mid = at.row_y + @map.details_row / 2.0 // summary の行の中心
  let hit = hit_face(doc, at)
  let mark = text_el(
    doc,
    [("class", "details-mark")],
    @map.tiny_font,
    x,
    row_mid,
    if open {
      "▾"
    } else {
      "▸"
    },
  )
  let name = text_el(
    doc,
    [("class", "details-row")],
    @map.card_font,
    x + @map.details_indent,
    row_mid,
    match summary {
      Some(s) => s
      None => @map.details_name
    },
  )
  let out = [hit, mark, name]
  guard open else { return out }
  let top = at.row_y + @map.details_row
  for i, text in lines {
    out.push(
      text_el(
        doc,
        [("class", "details-line")],
        @map.note_font,
        x + @map.details_indent,
        top + i.to_double() * @map.code_line + @map.code_line / 2.0,
        text,
      ),
    )
  }
  out
}

///|
/// カード 1 枚ぶんの要素。仕切り線を含む、並べればよい形で返す
fn draw_card(
  doc : @dom.Document,
  c : @map.Card,
  at : Spot,
  scene : Scene,
) -> Array[@dom.Element] {
  let body = match c.kind {
    Link(title~, url~) => link(doc, title, url, at)
    Svg(markup~) => inline_svg(doc, markup, at)
    Image(path~, name~) => image(doc, path, name, at, scene)
    Code(lang~, lines~) => code(doc, lang, lines, at, scene)
    Break => rule(doc, at)
    Details(open~, summary~, lines~) => details(doc, open, summary, lines, at)
  }
  let out = [separator(doc, at)]
  out.append(body)
  out
}

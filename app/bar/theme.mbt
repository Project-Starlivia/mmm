// 見た目の好み: アクセントカラーと、ライト / ダーク（既定は OS 設定、
// 分からなければダーク）。どちらも保存して、次のセッションでもそのまま。

///|
pub struct Theme {
  doc : @dom.Document
  set_editor_theme : (Bool) -> Unit
  base : String
  color_input : @dom.Element
  /// favicon は**色と未保存の印**の 2 つで決まる。片方だけ変わっても描き直す
  /// ので、両方をここが覚えておく（呼ぶ側に「前は何色だったか」を持たせない）
  mut favicon_color : String
  mut favicon_dirty : Bool
}

///|
/// index.html の素の favicon（同じ `logo_svg` からビルド時に吐いたもの）を、
/// 色と印の入った data URL で上書きする。実値で埋める必要がある
fn Theme::apply_favicon(self : Theme) -> Unit {
  let doc = self.doc
  // `<link rel=icon>` でないものが居たら作り直す
  let link = match doc.querySelector("link[rel=\"icon\"]") {
    Some(l) if l.tagName().to_upper() == "LINK" => l
    _ => {
      let l = doc.createElement("link")
      l.setAttribute("rel", "icon")
      @web.head(doc).append(l.as_node())
      l
    }
  }
  let svg = logo_svg(self.favicon_color, self.favicon_dirty)
  link.setAttribute(
    "href",
    "data:image/svg+xml," + @global.encode_uri_component(svg),
  )
}

///|
/// アクセントカラーを当てる。**置くのは色そのものだけ** — 薄い版
/// （`--accent-soft`）も輪（`--ring`）も style.css が色から作る。
///
/// ここで `rgba(...)` を組んで置くと、それは要素のインラインスタイルなので
/// `.light` の宣言に**必ず**勝ってしまう。ライト用に薄くしてあった
/// 宣言が一度も効かず、ライトでもダークの濃さのままになっていた
fn Theme::apply_color(self : Theme, hex : String) -> Unit {
  guard @parts.hex_of(hex) is Some(c) else { return }
  @web.set_style(self.doc.documentElement(), "--accent", c)
  self.favicon_color = c
  self.apply_favicon()
  @prefs.store("color", c)
}

///|
pub fn Theme::is_light(self : Theme) -> Bool {
  @web.has_class(self.doc.documentElement(), "light")
}

///|
fn Theme::apply_theme(self : Theme, light : Bool) -> Unit {
  @web.toggle_class(self.doc.documentElement(), "light", light)
  (self.set_editor_theme)(!light)
  @prefs.store("theme", if light { "light" } else { "dark" })
}

///|
pub fn Theme::toggle(self : Theme) -> Unit {
  self.apply_theme(!self.is_light())
}

///|
/// ネイティブの色のピッカーを開く
pub fn Theme::pick_color(self : Theme) -> Unit {
  @web.set_value(self.color_input, @parts.accent(self.doc).unwrap_or(self.base))
  @dom.HTMLElement::cast_from_element(self.color_input).click()
}

///|
/// 未保存かどうかが変わった。タブの印を描き直す（帯の `●` と同じ話）。
/// 変わっていないなら描き直さない — data URL の組み立てと favicon の差し替えは
/// 打鍵のたびに起きうるので、同じ絵を作り直さない
pub fn Theme::set_dirty(self : Theme, dirty : Bool) -> Unit {
  guard dirty != self.favicon_dirty else { return }
  self.favicon_dirty = dirty
  self.apply_favicon()
}

///|
/// カラーとテーマの配線と、保存値の復元。`logo` は 帯 の `<svg id="logo">`
/// （中身はここが入れる）。`set_editor_theme` は CodeMirror 側のテーマ切り替え
/// （DOM の外なので注入）
pub fn Theme::new(
  logo : @dom.Element,
  set_editor_theme : (Bool) -> Unit,
) -> Theme {
  let doc = logo.ownerDocument().unwrap()
  // 既定色は style.css のもの。読めないなら配線が壊れているので、黙って
  // 別の色にすり替えない
  guard @parts.accent(doc) is Some(base) else {
    abort("style.css の --accent が読めない")
  }
  // ロゴの形の源は `logo_path` ひとつ。帯 も favicon もここから作る
  // （静的ファイルに複製すると、以前のように片方だけ左右が反転していても
  // 誰も気づけない）。色は currentColor = --accent
  logo.insertAdjacentHTML("beforeend", logo_inner("currentColor"))
  // ---- アクセントカラー ----
  // ロゴの下に（見えない形で）置く。ネイティブのピッカーが画面外ではなく
  // 左上に開くようにするため
  let input = doc.createElement("input")
  input.setAttribute("type", "color")
  @web.set_style(input, "position", "fixed")
  @web.set_style(input, "left", "10px")
  @web.set_style(input, "top", "10px")
  @web.set_style(input, "width", "24px")
  @web.set_style(input, "height", "24px")
  @web.set_style(input, "opacity", "0")
  @web.set_style(input, "pointer-events", "none")
  match doc.body() {
    Some(b) => b.append(input.as_node())
    None => ()
  }
  let t : Theme = {
    doc,
    set_editor_theme,
    base,
    color_input: input,
    favicon_color: base,
    favicon_dirty: false,
  }
  @web.listen(input, "input", _ => t.apply_color(@web.value(input)))
  @web.listen(logo, "click", _ => t.pick_color())
  // ロゴは <svg role="button">。SVG はフォーカスされても Enter / Space で
  // click を出さないので、ボタンだと名乗る以上ここで自分で出す
  @web.listen(logo, "keydown", e => {
    let k = @web.keyboard(e)
    if k.key == "Enter" || k.key == " " {
      @web.prevent(e)
      t.pick_color()
    }
  })
  // ---- 復元 ----
  // localStorage の中身は何でもありうる（人が書き替えられるし、昔の版が
  // 別の値を入れているかもしれない）。名乗らせずに確かめる
  let light = match @prefs.load("theme") {
    Some("light") => true
    Some("dark") => false
    _ => @web.matches(@web.match_media(doc, "(prefers-color-scheme: light)"))
  }
  t.apply_theme(light)
  t.apply_color(@prefs.load("color").unwrap_or(base))
  t
}

///|
pub let logo_path = "M132.352 143.36V2.56H102.144V23.04H96L100.864 26.624C100.864 18.6027 98.56 12.2027 93.952 7.424C89.344 2.47467 83.6267 0 76.8 0C69.4613 0 63.744 3.15733 59.648 9.472C55.552 15.7867 53.504 24.1493 53.504 34.56L58.112 23.04H50.944L53.248 26.624C53.248 18.6027 51.0293 12.2027 46.592 7.424C42.1547 2.47467 36.1813 0 28.672 0C20.1387 0 13.2267 3.24267 7.936 9.728C2.64533 16.0427 0 24.7467 0 35.84V143.36H33.024V38.4C33.024 34.4747 33.8773 31.488 35.584 29.44C37.2907 27.2213 39.7653 26.112 43.008 26.112C46.2507 26.112 48.7253 27.2213 50.432 29.44C52.1387 31.488 52.992 34.4747 52.992 38.4V143.36H79.36V38.4C79.36 34.4747 80.2133 31.488 81.92 29.44C83.6267 27.2213 86.1013 26.112 89.344 26.112C92.5867 26.112 95.0613 27.2213 96.768 29.44C98.4747 31.488 99.328 34.4747 99.328 38.4V143.36H132.352Z"

///|
/// #logo（viewBox 0 0 144 144）に入れる中身。色は既定で currentColor
pub fn logo_inner(fill : String) -> String {
  "<g transform=\"translate(27.2,23) scale(0.68,0.68)\" fill=\"\{fill}\"><path d=\"\{logo_path}\"/></g>"
}

///|
/// 単体で完結する SVG 文字列（favicon の data URL / アイコンの源）。
///
/// `dirty` を立てると、右下に**未保存の印**が付く — 帯に出ている `●`
/// （`#dirty`）とまったく同じことを、タブの中で言う。ここが持つのは
/// 「ロゴがどう見えるか」だけで、いま未保存かどうかは呼ぶ側が知っている。
///
/// 右下は**状態**の位置（同期やプレゼンスの印と同じ）。右上はバッジ＝
/// 届いたものの件数を言う位置で、この印が言うのは件数ではない。
///
/// 印は**器の色で縁取ってから**塗る。地は白とは限らず（ブラウザのタブは
/// 明るくも暗くもなる）、ロゴのステムに重なると輪郭が溶けるため。
/// 縁取り（stroke の外へ半分）まで含めて viewBox に収める — はみ出すと
/// 16px のタブで印の角が切れる。大きさは 16px 換算で印 4.7px・縁込み
/// 5.8px（アイコンのおよそ 1/3）で、**添えものに見える**ところに置く
pub fn logo_svg(fill : String, dirty : Bool) -> String {
  let mark = if dirty {
    "<circle cx=\"118\" cy=\"118\" r=\"21\" fill=\"none\" stroke=\"#00000055\" stroke-width=\"10\"/>" +
    "<circle cx=\"118\" cy=\"118\" r=\"21\" fill=\"\{fill}\"/>"
  } else {
    ""
  }
  "<svg width=\"144\" height=\"144\" viewBox=\"0 0 144 144\" fill=\"none\" " +
  "xmlns=\"http://www.w3.org/2000/svg\">\{logo_inner(fill)}\{mark}</svg>"
}

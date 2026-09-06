// 見た目の好み: アクセントカラーと、ライト / ダーク（既定は OS 設定、
// 分からなければダーク）。どちらも保存して、次のセッションでもそのまま。

///|
/// 6 桁の hex（`#` は有っても無くても）なら `#rrggbb` に揃える。違えば None
pub fn hex_of(value : String) -> String? {
  let v = value.trim(chars=" \t\r\n").to_owned()
  let body = if v.has_prefix("#") {
    String::unsafe_substring(v, start=1, end=v.length())
  } else {
    v
  }
  guard body.length() == 6 else { return None }
  for i in 0..<6 {
    let c = body[i]
    let ok = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    guard ok else { return None }
  }
  Some("#" + body)
}

///|
/// いまのアクセントカラー。**綴りの源は style.css の `--accent` だけ**で、
/// ここは読むだけ（既定色を他にも書くと、同じ数字が 2 か所になる）。
/// 読んだ値は名乗らせず確かめる — 6 桁の hex でなければ None。
/// 筆にする側（ts の app/draw.ts）も同じ 1 つを読む
pub fn accent(doc : @dom.Document) -> String? {
  hex_of(@web.css_var(doc, "--accent"))
}

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
/// index.html の素の favicon（同じ logo.mbt からビルド時に吐いたもの）を、
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
  guard hex_of(hex) is Some(c) else { return }
  @web.set_style(self.doc.documentElement(), "--accent", c)
  self.favicon_color = c
  self.apply_favicon()
  store("color", c)
}

///|
pub fn Theme::is_light(self : Theme) -> Bool {
  @web.has_class(self.doc.documentElement(), "light")
}

///|
fn Theme::apply_theme(self : Theme, light : Bool) -> Unit {
  @web.toggle_class(self.doc.documentElement(), "light", light)
  (self.set_editor_theme)(!light)
  store("theme", if light { "light" } else { "dark" })
}

///|
pub fn Theme::toggle(self : Theme) -> Unit {
  self.apply_theme(!self.is_light())
}

///|
/// ネイティブの色のピッカーを開く
pub fn Theme::pick_color(self : Theme) -> Unit {
  @web.set_value(self.color_input, accent(self.doc).unwrap_or(self.base))
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
/// カラーとテーマの配線と、保存値の復元。`logo` は topbar の `<svg id="logo">`
/// （中身はここが入れる）。`set_editor_theme` は CodeMirror 側のテーマ切り替え
/// （DOM の外なので注入）
pub fn Theme::new(
  logo : @dom.Element,
  set_editor_theme : (Bool) -> Unit,
) -> Theme {
  let doc = logo.ownerDocument().unwrap()
  // 既定色は style.css のもの。読めないなら配線が壊れているので、黙って
  // 別の色にすり替えない
  guard accent(doc) is Some(base) else {
    abort("style.css の --accent が読めない")
  }
  // ロゴの形の源は logo.mbt ひとつ。topbar も favicon もここから作る
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
  let light = match load("theme") {
    Some("light") => true
    Some("dark") => false
    _ => @web.matches(@web.match_media(doc, "(prefers-color-scheme: light)"))
  }
  t.apply_theme(light)
  t.apply_color(load("color").unwrap_or(base))
  t
}

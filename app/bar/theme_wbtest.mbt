// ロゴ

///|
test "logo_svg: 印の有無" {
  assert_true(logo_svg("#ff0000", false).has_prefix("<svg width=\"144\""))
  assert_false(logo_svg("#ff0000", false).contains("circle"))
  assert_true(logo_svg("#ff0000", true).contains("<circle cx=\"118\""))
  assert_true(logo_inner("currentColor").contains("fill=\"currentColor\""))
}

// 好みの持ち方

///|
/// 見本のアクセントカラー。happy-dom は style.css を読まないので、`--accent` は
/// 直に置く（読めないと Theme::new は配線が壊れていると言って止まる）
let base = "#5932ff"

///|
/// 窓。出来事の構築子も、OS の好みの設定もここに居る
fn win(d : @dom.Document) -> @core.Any {
  d.as_any()._get("defaultView")
}

///|
/// 出来事を 1 つ鳴らす
fn fire(d : @dom.Document, target : @core.Any, name : String) -> Unit {
  let ev = @core.new(win(d)._get("Event"), [@core.any(name), @core.new_object()])
  target._call("dispatchEvent", [ev]) |> ignore
}

///|
/// OS のライト / ダークを差し替えて、変わったことを鳴らす。happy-dom の
/// MediaQueryList は窓の大きさが動いたときしか自分から鳴らない
fn set_os(t : Theme, light : Bool) -> Unit {
  win(t.doc)
  ._get("happyDOM")
  ._get("settings")
  ._get("device")
  ._set("prefersColorScheme", @core.any(if light { "light" } else { "dark" }))
  fire(t.doc, t.os.as_any(), "change")
}

///|
/// テーマを 1 つ立てる。持ち物は毎回まっさらから。返す `Ref` は md 側（本物は
/// CodeMirror）に最後に渡ったダークかどうか
fn stage(
  d : @dom.Document,
  theme? : String,
  color? : String,
) -> (Theme, Ref[Bool]) {
  @web.set_style(d.documentElement(), "--accent", base)
  for k in ["mmm.theme", "mmm.color"] {
    @web.storage_remove(d, k)
  }
  if theme is Some(v) {
    @prefs.store(d, "theme", v)
  }
  if color is Some(v) {
    @prefs.store(d, "color", v)
  }
  let dark : Ref[Bool] = { val: false, }
  (Theme::new(d.createElement("svg"), v => dark.val = v), dark)
}

///|
test "Theme: 選ぶまでは OS に従う。当てても覚えない" {
  with_doc(d => {
    let (t, dark) = stage(d)
    // 立ち上がりでは書かない — まだ誰も選んでいない
    assert_eq(@prefs.load(d, "theme"), None)
    assert_eq(@prefs.load(d, "color"), None)
    // happy-dom の既定はライト
    assert_true(t.is_light())
    assert_false(dark.val)
    set_os(t, false)
    assert_false(t.is_light())
    assert_true(dark.val)
    assert_eq(@prefs.load(d, "theme"), None)
    set_os(t, true)
    assert_true(t.is_light())
  })
}

///|
test "Theme: 人が選んだら覚える。以後 OS が変わっても人の選択が勝つ" {
  with_doc(d => {
    let (t, _) = stage(d)
    set_os(t, false)
    assert_false(t.is_light())
    t.toggle()
    assert_true(t.is_light())
    assert_eq(@prefs.load(d, "theme"), Some("light"))
    // OS はダークのまま。もう一度鳴っても、選んだライトは動かない
    set_os(t, false)
    assert_true(t.is_light())
    t.toggle()
    assert_eq(@prefs.load(d, "theme"), Some("dark"))
  })
}

///|
test "Theme: 覚えた明るさから始まる。知らない綴りは選んでいないのと同じ" {
  with_doc(d => {
    let (t, _) = stage(d, theme="dark")
    assert_false(t.is_light())
    // OS はライトだが、選んだダークが勝つ
    set_os(t, true)
    assert_false(t.is_light())
  })
  with_doc(d => {
    let (t, _) = stage(d, theme="purple")
    assert_true(t.is_light())
    // 直しもしない。書くのは人が選んだときだけ
    assert_eq(@prefs.load(d, "theme"), Some("purple"))
    set_os(t, false)
    assert_false(t.is_light())
  })
}

///|
test "Theme: 色は人が選んだときだけ覚える。覚えが無ければ style.css のまま" {
  with_doc(d => {
    let (t, _) = stage(d)
    assert_eq(@prefs.load(d, "color"), None)
    assert_eq(@parts.accent(d), Some(base))
    @web.set_value(t.color_input, "#00ff00")
    fire(d, t.color_input.as_any(), "input")
    assert_eq(@prefs.load(d, "color"), Some("#00ff00"))
    assert_eq(@parts.accent(d), Some("#00ff00"))
  })
  with_doc(d => {
    let (_, _) = stage(d, color="#00ff00")
    assert_eq(@parts.accent(d), Some("#00ff00"))
  })
}

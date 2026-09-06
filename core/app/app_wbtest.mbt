// 帯と枠の部品を happy-dom で固定する。分割線の居場所は数だけの話なので、
// 出来事無しで並びを総当たりする。

///|
let md_only : Vis = { md: true, map: false, }

///|
let both : Vis = { md: true, map: true, }

///|
let map_only : Vis = { md: false, map: true, }

///|
test "spots_for: 広いときは 3 つ、狭いときは 2 つ。左から右へ並ぶ順は狭くても変わらない" {
  assert_eq(spots_for(false), [map_only, both, md_only])
  assert_eq(spots_for(true), [map_only, md_only])
  for narrow in [false, true] {
    let list = spots_for(narrow)
    assert_eq(list[0], map_only)
    assert_eq(list[list.length() - 1], md_only)
  }
}

///|
test "project: 居場所にある形はそのまま。狭いところへ「両方」が来たらマップを残す。「両方消えた」は作らない" {
  assert_eq(project(both, spots_for(false)), both)
  assert_eq(project(md_only, spots_for(true)), md_only)
  assert_eq(project(both, spots_for(true)), map_only)
  // 名指しの要求を BOTH のまま渡すと map に丸められる（だから toggled が先に行き先を決める）
  let want_md : Vis = { md: true, map: true, }
  assert_eq(project(want_md, spots_for(true)), map_only)
  let none : Vis = { md: false, map: false, }
  assert_eq(project(none, spots_for(false)), both)
  assert_eq(project(none, spots_for(true)), map_only)
}

///|
test "toggled: 隠れているペインを出す / 指名した 1 枚だけ消える / 最後の 1 枚は消せずもう片方が出る" {
  assert_eq(toggled(map_only, Md, spots_for(false)), both)
  assert_eq(toggled(md_only, Map, spots_for(false)), both)
  assert_eq(toggled(map_only, Md, spots_for(true)), md_only)
  assert_eq(toggled(md_only, Map, spots_for(true)), map_only)
  assert_eq(toggled(both, Md, spots_for(false)), map_only)
  assert_eq(toggled(both, Map, spots_for(false)), md_only)
  assert_eq(toggled(md_only, Md, spots_for(false)), map_only)
  assert_eq(toggled(map_only, Map, spots_for(false)), md_only)
  assert_eq(toggled(md_only, Md, spots_for(true)), map_only)
  assert_eq(toggled(map_only, Map, spots_for(true)), md_only)
}

///|
test "toggled: 狭いときは、出す / 引っ込めるをどう繰り返しても「両方」にならない" {
  let list = spots_for(true)
  let mut v = map_only
  for which in [Md, Md, Map, Map, Md, Map] {
    v = toggled(v, which, list)
    assert_false(v.md && v.map)
  }
}

///|
test "Panes: 矢印は分割線を左右に動かし、端で沈む。名前は着く先" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = w.document()
  let body = d.body().unwrap()
  let mk = (id : String) => {
    let e = d.createElement("div")
    e.setAttribute("id", id)
    body.append(e.as_node())
    e
  }
  let md = mk("md-pane")
  let map = mk("map-pane")
  let panes = mk("panes")
  let splitter = mk("splitter")
  let focused : Ref[Int] = { val: 0, }
  let p = Panes::new(md, map, panes, splitter, () => focused.val += 1)
  assert_eq(panes.getAttribute("data-show"), Some("both"))
  assert_eq(p.go_left.getAttribute("aria-label"), Some("Mindmap only"))
  assert_eq(p.go_right.getAttribute("aria-label"), Some("Markdown only"))
  p.slide(1)
  assert_eq(panes.getAttribute("data-show"), Some("md"))
  assert_eq(p.go_right.as_any()._get("disabled").cast(), true)
  p.slide(1)
  assert_eq(panes.getAttribute("data-show"), Some("md"))
  p.toggle_vis(Md)
  assert_eq(panes.getAttribute("data-show"), Some("map"))
  p.toggle_vis(Md)
  assert_eq(panes.getAttribute("data-show"), Some("both"))
}

///|
test "logo_svg: 印の有無" {
  assert_true(logo_svg("#ff0000", false).has_prefix("<svg width=\"144\""))
  assert_false(logo_svg("#ff0000", false).contains("circle"))
  assert_true(logo_svg("#ff0000", true).contains("<circle cx=\"118\""))
  assert_true(logo_inner("currentColor").contains("fill=\"currentColor\""))
}

///|
test "hex_of: 6 桁の hex だけ。# は有っても無くても" {
  assert_eq(hex_of("#7c5cff"), Some("#7c5cff"))
  assert_eq(hex_of(" 7C5CFF "), Some("#7C5CFF"))
  assert_eq(hex_of("#fff"), None)
  assert_eq(hex_of("red"), None)
  assert_eq(hex_of(""), None)
}

///|
test "key_of: 持ち物の綴りはここだけ" {
  assert_eq(key_of("theme"), "mmm.theme")
  assert_eq(key_of("way"), "mmm.exportWay")
  assert_eq(key_of("grab"), "mmm.grab")
}

///|
test "ask_form: 題・補足・絵・字と欄の並び・ボタン。check があれば打つそばから見直す" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = w.document()
  let a = image_name(
    [
      Text("![]("),
      Text("./pics/"),
      // **見本の理由。本物の言葉ではない** — ここが試すのは器の振る舞い
      // （打つそばから見直す）で、言葉は検査と一緒に居る
      // （core/file/assets.mbt の image_name_problem）
      Blank({
        value: "shot",
        check: Some(v => if v == "shot" { Some("Nope") } else { None }),
      }),
      Text(".webp)"),
    ],
    "data:image/svg+xml,x",
  )
  let cancelled : Ref[Int] = { val: 0, }
  let (form, values) = ask_form(d, a, () => cancelled.val += 1)
  assert_eq(form.getAttribute("method"), Some("dialog"))
  assert_eq(
    form.querySelector(".title").unwrap().textContent(),
    "Name this image",
  )
  assert_eq(
    form.querySelector("img.shot").unwrap().getAttribute("src"),
    Some("data:image/svg+xml,x"),
  )
  assert_eq(form.querySelectorAll(".parts span").length(), 3)
  assert_eq(values(), ["shot"])
  // だめな値なので進めない
  let go = form.querySelector("button.go").unwrap()
  assert_eq(go.as_any()._get("disabled").cast(), true)
  assert_eq(form.querySelector(".bad").unwrap().textContent(), "Nope")
  let input = form.querySelector("input").unwrap()
  @web.set_value(input, "other")
  let ev = @core.new(w.as_any()._get("Event"), [@core.any("input")])
  input.as_event_target().dispatchEvent(ev.cast()) |> ignore
  assert_eq(go.as_any()._get("disabled").cast(), false)
  assert_eq(values(), ["other"])
  // 断る
  @dom.HTMLElement::cast_from_element(form.querySelectorAll("button")[0]).click()
  assert_eq(cancelled.val, 1)
  // はい / いいえ には欄も bad も無い
  let (yes, _) = ask_form(d, discard(), () => ())
  assert_true(yes.querySelector("input") is None)
  assert_true(yes.querySelector(".bad") is None)
  assert_eq(yes.querySelectorAll("button")[0].textContent(), "Cancel")
  assert_eq(connect("./pics/").note, Some("Images here point to ./pics/."))
}

///|
test "宣言の 2 箱は表が持つ — 頭の image-folder: は字で、打てるのは道だけ" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = w.document()
  let field : Field = { value: "./pics/", check: None, }
  // 初めて決めるとき。**どこにあるかではなく、md から見た道**を聞く
  let first = declaration("pics", field)
  assert_eq(first.title, "Where is pics, seen from the .md?")
  assert_eq(first.ok, "Save")
  assert_eq(first.note, None)
  assert_eq(first.cancel, None)
  // 選び直して食い違ったとき。断る側が「そのまま」と言う
  let again = redeclaration(field)
  assert_eq(again.title, "The folder changed — update the declaration?")
  assert_eq(again.ok, "Update")
  assert_eq(again.note, Some("Image paths in the document will follow."))
  assert_eq(again.cancel, Some("Keep as is"))
  // 並びはどちらも同じ — 字 1 つと欄 1 つ
  for a in [first, again] {
    assert_eq(a.parts.length(), 2)
    assert_true(a.parts[0] is Text("image-folder:"))
    assert_true(a.parts[1] is Blank(_))
  }
  let (form, values) = ask_form(d, first, () => ())
  assert_eq(
    form.querySelector(".parts span").unwrap().textContent(),
    "image-folder:",
  )
  assert_eq(values(), ["./pics/"])
}

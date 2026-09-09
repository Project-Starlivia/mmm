// たずねの器

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
      // （app/disk/images.mbt の image_name_problem）
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

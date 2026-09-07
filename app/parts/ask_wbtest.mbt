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
      Blank({
        value: "shot",
        check: Some(v => {
          if v == "shot" {
            Some("That name is taken")
          } else {
            None
          }
        }),
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
  assert_eq(
    form.querySelector(".bad").unwrap().textContent(),
    "That name is taken",
  )
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

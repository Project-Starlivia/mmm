// たずねの器

///|
test "ask_form: 題・補足・絵・字と欄の並び・ボタン。check があれば打つそばから見直す" {
  with_doc(d => {
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
    fire(d, input, "Event", "input")
    assert_eq(go.as_any()._get("disabled").cast(), false)
    assert_eq(values(), ["other"])
    // 断る。断る側は送らない（type=button）
    let no = form.querySelectorAll("button")[0]
    assert_eq(no.getAttribute("type"), Some("button"))
    @web.click(no)
    assert_eq(cancelled.val, 1)
    // はい / いいえ には欄も bad も無い
    let (yes, _) = ask_form(d, disk_changed("notes.md"), () => ())
    assert_true(yes.querySelector("input") is None)
    assert_true(yes.querySelector(".bad") is None)
    assert_eq(yes.querySelectorAll("button")[0].textContent(), "Cancel")
    assert_eq(
      folder_connection("./pics/").note,
      Some("Images here point to ./pics/."),
    )
  })
}

///|
test "宣言の 2 箱は表が持つ — 頭の image-folder: は字で、打てるのは道だけ" {
  with_doc(d => {
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
  })
}

///|
/// 名で引いたものは、主語で呼んだものと同じ 1 つ
test "named: 名は主語の表の写しで、渡したものがそのまま届く" {
  let field : Field = { value: "./pics/", check: None, }
  let ask = (kind : String) => {
    named(
      kind,
      text="pics",
      parts=[Text("![]("), Blank(field)],
      shot="data:,",
      field~,
    )
  }
  assert_eq(ask("save").title, save_changes("pics").title)
  assert_eq(ask("changed").title, disk_changed("pics").title)
  assert_eq(ask("place").title, image_place().title)
  assert_eq(ask("connect").note, Some("Images here point to pics."))
  assert_eq(ask("rename").parts.length(), 1)
  assert_eq(ask("imageName").preview, Some("data:,"))
  assert_eq(ask("imageName").parts.length(), 2)
  assert_eq(ask("declaration").title, "Where is pics, seen from the .md?")
  assert_eq(ask("redeclaration").ok, "Update")
}

///|
/// **IDE と同じ 3 択。** 並びは 断り → もう 1 つ → 進む で、色を持つのは進む側だけ。
/// もう 1 つの道は送信で、value が `"alt"`（器の外で 3 つ目の答えを組み立てない）
test "save_changes: 3 つのボタンが 断り・もう 1 つ・進む の順に並ぶ" {
  with_doc(d => {
    let (form, _) = ask_form(d, save_changes("notes.md"), () => ())
    assert_eq(
      form.querySelector(".title").unwrap().textContent(),
      "Do you want to save the changes you made to notes.md?",
    )
    // Don't Save は未保存の字も捨てるので、「残る」とは言わない
    assert_true(form.querySelector(".note") is None)
    let buttons = form.querySelectorAll(".row button")
    assert_eq(buttons.map(b => b.textContent()), [
      "Cancel", "Don't Save", "Save",
    ])
    assert_eq(buttons[0].getAttribute("type"), Some("button"))
    assert_eq(buttons[1].getAttribute("value"), Some("alt"))
    assert_eq(buttons[2].getAttribute("value"), Some("ok"))
    assert_eq(buttons[2].getAttribute("class"), Some("go"))
    // もう 1 つの道を持たないたずねは、ボタン 2 つのまま
    let (two, _) = ask_form(d, disk_changed("notes.md"), () => ())
    assert_eq(two.querySelectorAll(".row button").map(b => b.textContent()), [
      "Cancel", "Overwrite",
    ])
    assert_eq(
      two.querySelector(".title").unwrap().textContent(),
      "notes.md has changed on disk.",
    )
  })
}

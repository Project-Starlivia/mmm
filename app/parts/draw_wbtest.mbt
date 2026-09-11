// お絵描きの道具と窓。紙は sheet_wbtest の記録に載せる

///|
test "Board: 筆は黒・アクセント・消しゴムの並びで最初は黒。太さの点はインクで太る" {
  with_doc(d => {
    let log : Log = { lines: [], }
    let b = Board::new(d, paint=_ => log.paint())
    let inks = b.el.querySelectorAll(".ink")
    assert_eq(inks.length(), 3)
    assert_true(@web.has_class(inks[0], "on"))
    assert_eq(inks[0].getAttribute("aria-label"), Some("Color #111111"))
    assert_eq(inks[1].getAttribute("aria-label"), Some("Color #5932ff"))
    assert_true(@web.has_class(inks[2], "eraser"))
    assert_eq(inks[2].getAttribute("aria-label"), Some("Eraser"))
    // form の中なので、どのボタンも送らない
    for button in b.el.querySelectorAll("button") {
      assert_eq(button.getAttribute("type"), Some("button"))
    }
    let nibs = b.el.querySelectorAll(".nib")
    assert_eq(nibs.map(n => n.getAttribute("title").unwrap()), [
      "2px", "4px", "8px",
    ])
    assert_true(@web.has_class(nibs[1], "on"))
    @web.click(inks[2])
    assert_true(@web.has_class(inks[2], "on"))
    assert_false(@web.has_class(inks[0], "on"))
    assert_eq(nibs.map(n => n.getAttribute("title").unwrap()), [
      "8px", "16px", "24px",
    ])
    assert_eq(b.canvas.getAttribute("width"), Some("720"))
    assert_eq(log.lines, ["fill"])
  })
}

///|
test "draw_form: 題・道具と紙・断りと進む。Insert は板を渡す" {
  with_doc(d => {
    let log : Log = { lines: [], }
    let cancelled : Ref[Int] = { val: 0, }
    let inserted = []
    let (form, board) = draw_form(
      d,
      () => cancelled.val += 1,
      b => inserted.push(b.sheet.strokes.length()),
      paint=Some(_ => log.paint()),
    )
    assert_eq(form.querySelectorAll(".title")[0].textContent(), "Draw")
    assert_eq(form.querySelectorAll(".draw").length(), 1)
    let buttons = form.querySelectorAll(".row button")
    assert_eq(buttons.map(b => b.textContent()), ["Cancel", "Insert"])
    // 進む側も送らない — 押せば板を渡す
    assert_eq(buttons[1].getAttribute("type"), Some("button"))
    @web.click(buttons[0])
    assert_eq(cancelled.val, 1)
    board.sheet.begin({ x: 0, y: 0, }, "#111111", 2)
    @web.click(buttons[1])
    assert_eq(inserted, [1])
  })
}

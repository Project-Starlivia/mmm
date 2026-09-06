// お絵描き。紙は手の並びの写像で、載せ先は記録に差し替えて見る

///|
/// 載せた手の記録
struct Log {
  lines : Array[String]
}

///|
fn Log::paint(self : Log) -> Paint {
  {
    fill: () => self.lines.push("fill"),
    line: (color, w, pts) => {
      self.lines.push(
        color + " " + w.to_string() + " " + pts.length().to_string(),
      )
    },
  }
}

///|
test "Sheet: 点を打ち、引き足すのは最後の一区間だけ。取り消しは末尾を落として引き直し、クリアも一手" {
  let log : Log = { lines: [], }
  let s = Sheet::new(log.paint())
  assert_eq(log.lines, ["fill"])
  s.begin({ x: 1, y: 1, }, "#111111", 4)
  s.draw_to({ x: 2, y: 2, })
  s.draw_to({ x: 3, y: 3, })
  s.end()
  assert_eq(log.lines[1:], ["#111111 4 1", "#111111 4 2", "#111111 4 2"])
  // 終わった後の続きは何もしない
  s.draw_to({ x: 9, y: 9, })
  assert_eq(log.lines.length(), 4)
  s.clear()
  assert_eq(log.lines[4:], ["fill", "#111111 4 3", "fill"])
  s.undo()
  assert_eq(log.lines[7:], ["fill", "#111111 4 3"])
  s.undo()
  assert_eq(log.lines[9:], ["fill"])
  s.undo()
  assert_eq(log.lines.length(), 10)
}

///|
test "Board: 筆は黒・アクセント・消しゴムの並びで最初は黒。太さの点はインクで太る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let log : Log = { lines: [], }
  let b = Board::new(w.document(), paint=_ => log.paint())
  let inks = b.el.querySelectorAll(".ink")
  assert_eq(inks.length(), 3)
  assert_true(@web.has_class(inks[0], "on"))
  assert_eq(inks[0].getAttribute("aria-label"), Some("Color #111111"))
  assert_eq(inks[1].getAttribute("aria-label"), Some("Color #5932ff"))
  assert_true(@web.has_class(inks[2], "eraser"))
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
}

///|
test "draw_form: 題・道具と紙・断りと進む。Insert は板を渡す" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let log : Log = { lines: [], }
  let cancelled : Ref[Int] = { val: 0, }
  let inserted = []
  let (form, board) = draw_form(
    w.document(),
    () => cancelled.val += 1,
    b => inserted.push(b.sheet.strokes.length()),
    paint=Some(_ => log.paint()),
  )
  assert_eq(form.querySelectorAll(".title")[0].textContent(), "Draw")
  assert_eq(form.querySelectorAll(".draw").length(), 1)
  let buttons = form.querySelectorAll(".row button")
  assert_eq(buttons.map(b => b.textContent()), ["Cancel", "Insert"])
  @web.click(buttons[0])
  assert_eq(cancelled.val, 1)
  board.sheet.begin({ x: 0, y: 0, }, "#111111", 2)
  @web.click(buttons[1])
  assert_eq(inserted, [1])
}

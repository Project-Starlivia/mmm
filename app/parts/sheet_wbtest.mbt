// 紙。手の並びの写像で、載せ先は記録に差し替えて数で見る

///|
/// 載せた手の記録。draw_wbtest の板もこれに載せる
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

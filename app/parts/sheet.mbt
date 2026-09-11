// 紙。**描いた順の並びの写像**（`Sheet`）— 取り消しは末尾を落として描き直すだけ。
// 1 枚ずつ画像を控える形だと、720×440 の 2 倍解像度で 1 手あたり 5MB になる。
// 文書の undo が編集の集合を並べて再生するのと同じ考え方。
//
// 載せ先（`Paint`）は canvas の 2d が持つ 2 つの動きだけ。DOM を知らないので、
// 試験は記録に載せて数で見る。canvas に載せるのは draw.mbt

///|
/// 紙の中の座標（CSS ピクセル）
pub(all) struct Pt {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
/// 描いた順に積む手。取り消しはこの並びの末尾を落とす
pub(all) enum Stroke {
  Line(Array[Pt], String, Double)
  Clear
} derive(Eq, Debug)

///|
/// 手を載せる先。canvas の 2d が持つ 2 つの動きだけ（試験では記録に載せる）
pub(all) struct Paint {
  /// 紙の色で塗り潰す
  fill : () -> Unit
  /// 色・太さ・点の並びで線を引く
  line : (String, Double, Array[Pt]) -> Unit
}

///|
/// 紙。手の並びと、それを載せる先
pub struct Sheet {
  strokes : Array[Stroke]
  paint : Paint
  mut drawing : Array[Pt]?
}

///|
fn Sheet::new(paint : Paint) -> Sheet {
  let self : Sheet = { strokes: [], paint, drawing: None, }
  self.repaint()
  self
}

///|
/// 1 手ぶんを紙に載せる
fn Sheet::put(self : Sheet, s : Stroke) -> Unit {
  match s {
    Clear => (self.paint.fill)()
    Line(points, color, w) => (self.paint.line)(color, w, points)
  }
}

///|
/// 並びの通りに引き直す（取り消しと、消しゴムの後始末）
fn Sheet::repaint(self : Sheet) -> Unit {
  (self.paint.fill)()
  for s in self.strokes {
    self.put(s)
  }
}

///|
/// 一手の始まり（点を打つ）
fn Sheet::begin(self : Sheet, p : Pt, color : String, w : Double) -> Unit {
  let points = [p]
  self.drawing = Some(points)
  self.strokes.push(Line(points, color, w))
  self.put(Line(points, color, w))
}

///|
/// 一手の続き。引き足すのは最後の一区間だけ。全部引き直すのは取り消しのときでよい
fn Sheet::draw_to(self : Sheet, p : Pt) -> Unit {
  guard self.drawing is Some(points) else { return }
  guard self.strokes[self.strokes.length() - 1] is Line(_, color, w) else {
    return
  }
  let last = points[points.length() - 1]
  points.push(p)
  (self.paint.line)(color, w, [last, p])
}

///|
fn Sheet::end(self : Sheet) -> Unit {
  self.drawing = None
}

///|
/// 最後の一手を戻す
fn Sheet::undo(self : Sheet) -> Unit {
  if self.strokes.length() == 0 {
    return
  }
  self.strokes.pop() |> ignore
  self.repaint()
}

///|
/// クリアも手のひとつ。取り消しで戻せる
fn Sheet::clear(self : Sheet) -> Unit {
  self.strokes.push(Clear)
  self.repaint()
}

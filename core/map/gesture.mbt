// 指の台帳。**何本が生きていて、前回どこに居たか**だけを持つ。
//
// 「いま何本の指か」は、地図の 5 つの状態（パン / 矩形選択 / ノードのドラッグ /
// カードのドラッグ / ドラッグ候補）とは別の次元なので、混ぜない。
// 1 本のときは何も言わず、既存の 1 ポインタの流れがそのまま担う。
//
// **DOM を知らない。** 受け取るのはペインの左上から測った画面 px で、
// 出すのは `Span`。だから値として試験できる。

///|
/// 押した点からこれだけ動けば「なぞった」（画面 px）。手前なら押したまま
let stray = 8.0

///|
/// 長押しが右クリックメニューに化けるまでの間（ms）
pub let hold_ms = 500

///|
/// 押した点 `from` から (x, y) まで、slop を越えて動いたか
pub fn far(from : Pt, x : Double, y : Double) -> Bool {
  @math.hypot(x - from.x, y - from.y) > stray
}

///|
pub struct Fingers {
  at : Map[Int, Pt]
  /// 組にする 2 本。**途中で入れ替えない** — 入れ替わると地図が跳ぶ
  mut pair : (Int, Int)?
}

///|
pub fn Fingers::new() -> Fingers {
  { at: Map([]), pair: None, }
}

///|
pub fn Fingers::pinching(self : Fingers) -> Bool {
  self.pair is Some(_)
}

///|
/// ちょうど 1 本だけ生きていれば、その「いま」の位置。0 本 or 2 本以上なら None。
/// 組が壊れて 1 本に戻ったとき、その指から 1 本パンを立て直すために使う
/// （実機では、残った指の pointerdown は来ない）
pub fn Fingers::only(self : Fingers) -> Pt? {
  guard self.at.length() == 1 else { return None }
  self.at.values().head()
}

///|
/// 2 本以上あって組が無いなら、いま生きている先頭の 2 本で組む
fn Fingers::form(self : Fingers) -> Unit {
  guard self.pair is None && self.at.length() >= 2 else { return }
  let keys = self.at.keys().collect()
  self.pair = Some((keys[0], keys[1]))
}

///|
pub fn Fingers::down(self : Fingers, id : Int, x : Double, y : Double) -> Unit {
  self.at[id] = { x, y, }
  // 3 本目以降は台帳には載るが、組は最初の 2 本のまま
  self.form()
}

///|
/// 組の片方が実際に動いたときだけ、その前後を返す
pub fn Fingers::moved(
  self : Fingers,
  id : Int,
  x : Double,
  y : Double,
) -> (Span, Span)? {
  guard self.at.get(id) is Some(known) else { return None }
  self.at[id] = { x, y, }
  guard self.pair is Some((p0, p1)) && (p0 == id || p1 == id) else {
    return None
  }
  guard known.x != x || known.y != y else { return None }
  guard self.at.get(if p0 == id { p1 } else { p0 }) is Some(other) else {
    return None
  }
  Some(({ a: other, b: known, }, { a: other, b: { x, y, }, }))
}

///|
pub fn Fingers::up(self : Fingers, id : Int) -> Unit {
  self.at.remove(id)
  guard self.pair is Some((p0, p1)) else { return }
  guard p0 == id || p1 == id else { return }
  // 組の片方が離れた。3 本置いて 1 本離した場合は残りで組み直す
  self.pair = None
  self.form()
}

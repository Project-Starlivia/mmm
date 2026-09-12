// 「どれくらい前か」を英語で綴る。**綴りはここ 1 つ** — 覚えているものの一覧
// （Recent）と控えの一覧が、同じ言い方で古さを言う。

///|
/// どれくらい前か。**読み手が知りたいのは古さ 1 つ。**
///
/// メニューは開くたびに綴り直されるので、相対で書いても古びない。
/// **1 日を越えたら日付へ落とす** — `30 h ago` は数え直さないと読めないが、
/// 日付なら一目で古いと分かる。
///
/// 単位は複数形を持たない綴り（`min` / `h`）を選ぶ。`1 minute` と `2 minutes` を
/// 出し分けるために、言葉の規則を 1 つ抱えることになるのが割に合わない
pub fn age(now : Double, at : Double) -> String {
  let sec = (now - at) / 1000.0
  // 先の時刻（機械の時計が戻った・別の機械で書かれた）は「いま」に寄せる
  if sec < 45.0 {
    return "just now"
  }
  let min = sec / 60.0
  if min < 60.0 {
    return min.to_int().to_string() + " min ago"
  }
  let hour = min / 60.0
  if hour < 24.0 {
    return hour.to_int().to_string() + " h ago"
  }
  let t = @web.local_time(at)
  pad(t[0], 4) + "-" + pad(t[1], 2) + "-" + pad(t[2], 2)
}

///|
/// 頭に 0 を詰めて桁を揃える。日付は縦に並ぶので、桁が揃っていないと読みにくい
fn pad(n : Int, width : Int) -> String {
  let s = n.to_string()
  if s.length() >= width {
    return s
  }
  String::make(width - s.length(), '0') + s
}

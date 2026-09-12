// 古さの綴りを固定する。**日付へ落ちる境目は 24 時間**

///|
let minute : Double = 60_000.0

///|
let hour : Double = 60.0 * minute

///|
test "age: 45 秒までは just now" {
  let now = 1_000_000_000.0
  assert_eq(age(now, now), "just now")
  assert_eq(age(now, now - 44_000.0), "just now")
  // 機械の時計が戻ることがある。先の時刻も「いま」に寄せる
  assert_eq(age(now, now + minute), "just now")
}

///|
test "age: 分と時。単位は複数形を持たない綴り" {
  let now = 1_000_000_000.0
  assert_eq(age(now, now - 45_000.0), "0 min ago")
  assert_eq(age(now, now - minute), "1 min ago")
  assert_eq(age(now, now - 59.0 * minute), "59 min ago")
  assert_eq(age(now, now - hour), "1 h ago")
  assert_eq(age(now, now - 23.0 * hour), "23 h ago")
}

///|
/// **1 日を越えたら日付。** `30 h ago` は数え直さないと読めない
test "age: 24 時間を越えたら日付へ落とす" {
  let now = 1_000_000_000.0
  let out = age(now, now - 24.0 * hour)
  // 時間帯で日は変わるので、形だけを見る（`2026-09-07`）
  assert_eq(out.length(), 10)
  assert_eq(out[4], '-')
  assert_eq(out[7], '-')
  assert_false(out.contains("ago"))
}

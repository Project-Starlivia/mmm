// 覚えの世代交代を固定する。実測（canvas）は数えるだけの偽物に差し替える。

///|
/// 測った回数を数える偽の実測。幅は字数そのもの
fn counting() -> ((@map.Font, String) -> Double, () -> Int) {
  let calls : Ref[Int] = { val: 0, }
  (
    (_f, text) => {
      calls.val = calls.val + 1
      text.length().to_double()
    },
    () => calls.val,
  )
}

///|
let px13 : @map.Font = { px: 13, mono: false, }

///|
test "同じ字は 1 度しか測らない。字が違えば測る" {
  let (raw, calls) = counting()
  let m = cached(4, raw)
  assert_eq(m(px13, "abc"), 3.0)
  assert_eq(m(px13, "abc"), 3.0)
  assert_eq(calls(), 1)
  assert_eq(m(px13, "de"), 2.0)
  assert_eq(calls(), 2)
}

///|
/// 字の大きさが違えば別の覚え（同じ字でも幅が違う）
test "font が違えば別に覚える" {
  let (raw, calls) = counting()
  let m = cached(4, raw)
  m(px13, "a") |> ignore
  m({ px: 11, mono: false, }, "a") |> ignore
  m({ px: 13, mono: true, }, "a") |> ignore
  assert_eq(calls(), 3)
}

///|
/// **上限の倍までは 2 周目で全部当たる。** 全部捨てる形だと、ここが 1 つも
/// 当たらない（1 周の途中で捨てられ、次の周も頭から外れる）
test "上限の倍の綴りを持つ文書は、2 周目から測り直さない" {
  let (raw, calls) = counting()
  let cap = 4
  let m = cached(cap, raw)
  let words = Array::makei(cap * 2, i => "w\{i}")
  for w in words {
    m(px13, w) |> ignore
  }
  assert_eq(calls(), cap * 2)
  // 2 周目・3 周目は 1 つも測らない
  for w in words {
    m(px13, w) |> ignore
  }
  for w in words {
    m(px13, w) |> ignore
  }
  assert_eq(calls(), cap * 2)
}

///|
/// 使われない字（打っている最中の途中の字）は世代交代 2 回で落ちる
test "上限の倍を超えれば、古い字から落ちる" {
  let (raw, calls) = counting()
  let cap = 4
  let m = cached(cap, raw)
  for i in 0..<(cap * 2) {
    m(px13, "old\{i}") |> ignore
  }
  // 新しい字で 2 世代ぶん埋める
  for i in 0..<(cap * 2) {
    m(px13, "new\{i}") |> ignore
  }
  let before = calls()
  // 古い字は落ちているので測り直す
  m(px13, "old0") |> ignore
  assert_eq(calls(), before + 1)
  // 直近の字は残っている
  m(px13, "new\{cap * 2 - 1}") |> ignore
  assert_eq(calls(), before + 1)
}

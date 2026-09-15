// 時間の束ね — 次のフレームを待つもの（per_frame）と、手が止まるのを待つもの（after_quiet）。
// 窓は happy-dom のものを文書から辿る

///|
/// **同じフレームの中で何回頼まれても 1 回。** 画像が N 枚読めれば N 回頼まれる
/// ので、ここが崩れると描き直しが N 回に戻る（#77）
async test "per_frame: 同じフレームの中で何回頼んでも 1 回だけ走る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  let count = Ref::{ val: 0, }
  let ask = per_frame(doc, () => count.val += 1)
  // 100 枚読めた、と 100 回言う
  for _ in 0..<100 {
    ask()
  }
  // まだ 1 回も走っていない（次の描画の直前に回る）
  assert_eq(count.val, 0)
  @dom.wait_animation_frame()
  assert_eq(count.val, 1)
  // 次のフレームは、また頼まれれば走る（1 回きりではない）
  ask()
  ask()
  @dom.wait_animation_frame()
  assert_eq(count.val, 2)
  // 頼まれなければ走らない
  @dom.wait_animation_frame()
  assert_eq(count.val, 2)
}

///|
/// **手が止まるまで走らない。** 連打の最中にディスクへ書かないための束ね（#275）で、
/// ここが崩れると 1 打鍵ごとに書きに行く
async test "after_quiet: 手が止まってから 1 回だけ走る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  let count = Ref::{ val: 0, }
  let ask = after_quiet(doc, 2, () => count.val += 1)
  // 50 打鍵ぶん頼む
  for _ in 0..<50 {
    (ask.call)()
  }
  // まだ 1 回も走っていない（手が止まっていない）
  assert_eq(count.val, 0)
  rest(doc, 30)
  assert_eq(count.val, 1)
  // 止まったあとまた打てば、また 1 回
  (ask.call)()
  rest(doc, 30)
  assert_eq(count.val, 2)
  // 頼まれなければ走らない
  rest(doc, 30)
  assert_eq(count.val, 2)
}

///|
/// **捨てれば走らない。** 積んだ当人（文書）が居なくなったら、待っているものは
/// 行き先を失う（#299）
async test "after_quiet: 捨てれば、待っていたものは走らない" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  let count = Ref::{ val: 0, }
  let ask = after_quiet(doc, 2, () => count.val += 1)
  (ask.call)()
  (ask.cancel)()
  rest(doc, 30)
  assert_eq(count.val, 0)
  // 捨てた後でも、また頼めば走る（札そのものは生きている）
  (ask.call)()
  rest(doc, 30)
  assert_eq(count.val, 1)
  // 何も待っていないときに捨てても何も起きない
  (ask.cancel)()
  rest(doc, 30)
  assert_eq(count.val, 1)
}

///|
/// **打ち続けても、上限の間が経てば走る。** 手が止まるのを待つだけだと、打ち続けるあいだは
/// 何も書かれない — その最中に落ちれば全部を失う（docs/unsaved.md）
async test "after_quiet: 打ち続けても、上限の間が経てば走る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  let count = Ref::{ val: 0, }
  // 静まる間は長く（5 秒）、上限は短く（50ms）。試験のあいだに静まる間は来ないので、
  // 走ったなら上限のおかげ — 機械が重くて待ちが延びても、取り違えない
  let ask = after_quiet(doc, 5000, () => count.val += 1, max_wait=Some(50))
  for _ in 0..<12 {
    (ask.call)()
    rest(doc, 10)
  }
  // 手は一度も止まっていないが、上限が来たので走っている
  assert_true(count.val >= 1)
  // 打つのをやめて捨てれば、それ以上は走らない
  (ask.cancel)()
  let settled = count.val
  rest(doc, 100)
  assert_eq(count.val, settled)
}

///|
/// **待っているものを、いま走らせる。** タブが隠れる・閉じるときは待てない
async test "after_quiet: 急かせば待たずに 1 回走り、待っていなければ何もしない" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  let count = Ref::{ val: 0, }
  let ask = after_quiet(doc, 30, () => count.val += 1, max_wait=Some(60))
  (ask.call)()
  (ask.flush)()
  assert_eq(count.val, 1)
  // 急かした後に、静まる間・上限の間が来ても二度は走らない
  rest(doc, 100)
  assert_eq(count.val, 1)
  // 何も待っていなければ、急かしても走らない
  (ask.flush)()
  assert_eq(count.val, 1)
}

///|
/// **捨てれば、上限の待ちも一緒に捨てる**
async test "after_quiet: 捨てれば、上限の待ちも走らない" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  let count = Ref::{ val: 0, }
  let ask = after_quiet(doc, 30, () => count.val += 1, max_wait=Some(60))
  (ask.call)()
  (ask.cancel)()
  rest(doc, 100)
  assert_eq(count.val, 0)
}

///|
/// `ms` 経つまで返らない。時計そのものを待つので、`wait_animation_frame` では代わらない
async fn rest(doc : @dom.Document, ms : Int) -> Unit {
  promise_of(k => set_timer(doc, ms, () => k(@core.any(0))) |> ignore).wait()
  |> ignore
}

// フレームの束ね。窓は happy-dom のものを文書から辿る

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

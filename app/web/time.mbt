// 時間 — 時計（Date）と、次の描画のフレーム。
// 綴りは持たない — 名前に焼く形は置く側（app/disk）が決める

///|
/// 今の時刻（ms）
pub extern "js" fn now() -> Double =
  #| () => Date.now()

///|
/// その時刻をこの機械の時間帯で割ったもの — `[年, 月(1〜12), 日, 時, 分, 秒]`
pub extern "js" fn local_time(ms : Double) -> FixedArray[Int] =
  #| (ms) => { const d = new Date(ms);
  #|   return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds()]; }

///|
/// **1 フレームに 1 回だけにする。** 返った閉包を同じフレームの中で何回呼んでも、
/// 次の描画の直前に 1 回だけ `f` が走る。
///
/// 画像は 1 枚読めるたびに「描き直して」と言う（app/disk/images.mbt）。N 枚なら
/// N 回で、しかも 1 フレームの中に固まって届く — 描くのは最後の 1 回で足りる（#77）。
///
/// **落とすのは前の回で、残すのは後の回。** 先に 1 回描いてから束ねる形にすると
/// 1 フレームに 2 回になるし、「最後の状態が描かれている」と言い切れなくなる
pub fn per_frame(doc : @dom.Document, f : () -> Unit) -> () -> Unit {
  let waiting : Ref[Bool] = { val: false, }
  () => {
    guard !waiting.val else { return }
    waiting.val = true
    next_frame(doc, () => {
      waiting.val = false
      f()
    })
  }
}

///|
/// 次の描画の直前に 1 回呼ぶ。窓は文書から辿る（happy-dom は global に持たない）
extern "js" fn next_frame(doc : @dom.Document, f : () -> Unit) -> Unit =
  #| (doc, f) => doc.defaultView.requestAnimationFrame(() => f())

// 時間 — 時計（Date）と、次の描画のフレームと、手が止まるのを待つ間。
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

///|
/// **静まってから 1 回。** 返った閉包を何回呼んでも、最後の呼びから `ms` のあいだ
/// 何も来なければ、そこで 1 回だけ `f` が走る。来るたびに待ち時間は引き直す。
///
/// `per_frame` との違いは**待つ相手**。あちらは次の描画（16ms 後に必ず来る）で、
/// 束ねても遅れない。こちらは**人の手が止まるのを待つ** — 連打の最中に走らせたく
/// ないもの（ディスクへの書き込み。#275）はフレームでは早すぎる。
///
/// **落とすのは前の回で、残すのは後の回**（`per_frame` と同じ）。
pub fn after_quiet(doc : @dom.Document, ms : Int, f : () -> Unit) -> Quiet {
  let timer : Ref[Int] = { val: 0, }
  fn stop() {
    if timer.val != 0 {
      clear_timer(doc, timer.val)
      timer.val = 0
    }
  }

  {
    call: () => {
      stop()
      timer.val = set_timer(doc, ms, () => {
        timer.val = 0
        f()
      })
    },
    cancel: stop,
  }
}

///|
/// 静まるのを待つもの。`call` は待ちを積み（呼ぶたびに待ち時間は引き直す）、
/// `cancel` は待っているものを捨てる。
///
/// **待っているあいだに、頼んだ当人が居なくなることがある** — 文書を入れ替えれば、
/// 前の文書のために積んだ書き込みは行き先を失う（#299）。捨てる口が無いと、
/// 積んだものは必ず走ってしまう。
pub struct Quiet {
  call : () -> Unit
  cancel : () -> Unit
}

///|
/// `ms` 後に 1 回呼ぶ。返るのは取り消しに使う札
extern "js" fn set_timer(doc : @dom.Document, ms : Int, f : () -> Unit) -> Int =
  #| (doc, ms, f) => doc.defaultView.setTimeout(() => f(), ms)

///|
/// 待っている呼びを取り消す
extern "js" fn clear_timer(doc : @dom.Document, timer : Int) -> Unit =
  #| (doc, timer) => doc.defaultView.clearTimeout(timer)

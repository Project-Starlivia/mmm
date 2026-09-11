// 時計（Date）。綴りは持たない — 名前に焼く形は置く側（app/disk）が決める

///|
/// 今の時刻（ms）
pub extern "js" fn now() -> Double =
  #| () => Date.now()

///|
/// その時刻をこの機械の時間帯で割ったもの — `[年, 月(1〜12), 日, 時, 分, 秒]`
pub extern "js" fn local_time(ms : Double) -> FixedArray[Int] =
  #| (ms) => { const d = new Date(ms);
  #|   return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds()]; }

// 約束の糊。JS の Promise と MoonBit の async を繋ぐ。作法は
// docs/superpowers/specs/2026-09-07-mbt-practice.md

///|
/// 投げっぱなしで走らせる（結果は待たない）。しくじりは中で拾う — ここでは黙る
pub fn spawn(f : async () -> Unit) -> Unit {
  @js_async.Promise::from_async(f) |> ignore
}

///|
/// 約束（Promise）が済んだら続きを呼ぶ
pub fn after(promise : @core.Any, k : (@core.Any) -> Unit) -> Unit {
  promise._call("then", [@core.from_fn1(k)]) |> ignore
}

///|
/// 続きで答えるもの（callback）を Promise に
pub extern "js" fn promise_of(
  f : ((@core.Any) -> Unit) -> Unit,
) -> @js_async.Promise[@core.Any] =
  #| (f) => new Promise((ok) => f(ok))

///|
/// 何であれ Promise に（ts の閉包が返したものを待てるように）
pub extern "js" fn settled(v : @core.Any) -> @js_async.Promise[@core.Any] =
  #| (v) => Promise.resolve(v)

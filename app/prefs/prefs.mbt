// 永続化の器。
//
// **持つのは見た目と手触りの好みだけ**（テーマ・アクセントカラー・書き出しのやり方・
// 掴みやすさ）。文書の控えもファイルハンドルも持たない（ハンドルは IndexedDB の
// app/disk/recent.mbt が扱う）。
//
// 持ち物は名前で言う（`theme` / `color` / `way` / `grab`）。localStorage の綴り
// （`mmm.*`）はここだけが知っていて、外は名前を渡す — 知らない名前は壊れている。

///|
/// いま意味のある持ち物と、その綴り
let owned : Array[(String, String)] = [
  ("theme", "mmm.theme"),
  ("color", "mmm.color"),
  // 最後に選んだ書き出しのやり方（bar/export.mbt が持ち主）
  ("way", "mmm.exportWay"),
  // 掴みやすさ（⋯ の Easy grab）。"on" のときだけ広い
  ("grab", "mmm.grab"),
]

///|
pub fn key_of(name : String) -> String {
  for o in owned {
    if o.0 == name {
      return o.1
    }
  }
  abort("知らない持ち物: " + name)
}

///|
/// localStorage。容量オーバーや無効化で例外が飛ぶので（読むのも書くのも —
/// private mode やポリシーで無効化された環境では getItem も投げる）、触るたびに
/// ここを通す。無ければ None
fn storage() -> @core.Any? {
  try @core.try_sync(() => @dom.window().localStorage()) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
}

///|
fn quietly(f : () -> @core.Any) -> @core.Any? {
  try @core.try_sync(f) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
}

///|
pub fn store(name : String, value : String) -> Unit {
  let key = key_of(name)
  match storage() {
    Some(s) =>
      quietly(() => s._call("setItem", [@core.any(key), @core.any(value)]))
      |> ignore
    None => ()
  }
}

///|
pub fn load(name : String) -> String? {
  let key = key_of(name)
  guard storage() is Some(s) else { return None }
  guard quietly(() => s._call("getItem", [@core.any(key)])) is Some(v) else {
    return None
  }
  @core.identity_option(v)
}

///|
/// 役目を終えた `mmm.*` を捨てる。消えたキーの名前を並べる移行リストは
/// 増え続けて誰も消せなくなるので、持ち物のほうを宣言して残りを掃く。
pub fn sweep() -> Unit {
  guard storage() is Some(s) else { return }
  quietly(() => {
    for k in @core.object_keys(s) {
      if k.has_prefix("mmm.") && !owned.any(o => o.1 == k) {
        s._call("removeItem", [@core.any(k)]) |> ignore
      }
    }
    @core.undefined()
  })
  |> ignore
}

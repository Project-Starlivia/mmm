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
fn key_of(name : String) -> String {
  for o in owned {
    if o.0 == name {
      return o.1
    }
  }
  abort("知らない持ち物: " + name)
}

///|
/// この窓の文書。無ければ（試験の Node には global の window が無い）None。
/// 呼ぶ側はどれも文書を持たないので、ここだけ global に手を伸ばす
fn doc() -> @dom.Document? {
  try @core.try_sync(() => @dom.window().document().as_any()) catch {
    _ => None
  } noraise {
    d => Some(d.cast())
  }
}

///|
pub fn store(name : String, value : String) -> Unit {
  let key = key_of(name)
  match doc() {
    Some(d) => @web.storage_set(d, key, value)
    None => ()
  }
}

///|
pub fn load(name : String) -> String? {
  let key = key_of(name)
  doc().bind(d => @web.storage_get(d, key))
}

///|
/// 役目を終えた `mmm.*` を捨てる。消えたキーの名前を並べる移行リストは
/// 増え続けて誰も消せなくなるので、持ち物のほうを宣言して残りを掃く。
pub fn sweep() -> Unit {
  guard doc() is Some(d) else { return }
  for k in @web.storage_keys(d) {
    if k.has_prefix("mmm.") && !owned.any(o => o.1 == k) {
      @web.storage_remove(d, k)
    }
  }
}

// 永続化の器。
//
// **持つのは見た目と手触りの好みだけ**（テーマ・アクセントカラー・書き出しのやり方・
// 掴みやすさ・自動保存）。文書の控えもファイルハンドルも持たない（ハンドルは
// IndexedDB の app/disk/recent.mbt が扱う）。
//
// 持ち物は名前で言う（`theme` / `color` / `way` / `grab`）。localStorage の綴り
// （`mmm.*`）はここだけが知っていて、外は名前を渡す — 知らない名前は壊れている。
// 文書は呼ぶ側が渡す（web/ と同じ作法。global に手を伸ばさない）

///|
/// いま意味のある持ち物と、その綴り
let owned : Array[(String, String)] = [
  ("theme", "mmm.theme"),
  ("color", "mmm.color"),
  // 最後に選んだ書き出しのやり方（bar/export.mbt が持ち主）
  ("way", "mmm.exportWay"),
  // 掴みやすさ（⋯ の Easy grab）。"on" のときだけ広い
  ("grab", "mmm.grab"),
  // 最後に居た分割線の居場所（panes.mbt が持ち主。"both" / "md" / "map"）
  ("panes", "mmm.panes"),
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
pub fn store(doc : @dom.Document, name : String, value : String) -> Unit {
  @web.storage_set(doc, key_of(name), value)
}

///|
pub fn load(doc : @dom.Document, name : String) -> String? {
  @web.storage_get(doc, key_of(name))
}

///|
/// 役目を終えた `mmm.*` を捨てる。消えたキーの名前を並べる移行リストは
/// 増え続けて誰も消せなくなるので、持ち物のほうを宣言して残りを掃く。
pub fn sweep(doc : @dom.Document) -> Unit {
  for k in @web.storage_keys(doc) {
    if k.has_prefix("mmm.") && !owned.any(o => o.1 == k) {
      @web.storage_remove(doc, k)
    }
  }
}

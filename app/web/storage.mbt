// localStorage。容量オーバーや無効化で例外が飛ぶので（読むのも書くのも —
// private mode やポリシーで無効化された環境では getItem も投げる）、
// しくじりはここで飲む — 無ければ無いものとして扱う

///|
/// 1 つ読む。無い / 読めなければ None
pub extern "js" fn storage_get(doc : @dom.Document, key : String) -> String? =
  #| (doc, key) => { try { return doc.defaultView.localStorage.getItem(key) ?? undefined; } catch { return undefined; } }

///|
pub extern "js" fn storage_set(
  doc : @dom.Document,
  key : String,
  value : String,
) -> Unit =
  #| (doc, key, value) => { try { doc.defaultView.localStorage.setItem(key, value); } catch {} }

///|
pub extern "js" fn storage_remove(doc : @dom.Document, key : String) -> Unit =
  #| (doc, key) => { try { doc.defaultView.localStorage.removeItem(key); } catch {} }

///|
/// 置いてある鍵の全部。読めなければ空
pub extern "js" fn storage_keys(doc : @dom.Document) -> FixedArray[String] =
  #| (doc) => { try { const s = doc.defaultView.localStorage; return Array.from({ length: s.length }, (_, i) => s.key(i)); } catch { return []; } }

// クリップボード・アドレス。窓（`doc.defaultView`）から辿るので、
// 試験の DOM（happy-dom）でも同じ道を通る

///|
/// クリップボードの字。**断られれば None** — 空（`Some("")`）とは分ける。
/// 空は「何も無い」、断られたのは「許せば通る」で、次の一手の向きが違う
pub async fn read_clipboard(doc : @dom.Document) -> String? {
  try clipboard_text(doc).wait() catch {
    _ => None
  } noraise {
    text => Some(text)
  }
}

///|
/// 断られれば拒む
extern "js" fn clipboard_text(doc : @dom.Document) -> @js_async.Promise[String] =
  #| (doc) => doc.defaultView.navigator.clipboard.readText()

///|
/// クリップボードへ字を置く。断られれば拒む
pub extern "js" fn write_clipboard(
  doc : @dom.Document,
  text : String,
) -> @js_async.Promise[Unit] =
  #| async (doc, text) => doc.defaultView.navigator.clipboard.writeText(text)

///|
/// クリップボードに 1 品を置く。`types[i]` の中身が `blobs[i]`
pub extern "js" fn clipboard_write(
  doc : @dom.Document,
  types : FixedArray[String],
  blobs : FixedArray[@core.Any],
) -> @js_async.Promise[Unit] =
  #| (doc, types, blobs) => { const item = {}; types.forEach((t, i) => { item[t] = blobs[i]; });
  #|   const w = doc.defaultView; return w.navigator.clipboard.write([new w.ClipboardItem(item)]); }

///|
/// クリップボードの絵（最初の image/*）。**断られれば None** — 絵が無い
/// （`Some(None)`。読む道を持たないブラウザもこちら）とは分ける
pub async fn clipboard_image(doc : @dom.Document) -> @core.Any?? {
  try first_image(doc).wait() catch {
    _ => None
  } noraise {
    img => Some(@core.identity_option(img))
  }
}

///|
/// 最初の image/*。無ければ null、断られれば拒む
extern "js" fn first_image(doc : @dom.Document) -> @js_async.Promise[@core.Any] =
  #| async (doc) => {
  #|   const clip = doc.defaultView.navigator.clipboard;
  #|   if (!("read" in clip)) return null;
  #|   for (const item of await clip.read()) {
  #|     const t = item.types.find((x) => x.startsWith("image/"));
  #|     if (t) return await item.getType(t);
  #|   }
  #|   return null;
  #| }

///|
/// いまのアドレスの `#…`（無ければ ""）
pub extern "js" fn hash(doc : @dom.Document) -> String =
  #| (doc) => doc.defaultView.location.hash

///|
/// アドレスの元（origin + pathname）。リンクはこれに `#md=…` を足す
pub extern "js" fn address(doc : @dom.Document) -> String =
  #| (doc) => { const l = doc.defaultView.location; return l.origin + l.pathname; }

///|
/// `#…` をその場で消す（履歴は増やさない）
pub extern "js" fn drop_hash(doc : @dom.Document) -> Unit =
  #| (doc) => { const w = doc.defaultView; w.history.replaceState(null, "", w.location.pathname + w.location.search); }

///|
/// 閉じる前に聞く（beforeunload の出来事に言う）
pub extern "js" fn warn_unload(e : @core.Any) -> Unit =
  #| (e) => { e.preventDefault(); e.returnValue = ""; }

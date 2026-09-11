// Blob と、その URL。中身は不透明（`@core.Any`）で、種類（MIME）だけ読める。
// 結び付けの無い API なので `extern "js"` で書き、Promise は js_async の型で返す

///|
/// 字 1 つの Blob
pub extern "js" fn text_blob(text : String, mime : String) -> @core.Any =
  #| (text, type) => new Blob([text], { type })

///|
/// 種類（MIME）。無ければ ""
pub extern "js" fn blob_type(blob : @core.Any) -> String =
  #| (blob) => blob.type

///|
pub extern "js" fn object_url(blob : @core.Any) -> String =
  #| (blob) => URL.createObjectURL(blob)

///|
pub extern "js" fn revoke_url(url : String) -> Unit =
  #| (url) => URL.revokeObjectURL(url)

///|
/// ファイルを読んで objectURL に（種類は名前から決めたもの）
pub extern "js" fn read_url(
  f : FileHandle,
  mime : String,
) -> @js_async.Promise[String] =
  #| (f, type) => f.getFile().then((b) => b.arrayBuffer()).then((buf) => URL.createObjectURL(new Blob([buf], { type })))

///|
/// 絵を別の種類に焼き直す（`createImageBitmap` → OffscreenCanvas → `convertToBlob`）。
/// 出てくる種類はブラウザ次第 — 頼んだ種類で出たかは呼ぶ側が `blob_type` で確かめる
pub extern "js" fn convert(
  blob : @core.Any,
  mime : String,
  quality : Double,
) -> @js_async.Promise[@core.Any] =
  #| async (blob, type, quality) => {
  #|   const bitmap = await createImageBitmap(blob);
  #|   try {
  #|     const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  #|     canvas.getContext("2d").drawImage(bitmap, 0, 0);
  #|     return await canvas.convertToBlob({ type, quality });
  #|   } finally { bitmap.close(); }
  #| }

///|
/// ダウンロードさせる。click() の直後に revoke するとダウンロードが始まる前に
/// URL が消えることがあるので、次のタスクまで待つ
pub extern "js" fn download(
  doc : @dom.Document,
  blob : @core.Any,
  name : String,
) -> Unit =
  #| (doc, blob, name) => { const a = doc.createElement("a"); const url = URL.createObjectURL(blob);
  #|   a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 0); }

///|
/// URL の中身を data URL に（`blob:` のサムネイルをページの外へ持ち出す）。読めなければ拒む
pub extern "js" fn data_url(href : String) -> @js_async.Promise[String] =
  #| (href) => fetch(href).then((r) => r.blob()).then((b) => new Promise((ok, no) => {
  #|   const fr = new FileReader();
  #|   fr.onload = () => (typeof fr.result === "string" ? ok(fr.result) : no(new Error("not a data url")));
  #|   fr.onerror = () => no(fr.error); fr.readAsDataURL(b); }))

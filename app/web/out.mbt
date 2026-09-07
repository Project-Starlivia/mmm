// 外へ出す口。直列化・ラスタ化・ダウンロード・クリップボード・埋め込み。
// どれも結び付けの無い API なので `extern "js"` で書き、Promise は js_async の型で返す

///|
/// 要素をそのまま字にする（SVG の書き出し）
pub extern "js" fn serialize(e : @dom.Element) -> String =
  #| (e) => new XMLSerializer().serializeToString(e)

///|
/// 字 1 つの Blob
pub extern "js" fn text_blob(text : String, mime : String) -> @core.Any =
  #| (text, type) => new Blob([text], { type })

///|
/// ダウンロードさせる。click() の直後に revoke するとダウンロードが始まる前に
/// URL が消えることがあるので、次のタスクまで待つ
pub extern "js" fn download(blob : @core.Any, name : String) -> Unit =
  #| (blob, name) => { const a = document.createElement("a"); const url = URL.createObjectURL(blob);
  #|   a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 0); }

///|
/// SVG の字を絵にする。`blob:` の参照を残していると canvas が汚れて toBlob が
/// 投げるので、呼ぶ側が先に data URL へ埋め直しておく。絵にできなければ拒む
pub extern "js" fn rasterize(
  text : String,
  w : Double,
  h : Double,
  mime : String,
  scale : Double,
) -> @js_async.Promise[@core.Any] =
  #| (text, w, h, mime, scale) => new Promise((ok, no) => {
  #|   const img = new Image();
  #|   img.onload = () => {
  #|     const canvas = document.createElement("canvas");
  #|     canvas.width = Math.ceil(w * scale); canvas.height = Math.ceil(h * scale);
  #|     canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
  #|     canvas.toBlob((blob) => (blob ? ok(blob) : no(new Error("could not rasterize"))), mime);
  #|   };
  #|   img.onerror = () => no(new Error("svg could not be drawn"));
  #|   img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(text)}`;
  #| })

///|
/// クリップボードに 1 品を置く。`types[i]` の中身が `blobs[i]`
pub extern "js" fn clipboard_write(
  types : FixedArray[String],
  blobs : FixedArray[@core.Any],
) -> @js_async.Promise[Unit] =
  #| (types, blobs) => { const item = {}; types.forEach((t, i) => { item[t] = blobs[i]; });
  #|   return navigator.clipboard.write([new ClipboardItem(item)]); }

///|
/// URL の中身を data URL に（`blob:` のサムネイルをページの外へ持ち出す）。読めなければ拒む
pub extern "js" fn data_url(href : String) -> @js_async.Promise[String] =
  #| (href) => fetch(href).then((r) => r.blob()).then((b) => new Promise((ok, no) => {
  #|   const fr = new FileReader();
  #|   fr.onload = () => (typeof fr.result === "string" ? ok(fr.result) : no(new Error("not a data url")));
  #|   fr.onerror = () => no(fr.error); fr.readAsDataURL(b); }))

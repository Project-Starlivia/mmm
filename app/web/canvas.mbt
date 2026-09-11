// 紙（canvas）の道具。2d の文脈は不透明な持ち手で、載せる手は 2 つ —
// 塗り潰すか、線を引くか。太さ・色は手ごとに渡す。
//
// 2d の文脈は用ごとに別 — 描く紙（`paper_2d`。dpr 倍・丸い端）、字を測る紙
// （`text_width`。文書に 1 枚を持ち回す）、SVG を絵に焼く紙（`rasterize`。
// 絵の画素数に合わせて毎回作る）。1 枚を使い回すと、倍率と大きさが互いに邪魔をする

///|
/// 描く文脈。dpr 倍の画素に CSS ピクセルで描けるよう倍率を掛け、線の端と角を丸める。
/// 2d が無い（テストの DOM）ならしくじりとして投げる
pub extern "js" fn paper_2d(canvas : @dom.Element, dpr : Double) -> @core.Any =
  #| (c, dpr) => { const ctx = c.getContext("2d"); if (!ctx) throw new Error("no 2d context");
  #|   ctx.scale(dpr, dpr); ctx.lineCap = "round"; ctx.lineJoin = "round"; return ctx; }

///|
/// 左上から w × h を 1 色で塗る
pub extern "js" fn fill_rect(
  ctx : @core.Any,
  color : String,
  w : Double,
  h : Double,
) -> Unit =
  #| (ctx, color, w, h) => { ctx.fillStyle = color; ctx.fillRect(0, 0, w, h); }

///|
/// 折れ線を引く。`xy` は x, y, x, y, … の平ら。**1 点だけでも見える**よう、同じ点へ引く
pub extern "js" fn stroke_line(
  ctx : @core.Any,
  color : String,
  width : Double,
  xy : FixedArray[Double],
) -> Unit =
  #| (ctx, color, width, xy) => { ctx.strokeStyle = color; ctx.lineWidth = width; ctx.beginPath();
  #|   ctx.moveTo(xy[0], xy[1]); if (xy.length === 2) ctx.lineTo(xy[0], xy[1]);
  #|   for (let i = 2; i < xy.length; i += 2) ctx.lineTo(xy[i], xy[i + 1]); ctx.stroke(); }

///|
/// 画面の画素密度（読めなければ 1）
pub extern "js" fn device_pixel_ratio(doc : @dom.Document) -> Double =
  #| (doc) => doc.defaultView.devicePixelRatio || 1

///|
/// 紙の絵。作れなければ null
pub extern "js" fn canvas_blob(
  canvas : @dom.Element,
  image_type : String,
  quality : Double,
) -> @js_async.Promise[@core.Any] =
  #| (c, type, q) => new Promise((ok) => c.toBlob(ok, type, q))

///|
/// 字の幅（canvas の measureText）。`font` は CSS の綴り（`16px sans-serif`）。
/// 測る紙は文書に 1 枚（`__mmmMeasure`）— 測るたびに作ると、地図 1 枚で何百と作る
pub extern "js" fn text_width(
  doc : @dom.Document,
  font : String,
  text : String,
) -> Double =
  #| (doc, font, text) => {
  #|   const ctx = (doc.__mmmMeasure ??= doc.createElement("canvas").getContext("2d"));
  #|   if (!ctx) throw new Error("no 2d context");
  #|   ctx.font = font; return ctx.measureText(text).width;
  #| }

///|
/// SVG の字を、指定した px の絵にする。`blob:` の参照を残していると canvas が
/// 汚れて toBlob が投げるので、呼ぶ側が先に data URL へ埋め直しておく。
/// **大きさが上限に収まることは呼ぶ側の責任**（`fit`）— canvas は超えた分を
/// 黙って切るか null を返すだけで、何も言わない。絵にできなければ拒む
pub extern "js" fn rasterize(
  text : String,
  mime : String,
  px_w : Int,
  px_h : Int,
) -> @js_async.Promise[@core.Any] =
  #| (text, mime, px_w, px_h) => new Promise((ok, no) => {
  #|   const img = new Image();
  #|   img.onload = () => {
  #|     const canvas = document.createElement("canvas");
  #|     canvas.width = px_w; canvas.height = px_h;
  #|     canvas.getContext("2d").drawImage(img, 0, 0, px_w, px_h);
  #|     canvas.toBlob((blob) => (blob ? ok(blob) : no(new Error("could not rasterize"))), mime);
  #|   };
  #|   img.onerror = () => no(new Error("svg could not be drawn"));
  #|   img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(text)}`;
  #| })

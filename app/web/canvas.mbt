// 紙（canvas）の道具。2d の文脈は不透明な持ち手で、載せる手は 2 つ —
// 塗り潰すか、線を引くか。太さ・色は手ごとに渡す。

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
/// 押したことにする（隠したピッカーを開く・ボタンのふるまいをキーから通す）
pub extern "js" fn click(e : @dom.Element) -> Unit =
  #| (e) => e.click()

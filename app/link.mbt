// 本文を URL フラグメントへ載せる／そこから戻す。
//
// クエリではなくフラグメント（`#md=...`）に置く — フラグメントはブラウザから
// 外へ一切出ない。サーバのアクセスログにも、外部リンクを踏んだ先の
// Referer にも本文が漏れない（クエリはどちらにも漏れる）。
//
// 圧縮は `CompressionStream('gzip')`。mmm は元から Chromium 限定と
// 言い切っているので、追加のライブラリは要らない。

///|
let prefix = "md="

///|
/// この長さを超えたら「一部のアプリでは切られるかも」と伝える文字数。
/// 拒否はしない — 相手側の実際の上限は mmm には分からないので、勝手に決めない
let link_warn_length = 8000

///|
/// バイト列を stream（Compression / DecompressionStream）に通して集める。
/// 壊れた入力は reject（DecompressionStream が投げる）
extern "js" fn pipe(
  bytes : @arraybuffer.Uint8Array,
  stream : @core.Any,
) -> @js_async.Promise[@arraybuffer.Uint8Array] =
  #| (bytes, stream) =>
  #|   new Response(new Blob([bytes]).stream().pipeThrough(stream))
  #|     .arrayBuffer()
  #|     .then((b) => new Uint8Array(b))

///|
/// バイト列 → 1 バイト 1 文字の字（btoa の入力）
fn binary(bytes : @arraybuffer.Uint8Array) -> String {
  let out = StringBuilder()
  for i in 0..<bytes.length() {
    out.write_char(Int::unsafe_to_char(bytes.get_at(i)))
  }
  out.to_string()
}

///|
fn to_base64url(bytes : @arraybuffer.Uint8Array) -> String {
  let b64 = @global.btoa(binary(bytes)) catch {
    _ => abort("btoa が失敗した — 1 バイト 1 文字でない")
  }
  let mut end = b64.length()
  while end > 0 && b64[end - 1] == '=' {
    end -= 1
  }
  String::unsafe_substring(b64, start=0, end~)
  .replace_all(old="+", new="-")
  .replace_all(old="/", new="_")
}

///|
/// base64url → バイト列。読めなければ None
fn from_base64url(value : String) -> @arraybuffer.Uint8Array? {
  let padded = value.replace_all(old="-", new="+").replace_all(old="_", new="/")
  let pad = (4 - padded.length() % 4) % 4
  let bin = @global.atob(padded + "=".repeat(pad)) catch { _ => return None }
  let bytes = @arraybuffer.Uint8Array::from_size(bin.length())
  for i in 0..<bin.length() {
    bytes.set_at(i, bin[i].to_int())
  }
  Some(bytes)
}

///|
/// 本文を載せたフラグメント（`#md=...`）。URL の組み立ては呼び出し側
async fn to_hash(text : String) -> String {
  let raw = @encoding.TextEncoder::new().encode(text)
  let gz = pipe(raw, @streams.CompressionStream::new("gzip").as_any()).wait()
  "#" + prefix + to_base64url(gz)
}

///|
/// `location.hash` から本文を取り出す。リンクでなければ・壊れていれば None
async fn from_hash(hash : String) -> String? {
  guard hash.has_prefix("#" + prefix) else { return None }
  let value = String::unsafe_substring(
    hash,
    start=1 + prefix.length(),
    end=hash.length(),
  )
  guard from_base64url(value) is Some(bytes) else { return None }
  let plain = pipe(bytes, @streams.DecompressionStream::new("gzip").as_any()).wait() catch {
    _ => return None
  }
  Some(@encoding.TextDecoder::new().decode(plain))
}

///|
/// 本文へのリンクの綴り。`address` はいまのページ（`@web.address`）。作るのも測るのもこれ 1 つ
async fn link(address : String, text : String) -> String {
  address + to_hash(text)
}

///|
/// リンクにまつわる**押す前の但し書き**。無ければ空。`images` は木に画像が居るか
/// （read の `has_images`）、`length` は作ったリンクの長さ — gzip してからでないと
/// 分からないので、開くたびに本当に測る（1ms 弱）
fn link_caveat(images : Bool, length : Int) -> Array[String] {
  let out = []
  if images {
    out.push("Images won't travel")
  }
  if length > link_warn_length {
    out.push("Long link — may be cut")
  }
  out
}

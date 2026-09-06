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
pub let link_warn_length = 8000

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
pub async fn to_hash(text : String) -> String {
  let raw = @encoding.TextEncoder::new().encode(text)
  let gz = pipe(raw, @streams.CompressionStream::new("gzip").as_any()).wait()
  "#" + prefix + to_base64url(gz)
}

///|
/// `location.hash` から本文を取り出す。リンクでなければ・壊れていれば None
pub async fn from_hash(hash : String) -> String? {
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
/// 画像を貼った行があるか。`![...](...)` — 画像は旅をしないので、
/// Copy link の行に**押す前の但し書き**として出すのに使う
pub fn has_images(text : String) -> Bool {
  let mut from = 0
  while index_of(text, "![", from) is Some(bang) {
    // `]` まで（`]` を含まない）、その直後が `(`、その先に `)`
    guard index_of(text, "]", bang + 2) is Some(close) else { return false }
    if close + 1 < text.length() && text[close + 1] == '(' {
      if index_of(text, ")", close + 2) is Some(_) {
        return true
      }
    }
    from = bang + 2
  }
  false
}

///|
/// `from` から後ろで最初に見つかる位置
fn index_of(text : String, needle : String, from : Int) -> Int? {
  guard from <= text.length() else { return None }
  String::unsafe_substring(text, start=from, end=text.length())
  .find(needle)
  .map(i => i + from)
}

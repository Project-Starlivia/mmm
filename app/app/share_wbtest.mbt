// 本文を URL フラグメントへ載せる往復。`#md=` の中身だけを扱う純粋な変換なので、
// 字の往復と、リンクでないものを渡したときの判断だけを見る（Node の
// CompressionStream / Response / btoa で走る）。

///|
async test "to_hash → from_hash で往復する。base64url に + / = は出ない" {
  let text = "# 設計メモ\n\n## a\n本文だよ\n"
  let hash = to_hash(text)
  assert_true(hash.has_prefix("#md="))
  let body = String::unsafe_substring(hash, start=4, end=hash.length())
  assert_false(body.contains("+") || body.contains("/") || body.contains("="))
  assert_eq(from_hash(hash), Some(text))
}

///|
async test "リンクでない hash は None。壊れた md= も None（投げない）" {
  assert_eq(from_hash(""), None)
  assert_eq(from_hash("#"), None)
  assert_eq(from_hash("#foo=bar"), None)
  assert_eq(from_hash("#md=not-valid-base64url!!!"), None)
  assert_eq(from_hash("#md=AAAA"), None)
}

///|
test "has_images: 画像を貼った行があれば真。リンクは画像ではない" {
  assert_true(has_images("# a\n\n![](./images/a.webp)\n"))
  assert_false(has_images("# a\n\n本文だけ\n"))
  assert_false(has_images("[a](./b.md)"))
  assert_false(has_images("![alt] (x)"))
  assert_true(has_images("text ![alt](x.png) more"))
}

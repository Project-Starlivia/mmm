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
test "link_caveat: 画像が居れば言い、長ければ言う。どちらも無ければ空" {
  assert_eq(link_caveat(false, 0), [])
  assert_eq(link_caveat(true, link_warn_length), ["Images won't travel"])
  assert_eq(link_caveat(false, link_warn_length + 1), [
    "Long link — may be cut",
  ])
  assert_eq(link_caveat(true, link_warn_length + 1), [
    "Images won't travel", "Long link — may be cut",
  ])
}

///|
async test "link: ページの住所の後ろに #md= が付く" {
  let address = "https://mmm.example/"
  let l = link(address, "# a\n")
  assert_true(l.has_prefix(address + "#md="))
  assert_eq(from_hash(l[address.length():].to_owned()), Some("# a\n"))
}

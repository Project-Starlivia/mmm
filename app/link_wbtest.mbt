// 本文を URL フラグメントへ載せる往復。`#md=` の中身だけを扱う純粋な変換なので、
// 字の往復と、リンクでないものを渡したときの判断だけを見る（Node の
// CompressionStream / Response / btoa で走る）。
// 開く側の上限（#304）は、切り方を純粋に見たうえで、立ち上がりの 1 本で確かめる。

///|
/// 取り出した本文と、上限で切ったか。比べられる形にして返す
async fn shared(hash : String) -> (String, Bool)? {
  from_hash(hash).map(s => (s.text, s.cut))
}

///|
async test "to_hash → from_hash で往復する。base64url に + / = は出ない" {
  let text = "# 設計メモ\n\n## a\n本文だよ\n"
  let hash = to_hash(text)
  assert_true(hash.has_prefix("#md="))
  let body = String::unsafe_substring(hash, start=4, end=hash.length())
  assert_false(body.contains("+") || body.contains("/") || body.contains("="))
  assert_eq(shared(hash), Some((text, false)))
}

///|
async test "リンクでない hash は None。壊れた md= も None（投げない）" {
  assert_eq(shared(""), None)
  assert_eq(shared("#"), None)
  assert_eq(shared("#foo=bar"), None)
  assert_eq(shared("#md=not-valid-base64url!!!"), None)
  assert_eq(shared("#md=AAAA"), None)
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
  assert_eq(shared(l[address.length():].to_owned()), Some(("# a\n", false)))
}

// ---- 開く側の上限（#304）----

///|
/// 32 バイトの行。上限（2 MB）はこれのちょうど 65,536 行
let line = "- item with some ordinary words\n"

///|
async test "上限: ちょうどまでは丸ごと。1 バイトでも越えれば、越えた行を落とす" {
  let whole = line.repeat(link_read_bytes / line.length())
  assert_eq(shared(to_hash(whole)), Some((whole, false)))
  assert_eq(shared(to_hash(whole + "x")), Some((whole, true)))
}

///|
async test "上限: 行を半分に割らず、上限の内の最後の改行まで戻す" {
  let rows = link_read_bytes / line.length()
  assert_eq(
    shared(to_hash("#\n" + line.repeat(rows))),
    Some(("#\n" + line.repeat(rows - 1), true)),
  )
}

///|
/// 改行が無ければ上限から切るが、字の途中では切らない（`あ` は 3 バイト）
async test "上限: 改行が 1 つも無ければ、字の切れ目で切る" {
  assert_eq(
    shared(to_hash("あ".repeat(1_000_000))),
    Some(("あ".repeat(link_read_bytes / 3), true)),
  )
}

///|
/// よく縮む字は、短いリンクが桁違いに膨らむ（32 MB が数十 KB）。
/// 読むのは上限を 1 バイト越えるところまで
async test "上限: 膨らむリンクも、上限を越えたところで読むのをやめる" {
  let bomb = to_hash("a\n".repeat(16 * 1024 * 1024))
  assert_true(bomb.length() < 100_000)
  let plain = gunzip(
    from_base64url(bomb[prefix.length() + 1:].to_owned()).unwrap(),
    link_read_bytes + 1,
  ).wait()
  assert_eq(plain.length(), link_read_bytes + 1)
  assert_eq(shared(bomb), Some(("a\n".repeat(link_read_bytes / 2), true)))
}

///|
/// 立ち上がりのリンクは一拍おいて開く（展開が済むまで）。開くまで待つ
async fn opened(s : Stand) -> Unit {
  for _ in 0..<400 {
    guard s.fake.md == "" else { return }
    rest(s.doc, 5)
  }
  fail("リンクが開かない")
}

///|
async test "立ち上がり: 上限までのリンクは丸ごと開き、しらせは出ない" {
  let text = "# a\n\n## b\n"
  let s = stand(hash=to_hash(text))
  defer s.win.close()
  opened(s)
  assert_eq(s.fake.md, text)
  assert_eq(s.doc.querySelectorAll(".notice.on").length(), 0)
}

///|
/// **拒否せず、入るだけ開いて、全部は開けなかったと言う** — 読む人は入った分を
/// 見られるし、欠けていることも知る
async test "立ち上がり: 上限を越えるリンクは入るだけ開き、全部は開けなかったと言う" {
  let fits = "# a\n\n" + "b".repeat(link_read_bytes - 16) + "\n"
  let s = stand(hash=to_hash(fits + "c".repeat(64) + "\n"))
  defer s.win.close()
  opened(s)
  assert_eq(s.fake.md, fits)
  assert_eq(
    s.doc.querySelectorAll(".notice.on .msg").map(m => m.textContent()),
    ["Couldn't open all of it — the link is too large"],
  )
}

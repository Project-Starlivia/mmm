// 原文の字と行の算術。**md の意味は 1 つも知らない** — 位置と切り出しだけで、
// 読み（build / content）も合流（merge）も同じものを使う。

///|
/// 原文の切り出し。**容器の字下げは剥がす** — 項目や引用の中では行頭の空白は
/// その容器の記法であって中身ではないので、切り出しに混ぜると列がずれる
/// （深く入れ子にすると、切り出しを読み直したとき字下げコードに化ける）。
/// 1 行目は mdAst の span がもう剥がしているので、残りの行を同じだけ揃える。
/// 末尾の改行も記法なので落とす。
fn carve(md : String, from : Int, to : Int) -> String {
  let mut z = to
  while z > from && (md[z - 1] == '\n' || md[z - 1] == '\r') {
    z = z - 1
  }
  let indent = column(md, from)
  if indent == 0 {
    return String::unsafe_substring(md, start=from, end=z)
  }
  let out = StringBuilder()
  let mut i = from
  let mut head = false
  while i < z {
    if head {
      let mut n = 0
      while n < indent && i < z && (md[i] == ' ' || md[i] == '\t') {
        i = i + 1
        n = n + 1
      }
      head = false
      continue
    }
    let c = md[i]
    out.write_char(c.unsafe_to_char())
    head = c == '\n'
    i = i + 1
  }
  out.to_string()
}

///|
/// 字下げコードの記法の頭 — `at` から**空白 4 桁ぶん**だけ戻った位置。
/// 手前に残る空白は容器の字下げなので、そこは越えない（項目の中なら項目の桁で止まる）。
/// タブは 4 桁（CommonMark のタブ幅）。
fn undent(md : String, at : Int) -> Int {
  let head = line_start(md, at)
  let mut i = at
  let mut n = 0
  while i > head && n < 4 {
    let c = md[i - 1]
    guard c == ' ' || c == '\t' else { break }
    n = n + (if c == '\t' { 4 } else { 1 })
    i = i - 1
  }
  i
}

///|
/// 行頭からの桁。容器の字下げの幅になる。
fn column(md : String, at : Int) -> Int {
  let mut i = at
  while i > 0 && md[i - 1] != '\n' {
    i = i - 1
  }
  at - i
}

///|
/// その位置の行の頭。
fn line_start(md : String, at : Int) -> Int {
  at - column(md, at)
}

///|
/// その位置の行の尻（改行の次）。末尾に改行が無ければ文書の尻。
fn line_end(md : String, at : Int) -> Int {
  let mut i = at
  while i < md.length() && md[i] != '\n' {
    i = i + 1
  }
  if i < md.length() {
    i + 1
  } else {
    i
  }
}

///|
/// 行頭 `at` の手前に続く空行の頭。空行が無ければその位置のまま。
/// 空行は「改行までが空白だけの行」— 読みが空行と見るのと同じ。改行は `\n`（CRLF の
/// `\r` は行の中身ではない）。
fn blank_start(md : String, at : Int) -> Int {
  let mut p = at
  while p > 0 && md[p - 1] == '\n' {
    let nl = if p >= 2 && md[p - 2] == '\r' { p - 2 } else { p - 1 }
    let head = line_start(md, nl)
    guard skip_blank(md, head, nl) == nl else { break }
    p = head
  }
  p
}

///|
/// 先頭の `./` を落とした形。`./x` と `x` は同じ場所を指すので、比べる前に
/// 必ずこの形へ寄せる。カードが持つ path も、画像の鍵（app/assets.ts）も、
/// 宣言の下に在るかの判定（read/head.mbt）も、みなこの形
pub fn bare_path(path : String) -> String {
  match path.strip_prefix("./") {
    Some(v) => v.to_owned()
    None => path
  }
}

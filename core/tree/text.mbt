// 原文の字と行の算術。**md の意味は 1 つも知らない** — 位置と切り出しだけで、
// 読み（build / content）も合流（merge）も同じものを使う。

///|
/// 原文の切り出し。**容器の字下げは剥がす** — 項目や引用の中では行頭の空白は
/// その容器の記法であって中身ではないので、切り出しに混ぜると列がずれる
/// （深く入れ子にすると、切り出しを読み直したとき字下げコードに化ける）。
/// 1 行目は mdAst の span がもう剥がしているので、残りの行を同じだけ揃える。
/// 末尾の改行も記法なので落とす。
///
/// **改行は LF に揃える**（`lf`）— 「木が抱える字は LF だけ」という不変量。原文を
/// そのまま返す道（記法構造の書き戻し、地番）は `slice` を使うので影響しない。
fn carve(md : String, from : Int, to : Int) -> String {
  let mut z = to
  while z > from && (md[z - 1] == '\n' || md[z - 1] == '\r') {
    z = z - 1
  }
  let indent = column(md, from)
  if indent == 0 {
    return lf(slice(md, from, z))
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
  lf(out.to_string())
}

///|
/// 原文の切り出し。**1 バイトも変えない** — 記法構造の書き戻しと地番はこれを使う。
fn slice(md : String, from : Int, to : Int) -> String {
  String::unsafe_substring(md, start=from, end=to)
}

///|
/// 空白の字か。改行も含む（行の中の空白だけなら `skip_space`）。
fn space(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// 行の中の空白（空白とタブ）を読み飛ばした位置。
fn skip_space(md : String, from : Int, to : Int) -> Int {
  let mut p = from
  while p < to && (md[p] == ' ' || md[p] == '\t') {
    p = p + 1
  }
  p
}

///|
/// n 桁の空白。
fn pad(n : Int) -> String {
  String::make(n, ' ')
}

///|
/// 2 行目以降を n 桁字下げする。空行はそのまま。
fn indent(text : String, n : Int) -> String {
  if n == 0 {
    return text
  }
  let fill = pad(n)
  let out = StringBuilder()
  let mut head = false
  for c in text {
    if head && c != '\n' && c != '\r' {
      out.write_string(fill)
    }
    out.write_char(c)
    head = c == '\n'
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
    guard skip_space(md, head, nl) == nl else { break }
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

///|
/// 改行を LF に揃えた形。**書くときだけ通す** — 読みは原文を 1 バイトも変えない
/// （`carve` も記法構造の書き戻しも CR をそのまま返す）。
///
/// CommonMark では裸の CR も行の終わりなので、`\r\n` も単独の `\r` も LF にする。
fn lf(text : String) -> String {
  if !text.contains("\r") {
    return text
  }
  let out = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = text[i]
    if c == '\r' {
      out.write_char('\n')
      if i + 1 < n && text[i + 1] == '\n' {
        i = i + 1
      }
    } else {
      out.write_substring(text, i, 1)
    }
    i = i + 1
  }
  out.to_string()
}

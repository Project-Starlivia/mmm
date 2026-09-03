// `<details>` を読む。
//
// **限られた形のときだけ**そのノードの畳み（`details = true`、中身は普通に
// 読む）。`<summary>` がラベルと一致し、領域がそのノードの body・children と
// その body を過不足なく覆っていること。どちらか欠ければ中身の 1 枚
// （`Block::Details` の逐語）。裁定は docs/spec.md。

///|
/// 積む前のひと切れ。
priv enum Piece {
  Raw(@markdown.Block)
  /// 畳まれたノードの見出し・項目の行。中身は普通に読む
  Folded(@markdown.Block, open~ : Bool)
  /// ちょうど覆っていない領域。逐語のまま中身になる
  Capsule(String)
}

///|
/// 開きだけの塊（閉じは後ろの別の塊にある）。
fn opens(html : String) -> Bool {
  let t = html.trim()
  t.has_prefix("<details") && !t.has_suffix("</details>")
}

///|
/// 開きの塊が `<details>`（`open` 付きも可）の行と `<summary>` の行だけか。
/// 空行を挟まないと md は次の行まで飲み込むので、飲み込まれた行があれば偽。
/// 知らない属性が付いていても偽 — 畳みにすると開きの塊ごと落ちて属性が消える。
fn bare(html : String) -> Bool {
  for line in html.split("\n") {
    let t = line.trim().to_owned()
    if t == "" || t == "<details>" || t == "<details open>" {
      continue
    }
    if t.has_prefix("<summary>") && t.has_suffix("</summary>") {
      continue
    }
    return false
  }
  true
}

///|
/// 開きに `open` が付いているか。外部レンダラで開いた姿で出る。
fn open_of(html : String) -> Bool {
  for line in html.split("\n") {
    if line.trim().to_owned() == "<details open>" {
      return true
    }
  }
  false
}

///|
/// 閉じの塊が `</details>` の行 1 つだけか。
/// 空行を挟まないと md は閉じを重ねて 1 つの塊にするので、そのまま畳みの閉じに
/// 使うと**もう片方の `</details>` を落としてしまう**。
fn lone(html : String) -> Bool {
  let mut seen = 0
  for line in html.split("\n") {
    let t = line.trim().to_owned()
    if t == "" {
      continue
    }
    guard t == "</details>" else { return false }
    seen = seen + 1
  }
  seen == 1
}

///|
/// 閉じだけの塊。
fn closes(html : String) -> Bool {
  let t = html.trim()
  t.has_suffix("</details>") && !t.has_prefix("<details")
}

///|
/// ブロックの並びを、畳みを解いたひと切れの列にする。
fn pieces(md : String, blocks : Array[@markdown.Block]) -> Array[Piece] {
  let out = []
  let mut i = 0
  while i < blocks.length() {
    let b = blocks[i]
    let paired = match b {
      HtmlBlock(html~, ..) if opens(html) => closer(blocks, i)
      _ => None
    }
    match paired {
      None => {
        out.push(Raw(b))
        i = i + 1
      }
      Some(j) =>
        if covers(blocks, i, j) && summary_fits(md, blocks, i) {
          // 過不足なく覆っている。タグは落ち、包まれた行が畳まれる
          let open = b is HtmlBlock(html~, ..) && open_of(html)
          out.push(Folded(blocks[next(blocks, i)], open~))
          // 中はまた同じ規則で読む。入れ子の畳みも畳みになる
          let inner = []
          let mut k = next(blocks, i) + 1
          while k < j {
            inner.push(blocks[k])
            k = k + 1
          }
          for p in pieces(md, inner) {
            out.push(p)
          }
          i = j + 1
        } else {
          let from = block_span(b).from
          let to = block_span(blocks[j]).to
          out.push(Capsule(cut(md, from, to)))
          i = j + 1
        }
    }
  }
  out
}

///|
/// i の開きに対応する閉じの位置。入れ子は数えて釣り合わせる。
fn closer(blocks : Array[@markdown.Block], i : Int) -> Int? {
  let mut depth = 0
  let mut k = i
  while k < blocks.length() {
    match blocks[k] {
      HtmlBlock(html~, ..) =>
        if opens(html) {
          depth = depth + 1
        } else if closes(html) {
          depth = depth - 1
          if depth == 0 {
            return Some(k)
          }
        }
      _ => ()
    }
    k = k + 1
  }
  None
}

///|
/// 空行を飛ばした次の位置。空行は記法であって中身ではない。
fn next(blocks : Array[@markdown.Block], i : Int) -> Int {
  let mut k = i + 1
  while k < blocks.length() && blocks[k] is BlankLines(..) {
    k = k + 1
  }
  k
}

///|
/// 領域 [i, j] が、1 つのノードの body・children とその body を過不足なく
/// 覆っているか。開き・閉じの塊が記法だけで出来ていること、開きの直後が
/// 見出し・項目の行であること、その部分木でぴったり終わることを見る。
fn covers(blocks : Array[@markdown.Block], i : Int, j : Int) -> Bool {
  // 開きの塊が `<details>` と `<summary>` の行だけでなければ、空行を挟まずに
  // 書かれた行が飲み込まれている。それを捨てないよう、覆っていないものとして扱う
  guard blocks[i] is HtmlBlock(html~, ..) else { return false }
  guard bare(html) else { return false }
  // 閉じも同じ — 記法だけで出来ていない塊は畳みの綴りとして使えない
  guard blocks[j] is HtmlBlock(html=close, ..) else { return false }
  guard lone(close) else { return false }
  let head = next(blocks, i)
  guard head < j else { return false }
  let level = match blocks[head] {
    Heading(level~, ..) => level
    BulletList(items~, ..) | OrderedList(items~, ..) =>
      // 項目は 1 個だけで、それが領域の全部でなければ覆っていない
      return items.length() == 1 && next(blocks, head) >= j
    _ => return false
  }
  // 中に同じか浅い見出しが居たら、その部分木より広い
  let mut k = head + 1
  while k < j {
    if blocks[k] is Heading(level=l, ..) && l <= level {
      return false
    }
    k = k + 1
  }
  // 閉じの直後が部分木の中なら、はみ出している
  let after = next(blocks, j)
  after >= blocks.length() ||
  (blocks[after] is Heading(level=l, ..) && l <= level)
}

///|
/// `<summary>` があり、包まれた行のラベルと一致するか。
/// **名前が無ければ畳みではない** — 領域が誰のものか言えていないので。
/// 比べるのは**原文の文字列どうし**（どちらも mdAst を通っていない）。
fn summary_fits(md : String, blocks : Array[@markdown.Block], i : Int) -> Bool {
  guard blocks[i] is HtmlBlock(html~, ..) else { return false }
  guard summary_of(html) is Some(s) else { return false }
  s == label_of(md, blocks[next(blocks, i)])
}

///|
/// 開きの塊から `<summary>` の中身を取り出す。
fn summary_of(html : String) -> String? {
  let a = find(html, "<summary>")
  guard a >= 0 else { return None }
  let from = a + 9
  let b = find(html, "</summary>")
  guard b >= from else { return None }
  Some(String::unsafe_substring(html, start=from, end=b))
}

///|
/// 包まれた行のラベル。見出しと項目でラベルの切り出し方が違う。
fn label_of(md : String, b : @markdown.Block) -> String {
  match b {
    Heading(style~, children~, span~, ..) =>
      head_label(md, span, style, children)
    BulletList(items~, ..) | OrderedList(items~, ..) =>
      match items[0].children.iter().find_first(c => c is Paragraph(..)) {
        Some(p) => item_label(md, p)
        None => ""
      }
    _ => ""
  }
}

///|
fn find(s : String, pat : String) -> Int {
  let n = s.length()
  let m = pat.length()
  let mut i = 0
  while i + m <= n {
    let mut k = 0
    while k < m && s[i + k] == pat[k] {
      k = k + 1
    }
    if k == m {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 原文の切り出し。末尾の改行は記法なので落とす。
fn cut(md : String, from : Int, to : Int) -> String {
  let mut z = to
  while z > from && (md[z - 1] == '\n' || md[z - 1] == '\r') {
    z = z - 1
  }
  String::unsafe_substring(md, start=from, end=z)
}

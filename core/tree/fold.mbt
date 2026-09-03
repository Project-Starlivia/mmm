// `<details>` を読む。
//
// 領域が**ちょうど 1 つのノードの定義ごと**包んでいれば、そのノードの畳み
// （`details = true`、中身は普通に読む）。そうでなければ中身の 1 枚
// （`Block::Details` の逐語）。裁定は docs/spec.md。

///|
/// 積む前のひと切れ。
priv enum Piece {
  Raw(@markdown.Block)
  /// 畳まれたノードの見出し・項目の行。中身は普通に読む
  Folded(@markdown.Block)
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
          // ちょうど覆っている。タグは落ち、包まれた行が畳まれる
          out.push(Folded(blocks[next(blocks, i)]))
          let mut k = next(blocks, i) + 1
          while k < j {
            out.push(Raw(blocks[k]))
            k = k + 1
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
/// 領域 [i, j] が、ちょうど 1 つのノードの部分木を包んでいるか。
///
/// ① 開きの直後が見出し・項目の行
/// ③ その部分木でぴったり終わる（中に同じか浅い見出しが無く、
///    閉じの直後が部分木の外）
fn covers(blocks : Array[@markdown.Block], i : Int, j : Int) -> Bool {
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
/// `<summary>` があれば、包まれた行のラベルと一致するか。無ければ問わない。
/// 比べるのは**原文の文字列どうし**（どちらも mdAst を通っていない）。
fn summary_fits(md : String, blocks : Array[@markdown.Block], i : Int) -> Bool {
  guard blocks[i] is HtmlBlock(html~, ..) else { return false }
  match summary_of(html) {
    None => true
    Some(s) => s == label_of(md, blocks[next(blocks, i)])
  }
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

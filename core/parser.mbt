// 行の走査。構造になるのは見出し `^(#+)\s+…` とリスト項目 `^\s*[-*+]\s…` の
// 2 つ。深さに上限を置かないので既成の Markdown パーサは使えないが、必要なのは
// 行のオフセットとフェンス / hide 領域の追跡だけなので、これで足りる。
//
// リストの深さは「直近の見出しの深さ + 1 + 入れ子段数」。**見出しは入れ子を
// リセットする**ので、見出しとリストが混ざった文書も同じ式で読める。
// 入れ子は字下げのスタックで数える — 2 スペース決め打ちにせず、前の項目より
// 深ければ子、浅ければ戻る（他所の 4 スペースもタブも読める）。
//
// 「本文」という概念は持たない。`- x` は必ずノード（mmm は散文を編集する
// 道具ではない）。根拠と決めは docs/superpowers/specs/2026-08-25-list-form.md。

///|
priv struct Line {
  start : Int // char offset of line start
  end : Int // char offset of line end, excluding "\r\n" / "\n"
  next : Int // char offset of the next line start
}

///|
fn scan_lines(text : String) -> Array[Line] {
  let lines : Array[Line] = []
  let n = text.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if code_at(text, i) == 10 {
      let mut e = i
      if e > start && code_at(text, e - 1) == 13 {
        e = e - 1
      }
      lines.push(Line::{ start, end: e, next: i + 1 })
      start = i + 1
    }
    i = i + 1
  }
  if start < n || n == 0 {
    lines.push(Line::{ start, end: n, next: n })
  }
  lines
}

///|
priv struct Heading {
  depth : Int
  from : Int // heading line start offset
  head_end : Int // heading line end offset (excl newline)
  // ラベルの始まり = 接頭辞（`## ` や `  - `）の終わり。深さの変更は
  // [from, label_start) をまるごと書き直す
  label_start : Int
  content_start : Int // offset just after the heading line's newline
  label : String
  hidden : Bool // inside a <!-- … --> hide region
}

///|
/// `<!-- … -->` の一区間。閉じていない（文書末まで開いたまま）ときは
/// close_start/close_next が -1。4 つ組の位置指定タプルだと、取り違えても
/// 型では検知できず、呼び出し側ごとに順序を覚える必要があったための struct 化。
priv struct HideRegion {
  open_start : Int
  open_next : Int
  close_start : Int
  close_next : Int
}

///|
/// フェンスで囲まれたコードブロックの一区間。
///
/// カードとして見せるかどうかはアプリ側の仕事だが、**どこからどこまでが
/// フェンスか**は文書の意味なので、答えはここにしか無い。以前は同じ規則が
/// TS 側にも 3 つ書かれていて、`” ```js copy ”` のような情報文字列で
/// 食い違い、フェンスの中の URL がカードになっていた。
///
/// 閉じないまま文書が終わったときは、end / body_end が文書末を指す。
priv struct Fence {
  start : Int // 開きフェンス行の行頭
  end : Int // 閉じフェンス行の行末（改行の手前）
  body_start : Int // 中身の最初の行頭
  body_end : Int // 中身の最後の行末。中身が無ければ body_start より手前
  info : String // 開きフェンスの後ろ（言語名など）。前後の空白は落とす
}

///|
/// 文書の頭 — 先頭の `---` から次の `---` まで（YAML frontmatter）。
///
/// **中は一切走査しない。** 他所の md が持つ `tags:` 配下の `- 設計` は、
/// 走査すればリスト項目としてノードになる（`^\s*[-*+]\s` は構造なので）。
/// 頭は文書の設定であって木ではないので、区間ごと外す。
///
/// 開きも閉じも**ちょうど 3 本**の `---` の行。閉じないまま文書が終われば
/// 頭ではない（先頭の `---` はただの区切り線に戻る）。
priv struct Head {
  start : Int // 開き `---` 行の行頭
  end : Int // 閉じ `---` 行の行末（改行の手前）
  body_start : Int // 中身の最初の行頭
  body_end : Int // 中身の最後の行末。中身が無ければ body_start より手前
}

///|
/// 開きフェンスの読み取り結果。閉じを見つけるのに要る文字と本数、
/// そして情報文字列。
priv struct FenceOpen {
  ch : Int
  len : Int
  info : String
}

///|
fn is_space(c : Int) -> Bool {
  c == 32 || c == 9
}

///|
/// 1 回の走査で分かること。見出し・hide 領域・フェンス区間は同じ 1 パスで
/// しか正しく求まらない（フェンスの中の `#` は見出しではなく、hide の中で
/// 開いたフェンスは `-->` で終わる）ので、まとめて返す。
priv struct Scan {
  heads : Array[Heading]
  hides : Array[HideRegion]
  fences : Array[Fence]
  head : Head? // 文書の頭。無ければ None
  // リスト項目が現れた最も浅い深さ（無ければ 0）。**開いたときのモード判定**の
  // ため — 使うのは init_doc だけだが、走査は 1 度で済ませる
  list_from : Int
}

///|
/// Fence-aware scan: a line starting with # inside a fenced code block is
/// content, not structure.
///
/// Hide regions: a line that is `<!--` opens one, a line that is `-->`
/// closes it. Headings inside stay part of the structure but are flagged
/// hidden. An unclosed region reports -1 for the close marker.
fn scan_doc(text : String, lines : Array[Line]) -> Scan {
  let out : Array[Heading] = []
  let regions : Array[HideRegion] = []
  let fences : Array[Fence] = []
  // リストの深さの材料。見出しが来たら両方リセットする
  let mut head_depth = 0
  let levels : Array[Int] = [] // 入れ子の各段の字下げ幅（列）
  let mut list_from = 0
  // いま開いている構造行の「中身の列」。フェンスの字下げをここから数える
  // （見出しの下は 0、`  - x` の下は 4）
  let mut content_col = 0
  let mut fence_base = 0
  let mut in_fence = false
  let mut fence_char = 0
  let mut fence_len = 0
  let mut f_start = 0
  let mut f_body = 0
  let mut f_info = ""
  let mut in_comment = false
  let mut c_open = 0
  let mut c_open_next = 0
  // 頭は行走査より先に決める。中は見ないので、走査はその次の行から始める
  let (head, first) = match scan_head(text, lines) {
    Some((h, next)) => (Some(h), next)
    None => (None, 0)
  }
  for idx = first; idx < lines.length(); idx = idx + 1 {
    let l = lines[idx]
    if in_fence {
      // 中身の終わりは「1 つ前の行の行末」。閉じ方が何であれ同じなので
      // ここで 1 度だけ求める
      let body_end = lines[idx - 1].end
      // hide 領域の中で開いたフェンスは `-->` を食ってはいけない。
      // HTML コメントは最初の `-->` で必ず終わる（エディタも CommonMark も
      // そう読む）ので、領域の中で生まれたフェンスは領域と一緒に終わる
      if in_comment && is_comment_close(text, l) {
        regions.push(HideRegion::{
          open_start: c_open,
          open_next: c_open_next,
          close_start: l.start,
          close_next: l.next,
        })
        fences.push(Fence::{
          start: f_start,
          end: body_end,
          body_start: f_body,
          body_end,
          info: f_info,
        })
        in_comment = false
        in_fence = false
        continue
      }
      if fence_close_len(text, l, fence_char, fence_base) >= fence_len {
        fences.push(Fence::{
          start: f_start,
          end: l.end,
          body_start: f_body,
          body_end,
          info: f_info,
        })
        in_fence = false
      }
      continue
    }
    match fence_open(text, l, content_col) {
      Some(f) => {
        in_fence = true
        fence_base = content_col
        fence_char = f.ch
        fence_len = f.len
        f_start = l.start
        f_body = l.next
        f_info = f.info
        continue
      }
      None => ()
    }
    if !in_comment && is_comment_open(text, l) {
      in_comment = true
      c_open = l.start
      c_open_next = l.next
      continue
    }
    if in_comment && is_comment_close(text, l) {
      regions.push(HideRegion::{
        open_start: c_open,
        open_next: c_open_next,
        close_start: l.start,
        close_next: l.next,
      })
      in_comment = false
      continue
    }
    // strict ^(#+)\s+(.*)$ with no leading spaces allowed
    let mut p = l.start
    while p < l.end && code_at(text, p) == 35 {
      p = p + 1
    }
    let depth = p - l.start
    if depth >= 1 && p < l.end && is_space(code_at(text, p)) {
      while p < l.end && is_space(code_at(text, p)) {
        p = p + 1
      }
      head_depth = depth
      levels.clear()
      content_col = 0
      out.push(head_at(text, l, depth, p, in_comment))
      continue
    }
    // ^\s*[-*+](\s|行末) はリスト項目。`---`（区切り線）や `**強調**` は
    // 印の直後が空白でないので構造にならない
    let mut q = l.start
    let mut col = 0
    while q < l.end && is_space(code_at(text, q)) {
      col = col + (if code_at(text, q) == 9 { 2 } else { 1 })
      q = q + 1
    }
    if q < l.end {
      let c = code_at(text, q)
      if (c == 45 || c == 42 || c == 43) &&
        (q + 1 == l.end || is_space(code_at(text, q + 1))) {
        while levels.length() > 0 && levels[levels.length() - 1] > col {
          ignore(levels.unsafe_pop())
        }
        if levels.length() == 0 || levels[levels.length() - 1] < col {
          levels.push(col)
        }
        let ld = head_depth + levels.length()
        let mut ls = q + 1
        while ls < l.end && is_space(code_at(text, ls)) {
          ls = ls + 1
        }
        if list_from == 0 || ld < list_from {
          list_from = ld
        }
        content_col = ls - l.start
        out.push(head_at(text, l, ld, ls, in_comment))
      }
    }
  }
  if in_comment {
    regions.push(HideRegion::{
      open_start: c_open,
      open_next: c_open_next,
      close_start: -1,
      close_next: -1,
    })
  }
  // 閉じないまま文書が終わったフェンス。以降の `#` はどのみち見出しに
  // ならないので、区間は文書末まで伸ばして構わない
  if in_fence {
    let last_end = if lines.length() > 0 {
      lines[lines.length() - 1].end
    } else {
      0
    }
    fences.push(Fence::{
      start: f_start,
      end: last_end,
      body_start: f_body,
      body_end: last_end,
      info: f_info,
    })
  }
  Scan::{ heads: out, hides: regions, fences, head, list_from }
}

///|
/// 構造行 1 つぶんの Heading。ラベルは末尾の空白（と、\n 無しで終わる
/// ファイルの \r）を落とす。見出しもリスト項目も同じ形に落ちる。
fn head_at(
  text : String,
  l : Line,
  depth : Int,
  label_start : Int,
  hidden : Bool,
) -> Heading {
  let mut label_end = l.end
  while label_end > label_start &&
        (
          is_space(code_at(text, label_end - 1)) ||
          code_at(text, label_end - 1) == 13
        ) {
    label_end = label_end - 1
  }
  Heading::{
    depth,
    from: l.start,
    head_end: l.end,
    label_start,
    content_start: l.next,
    label: slice(text, label_start, label_end),
    hidden,
  }
}

///|
/// [a, b) の前後から空白（と行末に残った \r）を落とした範囲。
fn trim_range(text : String, a : Int, b : Int) -> (Int, Int) {
  let mut s = a
  let mut e = b
  while s < e && is_space(code_at(text, s)) {
    s = s + 1
  }
  while e > s && (is_space(code_at(text, e - 1)) || code_at(text, e - 1) == 13) {
    e = e - 1
  }
  (s, e)
}

///|
/// 行の中身（前後の空白を落とした範囲）。
fn trimmed_span(text : String, l : Line) -> (Int, Int) {
  trim_range(text, l.start, l.end)
}

///|
/// Comment-region markers, matched the way real Markdown/HTML renderers
/// behave rather than by exact string. `<!---` still opens a comment (the
/// extra dash is content) and `--->` still closes one (it is `-` followed
/// by `-->`). Being stricter than the renderer means a one-character typo
/// silently hides the rest of the document while every other tool shows it
/// closed — which is exactly what happened on a real document.
///
/// Opener: `<!` followed by 2+ dashes, nothing else on the line.
fn is_comment_open(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  if b - a < 4 || code_at(text, a) != 60 || code_at(text, a + 1) != 33 {
    return false
  }
  let mut p = a + 2
  let mut dashes = 0
  while p < b && code_at(text, p) == 45 {
    p = p + 1
    dashes = dashes + 1
  }
  dashes >= 2 && p == b
}

///|
/// Closer: 2+ dashes followed by `>`, nothing else on the line.
fn is_comment_close(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  let mut p = a
  let mut dashes = 0
  while p < b && code_at(text, p) == 45 {
    p = p + 1
    dashes = dashes + 1
  }
  dashes >= 2 && p + 1 == b && code_at(text, p) == 62
}

///|
/// ちょうど 3 本の `-` だけの行か。前後の空白は落として見る。
/// `----` は開きも閉じもしない（Jekyll と同じ）。
fn is_head_marker(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  b - a == 3 &&
  code_at(text, a) == 45 &&
  code_at(text, a + 1) == 45 &&
  code_at(text, a + 2) == 45
}

///|
/// 先頭の頭を読む。区間と「次に走査を始める行の添字」を返す。
/// 先頭が `---` でない / 閉じが無い なら None。
fn scan_head(text : String, lines : Array[Line]) -> (Head, Int)? {
  if lines.length() == 0 || !is_head_marker(text, lines[0]) {
    return None
  }
  for i = 1; i < lines.length(); i = i + 1 {
    if is_head_marker(text, lines[i]) {
      return Some(
        (
          Head::{
            start: lines[0].start,
            end: lines[i].end,
            body_start: lines[0].next,
            body_end: lines[i - 1].end,
          },
          i + 1,
        ),
      )
    }
  }
  None
}

///|
/// 開きフェンスなら読み取る。フェンスは 3 本以上、バッククォートのフェンスは
/// 情報文字列にバッククォートを含めない。
///
/// 行頭の空白は **`base` 列からさらに 3 つまで**。`base` は囲っているリスト
/// 項目の中身の列（見出しの下なら 0）で、CommonMark が「項目の中では字下げを
/// 項目の中身の列から数える」のと同じ。ここを 0 固定にしていたころ、
/// リストの中のフェンスが認識されず、**中の `- x` がノードに化けていた**。
fn fence_open(text : String, l : Line, base : Int) -> FenceOpen? {
  let mut p = l.start
  let mut indent = 0
  while p < l.end && code_at(text, p) == 32 && indent < base + 3 {
    p = p + 1
    indent = indent + 1
  }
  if p >= l.end {
    return None
  }
  let c = code_at(text, p)
  if c != 96 && c != 126 {
    return None
  }
  let mut q = p
  while q < l.end && code_at(text, q) == c {
    q = q + 1
  }
  let len = q - p
  if len < 3 {
    return None
  }
  if c == 96 {
    let mut r = q
    while r < l.end {
      if code_at(text, r) == 96 {
        return None
      }
      r = r + 1
    }
  }
  let (a, b) = trim_range(text, q, l.end)
  Some(FenceOpen::{ ch: c, len, info: slice(text, a, b) })
}

///|
/// Length of a closing fence run of `fence_char`, or 0 if not a closing fence.
fn fence_close_len(text : String, l : Line, fence_char : Int, base : Int) -> Int {
  let mut p = l.start
  let mut indent = 0
  while p < l.end && code_at(text, p) == 32 && indent < base + 3 {
    p = p + 1
    indent = indent + 1
  }
  let mut q = p
  while q < l.end && code_at(text, q) == fence_char {
    q = q + 1
  }
  let len = q - p
  if len < 3 {
    return 0
  }
  while q < l.end {
    if !is_space(code_at(text, q)) {
      return 0
    }
    q = q + 1
  }
  len
}

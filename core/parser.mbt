// Line-level scanner. Structure detection is a single rule: ^(#+)\s+(.*)$
// (spec 2.1). Depth is unbounded (spec 2.2), so the standard Markdown parser
// cannot be used for headings; we only need line offsets and fence tracking.

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
    if cc(text, i) == 10 {
      let mut e = i
      if e > start && cc(text, e - 1) == 13 {
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
  hs : Int // heading line start offset
  he : Int // heading line end offset (excl newline)
  content_start : Int // offset just after the heading line's newline
  label : String
  hidden : Bool // inside a <!-- … --> hide region
}

///|
fn is_space(c : Int) -> Bool {
  c == 32 || c == 9
}

///|
/// Fence-aware scan (spec 4.3): a line starting with # inside a fenced
/// code block is content, not structure.
///
/// Hide regions (mmm.md そのに: コメントアウトで無効化): a line that is
/// exactly `<!--` opens one, a line that is exactly `-->` closes it.
/// Headings inside stay part of the structure but are flagged hidden.
/// Returns regions as (open start, open next, close start, close next);
/// an unclosed region reports (-1, -1) for the close marker.
fn scan_doc(text : String, lines : Array[Line]) -> (Array[Heading], Array[HideRegion]) {
  let out : Array[Heading] = []
  let regions : Array[HideRegion] = []
  let mut in_fence = false
  let mut fence_char = 0
  let mut fence_len = 0
  let mut in_comment = false
  let mut c_open = 0
  let mut c_open_next = 0
  for idx = 0; idx < lines.length(); idx = idx + 1 {
    let l = lines[idx]
    if in_fence {
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
        in_comment = false
        in_fence = false
        continue
      }
      if fence_close_len(text, l, fence_char) >= fence_len {
        in_fence = false
      }
      continue
    }
    let (fc, fl) = fence_open(text, l)
    if fl >= 3 {
      in_fence = true
      fence_char = fc
      fence_len = fl
      continue
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
    while p < l.end && cc(text, p) == 35 {
      p = p + 1
    }
    let depth = p - l.start
    if depth >= 1 && p < l.end && is_space(cc(text, p)) {
      while p < l.end && is_space(cc(text, p)) {
        p = p + 1
      }
      let mut label_end = l.end
      // also trim a trailing \r (a file ending in "\r" with no final \n)
      while label_end > p &&
            (is_space(cc(text, label_end - 1)) || cc(text, label_end - 1) == 13) {
        label_end = label_end - 1
      }
      out.push(Heading::{
        depth,
        hs: l.start,
        he: l.end,
        content_start: l.next,
        label: sub(text, p, label_end),
        hidden: in_comment,
      })
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
  (out, regions)
}

///|
/// True when the line's trimmed content is exactly `marker`.
/// Trimmed [start, end) of a line: leading spaces/tabs and trailing
/// whitespace (including a stray \r) removed.
fn trimmed_span(text : String, l : Line) -> (Int, Int) {
  let mut a = l.start
  let mut b = l.end
  while a < b && is_space(cc(text, a)) {
    a = a + 1
  }
  while b > a && (is_space(cc(text, b - 1)) || cc(text, b - 1) == 13) {
    b = b - 1
  }
  (a, b)
}

///|
/// Comment-region markers, matched the way real Markdown/HTML renderers
/// behave rather than by exact string. `<!---` still opens a comment (the
/// extra dash is content) and `--->` still closes one (it is `-` followed
/// by `-->`). Being stricter than the renderer means a one-character typo
/// silently hides the rest of the document while every other tool shows it
/// closed — which is exactly what happened in mmm.md.
///
/// Opener: `<!` followed by 2+ dashes, nothing else on the line.
fn is_comment_open(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  if b - a < 4 || cc(text, a) != 60 || cc(text, a + 1) != 33 {
    return false
  }
  let mut p = a + 2
  let mut dashes = 0
  while p < b && cc(text, p) == 45 {
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
  while p < b && cc(text, p) == 45 {
    p = p + 1
    dashes = dashes + 1
  }
  dashes >= 2 && p + 1 == b && cc(text, p) == 62
}

///|
/// Returns (fence_char, fence_len) for an opening fence, or (0, 0).
/// Up to 3 leading spaces; >=3 backticks or tildes; a backtick fence's
/// info string must not contain a backtick.
fn fence_open(text : String, l : Line) -> (Int, Int) {
  let mut p = l.start
  let mut indent = 0
  while p < l.end && cc(text, p) == 32 && indent < 3 {
    p = p + 1
    indent = indent + 1
  }
  if p >= l.end {
    return (0, 0)
  }
  let c = cc(text, p)
  if c != 96 && c != 126 {
    return (0, 0)
  }
  let mut q = p
  while q < l.end && cc(text, q) == c {
    q = q + 1
  }
  let len = q - p
  if len < 3 {
    return (0, 0)
  }
  if c == 96 {
    let mut r = q
    while r < l.end {
      if cc(text, r) == 96 {
        return (0, 0)
      }
      r = r + 1
    }
  }
  (c, len)
}

///|
/// Length of a closing fence run of `fence_char`, or 0 if not a closing fence.
fn fence_close_len(text : String, l : Line, fence_char : Int) -> Int {
  let mut p = l.start
  let mut indent = 0
  while p < l.end && cc(text, p) == 32 && indent < 3 {
    p = p + 1
    indent = indent + 1
  }
  let mut q = p
  while q < l.end && cc(text, q) == fence_char {
    q = q + 1
  }
  let len = q - p
  if len < 3 {
    return 0
  }
  while q < l.end {
    if !is_space(cc(text, q)) {
      return 0
    }
    q = q + 1
  }
  len
}

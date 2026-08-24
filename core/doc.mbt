// Document state. The text IS the document (spec 2.5: untouched bytes are
// never re-serialized). The node tree is derived by parsing, and every
// mutation from either pane is an edit set pushed onto the single undo
// stack (spec 4.1).


///|
fn cc(s : String, i : Int) -> Int {
  s[i].to_int()
}

///|
fn sub(s : String, a : Int, b : Int) -> String {
  s[a:b].to_owned()
}

///|
priv struct Node {
  mut id : Int
  depth : Int // テキストに書かれている `#` の数
  label : String
  hs : Int // heading line start
  he : Int // heading line end (excl newline)
  // end of this node's block in the text. Normally the start of the next
  // heading with depth <= ours, but cut short by a boundary that must not be
  // swallowed by a comment marker that would otherwise be split.
  // otherwise be split. Every range-based command (delete / copy / move /
  // hide) works on [hs, sub_end).
  sub_end : Int
  mut parent : Int // node id, or -1
  has_content : Bool
  hidden : Bool // inside a <!-- … --> hide region
}

///|
priv struct St {
  mut text : String
  mut nodes : Array[Node]
  undo : Array[Entry]
  redo : Array[Entry]
  mut rev : Int
  mut next_id : Int
  mut focus : Int
  mut last_sets : Array[Array[Edit]] // sets applied by the current API call
  mut tx : Entry? // open transaction accumulating steps
  mut hide_regions : Array[HideRegion] // <!-- … --> marker spans
  mut fences : Array[Fence] // ``` … ``` spans
}

///|
let st : St = {
  text: "",
  nodes: [],
  undo: [],
  redo: [],
  rev: 0,
  next_id: 1,
  focus: -1,
  last_sets: [],
  tx: None,
  hide_regions: [],
  fences: [],
}

///|
/// テキストからノード列を作り直す。
///
/// `#` はいくつあってもよい。深さ 1 の見出しと、それより前に書かれた
/// 見出しは、それぞれ独立したツリーになる。
fn rebuild_nodes(id_at : Map[Int, Int]) -> Unit {
  let lines = scan_lines(st.text)
  let scan = scan_doc(st.text, lines)
  let heads = scan.heads
  let regions = scan.hides
  st.hide_regions = regions
  st.fences = scan.fences
  // Offsets that are NOT nodes but must still stop a subtree.
  //
  // A node's range [hs, sub_end) is what delete / copy / move / hide all
  // operate on. Anything that lives in the text but is not part of the tree
  // must be excluded from it, or those commands silently damage text the
  // user never selected:
  //   `<!--` / `-->` marker lines — the closing marker sat INSIDE the
  //   hidden node's range while the opening one sat outside, so deleting
  //   a folded node left an orphan `<!--` and silently hid everything
  //   after it.
  //
  // 2 つ目以降の `#` は「構造から外す」のをやめた（2026-08-12）。外すと
  // ノードが 1 つも作られず、テキストには在るのにマップから消える（選択も
  // 移動も削除もできない）うえ、その子は親を失って浮いていた。いまは最初の
  // `#` より前に書いたノードと同じ扱い＝親なしの別ツリーとして出す。
  // 深さ 1 は下の (1) で必ず全ての祖先を閉じるので、範囲も自然に切れる。
  let hn = heads.length()
  let n = st.text.length()

  // ---- subtree end ----
  // (1) next kept heading with depth <= ours (stack, O(n))
  // `sub_end` という名前は Node.sub_end へそのまま流れ込む値だから
  // （以前は `sub` という名で、同じファイル中の substring ヘルパー
  // `sub(s, a, b)` と紛らわしく衝突していた）。
  let sub_end : Array[Int] = Array::make(hn, n)
  let open : Array[Int] = []
  for i = 0; i < hn; i = i + 1 {
    while open.length() > 0 && heads[open[open.length() - 1]].depth >= heads[i].depth {
      sub_end[open.unsafe_pop()] = heads[i].hs
    }
    open.push(i)
  }
  // (2) comment markers cut a range ONLY when the range would split the
  //     pair (contain one marker but not the other). A region that sits
  //     wholly inside the range is fine — folding a child must not detach
  //     it from its parent.
  let mut rs = 0
  for i = 0; i < hn; i = i + 1 {
    while rs < regions.length() {
      // close_at = この region の実効的な閉じ位置（未閉鎖なら文書末）
      let close_at = if regions[rs].close_start < 0 { n } else { regions[rs].close_start }
      if close_at < heads[i].hs {
        rs = rs + 1
      } else {
        break
      }
    }
    let mut k = rs
    while k < regions.length() {
      let r = regions[k]
      if r.open_start >= sub_end[i] {
        break
      }
      let close_at = if r.close_start < 0 { n } else { r.close_start }
      let has_open = r.open_start >= heads[i].hs // (open_start < sub_end[i] は上で保証済み)
      let has_close = close_at < sub_end[i] // (close_at >= hs は rs の前進で保証済み)
      if has_open != has_close {
        sub_end[i] = if has_close { close_at } else { r.open_start }
      }
      k = k + 1
    }
  }

  let nodes : Array[Node] = []
  for i = 0; i < hn; i = i + 1 {
    let h = heads[i]
    let id = match id_at.get(h.hs) {
      Some(old) => old
      None => {
        let fresh = st.next_id
        st.next_id = st.next_id + 1
        fresh
      }
    }
    // attached content: non-blank text between the heading line and whichever
    // comes first — the next heading or the end of this node's own range
    let mut content_end = if i + 1 < hn { heads[i + 1].hs } else { n }
    if sub_end[i] < content_end {
      content_end = sub_end[i]
    }
    let has_content = !is_blank_range(h.content_start, content_end)
    nodes.push(Node::{
      id,
      depth: h.depth,
      label: h.label,
      hs: h.hs,
      he: h.he,
      sub_end: sub_end[i],
      parent: -1,
      has_content,
      hidden: h.hidden,
    })
  }
  st.nodes = nodes
  recompute_parents()
}

///|
fn is_blank_range(a : Int, b : Int) -> Bool {
  for p = a; p < b; p = p + 1 {
    let c = cc(st.text, p)
    if c != 32 && c != 9 && c != 10 && c != 13 {
      return false
    }
  }
  true
}

///|
/// Recompute parent references from depths (stack, O(n)). A node with no
/// shallower predecessor is a top-level tree of its own (nodes before the
/// root form separate maps, not children of the root).
fn recompute_parents() -> Unit {
  // (depth, id, sub_end) of open ancestors. sub_end matters because a range
  // can be cut short by a comment marker that would otherwise be split.
  // An ancestor whose range already
  // ended cannot be the parent — keeping it would produce a child that lies
  // outside its parent's range, which every range-based command relies on.
  let stack : Array[(Int, Int, Int)] = []
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    while stack.length() > 0 &&
          (stack[stack.length() - 1].0 >= nd.depth ||
          stack[stack.length() - 1].2 <= nd.hs) {
      ignore(stack.unsafe_pop())
    }
    nd.parent = if stack.length() > 0 {
      stack[stack.length() - 1].1
    } else {
      -1
    }
    stack.push((nd.depth, nd.id, nd.sub_end))
  }
}

///|
fn find_node(id : Int) -> Int {
  for i = 0; i < st.nodes.length(); i = i + 1 {
    if st.nodes[i].id == id {
      return i
    }
  }
  -1
}

///|
/// Drop ids whose text range is contained in another selected id's range
/// (spec 4.4), keeping document order. Range containment — not the parent
/// chain — matches what the text commands actually operate on.
fn normalize_selection(ids : Array[Int]) -> Array[Int] {
  let want : Map[Int, Bool] = Map([])
  for id in ids {
    want[id] = true
  }
  let out : Array[Int] = []
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    if want.get(nd.id) is Some(_) {
      let mut covered = false
      for j = 0; j < st.nodes.length(); j = j + 1 {
        if j != i && want.get(st.nodes[j].id) is Some(_) {
          let o = st.nodes[j]
          if nd.hs > o.hs && nd.hs < o.sub_end {
            covered = true
            break
          }
        }
      }
      if !covered {
        out.push(i)
      }
    }
  }
  out
}

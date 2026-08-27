// 文書の状態。**テキストがそのまま文書**で、触っていない行のバイト列は
// 決して書き直されない。木は読み取って導いたもので、どちらのペインからの
// 変更も 1 本の undo スタックに積まれる編集の集合になる。


///|
fn code_at(s : String, i : Int) -> Int {
  s[i].to_int()
}

///|
fn slice(s : String, a : Int, b : Int) -> String {
  s[a:b].to_owned()
}

///|
/// ノードは、テキストの一区間 `[from, to)` に付けた名前でしかない。
/// 削除・コピー・移動・折り畳みはすべてこの区間に対する編集になる。
priv struct Node {
  mut id : Int
  depth : Int // `#` の数、またはリスト項目なら 見出し + 1 + 入れ子
  label : String
  from : Int // 区間の始まり = 構造行の行頭
  label_start : Int // 接頭辞（`## ` / `  - `）の終わり。深さの変更はここまでを書き直す
  head_end : Int // 構造行の行末（改行の手前）。ラベルを書き換える範囲
  // 区間の終わり。ふつうは「深さが自分以下の次の見出し」の手前だが、
  // hide のマーカーを片方だけ含んでしまう位置では、そこで切り上げる
  // （含めると、畳んだノードを消したときにマーカーが対で孤立する）
  to : Int
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
  mut head : Head? // 文書の頭（YAML frontmatter）の区間。無ければ None
  mut index_of : Map[Int, Int] // node id -> 添字
  // 書き方のモード = 「深さ list_from 以上をリストで書く」。0 は全部見出し。
  // **読みには一切関与しない**（パーサは常に両方を読む）。変わるのは
  // init_doc の検知と set_list_from だけ — 編集中にモードは動かない
  mut list_from : Int
  mut scan_list_from : Int // 直近の走査の検知結果。init_doc だけが写し取る
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
  head: None,
  index_of: Map([]),
  list_from: 0,
  scan_list_from: 0,
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
  st.head = scan.head
  st.scan_list_from = scan.list_from
  // Offsets that are NOT nodes but must still stop a subtree.
  //
  // A node's range [from, to) is what delete / copy / move / hide all
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

  // ---- 区間の終わり ----
  // (1) 深さが自分以下の次の見出しの手前まで（スタックで O(n)）
  let range_end : Array[Int] = Array::make(hn, n)
  let open : Array[Int] = []
  for i = 0; i < hn; i = i + 1 {
    while open.length() > 0 && heads[open[open.length() - 1]].depth >= heads[i].depth {
      range_end[open.unsafe_pop()] = heads[i].from
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
      if close_at < heads[i].from {
        rs = rs + 1
      } else {
        break
      }
    }
    let mut k = rs
    while k < regions.length() {
      let r = regions[k]
      if r.open_start >= range_end[i] {
        break
      }
      let close_at = if r.close_start < 0 { n } else { r.close_start }
      let has_open = r.open_start >= heads[i].from // (open_start < range_end[i] は上で保証済み)
      let has_close = close_at < range_end[i] // (close_at >= from は rs の前進で保証済み)
      if has_open != has_close {
        range_end[i] = if has_close { close_at } else { r.open_start }
      }
      k = k + 1
    }
  }

  let nodes : Array[Node] = []
  for i = 0; i < hn; i = i + 1 {
    let h = heads[i]
    let id = match id_at.get(h.from) {
      Some(old) => old
      None => {
        let fresh = st.next_id
        st.next_id = st.next_id + 1
        fresh
      }
    }
    // attached content: non-blank text between the heading line and whichever
    // comes first — the next heading or the end of this node's own range
    let mut content_end = if i + 1 < hn { heads[i + 1].from } else { n }
    if range_end[i] < content_end {
      content_end = range_end[i]
    }
    let has_content = !is_blank_range(h.content_start, content_end)
    nodes.push(Node::{
      id,
      depth: h.depth,
      label: h.label,
      from: h.from,
      label_start: h.label_start,
      head_end: h.head_end,
      to: range_end[i],
      parent: -1,
      has_content,
      hidden: h.hidden,
    })
  }
  st.nodes = nodes
  reindex()
  recompute_parents()
}

///|
fn is_blank_range(a : Int, b : Int) -> Bool {
  for p = a; p < b; p = p + 1 {
    let c = code_at(st.text, p)
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
  // (depth, id, to) of open ancestors. to matters because a range
  // can be cut short by a comment marker that would otherwise be split.
  // An ancestor whose range already
  // ended cannot be the parent — keeping it would produce a child that lies
  // outside its parent's range, which every range-based command relies on.
  let stack : Array[(Int, Int, Int)] = []
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    while stack.length() > 0 &&
          (stack[stack.length() - 1].0 >= nd.depth ||
          stack[stack.length() - 1].2 <= nd.from) {
      ignore(stack.unsafe_pop())
    }
    nd.parent = if stack.length() > 0 {
      stack[stack.length() - 1].1
    } else {
      -1
    }
    stack.push((nd.depth, nd.id, nd.to))
  }
}

///|
/// id → 添字の表を作り直す。ノードを並べ替えたあと（move_block が id を
/// 貼り直したあとも含む）必ず呼ぶ。
fn reindex() -> Unit {
  let m : Map[Int, Int] = Map([])
  for i = 0; i < st.nodes.length(); i = i + 1 {
    m[st.nodes[i].id] = i
  }
  st.index_of = m
}

///|
/// 無ければ -1。線形に探していたころ、まとめて動かすと
/// 「選んだ数 × ノード数」になっていた。
fn find_node(id : Int) -> Int {
  match st.index_of.get(id) {
    Some(i) => i
    None => -1
  }
}

///|
/// 他の選択に含まれている id を落とし、文書順のまま返す。親子関係ではなく
/// **範囲の包含**で見るのは、テキストのコマンドが実際に相手にするのが
/// 範囲だから。
///
/// 文書順では「先に来るノードの from のほうが必ず小さい」ので、i が落ちる
/// 条件は「i より前の選択ノードの to の最大値 > i.from」と同じ。総当たりで
/// 見ていたころ、覆うノードが無い並び（兄弟だけを全選択）で二乗になり、
/// 4000 個の Mod+A → Tab が 240ms 固まっていた。
fn normalize_selection(ids : Array[Int]) -> Array[Int] {
  let want : Map[Int, Bool] = Map([])
  for id in ids {
    want[id] = true
  }
  let out : Array[Int] = []
  let mut cover_end = -1
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    if want.get(nd.id) is Some(_) {
      if nd.from >= cover_end {
        out.push(i)
      }
      if nd.to > cover_end {
        cover_end = nd.to
      }
    }
  }
  out
}

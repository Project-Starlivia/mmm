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
  depth : Int // 構造上の深さ（区間の中では読み替えられる）
  raw_depth : Int // テキストに書かれている `#` の数
  label : String
  hs : Int // heading line start
  he : Int // heading line end (excl newline)
  // end of this node's block in the text. Normally the start of the next
  // heading with depth <= ours, but cut short by a boundary that must not be
  // swallowed: 有効な区切り行、またはペアを割ってしまうコメントマーカー。
  // otherwise be split. Every range-based command (delete / copy / move /
  // hide) works on [hs, sub_end).
  sub_end : Int
  mut parent : Int // node id, or -1
  mut group : Int // sibling group index (split by --- separators)
  has_content : Bool
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
  mut seps : Array[Int] // 有効な区切り行の開始オフセット（区間の境目）
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
  seps: [],
}

///|
/// テキストからノード列を作り直す。
///
/// `#` はいくつあってもよい。最初の `#` が主ルートで、2 つ目以降と、
/// 最初の `#` より前に書かれた見出しは、それぞれ独立した別ツリーになる。
/// `---` で区切られた「区間」はルート直下の概念で、区間の中の見出しは
/// 区間の先頭を深さ 2 として相対的に読み替える。
fn rebuild_nodes(id_at : Map[Int, Int]) -> Unit {
  let lines = scan_lines(st.text)
  let (all, raw_seps, regions) = scan_doc(st.text, lines)
  st.hide_regions = regions
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
  let heads : Array[Heading] = all
  let hn = heads.length()
  // 区切りが有効になる条件（残り 3 つ。直前が本文でないことは scan_doc 済み）:
  //   3. 次に来る非空白が見出しであること（本文が挟まればただの水平線）
  //   4. その見出しが `##` 以下であること（`#` は常にルート＝別ツリーなので
  //      持ち上げる先が無い）
  //   5. ルート（最初の `#`）が既に現れている位置にあること
  // 5 のおかげで front matter の `---` は自動的に落ちる（どちらも最初の
  // `#` より前にあるため）。2 連の `---` も 3 で最後の 1 本だけが残る。
  let mut root_hs = -1
  for h in heads {
    if h.depth == 1 {
      root_hs = h.hs
      break
    }
  }
  let seps : Array[Int] = []
  let sep_head : Array[Int] = [] // その区切りが始める区間の先頭（heads の添字）
  let mut hp = 0
  for s in raw_seps {
    let (s_start, s_next) = s
    while hp < hn && heads[hp].hs < s_start {
      hp = hp + 1
    }
    // 空行のほかに hide のマーカー行も跨いでよい（hide しただけで
    // 区間が消えて、以降の左右が入れ替わるのを防ぐ）
    if hp >= hn || !is_blank_or_marker_range(st.text, s_next, heads[hp].hs) {
      continue
    }
    if heads[hp].depth < 2 {
      continue
    }
    if root_hs < 0 || s_start < root_hs {
      continue
    }
    seps.push(s_start)
    sep_head.push(hp)
  }

  st.seps = seps

  // ---- 区間ごとの深さの読み替え ----
  // 区切りの直後の見出しはルート直下（深さ 2）として読む。区間の中は先頭を
  // 基準にした相対の深さになり、先頭より浅いものは基準に丸める。
  // `#` は常にルート（別ツリー）なので持ち上げず、そこで区間も終わる。
  let eff : Array[Int] = Array::make(hn, 0)
  let mut base = 2 // いまの区間の基準の深さ
  let mut sc = 0
  for i = 0; i < hn; i = i + 1 {
    while sc < sep_head.length() && sep_head[sc] < i {
      sc = sc + 1
    }
    if sc < sep_head.length() && sep_head[sc] == i {
      base = heads[i].depth // この見出しが区間の先頭。ここを深さ 2 として読む
      sc = sc + 1
    }
    if heads[i].depth == 1 {
      eff[i] = 1
      base = 2 // 新しいツリーが始まるので区間は終わり
    } else {
      // 基準より浅い見出しが出たら基準を取り直す。そうしないと、それ以降の
      // 深い見出しが元の基準でずらされ、親子関係が崩れる
      if heads[i].depth < base {
        base = heads[i].depth
      }
      let shift = if base > 2 { 2 - base } else { 0 }
      eff[i] = heads[i].depth + shift
    }
  }
  let n = st.text.length()

  // ---- subtree end ----
  // (1) next kept heading with depth <= ours (stack, O(n))
  // `sub_end` という名前は Node.sub_end へそのまま流れ込む値だから
  // （以前は `sub` という名で、同じファイル中の substring ヘルパー
  // `sub(s, a, b)` と紛らわしく衝突していた）。
  let sub_end : Array[Int] = Array::make(hn, n)
  let open : Array[Int] = []
  for i = 0; i < hn; i = i + 1 {
    while open.length() > 0 && eff[open[open.length() - 1]] >= eff[i] {
      sub_end[open.unsafe_pop()] = heads[i].hs
    }
    open.push(i)
  }
  // (2) 有効な区切り行はどのノードにも属さない。範囲に含めてしまうと、
  //     コピーや削除に無関係な `---` が付いてくる（区間の先頭は次の見出し
  //     なので、範囲は区切り行の手前で終わるのが正しい）。
  // 区切りの直後の見出しで終わっているノードだけを、区切り行の手前まで
  // 縮める。全部を一律に切ると、区間をまたいで続くはずのルートの範囲まで
  // 切れてしまい、区間がルートの子でなくなる
  for k = 0; k < seps.length(); k = k + 1 {
    let head_hs = heads[sep_head[k]].hs
    for i = 0; i < hn; i = i + 1 {
      if sub_end[i] == head_hs && heads[i].hs < seps[k] {
        sub_end[i] = seps[k]
      }
    }
  }
  // (3) comment markers cut a range ONLY when the range would split the
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
      depth: eff[i],
      raw_depth: h.depth,
      label: h.label,
      hs: h.hs,
      he: h.he,
      sub_end: sub_end[i],
      parent: -1,
      group: 0,
      has_content,
      hidden: h.hidden,
    })
  }
  st.nodes = nodes
  recompute_parents()
  compute_groups(seps)
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
/// 各ノードに区間（`---` で区切られたまとまり）の番号を振る。
/// 番号はその位置より前にある有効な区切りの本数そのもの。
/// 親ごとに 0 から詰め直すのは**やめた**（詰め直すと、最初の子より前に
/// 置かれた区切りが吸収されて消え、「全部を反対側に出す」が書けなかった）。
fn compute_groups(seps : Array[Int]) -> Unit {
  // 区間の番号 = その位置より前にある有効な区切りの本数。
  //
  // 以前は親ごとに 0 から詰め直していたので、最初の子より前に置かれた
  // 区切りが吸収されて消えていた（「全部左に出す」が書けなかった原因）。
  // 区間はルート直下だけの概念になったので、単純な通し番号でよい。
  let mut sp = 0
  let mut g = 0
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    while sp < seps.length() && seps[sp] < nd.hs {
      sp = sp + 1
      g = g + 1
    }
    nd.group = g
  }
}

///|
/// Recompute parent references from depths (stack, O(n)). A node with no
/// shallower predecessor is a top-level tree of its own (nodes before the
/// root form separate maps, not children of the root).
fn recompute_parents() -> Unit {
  // (depth, id, sub_end) of open ancestors. sub_end matters because a range
  // can be cut short by a boundary (有効な区切り行、またはペアを割って
  // しまうコメントマーカー). An ancestor whose range already
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
/// 主ルート（最初の `#`）の添字。左右の側はこのノードの直下だけの概念。
fn root_index() -> Int {
  for i = 0; i < st.nodes.length(); i = i + 1 {
    if st.nodes[i].raw_depth == 1 {
      return i
    }
  }
  -1
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

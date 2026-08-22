// その場のコマンド。名前の変更・削除・折り畳み・コピー用テキスト。
// どれもノードの範囲 [hs, sub_end) に対する編集で、行を動かさない。

///|
/// Rename normalizes only the edited heading line (spec 2.5).
fn cmd_rename(id : Int, label : String, tag : String) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  let nd = st.nodes[i]
  let line = hashes(nd.depth) + " " + sanitize_label(label)
  let old = sub(st.text, nd.hs, nd.he)
  if line == old {
    return
  }
  apply_sets(
    [[Edit::{ from: nd.hs, to: nd.he, insert: line, removed: old }]],
    tag,
  )
  st.focus = id
}

///|
fn cmd_delete(ids : Array[Int]) -> Unit {
  let idxs = normalize_selection(ids)
  if idxs.length() == 0 {
    return
  }
  // pick focus: first surviving node after the last deleted range,
  // else the node before the first range, else none
  let last = st.nodes[idxs[idxs.length() - 1]]
  let first = st.nodes[idxs[0]]
  let deleted : Map[Int, Bool] = Map([])
  for k in idxs {
    deleted[st.nodes[k].id] = true
  }
  let mut focus_id = -1
  for nd in st.nodes {
    if nd.hs >= last.sub_end && deleted.get(nd.id) is None {
      focus_id = nd.id
      break
    }
  }
  if focus_id == -1 {
    for j = st.nodes.length() - 1; j >= 0; j = j - 1 {
      let nd = st.nodes[j]
      if nd.hs < first.hs && deleted.get(nd.id) is None {
        focus_id = nd.id
        break
      }
    }
  }
  let ranges : Array[(Int, Int)] = []
  for k in idxs {
    ranges.push((st.nodes[k].hs, st.nodes[k].sub_end))
  }
  // if deletion reaches EOF, the dangling separator blank must go too;
  // apply the cleanup at the start of the contiguous chain ending at EOF
  let lastr = ranges[ranges.length() - 1]
  if lastr.1 == st.text.length() {
    let mut ci = ranges.length() - 1
    while ci > 0 && ranges[ci - 1].1 == ranges[ci].0 {
      ci = ci - 1
    }
    let mut from = tidy_del_start(ranges[ci].0)
    if ci > 0 && from < ranges[ci - 1].1 {
      from = ranges[ci - 1].1
    }
    ranges[ci] = (from, ranges[ci].1)
  }
  let set : Array[Edit] = []
  for n = 0; n < idxs.length(); n = n + 1 {
    let nd = st.nodes[idxs[n]]
    let (from, to) = ranges[n]
    // 単独 hide されたノードを削除するときは、範囲の外にあるマーカーが
    // 対で孤立してしまう(範囲に含めていないのは、子を消しただけで
    // マーカー対が残らないようにするため)。ここで対ごと一緒に消す。
    // open は範囲より前・close は範囲より後なので、この位置に挟めば
    // apply_edit_set が要求する昇順のまま保たれる
    let hr = if nd.hidden { sole_hide_region(nd) } else { -1 }
    if hr >= 0 {
      let r = st.hide_regions[hr]
      set.push(Edit::{
        from: r.open_start,
        to: r.open_next,
        insert: "",
        removed: sub(st.text, r.open_start, r.open_next),
      })
    }
    set.push(Edit::{ from, to, insert: "", removed: sub(st.text, from, to) })
    if hr >= 0 {
      let r = st.hide_regions[hr]
      set.push(Edit::{
        from: r.close_start,
        to: r.close_next,
        insert: "",
        removed: sub(st.text, r.close_start, r.close_next),
      })
    }
  }
  apply_sets([set], "")
  st.focus = focus_id
}

///|
/// Markdown text of the selected subtrees, for copy / cut (spec 4.4).
/// Separators follow the document's own newline flavor.
fn subtree_text(ids : Array[Int]) -> String {
  let idxs = normalize_selection(ids)
  let br = nl()
  let sb = StringBuilder::new()
  for n = 0; n < idxs.length(); n = n + 1 {
    let nd = st.nodes[idxs[n]]
    let mut block = sub(st.text, nd.hs, nd.sub_end)
    while block.length() > 0 &&
          (
            cc(block, block.length() - 1) == 10 ||
            cc(block, block.length() - 1) == 13
          ) {
      block = sub(block, 0, block.length() - 1)
    }
    sb.write_string(block)
    sb.write_string(br)
    if n < idxs.length() - 1 {
      sb.write_string(br)
    }
  }
  sb.to_string()
}

///|
/// Toggle a subtree's hide region (mmm.md そのに: コメントアウトで無効化).
/// Hiding wraps [hs, sub_end) in `<!--` / `-->` marker lines — external
/// renderers skip the branch, but it stays in the structure as hidden
/// nodes. Showing removes the markers of the region containing the node.
/// Hiding a subtree that already contains markers (nested hide) is a no-op.
fn cmd_toggle_hidden(id : Int) -> Unit {
  let i = find_node(id)
  if i < 0 {
    return
  }
  let nd = st.nodes[i]
  let n = st.text.length()
  if nd.hidden {
    for r in st.hide_regions {
      let body_end = if r.close_start == -1 { n } else { r.close_start }
      if nd.hs >= r.open_next && nd.hs < body_end {
        let edits : Array[Edit] = [
          Edit::{
            from: r.open_start,
            to: r.open_next,
            insert: "",
            removed: sub(st.text, r.open_start, r.open_next),
          },
        ]
        if r.close_start != -1 {
          // 閉じマーカーが改行で終わっていない = hide のときに
          // 「本文が改行で終わっていなかったので改行を足した」ケース。
          // その改行も一緒に消さないと、往復するたびに末尾が伸びる
          let mut from = r.close_start
          if r.close_next == n && (n == 0 || cc(st.text, n - 1) != 10) {
            let eol = nl()
            let len = eol.length()
            if from >= len && sub(st.text, from - len, from) == eol {
              from = from - len
            }
          }
          edits.push(Edit::{
            from,
            to: r.close_next,
            insert: "",
            removed: sub(st.text, from, r.close_next),
          })
        }
        apply_sets([edits], "")
        st.focus = id
        return
      }
    }
    return
  }
  for r in st.hide_regions {
    if (r.open_start >= nd.hs && r.open_start < nd.sub_end) ||
      (r.close_start >= nd.hs && r.close_start < nd.sub_end) {
      return
    }
  }
  let eol = nl()
  // 閉じマーカーは必ず行頭に置く。本文が改行で終わっていないときは前に改行を
  // 足すが、そのぶん後ろには足さない。こうすると「マーカーが改行で終わって
  // いるか」で、足した改行の有無が show 側から判別できる（往復が可逆になる）
  let close = if nd.sub_end > 0 && cc(st.text, nd.sub_end - 1) != 10 {
    eol + "-->"
  } else {
    "-->" + eol
  }
  apply_sets(
    [
      [
        Edit::{ from: nd.hs, to: nd.hs, insert: "<!--" + eol, removed: "" },
        Edit::{ from: nd.sub_end, to: nd.sub_end, insert: close, removed: "" },
      ],
    ],
    "",
  )
  st.focus = id
}

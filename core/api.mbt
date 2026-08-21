// Public API surface. Strings in, JSON strings out. Every mutating call
// returns a snapshot carrying the edit sets applied during the call so the
// Markdown pane can update incrementally without re-sending the whole text.
// The js/ package wraps these with #export_name for the browser.

///|
fn json_escape(s : String, sb : StringBuilder) -> Unit {
  for ch in s.iter() {
    let c = ch.to_int()
    if c == 34 {
      sb.write_string("\\\"")
    } else if c == 92 {
      sb.write_string("\\\\")
    } else if c == 10 {
      sb.write_string("\\n")
    } else if c == 13 {
      sb.write_string("\\r")
    } else if c == 9 {
      sb.write_string("\\t")
    } else if c < 32 {
      let hex = "0123456789abcdef"
      sb.write_string("\\u00")
      sb.write_string(sub(hex, c / 16, c / 16 + 1))
      sb.write_string(sub(hex, c % 16, c % 16 + 1))
    } else {
      sb.write_char(ch)
    }
  }
}

///|
fn snapshot() -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"rev\":")
  sb.write_string(st.rev.to_string())
  sb.write_string(",\"focus\":")
  sb.write_string(st.focus.to_string())
  sb.write_string(",\"canUndo\":")
  sb.write_string(if st.undo.length() > 0 { "true" } else { "false" })
  sb.write_string(",\"canRedo\":")
  sb.write_string(if st.redo.length() > 0 { "true" } else { "false" })
  sb.write_string(",\"editSets\":[")
  for i = 0; i < st.last_sets.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("[")
    let set = st.last_sets[i]
    for j = 0; j < set.length(); j = j + 1 {
      if j > 0 {
        sb.write_string(",")
      }
      let e = set[j]
      sb.write_string("{\"from\":")
      sb.write_string(e.from.to_string())
      sb.write_string(",\"to\":")
      sb.write_string(e.to.to_string())
      sb.write_string(",\"insert\":\"")
      json_escape(e.insert, sb)
      sb.write_string("\"}")
    }
    sb.write_string("]")
  }
  sb.write_string("],\"nodes\":[")
  for i = 0; i < st.nodes.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    let nd = st.nodes[i]
    sb.write_string("{\"id\":")
    sb.write_string(nd.id.to_string())
    sb.write_string(",\"depth\":")
    sb.write_string(nd.depth.to_string())
    // テキストに書かれている `#` の数。UI 側で見出しを組み立てるとき
    // （貼り付けなど）は、構造上の深さではなくこちらを使わないと
    // 読み替えの起きている区間の中で深さがずれる
    sb.write_string(",\"rawDepth\":")
    sb.write_string(nd.raw_depth.to_string())
    sb.write_string(",\"parent\":")
    sb.write_string(nd.parent.to_string())
    sb.write_string(",\"hs\":")
    sb.write_string(nd.hs.to_string())
    sb.write_string(",\"he\":")
    sb.write_string(nd.he.to_string())
    sb.write_string(",\"subEnd\":")
    sb.write_string(nd.sub_end.to_string())
    sb.write_string(",\"group\":")
    sb.write_string(nd.group.to_string())
    sb.write_string(",\"hasContent\":")
    sb.write_string(if nd.has_content { "true" } else { "false" })
    sb.write_string(",\"hidden\":")
    sb.write_string(if nd.hidden { "true" } else { "false" })
    sb.write_string(",\"label\":\"")
    json_escape(nd.label, sb)
    sb.write_string("\"}")
  }
  sb.write_string("]}")
  st.last_sets = []
  st.focus = -1
  sb.to_string()
}

///|
pub fn init_doc(text : String) -> String {
  st.text = text
  st.undo.clear()
  st.redo.clear()
  st.tx = None
  st.next_id = 1
  st.nodes = []
  st.last_sets = []
  rebuild_nodes(Map([]))
  st.rev = st.rev + 1
  st.focus = -1
  snapshot()
}

///|
pub fn get_text() -> String {
  st.text
}

///|
pub fn replace_text(
  from : Int,
  to : Int,
  insert : String,
  tag : String,
) -> String {
  let n = st.text.length()
  if from < 0 || to > n || from > to {
    return snapshot()
  }
  let removed = sub(st.text, from, to)
  if removed == insert {
    return snapshot()
  }
  apply_sets([[Edit::{ from, to, insert, removed }]], tag)
  snapshot()
}

///|
pub fn add_child(id : Int, tag : String) -> String {
  cmd_add_child(id, tag)
  snapshot()
}

///|
pub fn add_sibling(id : Int, tag : String) -> String {
  cmd_add_sibling(id, tag)
  snapshot()
}

///|
pub fn add_sibling_before(id : Int, tag : String) -> String {
  cmd_add_sibling_before(id, tag)
  snapshot()
}

///|
pub fn add_parent(id : Int, tag : String) -> String {
  cmd_add_parent(id, tag)
  snapshot()
}

///|
pub fn add_root(tag : String) -> String {
  cmd_add_root(tag)
  snapshot()
}

///|
pub fn rename_node(id : Int, label : String, tag : String) -> String {
  cmd_rename(id, label, tag)
  snapshot()
}

///|
pub fn delete_nodes(ids : Array[Int]) -> String {
  cmd_delete(ids)
  snapshot()
}

///|
pub fn indent_nodes(ids : Array[Int]) -> String {
  cmd_indent(ids)
  snapshot()
}

///|
pub fn outdent_nodes(ids : Array[Int]) -> String {
  cmd_outdent(ids)
  snapshot()
}

///|
pub fn move_nodes(ids : Array[Int], target : Int, pos : Int) -> String {
  cmd_move(ids, target, pos)
  snapshot()
}

///|
/// A -> B の線への割り込み。ids を B の直前へ動かしてから B を 1 段下げる。
pub fn move_as_parent(ids : Array[Int], target : Int) -> String {
  cmd_move_as_parent(ids, target)
  snapshot()
}

///|
/// 側の末尾へ動かす。left=true で左（空なら `---` を 1 本書いて開く）。
pub fn move_side_end(ids : Array[Int], left : Bool) -> String {
  cmd_move_side_end(ids, left)
  snapshot()
}

///|
/// 側の末尾に新しい子を作る（ルートの左右 ＋ ボタン）。
pub fn add_side_end(left : Bool, tag : String) -> String {
  cmd_add_side_end(left, tag)
  snapshot()
}

///|
pub fn reorder_node(id : Int, dir : Int) -> String {
  cmd_reorder(id, dir)
  snapshot()
}

///|
pub fn toggle_hidden(id : Int) -> String {
  cmd_toggle_hidden(id)
  snapshot()
}

///|
pub fn undo() -> String {
  do_undo()
  snapshot()
}

///|
pub fn redo() -> String {
  do_redo()
  snapshot()
}

///|
/// 入力中のセッションを丸ごと取り消す。
/// **UI からは呼んでいない**（マップの編集は「確定のみ、キャンセル無し」と
/// 決めたため、js/exports.mbt にも出していない）。コアの機能としては
/// 生きていてテストもあるので、キャンセルを入れるならここから繋ぐ。
pub fn abort_session(tag : String) -> String {
  do_abort(tag)
  snapshot()
}

///|
pub fn selection_text(ids : Array[Int]) -> String {
  subtree_text(ids)
}

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
      sb.write_string(slice(hex, c / 16, c / 16 + 1))
      sb.write_string(slice(hex, c % 16, c % 16 + 1))
    } else {
      sb.write_char(ch)
    }
  }
}

///|
/// `"key":value` を 1 つ書く。前の要素との区切りは `sep` が持つ —
/// 「先頭かどうか」を知っているのは呼び出し側だけなので。
fn put_int(sb : StringBuilder, key : String, v : Int) -> Unit {
  sb.write_string("\"")
  sb.write_string(key)
  sb.write_string("\":")
  sb.write_string(v.to_string())
}

///|
fn put_bool(sb : StringBuilder, key : String, v : Bool) -> Unit {
  sb.write_string("\"")
  sb.write_string(key)
  sb.write_string("\":")
  sb.write_string(if v { "true" } else { "false" })
}

///|
fn put_str(sb : StringBuilder, key : String, v : String) -> Unit {
  sb.write_string("\"")
  sb.write_string(key)
  sb.write_string("\":\"")
  json_escape(v, sb)
  sb.write_string("\"")
}

///|
/// 配列の 2 つ目以降にカンマを打つ。
fn sep(sb : StringBuilder, i : Int) -> Unit {
  if i > 0 {
    sb.write_string(",")
  }
}

///|
fn take_snapshot() -> String {
  let sb = StringBuilder::new()
  sb.write_string("{")
  put_int(sb, "rev", st.rev)
  sb.write_string(",")
  put_int(sb, "focus", st.focus)
  sb.write_string(",")
  put_bool(sb, "canUndo", st.undo.length() > 0)
  sb.write_string(",")
  put_bool(sb, "canRedo", st.redo.length() > 0)
  sb.write_string(",")
  put_int(sb, "listFrom", st.list_from)
  sb.write_string(",\"editSets\":[")
  for i = 0; i < st.last_sets.length(); i = i + 1 {
    sep(sb, i)
    sb.write_string("[")
    let set = st.last_sets[i]
    for j = 0; j < set.length(); j = j + 1 {
      sep(sb, j)
      let e = set[j]
      sb.write_string("{")
      put_int(sb, "from", e.from)
      sb.write_string(",")
      put_int(sb, "to", e.to)
      sb.write_string(",")
      put_str(sb, "insert", e.insert)
      sb.write_string("}")
    }
    sb.write_string("]")
  }
  sb.write_string("],\"nodes\":[")
  for i = 0; i < st.nodes.length(); i = i + 1 {
    sep(sb, i)
    let nd = st.nodes[i]
    sb.write_string("{")
    put_int(sb, "id", nd.id)
    sb.write_string(",")
    put_int(sb, "depth", nd.depth)
    sb.write_string(",")
    put_int(sb, "parent", nd.parent)
    sb.write_string(",")
    put_int(sb, "from", nd.from)
    sb.write_string(",")
    put_int(sb, "headEnd", nd.head_end)
    sb.write_string(",")
    put_int(sb, "to", nd.to)
    sb.write_string(",")
    put_bool(sb, "hasContent", nd.has_content)
    sb.write_string(",")
    put_bool(sb, "hidden", nd.hidden)
    sb.write_string(",")
    put_str(sb, "label", nd.label)
    sb.write_string("}")
  }
  sb.write_string("],\"fences\":[")
  for i = 0; i < st.fences.length(); i = i + 1 {
    sep(sb, i)
    let f = st.fences[i]
    sb.write_string("{")
    put_int(sb, "from", f.start)
    sb.write_string(",")
    put_int(sb, "to", f.end)
    sb.write_string(",")
    put_int(sb, "bodyFrom", f.body_start)
    sb.write_string(",")
    put_int(sb, "bodyTo", f.body_end)
    sb.write_string(",")
    put_str(sb, "info", f.info)
    sb.write_string("}")
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
  // 開いたときだけの自動判定。以降どれだけ編集してもモードは動かない
  st.list_from = st.scan_list_from
  st.rev = st.rev + 1
  st.focus = -1
  take_snapshot()
}

///|
/// 書き方のモードを変える。0 = 全部見出し、n = 深さ n 以上をリストで書く。
/// テキストには触らない — 揃えるのは reformat の仕事。
pub fn set_list_from(b : Int) -> String {
  st.list_from = if b < 0 { 0 } else { b }
  take_snapshot()
}

///|
/// 文書ぜんぶをいまのモードの正規形に書き直す。1 回の undo で戻る。
///
/// **接頭辞だけでは足りない。** リストの形では、中身の行を項目の中身の列まで
/// 字下げしないと、外の Markdown パーサはそこでリストを閉じてしまう
/// （そのあとの項目は別のリストになり、深い字下げはコードブロックに化ける）。
/// mmm の外で読めることがこの機能の目的なので、字下げと空行まで面倒を見る。
pub fn reformat(tag : String) -> String {
  let set = reformat_edits()
  if set.length() > 0 {
    apply_sets([set], tag)
  }
  take_snapshot()
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
    return take_snapshot()
  }
  let removed = slice(st.text, from, to)
  if removed == insert {
    return take_snapshot()
  }
  apply_sets([[Edit::{ from, to, insert, removed }]], tag)
  take_snapshot()
}

///|
pub fn add_child(id : Int, tag : String) -> String {
  cmd_add_child(id, tag)
  take_snapshot()
}

///|
pub fn add_sibling(id : Int, tag : String) -> String {
  cmd_add_sibling(id, tag)
  take_snapshot()
}

///|
pub fn add_sibling_before(id : Int, tag : String) -> String {
  cmd_add_sibling_before(id, tag)
  take_snapshot()
}

///|
pub fn add_parent(id : Int, tag : String) -> String {
  cmd_add_parent(id, tag)
  take_snapshot()
}

///|
pub fn add_root(tag : String) -> String {
  cmd_add_root(tag)
  take_snapshot()
}

///|
pub fn rename_node(id : Int, label : String, tag : String) -> String {
  cmd_rename(id, label, tag)
  take_snapshot()
}

///|
/// そのノードの本文の末尾へ 1 行を追加する。**貼り付け・ドロップ・
/// お絵描き・その場でのリンクが通る唯一の道**（画像 / URL / `Shift+L`）。
///
/// リストの形で書かれたノードなら、その項目の中身の列まで字下げする。
/// TS 側が `insertBlock` で自前に組んでいた頃は常に列 0 で書いていたため、
/// リストの中に貼ると外の Markdown パーサがそこでリストを閉じ、続く兄弟が
/// 迷子になっていた（実際に踏んだ）。
pub fn insert_content(id : Int, line : String, tag : String) -> String {
  let i = find_node(id)
  if i >= 0 {
    apply_sets([[append_content_edit(i, line)]], tag)
  }
  take_snapshot()
}

///|
/// 深さ `depth` の新しい構造行（見出しかリスト項目か）を、**いまの文書の
/// モード**で 1 行ぶん書く。ラベルは正規化する（rename と同じ）。
///
/// 貼り付けの「見出し無しテキスト → 子ノードを並べる」が使う。以前は
/// `#`.repeat(depth) を直に書いていたため、リストの形の文書に貼ると
/// **見出しがリストの入れ子をリセットして以降の兄弟が丸ごと迷子になる**
/// という、書式の見た目ではなく木そのものを壊す不具合になっていた。
pub fn format_line(depth : Int, label : String) -> String {
  prefix_for(depth) + sanitize_label(label)
}

///|
pub fn delete_nodes(ids : Array[Int]) -> String {
  cmd_delete(ids)
  take_snapshot()
}

///|
pub fn indent_nodes(ids : Array[Int]) -> String {
  cmd_indent(ids)
  take_snapshot()
}

///|
pub fn outdent_nodes(ids : Array[Int]) -> String {
  cmd_outdent(ids)
  take_snapshot()
}

///|
pub fn move_nodes(ids : Array[Int], target : Int, pos : Int) -> String {
  cmd_move(ids, target, pos)
  take_snapshot()
}

///|
/// A -> B の線への割り込み。ids を B の直前へ動かしてから B を 1 段下げる。
pub fn move_as_parent(ids : Array[Int], target : Int) -> String {
  cmd_move_as_parent(ids, target)
  take_snapshot()
}

///|
pub fn reorder_node(id : Int, dir : Int) -> String {
  cmd_reorder(id, dir)
  take_snapshot()
}

///|
pub fn toggle_hidden(id : Int) -> String {
  cmd_toggle_hidden(id)
  take_snapshot()
}

///|
pub fn undo() -> String {
  do_undo()
  take_snapshot()
}

///|
pub fn redo() -> String {
  do_redo()
  take_snapshot()
}

///|
pub fn selection_text(ids : Array[Int]) -> String {
  subtree_text(ids)
}

///|
/// 貼り付けようとしている断片に見出しがあるか（フェンスの中は数えない）。
/// いまの文書には触らない。
pub fn has_headings(text : String) -> Bool {
  has_any_heading(text)
}

///|
/// 断片のいちばん浅い見出しが `target_depth` になるようずらす。
/// いまの文書には触らない。
pub fn relevel_text(text : String, target_depth : Int) -> String {
  relevel(text, target_depth)
}

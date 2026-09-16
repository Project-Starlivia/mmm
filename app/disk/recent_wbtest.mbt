// 札の台帳を、手元の表を置き場にして固定する。札は `{ id, name }` の object で代用し、
// 同じ実体かは id で決める（実物の `isSameEntry` の代わり）。

///|
/// 手元の置き場。読み書きした鍵を覚える
struct Memo {
  table : Map[String, @core.Any]
  log : Array[String]
}

///|
fn handle(id : Int, name : String, dir : Bool) -> @core.Any {
  let o = @core.new_object()
  o._set("id", @core.any(id))
  o._set("name", @core.any(name))
  o._set("dir", @core.any(dir))
  o
}

///|
fn is_handle(v : @core.Any, dir : Bool) -> Bool {
  @core.is_object(v) &&
  !@core.is_nullish(v._get("dir")) &&
  (v._get("dir").cast() : Bool) == dir
}

///|
fn memo_store(m : Memo) -> Store {
  {
    write: fn(key, value) {
      m.log.push("write " + key)
      m.table[key] = value
      true
    },
    remove: fn(key) {
      m.log.push("remove " + key)
      m.table.remove(key)
    },
    all: fn() {
      m.log.push("all")
      m.table.values().collect()
    },
    same: fn(a, b) { (a._get("id").cast() : Int) == b._get("id").cast() },
    is_file: v => is_handle(v, false),
    is_dir: v => is_handle(v, true),
  }
}

///|
fn file(id : Int, name : String) -> @web.FileHandle {
  handle(id, name, false).cast()
}

///|
fn dir(id : Int) -> @web.DirHandle {
  handle(id, "pics", true).cast()
}

///|
fn names(rows : Array[Known]) -> Array[String] {
  rows.map(r => r.doc.name())
}

///|
async test "opened: 行が無ければ作り、あれば前へ。画像フォルダは保つ" {
  let m : Memo = { table: Map([]), log: [], }
  let h = Recent::new(memo_store(m))
  assert_eq(h.rows().length(), 0)
  h.opened(file(1, "a.md"))
  h.opened(file(2, "b.md"))
  assert_eq(names(h.rows()), ["b.md", "a.md"])
  h.remember_folder(file(1, "a.md"), dir(9))
  assert_eq(names(h.rows()), ["a.md", "b.md"])
  assert_true(h.folder_for(file(1, "a.md")) is Some(_))
  assert_true(h.folder_for(file(2, "b.md")) is None)
  // 開き直しても結び付きは残る
  h.opened(file(2, "b.md"))
  h.opened(file(1, "a.md"))
  assert_true(h.folder_for(file(1, "a.md")) is Some(_))
  h.forget_folder(file(1, "a.md"))
  assert_true(h.folder_for(file(1, "a.md")) is None)
  assert_eq(names(h.rows()), ["a.md", "b.md"])
}

///|
async test "あふれたら古いものから捨てる（20 行）" {
  let m : Memo = { table: Map([]), log: [], }
  let h = Recent::new(memo_store(m))
  for i in 0..<25 {
    h.opened(file(i, "f\{i}.md"))
  }
  let rows = h.rows()
  assert_eq(rows.length(), 20)
  assert_eq(rows[0].doc.name(), "f24.md")
  assert_eq(rows[19].doc.name(), "f5.md")
}

///|
/// 棚に在る鍵
fn row_keys(m : Memo) -> Array[String] {
  m.table.keys().collect()
}

///|
/// **鍵は行の id そのもの。** 頭は付かない（未保存の字の棚と同じ形）
async test "鍵は行の id。読むのは棚ぜんぶで、鍵で引かない" {
  let m : Memo = { table: Map([]), log: [], }
  let h = Recent::new(memo_store(m))
  h.opened(file(1, "a.md"))
  let rows = h.rows()
  assert_eq(row_keys(m), [rows[0].id])
  assert_eq(m.log.filter(l => l.has_prefix("write ")), ["write " + rows[0].id])
}

///|
/// **1 回の操作で書く鍵は 1 つ。** これが #300 の答え — 一覧を丸ごと 1 つの鍵に
/// 入れていたころは、どの操作も一覧ぜんぶを書き戻していたので、タブが 2 つあると
/// 後の書きが相手の行ごと消した
async test "行ごとに鍵。文書が違えば書く鍵も違う" {
  let m : Memo = { table: Map([]), log: [], }
  let h = Recent::new(memo_store(m))
  m.log.clear()
  h.opened(file(1, "a.md"))
  h.opened(file(2, "b.md"))
  h.remember_folder(file(3, "c.md"), dir(9))
  // **3 つの操作が 3 つの違う鍵へ書く。** 一覧を丸ごと入れていたころは
  // どれも同じ 1 つの鍵（`docs`）だったので、後の書きが前の行ごと消した
  let writes = m.log.filter(l => l.has_prefix("write "))
  assert_eq(writes.length(), 3)
  assert_eq(Set::from_array(writes).length(), 3)
  assert_eq(row_keys(m).length(), 3)
  // 同じ文書をもう一度触っても、鍵は増えず、書くのはその 1 つだけ
  m.log.clear()
  h.opened(file(1, "a.md"))
  let again = m.log.filter(l => l.has_prefix("write "))
  assert_eq(again, [writes[0]])
  assert_eq(row_keys(m).length(), 3)
  assert_eq(names(h.rows()), ["a.md", "c.md", "b.md"])
}

///|
async test "壊れた行は落とす（型は名乗らせず確かめる）" {
  let m : Memo = { table: Map([]), log: [], }
  let bad = @core.new_object()
  bad._set("id", @core.any("bad"))
  bad._set("doc", @core.any("not a handle"))
  m.table["bad"] = bad
  // 鍵は在るが中身が行の形をしていない（前の版の残り・書き損じ）
  m.table["junk"] = @core.any(42)
  let good = @core.new_object()
  good._set("id", @core.any("good"))
  good._set("doc", handle(1, "ok.md", false))
  good._set("directory", @core.null())
  good._set("seen", @core.any(1.0))
  m.table["good"] = good
  let h = Recent::new(memo_store(m))
  let rows = h.rows()
  assert_eq(names(rows), ["ok.md"])
  assert_true(rows[0].directory is None)
}

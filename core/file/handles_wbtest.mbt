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
    read: fn(key) {
      m.log.push("read " + key)
      m.table.get(key).unwrap_or(@core.null())
    },
    write: fn(key, value) {
      m.log.push("write " + key)
      m.table[key] = value
    },
    remove: fn(key) {
      m.log.push("remove " + key)
      m.table.remove(key)
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
  let h = Handles::new(memo_store(m))
  assert_eq(h.list().length(), 0)
  h.opened(file(1, "a.md"))
  h.opened(file(2, "b.md"))
  assert_eq(names(h.list()), ["b.md", "a.md"])
  h.remember_folder(file(1, "a.md"), dir(9))
  assert_eq(names(h.list()), ["a.md", "b.md"])
  assert_true(h.folder_for(file(1, "a.md")) is Some(_))
  assert_true(h.folder_for(file(2, "b.md")) is None)
  // 開き直しても結び付きは残る
  h.opened(file(2, "b.md"))
  h.opened(file(1, "a.md"))
  assert_true(h.folder_for(file(1, "a.md")) is Some(_))
  h.forget_folder(file(1, "a.md"))
  assert_true(h.folder_for(file(1, "a.md")) is None)
  assert_eq(names(h.list()), ["a.md", "b.md"])
}

///|
async test "あふれたら古いものから捨てる（20 行）" {
  let m : Memo = { table: Map([]), log: [], }
  let h = Handles::new(memo_store(m))
  for i in 0..<25 {
    h.opened(file(i, "f\{i}.md"))
  }
  let rows = h.list()
  assert_eq(rows.length(), 20)
  assert_eq(rows[0].doc.name(), "f24.md")
  assert_eq(rows[19].doc.name(), "f5.md")
}

///|
async test "前の版の鍵（file / assets）を 1 行に読み替え、古い鍵は捨てる。読み替えは 1 度だけ" {
  let m : Memo = { table: Map([]), log: [], }
  m.table["file"] = handle(3, "old.md", false)
  let old = @core.new_object()
  old._set("directory", handle(7, "pics", true))
  m.table["assets"] = old
  let h = Handles::new(memo_store(m))
  let rows = h.list()
  assert_eq(names(rows), ["old.md"])
  assert_true(rows[0].directory is Some(_))
  assert_false(m.table.contains("file"))
  assert_false(m.table.contains("assets"))
  assert_true(m.table.contains("docs"))
  // 2 度目は docs から
  m.log.clear()
  h.list() |> ignore
  assert_eq(m.log, ["read docs"])
}

///|
async test "壊れた行は落とす（型は名乗らせず確かめる）。読めない置き場は空" {
  let m : Memo = { table: Map([]), log: [], }
  let bad = @core.new_object()
  bad._set("doc", @core.any("not a handle"))
  let good = @core.new_object()
  good._set("doc", handle(1, "ok.md", false))
  good._set("directory", @core.null())
  good._set("seen", @core.any(1.0))
  m.table["docs"] = @core.any([bad, good, @core.any(42)])
  let h = Handles::new(memo_store(m))
  let rows = h.list()
  assert_eq(names(rows), ["ok.md"])
  assert_true(rows[0].directory is None)
}

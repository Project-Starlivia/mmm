// 控えを、手元の棚を置き場にして固定する。時計は渡すので、版の切れ目を
// そのまま測れる。

///|
/// 手元の棚
fn shelf(table : Map[String, @core.Any]) -> Store {
  {
    read: fn(key) { table.get(key).unwrap_or(@core.null()) },
    write: fn(key, value) { table[key] = value },
    remove: fn(key) { table.remove(key) },
    all: fn() { table.values().collect() },
    same: fn(_, _) { false },
    is_file: v => @core.is_object(v) && !@core.is_nullish(v._get("name")),
    is_dir: _ => false,
  }
}

///|
fn drafts() -> Drafts {
  Drafts::new(shelf(Map([])))
}

///|
fn texts(rows : Array[Draft]) -> Array[String] {
  rows.map(d => d.text)
}

///|
/// **同じ版を上書きし、`span` を越えたら次の版へ。** 物差しは時間 1 つで、
/// 字数は見ない（打って消せば元へ戻るので、差では「大きく変えた」を言えない）
async test "控え: 同じ版を上書きし、5 分を越えたら次の版" {
  let d = drafts()
  let t = 1_000_000_000.0
  d.keep(t, "a.md", "one", None)
  d.keep(t + 1000.0, "a.md", "one two", None)
  // まだ 1 件。上書きされている
  assert_eq(texts(d.list()), ["one two"])
  // 5 分を越えたら次の版。前の版は残る
  d.keep(t + span, "a.md", "three", None)
  assert_eq(texts(d.list()), ["three", "one two"])
  // 次の 5 分までは、また上書き
  d.keep(t + span + 1000.0, "a.md", "four", None)
  assert_eq(texts(d.list()), ["four", "one two"])
}

///|
/// **流れは 1 つの編集の流れ。** 文書を入れ替えたら切れる（`load_text` を通る道が全部）
async test "控え: 流れを切ると、前の流れは残ったまま別の系列になる" {
  let d = drafts()
  let t = 1_000_000_000.0
  d.keep(t, "a.md", "first doc", None)
  d.start()
  d.keep(t + 1000.0, "b.md", "second doc", None)
  assert_eq(texts(d.list()), ["second doc", "first doc"])
  // 切った直後は、まだ何も控えていない
  d.start()
  assert_eq(d.kept(), "")
}

///|
/// 最後に控えた字。**同じ字を二度書かないための照合**で、真実ではない
async test "控え: 控えた字を覚えていて、呼ぶ側が変わったかを言える" {
  let d = drafts()
  assert_eq(d.kept(), "")
  d.keep(1.0, "a.md", "hello", None)
  assert_eq(d.kept(), "hello")
}

///|
/// **1 つの流れに持つ版は 3 つ**（時間で切るので、直近 15 分ぶん遡れる）
async test "控え: 版があふれたら、その流れの古い版から捨てる" {
  let d = drafts()
  let t = 1_000_000_000.0
  for i in 0..<5 {
    d.keep(t + i.to_double() * span, "a.md", "v" + i.to_string(), None)
  }
  assert_eq(texts(d.list()), ["v4", "v3", "v2"])
}

///|
/// **流れがあふれたら、古い流れを丸ごと捨てる**
async test "控え: 流れがあふれたら、古い流れから丸ごと捨てる" {
  let d = drafts()
  let t = 1_000_000_000.0
  for i in 0..<(keep_flows + 3) {
    d.start()
    d.keep(t + i.to_double() * 1000.0, "f.md", "flow" + i.to_string(), None)
  }
  let rows = d.list()
  assert_eq(rows.length(), keep_flows)
  assert_eq(rows[0].text, "flow22")
  assert_eq(rows[keep_flows - 1].text, "flow3")
}

///|
/// **並びは、新しい流れが先・流れの中は新しい版が先**
async test "控え: 新しい流れが先、流れの中は新しい版が先" {
  let d = drafts()
  let t = 1_000_000_000.0
  d.keep(t, "a.md", "a0", None)
  d.keep(t + span, "a.md", "a1", None)
  d.start()
  d.keep(t + span * 2.0, "b.md", "b0", None)
  assert_eq(texts(d.list()), ["b0", "a1", "a0"])
}

///|
/// **人が全部忘れる道は 1 つ。** 1 件ごとの × は置かない
async test "控え: 全部忘れる" {
  let d = drafts()
  d.keep(1.0, "a.md", "one", None)
  d.start()
  d.keep(2.0, "b.md", "two", None)
  assert_eq(d.list().length(), 2)
  d.forget_all()
  assert_eq(d.list().length(), 0)
  assert_eq(d.kept(), "")
}

///|
/// 控えは**その文書のファイルも覚える** — 控えから開いたとき Save の行き先が要る
async test "控え: ファイルの札も一緒に持つ。まだ保存していなければ持たない" {
  let d = drafts()
  let held : @web.FileHandle = handle_named("notes.md")
  d.keep(1.0, "notes.md", "saved one", Some(held))
  assert_true(d.list()[0].doc is Some(_))
  d.start()
  d.keep(2.0, "Untitled.md", "new one", None)
  assert_true(d.list()[0].doc is None)
}

///|
extern "js" fn handle_named(name : String) -> @web.FileHandle =
  #| (name) => ({ name })

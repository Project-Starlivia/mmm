// 未保存の字の台帳を、手元の棚を置き場にして固定する。時計は渡すので、並びの
// 新しさをそのまま測れる。

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
fn unsaved() -> Unsaved {
  Unsaved::new(shelf(Map([])))
}

///|
fn texts(rows : Array[UnsavedDoc]) -> Array[String] {
  rows.map(d => d.text)
}

///|
/// **1 文書 1 件。** 書くたびに同じ件を上書きする — 版は持たない（docs/unsaved.md）
async test "未保存の字: 1 文書 1 件を上書きする" {
  let u = unsaved()
  u.keep(1.0, "a.md", "one", None)
  u.keep(2.0, "a.md", "one two", None)
  assert_eq(texts(u.list()), ["one two"])
}

///|
/// 書いた字を覚える。**同じ字を二度書かないための照合**で、真実ではない
async test "未保存の字: 書いた字を覚え、始め直せば忘れる" {
  let u = unsaved()
  assert_eq(u.written(), None)
  u.keep(1.0, "a.md", "hello", None)
  assert_eq(u.written(), Some("hello"))
  u.start()
  assert_eq(u.written(), None)
}

///|
/// **文書を入れ替えたら別の件。** 前の文書の件は残る（捨てるのは呼ぶ側が決める）
async test "未保存の字: 始め直すと別の件になり、新しいものが先に並ぶ" {
  let u = unsaved()
  u.keep(1.0, "a.md", "first", None)
  u.start()
  u.keep(2.0, "b.md", "second", None)
  assert_eq(texts(u.list()), ["second", "first"])
}

///|
/// **捨てるのはいまの件だけ。** ほかの文書の件には触らない
async test "未保存の字: いまの件だけを捨てる" {
  let u = unsaved()
  u.keep(1.0, "a.md", "first", None)
  u.start()
  u.keep(2.0, "b.md", "second", None)
  u.discard()
  assert_eq(texts(u.list()), ["first"])
  assert_eq(u.written(), None)
}

///|
/// **引き継いだ件はそのまま上書きする。** 開き直すたびに同じ字の件を増やさない
async test "未保存の字: 引き受けると、その件に書き、書いた字も引き受ける" {
  let u = unsaved()
  u.keep(1.0, "a.md", "kept", None)
  let was = u.list()[0]
  u.start()
  u.adopt(was)
  assert_eq(u.written(), Some("kept"))
  u.keep(2.0, "a.md", "kept more", None)
  assert_eq(texts(u.list()), ["kept more"])
}

///|
/// **いま開いている文書の件は並べない** — 押しても同じ字がもう 1 つ開くだけ
async test "未保存の字: いまの件のほかを並べる" {
  let u = unsaved()
  u.keep(1.0, "a.md", "first", None)
  u.start()
  u.keep(2.0, "b.md", "second", None)
  assert_eq(texts(u.others()), ["first"])
}

///|
/// **あふれたら古いものから捨てる。** 物差しは件数 — 日数で消すと、落ちた直後に
/// 見たいものが期限で消える
async test "未保存の字: 件数があふれたら古いものから捨てる" {
  let u = unsaved()
  for i in 0..<(keep_docs + 3) {
    u.start()
    u.keep(i.to_double(), "f.md", "doc" + i.to_string(), None)
  }
  let rows = u.list()
  assert_eq(rows.length(), keep_docs)
  assert_eq(rows[0].text, "doc22")
  assert_eq(rows[keep_docs - 1].text, "doc3")
}

///|
/// **人が全部捨てる道は 1 つ。** 1 件ごとの × は置かない
async test "未保存の字: 全部捨てる" {
  let u = unsaved()
  u.keep(1.0, "a.md", "one", None)
  u.start()
  u.keep(2.0, "b.md", "two", None)
  u.discard_all()
  assert_eq(u.list().length(), 0)
  assert_eq(u.written(), None)
}

///|
/// その文書のファイルも覚える — 開き直したとき Save の行き先が要る
async test "未保存の字: ファイルの札も一緒に持つ。まだ保存していなければ持たない" {
  let u = unsaved()
  let held : @web.FileHandle = handle_named("notes.md")
  u.keep(1.0, "notes.md", "saved one", Some(held))
  assert_true(u.list()[0].doc is Some(_))
  u.start()
  u.keep(2.0, "Untitled.md", "new one", None)
  assert_true(u.list()[0].doc is None)
}

///|
extern "js" fn handle_named(name : String) -> @web.FileHandle =
  #| (name) => ({ name })

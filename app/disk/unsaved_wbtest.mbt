// 未保存の字の台帳を、手元の棚を置き場にして固定する。時計は渡すので、並びの
// 新しさをそのまま測れる。**台帳 1 つが 1 つのセッション**（タブ）で、棚を分け合えば、
// 落ちる前のセッションが残した件を持って立てる。

///|
/// 手元の棚。`broken` なら書けない（private mode・容量あふれ・壊れた置き場の代わり）。
/// `gate` を渡せば、書き込みはそれが解けるまで終わらない（書いている途中を作る）
fn shelf(
  table : Map[String, @core.Any],
  broken? : Bool = false,
  gate? : @js_async.Promise[@core.Any]? = None,
) -> Store {
  {
    read: fn(key) { table.get(key).unwrap_or(@core.null()) },
    write: async fn(key, value) {
      guard !broken else { return false }
      match gate {
        Some(g) => g.wait() |> ignore
        None => ()
      }
      table[key] = value
      true
    },
    remove: fn(key) { table.remove(key) },
    all: fn() { table.values().collect() },
    same: fn(_, _) { false },
    is_file: v => @core.is_object(v) && !@core.is_nullish(v._get("name")),
    is_dir: _ => false,
  }
}

///|
/// 棚を分け合う 1 つのセッション
fn session(table : Map[String, @core.Any]) -> Unsaved {
  Unsaved::new(shelf(table))
}

///|
fn unsaved() -> Unsaved {
  session(Map([]))
}

///|
fn texts(rows : Array[UnsavedDoc]) -> Array[String] {
  rows.map(d => d.text)
}

///|
/// **1 文書 1 件。** 書くたびに同じ件を上書きする — 版は持たない（docs/unsaved.md）
async test "未保存の字: 1 文書 1 件を上書きする" {
  let u = unsaved()
  assert_true(u.keep(1.0, "a.md", "one", None))
  assert_true(u.keep(2.0, "a.md", "one two", None))
  assert_eq(texts(u.list()), ["one two"])
}

///|
/// **書けなければそう返し、書いた字も覚えない** — 覚えると、同じ字は二度書かない照合に
/// 引っかかって、置き場が戻っても書き直さない
async test "未保存の字: 書けなければ偽を返し、書いた字を覚えない" {
  let u = Unsaved::new(shelf(Map([]), broken=true))
  assert_false(u.keep(1.0, "a.md", "one", None))
  assert_eq(u.written(), None)
  assert_eq(u.list().length(), 0)
}

///|
/// 書いた字を覚える。**同じ字を二度書かないための照合**で、真実ではない
async test "未保存の字: 書いた字を覚え、捨てれば件ごと忘れる" {
  let u = unsaved()
  assert_eq(u.written(), None)
  assert_true(u.keep(1.0, "a.md", "hello", None))
  assert_eq(u.written(), Some("hello"))
  u.discard()
  assert_eq(u.written(), None)
  assert_eq(u.list().length(), 0)
}

///|
/// **書いている途中で捨てれば、書き終えた件も残らない。** 保存（ディスクと同じ字になった）が
/// 最初の書き込みと重なると、捨てた後に書き込みが着いて件が蘇る
async test "未保存の字: 書いている途中で捨てれば、書き終えた件も残らない" {
  let table : Map[String, @core.Any] = Map([])
  let release : Ref[(@core.Any) -> Unit] = { val: _ => (), }
  let gate = @web.promise_of(k => release.val = k)
  let u = Unsaved::new(shelf(table, gate=Some(gate)))
  let writing = @js_async.Promise::from_async(async fn() {
    u.keep(1.0, "a.md", "one", None)
  })
  u.discard()
  (release.val)(@core.any(0))
  assert_true(writing.wait())
  assert_eq(u.list().length(), 0)
  assert_eq(u.written(), None)
}

///|
/// **ほかのセッションの件は残る。** 並びは新しいものが先
async test "未保存の字: ほかのセッションの件は残り、新しいものが先に並ぶ" {
  let table : Map[String, @core.Any] = Map([])
  assert_true(session(table).keep(1.0, "a.md", "first", None))
  let u = session(table)
  assert_true(u.keep(2.0, "b.md", "second", None))
  assert_eq(texts(u.list()), ["second", "first"])
}

///|
/// **捨てるのはいまの件だけ。** ほかの文書の件には触らない
async test "未保存の字: いまの件だけを捨てる" {
  let table : Map[String, @core.Any] = Map([])
  assert_true(session(table).keep(1.0, "a.md", "first", None))
  let u = session(table)
  assert_true(u.keep(2.0, "b.md", "second", None))
  u.discard()
  assert_eq(texts(u.list()), ["first"])
  assert_eq(u.written(), None)
}

///|
/// **引き受けた件はそのまま上書きする。** 開き直すたびに同じ字の件を増やさない
async test "未保存の字: 引き受けると、その件に書き、書いた字も引き受ける" {
  let table : Map[String, @core.Any] = Map([])
  assert_true(session(table).keep(1.0, "a.md", "kept", None))
  let u = session(table)
  u.adopt(u.list()[0])
  assert_eq(u.written(), Some("kept"))
  assert_true(u.keep(2.0, "a.md", "kept more", None))
  assert_eq(texts(u.list()), ["kept more"])
}

///|
/// **いま開いている文書の件は並べない** — 押しても同じ字がもう 1 つ開くだけ
async test "未保存の字: いまの件のほかを並べる" {
  let table : Map[String, @core.Any] = Map([])
  assert_true(session(table).keep(1.0, "a.md", "first", None))
  let u = session(table)
  assert_true(u.keep(2.0, "b.md", "second", None))
  assert_eq(texts(u.others()), ["first"])
}

///|
/// **あふれたら古いものから捨てる。** 物差しは件数 — 日数で消すと、落ちた直後に
/// 見たいものが期限で消える
async test "未保存の字: 件数があふれたら古いものから捨てる" {
  let table : Map[String, @core.Any] = Map([])
  for i in 0..<(keep_docs + 3) {
    assert_true(
      session(table).keep(i.to_double(), "f.md", "doc" + i.to_string(), None),
    )
  }
  let rows = unsaved_in(table)
  assert_eq(rows.length(), keep_docs)
  assert_eq(rows[0].text, "doc22")
  assert_eq(rows[keep_docs - 1].text, "doc3")
}

///|
/// その棚に残っている件（新しいものが先）
async fn unsaved_in(table : Map[String, @core.Any]) -> Array[UnsavedDoc] {
  session(table).list()
}

///|
/// **巨大な 1 件は書かない。** 書いた直後に柵で捨てるのに「書けた」と言うと、
/// 人は残っていると思ったまま打ち続ける
async test "未保存の字: 柵より大きい字は書かず、偽を返す" {
  let u = unsaved()
  assert_false(u.keep(1.0, "big.md", "a".repeat(keep_chars + 1), None))
  assert_eq(u.list().length(), 0)
  assert_eq(u.written(), None)
}

///|
/// **人が捨てるのは並んでいるものだけ。** いま開いている文書の件は並んでいないので、
/// 残す — 汚れたまま画面に居るのに、落ちたら戻せなくなる
async test "未保存の字: ほかの件だけを捨て、いまの件は残す" {
  let table : Map[String, @core.Any] = Map([])
  assert_true(session(table).keep(1.0, "a.md", "one", None))
  let u = session(table)
  assert_true(u.keep(2.0, "b.md", "two", None))
  u.discard_others()
  assert_eq(texts(u.list()), ["two"])
  assert_eq(u.written(), Some("two"))
}

///|
/// **ディスクの基準の時刻も一緒に持つ。** 開き直したとき、保存時の上書きの確かめを
/// この時刻からにする（開いた時刻からにすると、その間にほかで保存された版を見落とす）
async test "未保存の字: ディスクの基準の時刻も一緒に持ち、渡さなければ持たない" {
  let u = unsaved()
  assert_true(u.keep(1.0, "a.md", "one", None, stamp=Some(5.0)))
  assert_eq(u.list()[0].stamp, Some(5.0))
  assert_true(u.keep(2.0, "a.md", "two", None))
  assert_eq(u.list()[0].stamp, None)
}

///|
/// その文書のファイルも覚える — 開き直したとき Save の行き先が要る
async test "未保存の字: ファイルの札も一緒に持つ。まだ保存していなければ持たない" {
  let table : Map[String, @core.Any] = Map([])
  let held : @web.FileHandle = handle_named("notes.md")
  assert_true(session(table).keep(1.0, "notes.md", "saved one", Some(held)))
  assert_true(session(table).list()[0].doc is Some(_))
  assert_true(session(table).keep(2.0, "Untitled.md", "new one", None))
  assert_true(session(table).list()[0].doc is None)
}

///|
extern "js" fn handle_named(name : String) -> @web.FileHandle =
  #| (name) => ({ name })

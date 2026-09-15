// ブラウザの中に置く、ディスクに届いていない字。**ディスクの .md が正で、ここは
// 落ちて失わないための退避だけ** — 前の版に戻る履歴は持たない（docs/unsaved.md）。
//
// 未保存の字は正を名乗らない — 開くのは常に人で、勝手には開き直さず、書き戻さない。
// 開き直した文書は印が立ったまま出るので、どちらが正かを人が読める。
//
// **1 文書 1 件。** 文書を入れ替えるたびに件を捨てて鍵を振り直し、同じ文書のあいだは
// その件を上書きする。捨てるかどうか（ディスクと同じ字になった・入れ替えた）は呼ぶ側が
// 決める。一覧を丸ごと 1 つの鍵に入れると読みと書きが食い合う（#300 と同じ形）ので、
// 1 件が 1 レコード。

///|
/// 未保存の文書 1 つ
pub(all) struct UnsavedDoc {
  /// この件の鍵。文書を入れ替えるたびに振る
  id : String
  /// 見出しに出す名前
  name : String
  /// 最後に書いた時刻
  at : Double
  /// 本文。**生で置く** — gzip は非同期の段と失敗の口を 1 つ増やすわりに、
  /// 上限（件数）が先に当たるので効かない
  text : String
  /// その文書のファイル。開き直したとき Save の行き先が要る。
  /// まだ保存していない文書では None
  doc : @web.FileHandle?
}

///|
/// 覚えておく件数。**あふれたら古いものから捨てる** — 物差しは件数で、日数では
/// 消さない（落ちた直後に見たいものが期限で消えるのは、約束として弱い）
let keep_docs : Int = 20

///|
/// 全部で持てる字の数。**巨大な文書 1 つが棚を食い尽くすのだけを止める柵**
let keep_chars : Int = 20 * 1024 * 1024

///|
/// 未保存の字の台帳
pub struct Unsaved {
  store : Store
  /// いま開いている文書の件
  mut id : String
  /// その件に最後に書いた字。まだ書いていなければ None。
  /// 同じ字を二度書かないための照合で、真実ではない
  mut written : String?
  /// 書いている途中の数。**書き終える前に捨てられることがある** — 保存が最初の書き込みと
  /// 重なると、捨てた後に書き込みが着く
  mut writing : Int
}

///|
pub fn Unsaved::new(store : Store) -> Unsaved {
  { store, id: @web.unique_id(), written: None, writing: 0, }
}

///|
/// 開き直した件を引き受ける。**同じ字の件を増やさない** — 以後の書き込みはその件へ
/// （`Disk::adopt` が札を引き受けるのと同じ語）
pub fn Unsaved::adopt(self : Unsaved, doc : UnsavedDoc) -> Unit {
  self.id = doc.id
  self.written = Some(doc.text)
}

///|
/// いまの件に最後に書いた字。呼ぶ側はこれと本文を比べて、変わっていれば書くよう頼む
pub fn Unsaved::written(self : Unsaved) -> String? {
  self.written
}

///|
/// いまの件が在るか、書いている途中か。**捨てる相手が居るか**を呼ぶ側が問う口
pub fn Unsaved::held(self : Unsaved) -> Bool {
  self.written is Some(_) || self.writing > 0
}

///|
/// いまの件に書く（上書き）。**書けたかを返す。** 書けなければ書いた字も覚えない —
/// 覚えると同じ字は二度書かない照合に引っかかり、置き場が戻っても書き直さない
pub async fn Unsaved::keep(
  self : Unsaved,
  now : Double,
  name : String,
  text : String,
  doc : @web.FileHandle?,
) -> Bool {
  // **柵より大きい 1 件は書かない。** 書いた直後に柵で捨てるのに「書けた」と言うと、
  // 人は残っていると思ったまま打ち続ける
  guard text.length() <= keep_chars else { return false }
  let id = self.id
  self.writing = self.writing + 1
  let ok = (self.store.write)(
    id,
    unsaved_doc_of({ id, name, at: now, text, doc, }),
  )
  self.writing = self.writing - 1
  guard ok else { return false }
  // 書いているあいだに捨てられた（入れ替えた・ディスクと同じ字になった）なら、
  // 書いた件は役目を終えている — 着いた件をそのまま捨てる
  if self.id != id {
    (self.store.remove)(id)
    return true
  }
  self.written = Some(text)
  self.trim()
  true
}

///|
/// いまの件を捨て、鍵を振り直す。**鍵は待つ前に替える** — 書いている途中の書き込みは
/// 着いたときに鍵が違うと気づいて自分を捨てる（`keep`）。待っているあいだに文書が
/// 入れ替わっても、捨てるのは入れ替わる前の件
pub async fn Unsaved::discard(self : Unsaved) -> Unit {
  let id = self.id
  let held = self.held()
  self.id = @web.unique_id()
  self.written = None
  if held {
    (self.store.remove)(id)
  }
}

///|
/// 覚えている未保存の文書。**新しいものが先**
pub async fn Unsaved::list(self : Unsaved) -> Array[UnsavedDoc] {
  let all = (self.store.all)().filter_map(v => self.unsaved_doc_at(v))
  all.sort_by((a, b) => {
    if b.at > a.at {
      1
    } else if b.at < a.at {
      -1
    } else {
      0
    }
  })
  all
}

///|
/// いまの件のほか。**いま開いている文書は並べない** — 押しても同じ字がもう 1 つ開くだけ
pub async fn Unsaved::others(self : Unsaved) -> Array[UnsavedDoc] {
  self.list().filter(d => d.id != self.id)
}

///|
/// 人が捨てる。**捨てるのは並んでいるもの（ほかの件）だけ** — いまの文書の件は並んで
/// いないので残す。汚れたまま画面に居るのに、落ちたら戻せなくなる。
/// 1 件ごとの × は置かない — Recent の行が持たないので、同じ器の中に 2 通りの行ができる
pub async fn Unsaved::discard_others(self : Unsaved) -> Unit {
  for d in self.others() {
    (self.store.remove)(d.id)
  }
}

///|
/// あふれたぶんを捨てる。新しいものから数えて、件数か字数を超えたものを。
/// **いまの件は捨てない** — 書けたと答えた直後に消すことになる
async fn Unsaved::trim(self : Unsaved) -> Unit {
  let mut chars = 0
  for i, d in self.list() {
    chars = chars + d.text.length()
    if d.id != self.id && (i >= keep_docs || chars > keep_chars) {
      (self.store.remove)(d.id)
    }
  }
}

///|
/// 置き場に入れる形
fn unsaved_doc_of(d : UnsavedDoc) -> @core.Any {
  @web.record([
    ("id", @core.any(d.id)),
    ("name", @core.any(d.name)),
    ("at", @core.any(d.at)),
    ("text", @core.any(d.text)),
    ("doc", @core.from_option(d.doc)),
  ])
}

///|
/// 覚えていたものが、いまも期待の形をしているか（型は名乗らせず確かめる）
fn Unsaved::unsaved_doc_at(self : Unsaved, v : @core.Any) -> UnsavedDoc? {
  guard @core.is_object(v) else { return None }
  let id = @web.field(v, "id")
  let name = @web.field(v, "name")
  let at = @web.field(v, "at")
  let text = @web.field(v, "text")
  guard @core.typeof_(id) == "string" &&
    @core.typeof_(name) == "string" &&
    @core.typeof_(at) == "number" &&
    @core.typeof_(text) == "string" else {
    return None
  }
  let held = @web.field(v, "doc")
  let doc = if @core.is_nullish(held) {
    None
  } else if (self.store.is_file)(held) {
    Some((held.cast() : @web.FileHandle))
  } else {
    None
  }
  Some({
    id: id.cast(),
    name: name.cast(),
    at: at.cast(),
    text: text.cast(),
    doc,
  })
}

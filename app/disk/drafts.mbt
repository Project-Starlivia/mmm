// ブラウザの中に置く本文の控え。**ディスクの .md が正で、ここはまだそこへ届いて
// いない字と、届く前に通った字を覚えているだけ**
// （docs/superpowers/specs/2026-09-12-drafts-design.md）。
//
// 控えは正を名乗らない — 開くのは常に人で、勝手には開き直さず、書き戻さない。
// 控えから開いた文書は印が立ったまま出るので、どちらが正かを人が読める。
//
// **1 件が 1 レコード**（鍵は `<flow>/<seq>`）。一覧を丸ごと 1 つの鍵に入れると
// 読みと書きが食い合う（#300 と同じ形）。
//
// **系列（flow）は 1 つの編集の流れ。** 新規・開く・Discard・共有リンクで振り直す
// （`load_text` を通る道が全部それ）。同じ流れの中では、時間で版（seq）を切る。

///|
/// 控え 1 つ
pub(all) struct Draft {
  /// 1 つの編集の流れ
  flow : String
  /// 流れの中の版。0 から増える
  seq : Int
  /// 見出しに出す名前
  name : String
  /// 最後に書いた時刻
  at : Double
  /// 本文。**生で置く** — gzip は非同期の段と失敗の口を 1 つ増やすわりに、
  /// 上限（件数）が先に当たるので効かない
  text : String
  /// その文書のファイル。控えから開いたとき Save の行き先が要る。
  /// まだ保存していない文書では None
  doc : @web.FileHandle?
}

///|
/// 覚えておく流れの数。**あふれたら古い流れから丸ごと捨てる**
let keep_flows : Int = 20

///|
/// 1 つの流れに持つ版の数。時間で切るので、3 版 = 直近 15 分ぶん遡れる
let keep_seqs : Int = 3

///|
/// 版を切る間合い（ms）。**物差しは時間 1 つ** — 字数は打って消せば元へ戻るので、
/// 「大きく変えた」を差では言えない（大改稿ほど差が小さく出ることがある）
let span : Double = 5.0 * 60.0 * 1000.0

///|
/// 全部で持てる字の数。**巨大な文書 1 つが列を食い尽くすのだけを止める柵**
let keep_chars : Int = 20 * 1024 * 1024

///|
/// 控えの台帳
pub struct Drafts {
  store : Store
  /// いまの編集の流れ
  mut flow : String
  /// その流れで書いている版
  mut seq : Int
  /// その版が生まれた時刻。**ここから `span` 経ったら次の版へ**
  mut born : Double
  /// 最後に控えた字。同じ字を二度書かないための照合で、真実ではない
  mut kept : String
}

///|
pub fn Drafts::new(store : Store) -> Drafts {
  { store, flow: @web.unique_id(), seq: 0, born: 0.0, kept: "", }
}

///|
/// 新しい流れを始める。**文書を入れ替えたら前の流れは終わる** —
/// 続きを同じ流れに足すと、別の文書の字が 1 つの系列に混ざる
pub fn Drafts::start(self : Drafts) -> Unit {
  self.flow = @web.unique_id()
  self.seq = 0
  self.born = 0.0
  self.kept = ""
}

///|
/// 最後に控えた字。呼ぶ側はこれと本文を比べて、変わっていれば控えを頼む
pub fn Drafts::kept(self : Drafts) -> String {
  self.kept
}

///|
fn key_of(flow : String, seq : Int) -> String {
  flow + "/" + seq.to_string()
}

///|
/// 控える。**同じ版を上書きし、`span` を越えたら次の版へ。**
///
/// 版が変わる引き金は時間だけ。人の一手（新規・開く・Discard）は流れそのものを
/// 変えるので、こちらの物差しには乗らない
pub async fn Drafts::keep(
  self : Drafts,
  now : Double,
  name : String,
  text : String,
  doc : @web.FileHandle?,
) -> Unit {
  if self.born == 0.0 {
    self.born = now
  } else if now - self.born >= span {
    // **版を切るのは時間だけ。** 同じ流れの中で、直近 span ぶんが 1 版。
    // 数の上限（`keep_seqs`）は `trim` が古い版から落とす
    self.seq = self.seq + 1
    self.born = now
  }
  self.kept = text
  (self.store.write)(
    key_of(self.flow, self.seq),
    draft_of({ flow: self.flow, seq: self.seq, name, at: now, text, doc, }),
  )
  self.trim()
}

///|
/// 覚えている控え。**新しい流れが先、流れの中は新しい版が先**
pub async fn Drafts::list(self : Drafts) -> Array[Draft] {
  let all = (self.store.all)().filter_map(v => self.draft_at(v))
  by_newest(all)
}

///|
/// 人が全部忘れる。**1 件ごとの × は置かない** — Recent の行が持たないので、
/// 同じ器の中に 2 通りの行ができる
pub async fn Drafts::forget_all(self : Drafts) -> Unit {
  for d in (self.store.all)().filter_map(v => self.draft_at(v)) {
    (self.store.remove)(key_of(d.flow, d.seq))
  }
  self.kept = ""
}

///|
/// あふれたぶんを捨てる。**捨てるのは 2 つの場合だけ** — 上限に当たったときと、
/// 人が消したとき。保存しても捨てない（保存の直後こそ間違いに気づく）
async fn Drafts::trim(self : Drafts) -> Unit {
  // 新しい流れが先、流れの中は新しい版が先。**頭から数えて、超えたものを捨てる**
  let flows : Array[String] = []
  let ranks : Map[String, Int] = Map([])
  let mut chars = 0
  for d in self.list() {
    if !flows.contains(d.flow) {
      flows.push(d.flow)
    }
    let rank = ranks.get(d.flow).unwrap_or(0)
    ranks[d.flow] = rank + 1
    chars = chars + d.text.length()
    if flows.length() > keep_flows || rank >= keep_seqs || chars > keep_chars {
      (self.store.remove)(key_of(d.flow, d.seq))
    }
  }
}

///|
/// 新しい流れが先、流れの中は新しい版が先。**触れた時刻で並べる** —
/// 流れの新しさは、その流れのいちばん新しい控えの時刻
fn by_newest(rows : Array[Draft]) -> Array[Draft] {
  let newest : Map[String, Double] = Map([])
  for d in rows {
    let at = newest.get(d.flow).unwrap_or(0.0)
    if d.at > at {
      newest[d.flow] = d.at
    }
  }
  let out = rows.copy()
  out.sort_by((a, b) => {
    let fa = newest.get(a.flow).unwrap_or(0.0)
    let fb = newest.get(b.flow).unwrap_or(0.0)
    if fa != fb {
      return if fb > fa { 1 } else { -1 }
    }
    if a.flow != b.flow {
      return if a.flow < b.flow { -1 } else { 1 }
    }
    b.seq - a.seq
  })
  out
}

///|
/// 置き場に入れる形
fn draft_of(d : Draft) -> @core.Any {
  @web.record([
    ("flow", @core.any(d.flow)),
    ("seq", @core.any(d.seq.to_double())),
    ("name", @core.any(d.name)),
    ("at", @core.any(d.at)),
    ("text", @core.any(d.text)),
    ("doc", @core.from_option(d.doc)),
  ])
}

///|
/// 覚えていたものが、いまも期待の形をしているか（型は名乗らせず確かめる）
fn Drafts::draft_at(self : Drafts, v : @core.Any) -> Draft? {
  guard @core.is_object(v) else { return None }
  let flow = @web.field(v, "flow")
  let seq = @web.field(v, "seq")
  let name = @web.field(v, "name")
  let at = @web.field(v, "at")
  let text = @web.field(v, "text")
  guard @core.typeof_(flow) == "string" &&
    @core.typeof_(seq) == "number" &&
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
  let n : Double = seq.cast()
  Some({
    flow: flow.cast(),
    seq: n.to_int(),
    name: name.cast(),
    at: at.cast(),
    text: text.cast(),
    doc,
  })
}

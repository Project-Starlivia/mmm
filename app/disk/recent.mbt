// File System Access API の札を IndexedDB に置く小さな層。
// 本文は持たない。ディスク上の実体を指す札だけを覚える。
//
// **札は参照 ID でしかない。** 中身は覗けず、実際のパスはブラウザの中にしか無い。
// 触ってよいかはまた別の台帳（許可）で、指し先が消えていることもある。だからここが
// 持っているのは**番号札**で、使えるかどうかは毎回下まで確かめる — **覚えているのは
// 高速化であって、真実ではない**。札が死んでいれば、指し直しの駅（images.mbt の `choose_folder`）へ落ちる。
//
// 覚えるのは**知っている文書の一覧**だけ。1 行が 1 つの .md で、
// その文書の画像フォルダを一緒に持つ。
//
// **1 行が 1 つの鍵**（`docs/<id>`）。一覧を丸ごと 1 つの鍵に入れると、読みと書きが
// 別の取引になり、タブが 2 つあると後の書きが相手の行ごと消す。行を分けておけば、
// 触るのは自分の行だけで済む。id をこちらで振るのは、**札が鍵にできない**から
// （中が覗けず、綴りも取れない）。
//
// **「いま開いているのはこれ」は覚えない。** 起動時に勝手に開き直さないので、
// 持っていても使い道が無い — 開くのは常に人が選んだとき（Open か、この一覧）。

///|
/// 知っている文書 1 つ。**持つのは札だけ** — 「md から見てどこか」は .md の頭が
/// 宣言する（read/head.mbt）。
///
/// `seen` は最後に触れた時刻。**あふれたら古いものから捨てる** — 番号札は
/// 腐るので、際限なく貯めても当たらない札が増えるだけ
pub(all) struct Known {
  /// この行の鍵。`docs/<id>` で置く。**札は鍵にできない**ので、こちらで振る
  id : String
  doc : @web.FileHandle
  /// その文書の画像フォルダ。まだ指してもらっていなければ None
  directory : @web.DirHandle?
  seen : Double
}

///|
/// 覚えておく文書の数。**捨てる基準は「最後に触れた順」**
let keep = 20

///|
/// 行の鍵の頭。後ろに行の id が付く
let row_prefix = "docs/"

///|
/// 前の版の鍵。読み替えたら消す（`carry_over`）。
/// `file` は「いまのファイル」、`assets` は枠 1 つの画像フォルダだった。
/// `docs` は一覧を丸ごと 1 つの鍵に入れていたときの形
let legacy_docs = "docs"

///|
let legacy_file = "file"

///|
let legacy_assets = "assets"

///|
/// 置き場。実物は IndexedDB（`idb_store`）、試験は手元の表。
/// 読み書きの失敗は諦めて null に倒す — private mode でのブロックやスキーマのずれで
/// 壊れても、開く・新規・保存という本体機能を道連れにしない
pub(all) struct Store {
  read : async (String) -> @core.Any
  write : async (String, @core.Any) -> Unit
  remove : async (String) -> Unit
  /// 棚の中身を全部。**行ごとに鍵を分けたので、一覧はこれで引く**
  all : async () -> Array[@core.Any]
  /// 札どうしが同じ実体を指すか
  same : async (@core.Any, @core.Any) -> Bool
  is_file : (@core.Any) -> Bool
  is_dir : (@core.Any) -> Bool
}

///|
pub struct Recent {
  store : Store
  /// 読み替えは済んだか。**1 セッションに 1 度でいい** — 済んだ後も毎回
  /// 古い鍵を読みに行くと、`list` を呼ぶたびに無駄な往復が 4 回増える
  mut inherited : Bool
}

///|
pub fn Recent::new(store : Store) -> Recent {
  { store, inherited: false, }
}

///|
/// 覚えていたものが、いまも期待の形をしているか（型は名乗らせず確かめる）。
/// id を持たないものは前の版の行なので、読み替えの側（`carry_over`）が id を振る
fn Recent::known_of(self : Recent, v : @core.Any) -> Known? {
  let id = @web.field(v, "id")
  guard @core.is_object(v) && @core.typeof_(id) == "string" else { return None }
  self.row_at(v, id.cast())
}

///|
/// 行の中身（id 以外）を確かめる
fn Recent::row_at(self : Recent, v : @core.Any, id : String) -> Known? {
  guard @core.is_object(v) else { return None }
  let doc = @web.field(v, "doc")
  guard (self.store.is_file)(doc) else { return None }
  let dir = @web.field(v, "directory")
  let directory = if @core.is_nullish(dir) {
    None
  } else if (self.store.is_dir)(dir) {
    Some((dir.cast() : @web.DirHandle))
  } else {
    return None
  }
  let seen = @web.field(v, "seen")
  guard @core.typeof_(seen) == "number" else { return None }
  Some({ id, doc: doc.cast(), directory, seen: seen.cast(), })
}

///|
/// 前の版が残したものを、行ごとの鍵へ読み替える。**版が上がっただけで
/// 開き直しをさせない。** 読み替えたら古い鍵は捨てる。
///
/// 読み替える形は 2 つ。一覧を丸ごと入れていた `docs` と、その前の
/// `file`（いまのファイル）+ `assets`（枠 1 つの画像フォルダ）
async fn Recent::carry_over(self : Recent) -> Unit {
  guard !self.inherited else { return }
  self.inherited = true
  let bulk = (self.store.read)(legacy_docs)
  if @core.is_array(bulk) {
    for v in @core.array_from(bulk) {
      guard self.row_at(v, @web.unique_id()) is Some(row) else { continue }
      self.put(row)
    }
    (self.store.remove)(legacy_docs)
  }
  let file = (self.store.read)(legacy_file)
  if (self.store.is_file)(file) {
    let old = (self.store.read)(legacy_assets)
    let dir = if @core.is_object(old) &&
      (self.store.is_dir)(@web.field(old, "directory")) {
      Some((@web.field(old, "directory").cast() : @web.DirHandle))
    } else {
      None
    }
    self.put({
      id: @web.unique_id(),
      doc: file.cast(),
      directory: dir,
      seen: @web.now(),
    })
  }
  (self.store.remove)(legacy_file)
  (self.store.remove)(legacy_assets)
}

///|
/// 置き場に入れる形（素の object）。MoonBit の Option は JS の値ではない —
/// 無い箱は null にして置く
fn row_of(k : Known) -> @core.Any {
  @web.record([
    ("id", @core.any(k.id)),
    ("doc", k.doc.as_any()),
    ("directory", @core.from_option(k.directory)),
    ("seen", @core.any(k.seen)),
  ])
}

///|
/// 知っている文書。**最後に触れた順** — Files の並びがそのままこれ。
/// 並べるのは読むとき（書くのは自分の行 1 つだけなので、並びを書き戻す口が無い）
async fn Recent::rows(self : Recent) -> Array[Known] {
  self.carry_over()
  by_recent((self.store.all)().filter_map(x => self.known_of(x)))
}

///|
/// その文書の行を探す。**札どうしは `same` でしか比べられない** —
/// 中身が覗けないので、鍵で引くのではなく端から照合する（だから `keep` 行）
async fn Recent::find(
  self : Recent,
  rows : Array[Known],
  file : @web.FileHandle,
) -> Int {
  for i, row in rows {
    if (self.store.same)(row.doc.as_any(), file.as_any()) {
      return i
    }
  }
  -1
}

///|
/// 最後に触れた順に。同じ時刻なら先に居たほうが先（安定）— 続けて開いた 2 つの文書が
/// 同じ ms に入ることがあり、そこで順が崩れると Recent が嘘をつく
fn by_recent(rows : Array[Known]) -> Array[Known] {
  let out : Array[Known] = []
  for r in rows {
    let mut at = out.length()
    while at > 0 && out[at - 1].seen < r.seen {
      at -= 1
    }
    out.insert(at, r)
  }
  out
}

///|
/// 行を 1 つ置く。**触るのは自分の行だけ** — 隣の行は読みもしない
async fn Recent::put(self : Recent, row : Known) -> Unit {
  (self.store.write)(row_prefix + row.id, row_of(row))
}

///|
/// あふれたぶんを捨てる。**捨てるのは超えた行だけ**（残る行は書き直さない）
async fn Recent::trim(self : Recent) -> Unit {
  let rows = self.rows()
  for i in keep..<rows.length() {
    (self.store.remove)(row_prefix + rows[i].id)
  }
}

///|
/// 知っている文書の札を、`file` を除いて（いま開いているものは Files に並べない）
async fn Recent::list_besides(
  self : Recent,
  file : @web.FileHandle?,
) -> Array[@web.FileHandle] {
  let rows = self.rows()
  let skip = match file {
    Some(f) => self.find(rows, f)
    None => -1
  }
  let out = []
  for i, row in rows {
    if i != skip {
      out.push(row.doc)
    }
  }
  out
}

///|
/// 開いた / 保存した。行が無ければ作り、あれば触れた印を新しくする。
/// **画像フォルダは保つ** — 同じ文書に戻れば結び付きも戻る
async fn Recent::opened(self : Recent, file : @web.FileHandle) -> Unit {
  let rows = self.rows()
  let was = rows.get(self.find(rows, file))
  self.put({
    id: match was {
      Some(w) => w.id
      None => @web.unique_id()
    },
    doc: file,
    directory: was.bind(w => w.directory),
    seen: next_seen(rows),
  })
  self.trim()
}

///|
/// 触れた印。**必ずいちばん新しい行より大きい** — 続けて開いた 2 つが同じ ms に
/// 入ると、並びが置き場の返す順に委ねられて Recent が嘘をつく。
/// 行ごとに鍵を分けたので、並びを支えるのは印そのものしか無い
fn next_seen(rows : Array[Known]) -> Double {
  let now = @web.now()
  match rows.get(0) {
    Some(top) if top.seen >= now => top.seen + 1.0
    _ => now
  }
}

///|
/// その文書の行。無ければ None
async fn Recent::row_for(self : Recent, file : @web.FileHandle) -> Known? {
  let rows = self.rows()
  rows.get(self.find(rows, file))
}

///|
/// その文書の画像フォルダ。覚えていなければ None
async fn Recent::folder_for(
  self : Recent,
  file : @web.FileHandle,
) -> @web.DirHandle? {
  self.row_for(file).bind(r => r.directory)
}

///|
/// 画像フォルダを覚える。行が無ければ作る
async fn Recent::remember_folder(
  self : Recent,
  file : @web.FileHandle,
  directory : @web.DirHandle,
) -> Unit {
  let rows = self.rows()
  let was = rows.get(self.find(rows, file))
  self.put({
    id: match was {
      Some(w) => w.id
      None => @web.unique_id()
    },
    doc: file,
    directory: Some(directory),
    seen: next_seen(rows),
  })
  self.trim()
}

///|
/// 画像フォルダだけ忘れる（触って失敗した・指し先が消えた）。行は残す
async fn Recent::forget_folder(self : Recent, file : @web.FileHandle) -> Unit {
  guard self.row_for(file) is Some(row) else { return }
  self.put({ id: row.id, doc: row.doc, directory: None, seen: row.seen, })
}

///|
let db_name = "mmm"

///|
/// 棚は 2 つ。**札と本文を混ぜない** — 読み方が違う（札は同一性を照合しないと
/// 引けないが、本文は鍵で引ける）し、片方が壊れてももう片方は読める
pub let handles_shelf = "handles"

///|
pub let drafts_shelf = "drafts"

///|
/// 置き場の版。**棚を増やしたら上げる** — 上げないと、前から在るタブの DB に
/// 新しい棚が生えない
let db_version = 2

///|
/// 実物の置き場（IndexedDB）。1 つの取引ごとに開いて閉じる。失敗は null に倒す
pub fn idb_store(shelf : String) -> Store {
  let run = async fn(
    mode : String,
    op : (@core.Any) -> @core.Any,
  ) -> @core.Any {
    let db = @web.idb_open(db_name, db_version, d => {
      @web.idb_ensure_store(d, handles_shelf)
      @web.idb_ensure_store(d, drafts_shelf)
    }).wait() catch {
      _ => return @core.null()
    }
    let out = @web.idb_run(db, shelf, mode, op).wait() catch {
      _ => @core.null()
    }
    @web.idb_close(db)
    out
  }
  {
    read: async fn(key) { run("readonly", @web.idb_get(key)) },
    write: async fn(key, value) {
      run("readwrite", @web.idb_put(key, value)) |> ignore
    },
    remove: async fn(key) { run("readwrite", @web.idb_delete(key)) |> ignore },
    all: async fn() {
      let v = run("readonly", @web.idb_all())
      if @core.is_array(v) {
        @core.array_from(v)
      } else {
        []
      }
    },
    same: async fn(a, b) { @web.same_entry(a, b).wait() catch { _ => false } },
    is_file: @web.is_file_handle,
    is_dir: @web.is_dir_handle,
  }
}

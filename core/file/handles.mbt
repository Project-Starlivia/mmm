// File System Access API の札を IndexedDB に置く小さな層。
// 本文は持たない。ディスク上の実体を指す札だけを覚える。
//
// **札は参照 ID でしかない。** 中身は覗けず、実際のパスはブラウザの中にしか無い。
// 触ってよいかはまた別の台帳（許可）で、指し先が消えていることもある。だからここが
// 持っているのは**番号札**で、使えるかどうかは毎回下まで確かめる — **覚えているのは
// 高速化であって、真実ではない**。札が死んでいれば、指し直しの駅（ts の app/assets.ts）へ落ちる。
//
// 覚えるのは**知っている文書の一覧**だけ（`docs`）。1 行が 1 つの .md で、
// その文書の画像フォルダを一緒に持つ。
//
// **「いま開いているのはこれ」は覚えない。** 起動時に勝手に開き直さないので、
// 持っていても使い道が無い — 開くのは常に人が選んだとき（Open か、この一覧）。

///|
/// 知っている文書 1 つ。**持つのは札だけ** — 「md から見てどこか」は .md の頭が
/// 宣言する（read/head.mbt）。以前はここが `path` も持っていて、別マシンで開くと
/// 宣言ごと消えていた。
///
/// `seen` は最後に触れた時刻。**あふれたら古いものから捨てる** — 番号札は
/// 腐るので、際限なく貯めても当たらない札が増えるだけ
pub(all) struct Known {
  doc : @web.FileHandle
  /// その文書の画像フォルダ。まだ指してもらっていなければ None
  directory : @web.DirHandle?
  seen : Double
}

///|
/// 覚えておく文書の数。**捨てる基準は「最後に触れた順」**
let keep = 20

///|
let docs_key = "docs"

///|
/// 前の版の鍵。読み替えたら消す（`inherit`）。
/// `file` は「いまのファイル」、`assets` は枠 1 つの画像フォルダだった
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
  /// 札どうしが同じ実体を指すか
  same : async (@core.Any, @core.Any) -> Bool
  is_file : (@core.Any) -> Bool
  is_dir : (@core.Any) -> Bool
}

///|
pub struct Handles {
  store : Store
  /// 読み替えは済んだか。**1 セッションに 1 度でいい** — 済んだ後も毎回
  /// 古い鍵を読みに行くと、`list` を呼ぶたびに無駄な往復が 4 回増える
  mut inherited : Bool
}

///|
pub fn Handles::new(store : Store) -> Handles {
  { store, inherited: false, }
}

///|
/// 覚えていたものが、いまも期待の形をしているか（型は名乗らせず確かめる）
fn Handles::known_of(self : Handles, v : @core.Any) -> Known? {
  guard @core.is_object(v) else { return None }
  let doc = v._get("doc")
  guard (self.store.is_file)(doc) else { return None }
  let dir = v._get("directory")
  let directory = if @core.is_nullish(dir) {
    None
  } else if (self.store.is_dir)(dir) {
    Some((dir.cast() : @web.DirHandle))
  } else {
    return None
  }
  let seen = v._get("seen")
  guard @core.typeof_(seen) == "number" else { return None }
  Some({ doc: doc.cast(), directory, seen: seen.cast(), })
}

///|
/// 前の版が残したもの（`file` と `assets`）を 1 行に読み替える。
/// **版が上がっただけで開き直しをさせない。** 読み替えたら古い鍵は捨てる
async fn Handles::carry_over(self : Handles) -> Array[Known] {
  guard !self.inherited else { return [] }
  self.inherited = true
  let file = (self.store.read)(legacy_file)
  let old = (self.store.read)(legacy_assets)
  let dir = if @core.is_object(old) &&
    (self.store.is_dir)(old._get("directory")) {
    Some((old._get("directory").cast() : @web.DirHandle))
  } else {
    None
  }
  let rows : Array[Known] = if (self.store.is_file)(file) {
    [{ doc: file.cast(), directory: dir, seen: @web.now(), }]
  } else {
    []
  }
  if rows.length() > 0 {
    (self.store.write)(docs_key, @core.any(rows.map(row_of)))
  }
  (self.store.remove)(legacy_file)
  (self.store.remove)(legacy_assets)
  rows
}

///|
/// 置き場に入れる形（素の object）。MoonBit の Option は JS の値ではない —
/// 無い箱は null にして置く
fn row_of(k : Known) -> @core.Any {
  let o = @core.new_object()
  o._set("doc", k.doc.as_any())
  o._set("directory", @core.from_option(k.directory))
  o._set("seen", @core.any(k.seen))
  o
}

///|
async fn Handles::rows(self : Handles) -> Array[Known] {
  let v = (self.store.read)(docs_key)
  if @core.is_array(v) {
    @core.array_from(v).filter_map(x => self.known_of(x))
  } else {
    self.carry_over()
  }
}

///|
/// その文書の行を探す。**札どうしは `same` でしか比べられない** —
/// 中身が覗けないので、鍵で引くのではなく端から照合する（だから `keep` 行）
async fn Handles::find(
  self : Handles,
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
async fn Handles::save(self : Handles, rows : Array[Known]) -> Unit {
  (self.store.write)(
    docs_key,
    @core.any(by_recent(rows).iter().take(keep).map(row_of).collect()),
  )
}

///|
/// 知っている文書。**最後に触れた順** — Files の並びがそのままこれ
pub async fn Handles::list(self : Handles) -> Array[Known] {
  self.rows()
}

///|
/// 開いた / 保存した。行が無ければ作り、あれば触れた印を新しくする。
/// **画像フォルダは保つ** — 同じ文書に戻れば結び付きも戻る
pub async fn Handles::opened(self : Handles, file : @web.FileHandle) -> Unit {
  let rows = self.rows()
  let at = self.find(rows, file)
  let was = rows.get(at)
  if at >= 0 {
    rows.remove(at) |> ignore
  }
  rows.insert(0, {
    doc: file,
    directory: was.bind(w => w.directory),
    seen: @web.now(),
  })
  self.save(rows)
}

///|
/// その文書の画像フォルダ。覚えていなければ None
pub async fn Handles::folder_for(
  self : Handles,
  file : @web.FileHandle,
) -> @web.DirHandle? {
  let rows = self.rows()
  let at = self.find(rows, file)
  rows.get(at).bind(r => r.directory)
}

///|
/// 画像フォルダを覚える。行が無ければ作る
pub async fn Handles::remember_folder(
  self : Handles,
  file : @web.FileHandle,
  directory : @web.DirHandle,
) -> Unit {
  let rows = self.rows()
  let at = self.find(rows, file)
  if at >= 0 {
    rows.remove(at) |> ignore
  }
  rows.insert(0, { doc: file, directory: Some(directory), seen: @web.now(), })
  self.save(rows)
}

///|
/// 画像フォルダだけ忘れる（触って失敗した・指し先が消えた）。行は残す
pub async fn Handles::forget_folder(
  self : Handles,
  file : @web.FileHandle,
) -> Unit {
  let rows = self.rows()
  let at = self.find(rows, file)
  guard rows.get(at) is Some(row) else { return }
  rows[at] = { doc: row.doc, directory: None, seen: row.seen, }
  self.save(rows)
}

///|
let db_name = "mmm"

///|
let store_name = "handles"

///|
/// 実物の置き場（IndexedDB）。1 つの取引ごとに開いて閉じる。失敗は null に倒す
pub fn idb_store() -> Store {
  let run = async fn(
    mode : String,
    op : (@core.Any) -> @core.Any,
  ) -> @core.Any {
    let db = @web.idb_open(db_name, 1, d => @web.idb_ensure_store(d, store_name)).wait() catch {
      _ => return @core.null()
    }
    let out = @web.idb_run(db, store_name, mode, op).wait() catch {
      _ => @core.null()
    }
    @web.idb_close(db)
    out
  }
  {
    read: async fn(key) {
      run("readonly", s => s._call("get", [@core.any(key)]))
    },
    write: async fn(key, value) {
      run("readwrite", s => s._call("put", [value, @core.any(key)])) |> ignore
    },
    remove: async fn(key) {
      run("readwrite", s => s._call("delete", [@core.any(key)])) |> ignore
    },
    same: async fn(a, b) { @web.same_entry(a, b).wait() catch { _ => false } },
    is_file: @web.is_file_handle,
    is_dir: @web.is_dir_handle,
  }
}

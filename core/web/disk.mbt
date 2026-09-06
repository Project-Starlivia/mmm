// ディスクの口。File System Access API と IndexedDB の、型の無い呼び出しを 1 行ずつ包む。
// 結び付けの無い API なので `extern "js"` で書き、Promise は js_async の型で返す。
// 取り消し（ピッカーの AbortError）は**値**（null）にして返す — 断りは例外ではない。

///|
/// ファイルの札（FileSystemFileHandle）。中は覗けず、指し先はブラウザの中にしか無い
#external
pub type FileHandle

///|
pub fn FileHandle::as_any(self : FileHandle) -> @core.Any = "%identity"

///|
/// フォルダの札（FileSystemDirectoryHandle）
#external
pub type DirHandle

///|
pub fn DirHandle::as_any(self : DirHandle) -> @core.Any = "%identity"

///|
pub fn FileHandle::name(self : FileHandle) -> String {
  self.as_any()._get("name").cast()
}

///|
pub extern "js" fn is_file_handle(v : @core.Any) -> Bool =
  #| (v) => typeof FileSystemFileHandle !== "undefined" && v instanceof FileSystemFileHandle

///|
pub extern "js" fn is_dir_handle(v : @core.Any) -> Bool =
  #| (v) => typeof FileSystemDirectoryHandle !== "undefined" && v instanceof FileSystemDirectoryHandle

///|
/// 同じ実体を指すか。**札どうしはこれでしか比べられない**（中身が覗けない）
pub extern "js" fn same_entry(
  a : @core.Any,
  b : @core.Any,
) -> @js_async.Promise[Bool] =
  #| (a, b) => a.isSameEntry(b)

///|
/// 触ってよいかを聞く（"granted" / "denied" / "prompt"）。mode は "read" / "readwrite"
pub extern "js" fn request_permission(
  h : @core.Any,
  mode : String,
) -> @js_async.Promise[String] =
  #| (h, mode) => h.requestPermission({ mode })

///|
pub extern "js" fn query_permission(
  h : @core.Any,
  mode : String,
) -> @js_async.Promise[String] =
  #| (h, mode) => h.queryPermission({ mode })

///|
/// ファイルの中身を字で
pub extern "js" fn read_text(h : FileHandle) -> @js_async.Promise[String] =
  #| (h) => h.getFile().then((f) => f.text())

///|
/// 字をファイルに書く（書き終えるまで閉じない）
pub extern "js" fn write_text(
  h : FileHandle,
  text : String,
) -> @js_async.Promise[Unit] =
  #| (h, text) => h.createWritable().then(async (s) => { try { await s.write(text); } finally { await s.close(); } })

///|
/// このブラウザがファイルを開けるか。**スマホには無い**
pub extern "js" fn can_open() -> Bool =
  #| () => typeof window !== "undefined" && typeof window.showOpenFilePicker === "function"

///|
pub extern "js" fn can_save_as() -> Bool =
  #| () => typeof window !== "undefined" && typeof window.showSaveFilePicker === "function"

///|
/// 改名（`move`）を持つか。Chromium だけが持つ
pub extern "js" fn can_rename() -> Bool =
  #| () => typeof FileSystemFileHandle !== "undefined" && typeof FileSystemFileHandle.prototype.move === "function"

///|
/// ファイルを 1 つ選ぶ。取り消しは null。`types` はピッカーの受け付ける種類
pub extern "js" fn pick_open(types : @core.Any) -> @js_async.Promise[@core.Any] =
  #| (types) => window.showOpenFilePicker({ multiple: false, types })
  #|   .then(([f]) => f ?? null)
  #|   .catch((e) => (e && e.name === "AbortError" ? null : Promise.reject(e)))

///|
/// 保存先を選ぶ。取り消しは null
pub extern "js" fn pick_save(
  suggested : String,
  types : @core.Any,
) -> @js_async.Promise[@core.Any] =
  #| (suggestedName, types) => window.showSaveFilePicker({ suggestedName, types })
  #|   .catch((e) => (e && e.name === "AbortError" ? null : Promise.reject(e)))

///|
/// 同じフォルダの中での改名
pub extern "js" fn move_to(
  h : FileHandle,
  name : String,
) -> @js_async.Promise[Unit] =
  #| (h, name) => h.move(name)

///|
/// IndexedDB を開く。版が上がったときは `upgrade(db)` が走る
pub extern "js" fn idb_open(
  name : String,
  version : Int,
  upgrade : (@core.Any) -> Unit,
) -> @js_async.Promise[@core.Any] =
  #| (name, version, upgrade) => new Promise((ok, err) => {
  #|   const req = indexedDB.open(name, version);
  #|   req.onupgradeneeded = () => upgrade(req.result);
  #|   req.onsuccess = () => ok(req.result);
  #|   req.onerror = () => err(req.error);
  #| })

///|
/// 1 つの取引を走らせて、結果をそのまま。`op` は store を受けて request を返す
pub extern "js" fn idb_run(
  db : @core.Any,
  store : String,
  mode : String,
  op : (@core.Any) -> @core.Any,
) -> @js_async.Promise[@core.Any] =
  #| (db, store, mode, op) => new Promise((ok, err) => {
  #|   const req = op(db.transaction(store, mode).objectStore(store));
  #|   req.onsuccess = () => ok(req.result);
  #|   req.onerror = () => err(req.error);
  #| })

///|
/// 店（objectStore）を作る（無ければ）
pub extern "js" fn idb_ensure_store(db : @core.Any, store : String) -> Unit =
  #| (db, store) => { if (!db.objectStoreNames.contains(store)) db.createObjectStore(store); }

///|
pub extern "js" fn idb_close(db : @core.Any) -> Unit =
  #| (db) => db.close()

///|
/// 今の時刻（ms）
pub extern "js" fn now() -> Double =
  #| () => Date.now()

///|
pub fn DirHandle::name(self : DirHandle) -> String {
  self.as_any()._get("name").cast()
}

///|
/// このブラウザがフォルダを選べるか（触る道具では持たないことがある）
pub extern "js" fn can_choose_folder() -> Bool =
  #| () => typeof window !== "undefined" && typeof window.showDirectoryPicker === "function"

///|
/// フォルダを指してもらう。取り消しは null。`start` は開く場所の札
pub extern "js" fn pick_directory(
  start : @core.Any,
  mode : String,
) -> @js_async.Promise[@core.Any] =
  #| (startIn, mode) => window.showDirectoryPicker({ startIn, mode })
  #|   .catch((e) => (e && e.name === "AbortError" ? null : Promise.reject(e)))

///|
pub extern "js" fn get_dir(
  d : DirHandle,
  name : String,
  create : Bool,
) -> @js_async.Promise[DirHandle] =
  #| (d, name, create) => d.getDirectoryHandle(name, { create })

///|
pub extern "js" fn get_file(
  d : DirHandle,
  name : String,
  create : Bool,
) -> @js_async.Promise[FileHandle] =
  #| (d, name, create) => d.getFileHandle(name, { create })

///|
/// フォルダから見た f の断片（`["notes", "a.md"]`）。含まなければ null
pub extern "js" fn resolve_path(
  d : DirHandle,
  f : FileHandle,
) -> @js_async.Promise[@core.Any] =
  #| (d, f) => d.resolve(f)

///|
/// フォルダの中身。`[name, dirHandle | null]` の並び（null は ファイル）
pub extern "js" fn list_entries(d : DirHandle) -> @js_async.Promise[@core.Any] =
  #| async (d) => { const out = []; for await (const [name, h] of d.entries()) out.push([name, h.kind === "directory" ? h : null]); return out; }

///|
/// ファイルを読んで objectURL に（種類は名前から決めたもの）
pub extern "js" fn read_url(
  f : FileHandle,
  mime : String,
) -> @js_async.Promise[String] =
  #| (f, type) => f.getFile().then((b) => b.arrayBuffer()).then((buf) => URL.createObjectURL(new Blob([buf], { type })))

///|
pub extern "js" fn object_url(blob : @core.Any) -> String =
  #| (blob) => URL.createObjectURL(blob)

///|
pub extern "js" fn revoke_url(url : String) -> Unit =
  #| (url) => URL.revokeObjectURL(url)

///|
pub extern "js" fn blob_type(blob : @core.Any) -> String =
  #| (blob) => blob.type

///|
/// 絵を webp に（もう webp ならそのまま）
pub extern "js" fn to_webp(blob : @core.Any) -> @js_async.Promise[@core.Any] =
  #| async (blob) => {
  #|   if (blob.type === "image/webp") return blob;
  #|   const bitmap = await createImageBitmap(blob);
  #|   try {
  #|     const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  #|     canvas.getContext("2d").drawImage(bitmap, 0, 0);
  #|     const out = await canvas.convertToBlob({ type: "image/webp", quality: 0.92 });
  #|     if (out.type !== "image/webp") throw new Error("webp conversion failed");
  #|     return out;
  #|   } finally { bitmap.close(); }
  #| }

///|
pub extern "js" fn write_blob(
  f : FileHandle,
  blob : @core.Any,
) -> @js_async.Promise[Unit] =
  #| (f, blob) => f.createWritable().then(async (s) => { try { await s.write(blob); } finally { await s.close(); } })

///|
/// いまの時刻の綴り（`2026-09-07-153012`）
pub extern "js" fn stamp() -> String =
  #| () => { const d = new Date(), two = (v) => String(v).padStart(2, "0");
  #|   return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}-${two(d.getHours())}${two(d.getMinutes())}${two(d.getSeconds())}`; }

///|
/// 続きで答えるもの（callback）を Promise に
pub extern "js" fn promise_of(
  f : ((@core.Any) -> Unit) -> Unit,
) -> @js_async.Promise[@core.Any] =
  #| (f) => new Promise((ok) => f(ok))

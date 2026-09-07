// ファイルのドラッグ。ドラッグ中に読めるのは種類（MIME）までで、名前も中身も
// drop まで伏せられている。取り出しは**待つ前に全部**始める — 最初の await で
// drop の出来事が終わり、以後 items は空に見える

///|
/// 掴んでいるファイルの種類の並び。ファイルが無ければ空
pub extern "js" fn drag_files(e : @core.Any) -> FixedArray[String] =
  #| (e) => [...(e.dataTransfer?.items ?? [])].filter((i) => i.kind === "file").map((i) => i.type)

///|
/// 受けるか（`copy`）、断るか（`none`）をブラウザのカーソルに言う
pub extern "js" fn set_drop_effect(e : @core.Any, effect : String) -> Unit =
  #| (e, effect) => { if (e.dataTransfer) e.dataTransfer.dropEffect = effect; }

///|
/// 窓の外へ出た（戻ってくれば dragover がまた点ける）
pub extern "js" fn left_window(e : @core.Any) -> Bool =
  #| (e) => e.relatedTarget == null

///|
/// 落ちたもののうち、ファイルの札として取れたものの並び
pub extern "js" fn dropped_files(
  e : @core.Any,
) -> @js_async.Promise[FixedArray[FileHandle]] =
  #| (e) => Promise.all([...(e.dataTransfer?.items ?? [])]
  #|   .filter((i) => i.kind === "file" && i.getAsFileSystemHandle).map((i) => i.getAsFileSystemHandle()))
  #|   .then((hs) => hs.filter((h) => h instanceof FileSystemFileHandle))

///|
/// 札の中身（File。Blob として扱う）
pub extern "js" fn file_of(h : FileHandle) -> @js_async.Promise[@core.Any] =
  #| (h) => h.getFile()

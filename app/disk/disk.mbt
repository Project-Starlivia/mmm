// ブラウザの File System Access API との窓口。
// UTF-8 / LF の Markdown を 1 ファイルずつ読み書きする。

///|
pub(all) struct Doc {
  name : String
  text : String
}

///|
/// いま開いているファイルと、覚えている札と、控え。
///
/// 控え（`drafts`）はディスクではなくブラウザの中に置くが、**覚えているものと
/// 同じ置き場（IndexedDB）に同じ流儀で並ぶ**ので、口も 1 つにまとめる
pub struct Disk {
  recent : Recent
  drafts : Drafts
  mut current : @web.FileHandle?
}

///|
pub fn Disk::new(recent : Recent, drafts : Drafts) -> Disk {
  { recent, drafts, current: None, }
}

///|
/// 控えの台帳
pub fn Disk::drafts(self : Disk) -> Drafts {
  self.drafts
}

///|
/// ピッカーの受け付ける種類（Markdown）
fn markdown_types() -> @core.Any {
  @web.file_types("Markdown", "text/markdown", @read.md_exts)
}

///|
/// 改行を LF に揃える
fn lf(text : String) -> String {
  text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
async fn read_doc(file : @web.FileHandle) -> Doc {
  { name: file.name(), text: lf(@web.read_text(file).wait()), }
}

///|
/// このファイルをいまのものにして、覚えて、読む
async fn Disk::use_(self : Disk, file : @web.FileHandle) -> Doc {
  self.current = Some(file)
  self.recent.opened(file)
  read_doc(file)
}

///|
pub fn Disk::current_file(self : Disk) -> @web.FileHandle? {
  self.current
}

///|
/// 覚えている文書を開く。**許可はここで取り直す** — 札は残っていても
/// 触ってよいかは別の台帳で、押した瞬間しか聞けない（押されたことが
/// その資格になる）。断られたら None
pub async fn Disk::open_known(self : Disk, file : @web.FileHandle) -> Doc? {
  guard @web.request_permission(file.as_any(), "readwrite").wait() == "granted" else {
    return None
  }
  Some(self.use_(file))
}

///|
/// いまのファイルを手放す（New file）。**覚えている一覧はそのまま**
pub fn Disk::close(self : Disk) -> Unit {
  self.current = None
}

///|
/// ピッカーで開く。取り消しは None
pub async fn Disk::open_dialog(self : Disk) -> Doc? {
  guard @web.can_open() else { return None }
  let picked = @web.pick_open(markdown_types()).wait()
  guard !@core.is_nullish(picked) else { return None }
  Some(self.use_(picked.cast()))
}

///|
/// 札から開く（落とされたファイル）
pub async fn Disk::open_handle(self : Disk, file : @web.FileHandle) -> Doc {
  self.use_(file)
}

///|
/// いまのファイルに書く。無ければ失敗
pub async fn Disk::save(self : Disk, text : String) -> Unit {
  guard self.current is Some(file) else { fail("no-file") }
  @web.write_text(file, text).wait()
}

///|
/// 別名で保存。取り消しは None
pub async fn Disk::save_as(
  self : Disk,
  suggested : String,
  text : String,
) -> Doc? {
  guard @web.can_save_as() else { return None }
  let picked = @web.pick_save(suggested, markdown_types()).wait()
  guard !@core.is_nullish(picked) else { return None }
  let file : @web.FileHandle = picked.cast()
  @web.write_text(file, text).wait()
  self.current = Some(file)
  self.recent.opened(file)
  Some({ name: file.name(), text, })
}

///|
/// いま開いているファイル**そのもの**の名前を変える（`move` は同じフォルダの中での
/// 改名になる）。保存していなければ何もしない — 名前を変える相手がディスクに無い
pub async fn Disk::rename(self : Disk, name : String) -> String? {
  guard @web.can_rename() && self.current is Some(file) else { return None }
  @web.move_to(file, name).wait()
  self.recent.opened(file)
  Some(file.name())
}

///|
/// 覚えている文書。**Files の `Recent` に並ぶのがこれ** — 最後に触れた順で、
/// いま開いているものは外す
pub async fn Disk::remembered(self : Disk) -> Array[@web.FileHandle] {
  self.recent.list_besides(self.current)
}

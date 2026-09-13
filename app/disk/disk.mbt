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
  /// いまのファイルを最後に読んだ / 書いたときの、ディスク側の時刻。
  /// **書く直前に 1 度だけ比べる**（#318）。見張りではないので「外部変更は追わない」は
  /// そのまま — 追わないが、他所の変更を黙って塗り潰しもしない
  mut stamp : Double?
}

///|
pub fn Disk::new(recent : Recent, drafts : Drafts) -> Disk {
  { recent, drafts, current: None, stamp: None, }
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
  self.stamp = stamp_of(file)
  read_doc(file)
}

///|
/// ディスク側の時刻。持たない実装なら None（比べようが無いので、聞かない側に倒す）
async fn stamp_of(file : @web.FileHandle) -> Double? {
  let v = @web.last_modified(file).wait() catch { _ => return None }
  if @core.typeof_(v) == "number" {
    Some(v.cast())
  } else {
    None
  }
}

///|
/// 最後に読んだ / 書いたときから、**他所で書き換わったか**。
/// 比べる材料が無ければ false — 分からないことを理由に人を止めない
pub async fn Disk::changed_elsewhere(self : Disk) -> Bool {
  guard self.current is Some(file) && self.stamp is Some(before) else {
    return false
  }
  match stamp_of(file) {
    Some(now) => now != before
    None => false
  }
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
/// 札を引き受けて、**中身は読まない**。控えから戻すときの道 — ディスクの字より
/// 控えのほうが新しいので、読めば戻した字を上書きしてしまう。
/// 許可はここでも取り直す（押されたことがその資格）
pub async fn Disk::adopt(self : Disk, file : @web.FileHandle) -> Bool {
  guard @web.request_permission(file.as_any(), "readwrite").wait() == "granted" else {
    return false
  }
  self.current = Some(file)
  self.recent.opened(file)
  // 戻すと決めたのは人。**いまのディスクの字を知ったうえで**控えを選んだので、
  // ここから先の上書きは聞かない
  self.stamp = stamp_of(file)
  true
}

///|
/// いまのファイルを手放す（New file）。**覚えている一覧はそのまま**
pub fn Disk::close(self : Disk) -> Unit {
  self.current = None
  self.stamp = None
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
  // 自分の書き込みも時刻を進める。**書いた後に読み直して控える** —
  // 控えなければ、次の保存で自分の書き込みを「他所の変更」と取り違える
  self.stamp = stamp_of(file)
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
  self.stamp = stamp_of(file)
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
pub async fn Disk::remembered(self : Disk) -> Array[Known] {
  self.recent.list_besides(self.current)
}

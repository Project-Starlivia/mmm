// ブラウザの File System Access API との窓口。
// UTF-8 / LF の Markdown を 1 ファイルずつ読み書きする。

///|
pub(all) struct Doc {
  name : String
  text : String
}

///|
/// いま開いているファイルと、覚えている札
pub struct Io {
  handles : Handles
  mut current : @web.FileHandle?
}

///|
pub fn Io::new(handles : Handles) -> Io {
  { handles, current: None, }
}

///|
/// ピッカーの受け付ける種類（Markdown）
fn markdown_types() -> @core.Any {
  let accept = @core.new_object()
  accept._set("text/markdown", @core.any(@app.md_exts))
  let kind = @core.new_object()
  kind._set("description", @core.any("Markdown"))
  kind._set("accept", accept)
  @core.any([kind])
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
async fn Io::use_(self : Io, file : @web.FileHandle) -> Doc {
  self.current = Some(file)
  self.handles.opened(file)
  read_doc(file)
}

///|
pub fn Io::current_file(self : Io) -> @web.FileHandle? {
  self.current
}

///|
/// 覚えている文書を開く。**許可はここで取り直す** — 札は残っていても
/// 触ってよいかは別の台帳で、押した瞬間しか聞けない（押されたことが
/// その資格になる）。断られたら None
pub async fn Io::open_known(self : Io, file : @web.FileHandle) -> Doc? {
  guard @web.request_permission(file.as_any(), "readwrite").wait() == "granted" else {
    return None
  }
  Some(self.use_(file))
}

///|
/// いまのファイルを手放す（New file）。**覚えている一覧はそのまま**
pub fn Io::close(self : Io) -> Unit {
  self.current = None
}

///|
/// ピッカーで開く。取り消しは None
pub async fn Io::open_dialog(self : Io) -> Doc? {
  guard @web.can_open() else { return None }
  let picked = @web.pick_open(markdown_types()).wait()
  guard !@core.is_nullish(picked) else { return None }
  Some(self.use_(picked.cast()))
}

///|
/// 札から開く（落とされたファイル）
pub async fn Io::open_handle(self : Io, file : @web.FileHandle) -> Doc {
  self.use_(file)
}

///|
/// いまのファイルに書く。無ければ失敗
pub async fn Io::save(self : Io, text : String) -> Unit {
  guard self.current is Some(file) else { fail("no-file") }
  @web.write_text(file, text).wait()
}

///|
/// 別名で保存。取り消しは None
pub async fn Io::save_as(self : Io, suggested : String, text : String) -> Doc? {
  guard @web.can_save_as() else { return None }
  let picked = @web.pick_save(suggested, markdown_types()).wait()
  guard !@core.is_nullish(picked) else { return None }
  let file : @web.FileHandle = picked.cast()
  @web.write_text(file, text).wait()
  self.current = Some(file)
  self.handles.opened(file)
  Some({ name: file.name(), text, })
}

///|
/// いま開いているファイル**そのもの**の名前を変える（`move` は同じフォルダの中での
/// 改名になる）。保存していなければ何もしない — 名前を変える相手がディスクに無い
pub async fn Io::rename(self : Io, name : String) -> String? {
  guard @web.can_rename() && self.current is Some(file) else { return None }
  @web.move_to(file, name).wait()
  self.handles.opened(file)
  Some(file.name())
}

///|
/// 覚えている文書。**Files の `Recent` に並ぶのがこれ** — 最後に触れた順で、
/// いま開いているものは外す
pub async fn Io::recent(self : Io) -> Array[@web.FileHandle] {
  let out = []
  for row in self.handles.list() {
    match self.current {
      Some(now) =>
        if (self.handles.store.same)(row.doc.as_any(), now.as_any()) {
          continue
        }
      None => ()
    }
    out.push(row.doc)
  }
  out
}

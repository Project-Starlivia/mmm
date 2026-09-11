// Markdown からの相対パスで画像を読み書きする。
//
// **宣言（md から見てどこか）は .md の頭が持ち、許可（そのフォルダを読み書き
// してよい）だけをここが持つ。** ブラウザはパス文字列からフォルダの札を
// 作れないので、2 つに分かれること自体は避けられない — どちらが何の真実かを
// 言い切ることで、食い違いを事故にしない。
//
// 宣言が無い文書は `./`（md と同じ場所）として読み書きする。**宣言を決める /
// 直すのもここ**（`settle`）— ただし道具は宣言を黙って書き換えない。書くのは
// 計算できたとき（`resolve`）と、人が箱で確定したときだけ。書き込みそのものは
// md への操作なので `deps.set_declared` に渡す（App の `set_declared`）。

///|
/// 読みに行ってよい絵の種類。**綴りはここ 1 つ**で、種類の判定も
/// `<image>` に載せる MIME も同じ表から引く
let image_types : Array[(String, String)] = [
  ("webp", "image/webp"),
  ("png", "image/png"),
  ("jpg", "image/jpeg"),
  ("jpeg", "image/jpeg"),
  ("gif", "image/gif"),
  ("avif", "image/avif"),
  ("svg", "image/svg+xml"),
  ("bmp", "image/bmp"),
  ("ico", "image/x-icon"),
]

///|
/// その名前が指す絵の種類。絵でなければ None
fn image_type(name : String) -> String? {
  guard name.rev_find(".") is Some(dot) && dot > 0 else { return None }
  let ext = String::unsafe_substring(name, start=dot + 1, end=name.length()).to_lower()
  for t in image_types {
    if t.0 == ext {
      return Some(t.1)
    }
  }
  None
}

///|
/// md に書かれたパスが、宣言した保存パスの下に収まるか。
/// 収まればフォルダからの相対を断片で返し、外れていれば None。
///
/// 「その綴りは宣言の下か」の判定は read の `under` が唯一の持ち主。
/// ここが足すのは、**フォルダの中として受け取ってよいか**の柵だけ
fn asset_target(declared : String, path : String) -> Array[String]? {
  guard @read.under(path, declared) is Some(rest) else { return None }
  let parts = rest
    .split("/")
    .map(p => p.to_owned())
    .filter(p => p != "")
    .collect()
  guard parts.length() > 0 else { return None }
  // フォルダの外へ出る綴りは受け取らない（宣言の外は見に行かない）
  if parts.any(p => p == "." || p == "..") {
    return None
  }
  // **絵でないものは読みに行かない。** `![](notes.txt)` と書けば、マップに
  // 何も出ないまま中身が読まれ、書き出した SVG に base64 で載ってしまう
  // （`<image>` は描けなくてもデータは埋まる）。宣言したフォルダの中に
  // 限られるとはいえ、絵を置く場所として渡したフォルダなので、絵だけ見る
  guard image_type(parts[parts.length() - 1]) is Some(_) else { return None }
  Some(parts)
}

///|
/// md に書く形。`./` を付ける。上へ出る道はそのまま
fn md_path(rel : String) -> String {
  if rel.has_prefix("../") {
    rel
  } else {
    "./" + @tree.bare_path(rel)
  }
}

// ---- 宣言 ----

///|
/// **宣言の綴りとして通らない理由。** 通るなら None。
///
/// `dir_name` は、末尾に来るはずの**選んだフォルダの実名**。`resolve` が効かな
/// かったとき — つまり選んだフォルダは md を含んでいない — 末尾のフォルダ名は
/// 必ず選んだものと一致するはずで、一致しなければ打ち間違い。`./`（md と同じ
/// 場所）もこの場では矛盾になる。
///
/// 位置が計算できたとき（選んだフォルダが md を含む）は None を渡す。宣言は
/// `./` や `../` の形で、末尾に実名は来ないので照合しようが無い。
///
/// 深さ（`../` が何段か）だけは確かめようが無い — 札から親は辿れない。
/// **確かめられる嘘は全部止めて、確かめられないところだけ人を信じる**
pub fn folder_problem(typed : String, dir_name : String?) -> String? {
  guard @read.normalize_path(typed) is Some(norm) else {
    return Some("Use a path relative to the .md")
  }
  guard dir_name is Some(name) else { return None }
  let last = norm
    .split("/")
    .map(p => p.to_owned())
    .filter(p => p != "")
    .collect()
    .last()
  if last == Some(name) {
    None
  } else {
    Some("The folder you picked is named \{name}")
  }
}

///|
/// 選んだフォルダから md までの断片を、md から見たフォルダの相対に読み替える。
/// `resolve` が返すのは「フォルダ → md」なので、**末尾のファイル名を除いた数**だけ
/// 上へ戻る（`["notes","a.md"]` なら md は 1 段深いところに居るので `../`）
fn folder_from_doc(segments : Array[String]) -> String {
  let up = @cmp.maximum(0, segments.length() - 1)
  if up == 0 {
    "./"
  } else {
    "../".repeat(up)
  }
}

// ---- 画像の名前 ----
//
// **決めるのも咎めるのも 1 か所**。`name_problem` はたずね箱が打鍵のたびに
// 呼び、`name_parts` は通った値だけを受け取る — だめな値がここから先へ
// 進むことは無いので、書き込む側で二度確かめない。

///|
/// 名前をフォルダの断片に割る（末尾が置くファイル）。`.webp` は落とす
fn name_parts(typed : String) -> Array[String] {
  let t = typed.trim(chars=" \t\r\n").to_owned()
  let base = if t.to_lower().has_suffix(".webp") {
    String::unsafe_substring(t, start=0, end=t.length() - 5)
  } else {
    t
  }
  base.split("/").map(p => p.to_owned()).filter(p => p != "").collect()
}

///|
/// その名前では置けない理由。置けるなら None
fn name_problem(typed : String) -> String? {
  let parts = name_parts(typed)
  guard parts.length() > 0 else { return Some("Give it a name") }
  if parts.any(p => p == "." || p == "..") {
    return Some("Folder names cannot be . or ..")
  }
  let joined = parts.join("")
  for i in 0..<joined.length() {
    let c = joined[i]
    if c == '\\' ||
      c == ':' ||
      c == '*' ||
      c == '?' ||
      c == '"' ||
      c == '<' ||
      c == '>' ||
      c == '|' {
      return Some("A file name cannot contain \{c.to_char().unwrap()}")
    }
  }
  None
}

// ---- 握り ----

///|
/// 外に頼るもの
pub(all) struct ImageDeps {
  /// 果たせなかった（しらせの言葉）
  failed : (String) -> Unit
  /// 絵を引き直したので描き直す
  refresh : () -> Unit
  /// いま頭が言っている宣言（正規化済み）。無ければ None
  declared : () -> String?
  /// 宣言を頭に書く（md への操作。本文の画像もそれに追従する）
  set_declared : (String) -> Unit
}

///|
/// いま握っているもの。**セッションの持ち物**で、覚えているのは札だけ（handles）。
/// `doc` を組で持つのは、握りが「**この md** から見た**あのフォルダ**」という対でしか
/// 意味を持たないから
pub(all) struct Binding {
  doc : @web.FileHandle
  directory : @web.DirHandle
}

///|
/// 指してもらった結果。**宣言をどう決めるかは、ここでは決めない**
priv struct Picked {
  binding : Binding
  /// md から見た位置。`resolve` が効いたときだけ確か（効かなければ None）
  computed : String?
  /// 効かなかったときの当て推量。人に確かめてもらう既定値になる
  guess : String
}

///|
pub struct Images {
  doc : @dom.Document
  io : Disk
  deps : ImageDeps
  /// path → objectURL。None は「引きに行ったが無い / まだ」
  urls : Map[String, String?]
  mut cached : Binding?
  /// `cached` を引いたか（引いて無かった、と、まだ引いていない、を分ける）
  mut cached_known : Bool
  /// 直近に確かめた「読めているか」。描くたびに同期で聞かれるので覚えておく
  mut live : Bool
}

///|
pub fn Images::new(doc : @dom.Document, io : Disk, deps : ImageDeps) -> Images {
  {
    doc,
    io,
    deps,
    urls: Map([]),
    cached: None,
    cached_known: false,
    live: false,
  }
}

///|
/// 宣言が無いのは「md と同じ場所」。頭を持たない古い文書がそのまま読めるように、ここで倒す
fn Images::declared_path(self : Images) -> String {
  (self.deps.declared)().unwrap_or("./")
}

///|
fn Images::release_urls(self : Images) -> Unit {
  for _, url in self.urls {
    match url {
      Some(u) => @web.revoke_url(u)
      None => ()
    }
  }
  self.urls.clear()
}

///|
async fn Images::stored_binding(self : Images) -> Binding? {
  if self.cached_known {
    return self.cached
  }
  // **札は文書ごと**（handles）。別の .md を開いても前の結び付きは残る
  let b = match self.io.current_file() {
    Some(file) =>
      match self.io.handles.folder_for(file) {
        Some(directory) => Some({ doc: file, directory, })
        None => None
      }
    None => None
  }
  self.cached = b
  self.cached_known = true
  b
}

///|
/// フォルダを指してもらい、握る。取りやめは None
async fn Images::pick(self : Images) -> Picked? {
  guard self.io.current_file() is Some(file) else { return None }
  guard @web.can_choose_folder() else { return None }
  let picked = @web.pick_directory(file.as_any(), "readwrite").wait()
  guard !@core.is_nullish(picked) else { return None }
  let directory : @web.DirHandle = picked.cast()
  let binding : Binding = { doc: file, directory, }
  self.io.handles.remember_folder(file, directory)
  self.cached = Some(binding)
  self.cached_known = true
  self.live = true
  // 選んだフォルダが md を含んでいれば、md から見た位置は**計算できる**。
  // 含まなければ手がかりはフォルダ名だけ
  let segments : Array[String]? = @core.identity_option(
    @web.resolve_path(directory, file).wait(),
  )
  self.release_urls()
  (self.deps.refresh)()
  Some({
    binding,
    computed: segments.map(folder_from_doc),
    guess: "./\{directory.name()}/",
  })
}

///|
/// 指してもらった結果を打てる欄にする。計算できていればそれが値で、実名の
/// 照合は無い。できていなければ当て推量が値で、末尾を実名と照合する
fn field_of(p : Picked) -> @parts.Field {
  let dir_name = if p.computed is None {
    Some(p.binding.directory.name())
  } else {
    None
  }
  {
    value: p.computed.unwrap_or(p.guess),
    check: Some(typed => folder_problem(typed, dir_name)),
  }
}

///|
/// その名前では**置けない**理由。名前そのものの検査（`name_problem`）に、
/// **置き場に同じ名前が居るか**を足したもの。置けるなら None。
/// `here` はそのフォルダに既に在る名前（小文字、`.webp` 込み）。
///
/// 1 つの関数にしてあるのは、貼る側と並べて見る道具が**同じ検査を通す**ため —
/// 言葉を写すと、条件を足したときに片方だけ古くなる
pub fn image_name_problem(typed : String, here : Set[String]) -> String? {
  match name_problem(typed) {
    Some(why) => Some(why)
    None => {
      let parts = name_parts(typed)
      guard parts.last() is Some(last) else { return None }
      let head = parts.iter().take(parts.length() - 1).collect()
      head.push(last + ".webp")
      if here.contains(head.join("/").to_lower()) {
        Some("That name is taken")
      } else {
        None
      }
    }
  }
}

///|
/// 宣言を聞く箱。初めて決めるときと、選び直して食い違ったときの両方。
/// **綴りは持たない** — 箱は表（app/parts/asks.mbt）から引き、ここが渡すのは欄だけ
async fn Images::ask_declaration(
  self : Images,
  p : Picked,
  was : String?,
) -> String? {
  let field = field_of(p)
  let a = match was {
    None => @parts.declaration(p.binding.directory.name(), field)
    Some(_) => @parts.redeclaration(field)
  }
  @parts.asked(self.doc, a).bind(out => out.get(0))
}

///|
/// 宣言を書く。宣言が変われば「どのパスが読めるか」も変わるので、絵は引き直す
fn Images::set_declared(self : Images, value : String) -> Unit {
  (self.deps.set_declared)(value)
  self.release_urls()
  (self.deps.refresh)()
}

///|
/// 指してもらった結果に対して、宣言を決める。
///
/// **道具は宣言を黙って書き換えない。** 書くのは 2 通りだけ —
/// `resolve` で**計算できた**とき（推量ではない）と、**人が箱で確定した**とき。
///
/// `inline` は「呼ぶ側のフォームが位置の欄を持っている」の合図。
/// 画像を置く流れでは、フォルダも名前も 1 枚の中で聞きたいので、
/// ここでは聞かずに欄だけ返す
async fn Images::settle(
  self : Images,
  p : Picked,
  inline : Bool,
) -> @parts.Field? {
  match (self.deps.declared)() {
    None => {
      if p.computed is Some(c) {
        self.set_declared(c)
        return None
      }
      if inline {
        return Some(field_of(p))
      }
      match self.ask_declaration(p, None) {
        Some(typed) => self.set_declared(typed)
        None => ()
      }
      None
    }
    Some(was) => {
      // 記録があるのに別の場所を指された。**黙って書き換えない** — 直すのも、
      // 記録を古いままにするのも、人が決める（握りはもう移っている）
      if @read.normalize_path(p.computed.unwrap_or(p.guess)) != Some(was) {
        match self.ask_declaration(p, Some(was)) {
          Some(typed) => self.set_declared(typed)
          None => ()
        }
      }
      None
    }
  }
}

///|
/// 握りが腐った。**捨てて、繋ぎ直しの駅へ落とす** — 腐ったまま持っていると
/// 次も同じところで失敗する。宣言は md に残るので、指し直せば戻る
fn Images::forget(self : Images) -> Unit {
  self.cached = None
  self.cached_known = true
  self.live = false
  match self.io.current_file() {
    Some(file) => @web.spawn(async fn() { self.io.handles.forget_folder(file) })
    None => ()
  }
  self.release_urls()
  (self.deps.refresh)()
}

///|
async fn granted(h : @web.DirHandle, mode : String) -> Bool {
  @web.query_permission(h.as_any(), mode).wait() == "granted"
}

///|
async fn allowed(h : @web.DirHandle, mode : String) -> Bool {
  let state = @web.query_permission(h.as_any(), mode).wait()
  state == "granted" ||
  (
    state == "prompt" &&
    @web.request_permission(h.as_any(), mode).wait() == "granted"
  )
}

///|
/// 書けるフォルダを用意する。握っていればそれ、無ければ指してもらう。
/// 返すのは「呼ぶ側のフォームに載せる位置の欄」（要らなければ None）。取りやめは None
async fn Images::ensure_binding(self : Images) -> (Binding, @parts.Field?)? {
  match self.stored_binding() {
    Some(binding) => {
      if allowed(binding.directory, "readwrite") {
        return Some((binding, None))
      }
      // 許可が下りない札は腐っている。捨ててから指し直してもらう
      self.forget()
    }
    None => ()
  }
  guard self.pick() is Some(picked) else { return None }
  // 位置の欄は**画像のフォームの中で**聞く（inline）。フォルダと名前は
  // 1 つの行き先の 2 つの部分でしかないので、箱を分けない
  Some((picked.binding, self.settle(picked, true)))
}

///|
async fn nested_file(
  root : @web.DirHandle,
  parts : Array[String],
  create : Bool,
) -> @web.FileHandle {
  let mut directory = root
  for i in 0..<(parts.length() - 1) {
    directory = @web.get_dir(directory, parts[i], create).wait()
  }
  @web.get_file(directory, parts[parts.length() - 1], create).wait()
}

///|
async fn Images::load_asset(self : Images, path : String) -> Unit {
  guard self.stored_binding() is Some(binding) else { return }
  guard asset_target(self.declared_path(), path) is Some(parts) else { return }
  guard granted(binding.directory, "read") else { return }
  // 種類は名前から引く（`asset_target` を通った時点で必ず絵）
  let mime = image_type(parts[parts.length() - 1]).unwrap_or("image/webp")
  // 不在・許可待ち — 場所取りのまま
  let file = nested_file(binding.directory, parts, false) catch { _ => return }
  let url = @web.read_url(file, mime).wait() catch { _ => return }
  match self.urls.get(path) {
    Some(Some(old)) => @web.revoke_url(old)
    _ => ()
  }
  self.urls[path] = Some(url)
  self.live = true
  (self.deps.refresh)()
}

///|
/// ローカル画像の objectURL。まだ読めていなければ None（引きに行く）
pub fn Images::image_url(self : Images, path : String) -> String? {
  match self.urls.get(path) {
    Some(hit) => hit
    None => {
      self.urls[path] = None
      @web.spawn(async fn() { self.load_asset(path) })
      None
    }
  }
}

///|
/// 文書が入れ替わった。絵も握りも捨て、その場で引き直す
pub fn Images::clear(self : Images) -> Unit {
  self.release_urls()
  self.cached = None
  self.cached_known = false
  self.live = false
  // 捨てたその場で引き直す。`folder_name` は同期で答えるしかなく、
  // 「まだ引いていない」と「無い」を区別できない — 人が
  // メニューを開くより先に決着させて、嘘を言わせない
  @web.spawn(async fn() { self.stored_binding() |> ignore })
}

///|
/// いま結び付いている画像フォルダの名前。未設定なら None
pub fn Images::folder_name(self : Images) -> String? {
  self.cached.map(b => b.directory.name())
}

///|
/// いま画像が読めているか。**同期で答える** — 場所取りの字は描くたびに引かれるので、待てない
pub fn Images::readable(self : Images) -> Bool {
  self.live
}

///|
/// いま画像を読める状態か。**繋ぎ直しの箱を出すかの判定**。札を引き直し、許可まで見る
pub async fn Images::connected(self : Images) -> Bool {
  self.live = match self.stored_binding() {
    Some(b) => granted(b.directory, "read")
    None => false
  }
  self.live
}

///|
/// 繋ぎ直す。**札を持っているなら許可を聞くだけ**で済ませ、指し直しの
/// ピッカーは出さない — 場所はもう分かっているのに選ばせるのは、
/// 分かっていることを聞くのと同じ。札が無い / 断られたときだけ指してもらう
pub async fn Images::connect(self : Images) -> Unit {
  let ok = (async fn() -> Unit {
    match self.stored_binding() {
      Some(b) =>
        if @web.request_permission(b.directory.as_any(), "readwrite").wait() ==
          "granted" {
          self.live = true
          self.release_urls()
          (self.deps.refresh)()
          return
        }
      None => ()
    }
    match self.pick() {
      Some(p) => self.settle(p, false) |> ignore
      None => ()
    }
  })() catch {
    _ => (self.deps.failed)("Couldn't open the image folder")
  }
  ok
}

///|
/// フォルダを指してもらう。**繋ぎ直しも選び直しも同じ一手** —
/// 記録が無ければ宣言を決め、あって食い違えば直すか聞く（`settle`）。
/// 保存されているかの確認は呼ぶ側（App）が済ませている
pub async fn Images::choose_folder(self : Images) -> Unit {
  (async fn() -> Unit {
    match self.pick() {
      Some(p) => self.settle(p, false) |> ignore
      None => ()
    }
  })() catch {
    _ => (self.deps.failed)("Couldn't open the image folder")
  }
}

///|
/// フォルダの中に**既に在る**綴り（小文字・フォルダからの相対）。
///
/// 名前がぶつかると `createWritable` は黙って上書きする。押す前に言えるよう、
/// 箱を開く時点で 1 度だけ数える。数えられなくても、上書きの警告が出ない
/// だけで先へは進める
async fn taken(dir : @web.DirHandle) -> Set[String] {
  let out : Set[String] = Set([])
  async fn walk(d : @web.DirHandle, prefix : String) -> Unit {
    let entries = @core.array_from(@web.list_entries(d).wait())
    for e in entries {
      let name : String = e._get_by_index(0).cast()
      let sub = e._get_by_index(1)
      let path = prefix + name
      if @core.is_nullish(sub) {
        out.add(path.to_lower())
      } else {
        walk(sub.cast(), path + "/")
      }
    }
  }

  walk(dir, "") catch {
    _ => () // 数えられない — 警告が出ないだけ
  }
  out
}

///|
/// 画像を置き、md に書く相対パスを返す。取りやめ / 失敗は None
pub async fn Images::save_to_disk(self : Images, blob : @core.Any) -> String? {
  let ready = self.ensure_binding() catch {
    _ => {
      (self.deps.failed)("Couldn't open the image folder")
      return None
    }
  }
  guard ready is Some((binding, folder)) else { return None }
  // **どれの名前を聞かれているのかを、絵が言う。** 何枚も続けて落とした
  // ときは、字だけでは区別が付かない
  let shot = @web.object_url(blob)
  let here = taken(binding.directory)
  let name : @parts.Field = {
    value: @web.stamp(),
    check: Some(typed => image_name_problem(typed, here)),
  }
  // **分かっているところは字、分からないところだけ欄。** 位置が決まって
  // いれば（宣言、または計算できた）`./pics/` はただの字で、打てるのは名前だけ
  let place : @parts.Part = match folder {
    Some(f) => Blank(f)
    None => Text(self.declared_path())
  }
  let shape : Array[@parts.Part] = [
    Text("![]("),
    place,
    Blank(name),
    Text(".webp)"),
  ]
  let out = @parts.asked(self.doc, @parts.image_name(shape, shot))
  @web.revoke_url(shot)
  guard out is Some(values) else { return None }
  // 欄の並び順は `shape` の並び順。位置の欄があるなら先に居る
  let typed = match folder {
    Some(f) => {
      self.set_declared(values.get(0).unwrap_or(f.value))
      values.get(1).unwrap_or("")
    }
    None => values.get(0).unwrap_or("")
  }
  let parts = name_parts(typed)
  guard parts.last() is Some(last) else { return None }
  parts[parts.length() - 1] = last + ".webp"
  let written = (async fn() -> String {
    let webp = @web.to_webp(blob).wait()
    let file = nested_file(binding.directory, parts, true)
    @web.write_blob(file, webp).wait()
    let rel = self.declared_path() + parts.join("/")
    // 鍵はカード側が問い合わせてくる形（裸）に合わせる。md へ書くのは md_path の形（`./x`）
    let key = @tree.bare_path(rel)
    match self.urls.get(key) {
      Some(Some(old)) => @web.revoke_url(old)
      _ => ()
    }
    self.urls[key] = Some(@web.object_url(webp))
    md_path(rel)
  })() catch {
    _ => {
      // **触って失敗した握りは腐っている。** 抜かれた USB・消されたフォルダ
      // を掴んだまま持っていると、次も同じところで転ぶ
      (self.deps.failed)("Couldn't save the image")
      self.forget()
      return None
    }
  }
  Some(written)
}

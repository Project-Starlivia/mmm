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
// md への操作なので `host.set_declared` に渡す（App の `set_declared`）。
//
// 置き場と名前の柵（純粋）は path.mbt。

// ---- 握り ----

///|
/// 外に頼るもの（値と動詞）
pub(all) struct ImageHost {
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
/// いま握っているもの。**セッションの持ち物**で、覚えているのは札だけ（recent）。
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
  disk : Disk
  host : ImageHost
  /// path → objectURL。None は「引きに行ったが無い / まだ」
  urls : Map[String, String?]
  /// 握りの控え。None は「まだ引いていない」、Some(None) は「引いたが無い」
  mut cached : Binding??
  /// 直近に確かめた「読めているか」。描くたびに同期で聞かれるので覚えておく
  mut live : Bool
}

///|
pub fn Images::new(
  doc : @dom.Document,
  disk : Disk,
  host : ImageHost,
) -> Images {
  { doc, disk, host, urls: Map([]), cached: None, live: false, }
}

///|
/// 宣言が無いのは「md と同じ場所」。頭を持たない古い文書がそのまま読めるように、ここで倒す
fn Images::declared_path(self : Images) -> String {
  (self.host.declared)().unwrap_or("./")
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
  if self.cached is Some(b) {
    return b
  }
  // **札は文書ごと**（recent）。別の .md を開いても前の結び付きは残る
  let b = match self.disk.current_file() {
    Some(file) =>
      match self.disk.recent.folder_for(file) {
        Some(directory) => Some({ doc: file, directory, })
        None => None
      }
    None => None
  }
  self.cached = Some(b)
  b
}

///|
/// フォルダを指してもらい、握る。取りやめは None
async fn Images::pick(self : Images) -> Picked? {
  guard self.disk.current_file() is Some(file) else { return None }
  guard @web.can_choose_folder() else { return None }
  let picked = @web.pick_directory(file.as_any(), "readwrite").wait()
  guard !@core.is_nullish(picked) else { return None }
  let directory : @web.DirHandle = picked.cast()
  let binding : Binding = { doc: file, directory, }
  self.disk.recent.remember_folder(file, directory)
  self.cached = Some(Some(binding))
  self.live = true
  // 選んだフォルダが md を含んでいれば、md から見た位置は**計算できる**。
  // 含まなければ手がかりはフォルダ名だけ
  let segments : Array[String]? = @core.identity_option(
    @web.resolve_path(directory, file).wait(),
  )
  self.release_urls()
  (self.host.refresh)()
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
  (self.host.set_declared)(value)
  self.release_urls()
  (self.host.refresh)()
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
  match (self.host.declared)() {
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
  self.cached = Some(None)
  self.live = false
  match self.disk.current_file() {
    Some(file) =>
      @web.spawn(async fn() { self.disk.recent.forget_folder(file) })
    None => ()
  }
  self.release_urls()
  (self.host.refresh)()
}

///|
/// 触ってよいか。`ask` なら、まだなら（断られていても）聞き直す — 聞けるのは
/// 押した瞬間だけで、押されたことがその資格になる。`mode` は "read" / "readwrite"
async fn permission(h : @web.DirHandle, mode : String, ask~ : Bool) -> Bool {
  @web.query_permission(h.as_any(), mode).wait() == "granted" ||
  (ask && @web.request_permission(h.as_any(), mode).wait() == "granted")
}

///|
/// 書けるフォルダを用意する。握っていればそれ、無ければ指してもらう。
/// 返すのは「呼ぶ側のフォームに載せる位置の欄」（要らなければ None）。取りやめは None
async fn Images::ensure_binding(self : Images) -> (Binding, @parts.Field?)? {
  match self.stored_binding() {
    Some(binding) => {
      if permission(binding.directory, "readwrite", ask=true) {
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
  guard permission(binding.directory, "read", ask=false) else { return }
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
  (self.host.refresh)()
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
  self.live = false
  // 捨てたその場で引き直す。`folder_name` は同期で答えるしかなく、
  // 「まだ引いていない」と「無い」を区別できない — 人が
  // メニューを開くより先に決着させて、嘘を言わせない
  @web.spawn(async fn() { self.stored_binding() |> ignore })
}

///|
/// いま結び付いている画像フォルダの名前。未設定なら None
pub fn Images::folder_name(self : Images) -> String? {
  self.cached.bind(c => c).map(b => b.directory.name())
}

///|
/// 画像フォルダの状態の一言（帯の Files の見出し）。`name` は握っているフォルダの名前
/// （`folder_name`）、`declared` は頭の宣言。**言葉は宣言と許可の 2 つだけ**（冒頭）。
/// 許可が無いときは宣言のパスを出す — どこを指していて届いていないのかが
/// 見えないと、直しようがない
pub fn folder_caption(name : String?, declared : String?) -> String {
  match (name, declared) {
    (None, None) => "no folder"
    (None, Some(declared)) => declared + ", no access"
    (Some(name), Some(_)) => name
    (Some(name), None) => name + ", not declared"
  }
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
    Some(b) => permission(b.directory, "read", ask=false)
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
        if permission(b.directory, "readwrite", ask=true) {
          self.live = true
          self.release_urls()
          (self.host.refresh)()
          return
        }
      None => ()
    }
    match self.pick() {
      Some(p) => self.settle(p, false) |> ignore
      None => ()
    }
  })() catch {
    _ => (self.host.failed)("Couldn't open the image folder")
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
    _ => (self.host.failed)("Couldn't open the image folder")
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
    for e in @web.entries(d) {
      let path = prefix + e.name
      match e.directory {
        None => out.add(path.to_lower())
        Some(sub) => walk(sub, path + "/")
      }
    }
  }

  walk(dir, "") catch {
    _ => () // 数えられない — 警告が出ないだけ
  }
  out
}

///|
let webp_quality = 0.92

///|
/// 置く絵は webp。もう webp ならそのまま、違えば焼き直す — 焼けなければ拒む
/// （ブラウザが webp を書けないと、頼んだ種類と違う絵が黙って出る）
async fn as_webp(blob : @core.Any) -> @core.Any {
  guard @web.blob_type(blob) != "image/webp" else { return blob }
  let out = @web.convert(blob, "image/webp", webp_quality).wait()
  guard @web.blob_type(out) == "image/webp" else {
    fail("webp conversion failed")
  }
  out
}

///|
/// 画像を置き、md に書く相対パスを返す。取りやめ / 失敗は None
pub async fn Images::save_to_disk(self : Images, blob : @core.Any) -> String? {
  let ready = self.ensure_binding() catch {
    _ => {
      (self.host.failed)("Couldn't open the image folder")
      return None
    }
  }
  guard ready is Some((binding, folder)) else { return None }
  // **どれの名前を聞かれているのかを、絵が言う。** 何枚も続けて落とした
  // ときは、字だけでは区別が付かない
  let shot = @web.object_url(blob)
  let here = taken(binding.directory)
  let name : @parts.Field = {
    value: stamp(@web.local_time(@web.now())),
    check: Some(typed => image_name_problem(typed, here)),
  }
  let (shape, read) = image_form(folder, self.declared_path(), name)
  let out = @parts.asked(self.doc, @parts.image_name(shape, shot))
  @web.revoke_url(shot)
  guard out is Some(values) else { return None }
  let (place, typed) = read(values)
  match place {
    Some(p) => self.set_declared(p)
    None => ()
  }
  let parts = name_parts(typed)
  guard parts.last() is Some(last) else { return None }
  parts[parts.length() - 1] = last + ".webp"
  let written = (async fn() -> String {
    let webp = as_webp(blob)
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
      (self.host.failed)("Couldn't save the image")
      self.forget()
      return None
    }
  }
  Some(written)
}

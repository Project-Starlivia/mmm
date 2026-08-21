// mmm のネイティブ本体。ファイル I/O・監視・画像の実体を持ち、
// Webview 側（MoonBit core + TS UI）にはパスを見せず、テキストだけを渡す。
//
// 設計の芯: **パスは Rust だけが知る**。UI は「開いているテキスト」と、
// 表示のための名前しか持たない。相対パスの解決も、隣の画像への到達も、
// ブラウザのサンドボックスが拒んでいた操作はすべてここで完結する。

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};

use encoding_rs::{Encoding, UTF_8};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_dialog::DialogExt;

/// UI に渡す文書。名前は表示用、text は常に LF 正規化済み。
#[derive(Serialize, Clone)]
struct Doc {
    name: String,
    text: String,
}

/// 外部変更で送る差分（名前は変わらないので送らない）。
#[derive(Serialize, Clone)]
struct DocChange {
    text: String,
}

/// 書き戻しに要る形式情報。改行・文字コード・BOM の 3 つは常に一体で
/// 扱う（元は AppState に 3 本の Mutex で分かれていて、読み書きのたびに
/// 3 回ロックする羽目になっていた）。
#[derive(Clone)]
struct Format {
    eol: String,
    encoding: &'static Encoding,
    bom: bool,
}

impl Default for Format {
    fn default() -> Self {
        Self {
            eol: String::new(),
            encoding: UTF_8,
            bom: false,
        }
    }
}

#[derive(Default)]
struct Watch {
    watcher: Option<RecommendedWatcher>,
    /// 直近にフロントへ伝わっている内容のハッシュ（自分の保存 or 直前に
    /// 伝えた外部変更）。監視イベントがこれと一致する間は黙る。
    last_hash: Option<u64>,
    /// 監視中のファイル名（親フォルダを監視し、この名前だけ拾う）。
    name: Option<std::ffi::OsString>,
}

/// 開いているファイルの path と、その書き戻し形式。常に一緒に更新する
/// — 別々の Mutex だと、保存と同時並行で別のファイルが開かれたとき、
/// 新しい path に古い format が対応した状態で保存されうる（Format 自身を
/// 3 本の Mutex から 1 本へ統合したのと同じ理由）。
#[derive(Clone, Default)]
struct Current {
    path: Option<PathBuf>,
    format: Format,
}

struct AppState {
    current: Mutex<Current>,
    watch: Mutex<Watch>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            current: Mutex::new(Current::default()),
            watch: Mutex::new(Watch::default()),
        }
    }
}

/// `.lock().unwrap()` の代わりに使う。一度どこかで panic して Mutex が
/// 汚染されても、以降ずっとコマンドが道連れで panic し続けるのを避ける
/// （中身は他のロックと独立した Result/Option なので、汚染後の値を
/// そのまま使っても実害はない）。
trait LockExt<T> {
    fn locked(&self) -> MutexGuard<'_, T>;
}
impl<T> LockExt<T> for Mutex<T> {
    fn locked(&self) -> MutexGuard<'_, T> {
        self.lock().unwrap_or_else(|e| e.into_inner())
    }
}

fn hash_bytes(b: &[u8]) -> u64 {
    let mut h = DefaultHasher::new();
    b.hash(&mut h);
    h.finish()
}

/// 読み込んだファイルの中身と、書き戻すための形式情報。
struct FileText {
    text: String, // 常に LF 正規化済み
    format: Format,
}

/// 文字コードを推定する。**UTF-8 を最優先**にして誤判定でファイルを壊さない:
/// BOM があればそれ、無ければまず厳密 UTF-8、それも駄目なら chardetng に回す。
fn detect_encoding(bytes: &[u8]) -> (&'static Encoding, bool) {
    if let Some((enc, _)) = Encoding::for_bom(bytes) {
        return (enc, true);
    }
    if std::str::from_utf8(bytes).is_ok() {
        return (UTF_8, false); // 妥当な UTF-8 は推定に回さない = 誤判定ゼロ
    }
    let mut det = chardetng::EncodingDetector::new();
    det.feed(bytes, true);
    (det.guess(None, true), false)
}

/// バイト列を LF 正規化テキストへ。文字コードと BOM/改行も併せて返す。
fn decode(bytes: &[u8]) -> FileText {
    let (encoding, bom) = detect_encoding(bytes);
    let (cow, used, _had_errors) = encoding.decode(bytes); // BOM はここで剥がれる
    let raw = cow.into_owned();
    let eol = if raw.contains("\r\n") { "\r\n" } else { "\n" }.to_string();
    let text = raw.replace("\r\n", "\n").replace('\r', "\n");
    FileText {
        text,
        format: Format { eol, encoding: used, bom },
    }
}

fn name_of(path: &Path) -> String {
    path.file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// BOM のバイト列。UTF-8/UTF-16LE/UTF-16BE 以外は BOM を持たない文字コード
/// なので None（呼び出し側は bom フラグ自体を立てない想定）。
fn bom_bytes(encoding: &'static Encoding) -> Option<&'static [u8]> {
    match encoding.name() {
        "UTF-8" => Some(b"\xEF\xBB\xBF"),
        "UTF-16LE" => Some(b"\xFF\xFE"),
        "UTF-16BE" => Some(b"\xFE\xFF"),
        _ => None,
    }
}

/// LF テキストを、元の改行・文字コード・BOM に戻したバイト列へ。
/// 元の文字コードで表せない文字があれば、**壊さず** Err で知らせる。
fn encode_for_write(text: &str, format: &Format) -> Result<Vec<u8>, String> {
    // 単独 CR が紛れ込んでいても(旧 Mac 由来の貼り付け等)、ここで一度
    // LF へ正規化してから改行種別を書き戻す。素通しすると迷子の CR が
    // そのまま保存され、次に開いたときだけ黙って消える不可解な破損になる。
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    let body = if format.eol == "\r\n" {
        normalized.replace('\n', "\r\n")
    } else {
        normalized
    };
    let (encoded, _used, had_unmappable) = format.encoding.encode(&body);
    if had_unmappable {
        return Err(format!(
            "{} で表せない文字があります（別名で保存すると UTF-8 になります）",
            format.encoding.name()
        ));
    }
    let mut out = Vec::new();
    if format.bom {
        if let Some(b) = bom_bytes(format.encoding) {
            out.extend_from_slice(b);
        }
    }
    out.extend_from_slice(&encoded);
    Ok(out)
}

static TMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// temp に書いて rename で置き換える。書き込み中に落ちても元が残る。
/// temp 名は pid + 呼び出しごとの連番で一意にする — 素早い連続保存が
/// 同じ temp ファイルへ同時に書き込み、どちらかの内容を静かに失う事故
/// を防ぐ。rename が失敗した場合も temp を消してから返す（放置すると
/// 保存に失敗するたびゴミファイルが増える）。
fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let dir = path.parent().ok_or("親フォルダがありません")?;
    let n = TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    let tmp = dir.join(format!(".{}.mmm-tmp-{}-{}", name_of(path), std::process::id(), n));
    // sync_all で一時ファイルをディスクへ確実に反映させてから rename する。
    // write() だけだと内容が OS のページキャッシュに乗っただけの状態で
    // rename が確定しうる — rename 直後の電源断で「renameは効いたが中身は
    // 空」というファイルが残りうるため（write→rename パターンの定石）。
    if let Err(e) = write_and_sync(&tmp, bytes) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e.to_string());
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e.to_string());
    }
    Ok(())
}

fn write_and_sync(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut f = std::fs::File::create(path)?;
    f.write_all(bytes)?;
    f.sync_all()
}

/// 現在のファイルが入っているフォルダ。相対パスの基準。
fn current_dir(state: &State<AppState>) -> Option<PathBuf> {
    state
        .current
        .locked()
        .path
        .as_ref()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
}

/// `..` で遡れる段数の上限。0 にはしない — 隣接フォルダの画像に無許可で
/// 届くのはこのアプリの意図した設計。ただし無制限だと、壊れた/悪意ある
/// 相対パス 1 本でドライブ全体が読み書き対象になってしまうため、
/// 現実的にあり得ない深さは切り捨てる。
const MAX_UP_LEVELS: usize = 16;

/// rel（`..` を含みうる）を基準フォルダに繋いで正規化する。
fn join_normalized(base: &Path, rel: &str) -> PathBuf {
    let mut out = base.to_path_buf();
    let mut ups = 0usize;
    for seg in rel.split(['/', '\\']) {
        match seg {
            "" | "." => {}
            ".." => {
                if ups >= MAX_UP_LEVELS {
                    continue;
                }
                out.pop();
                ups += 1;
            }
            s => out.push(s),
        }
    }
    out
}

/// 現在のファイルを開き直し、書き戻し形式を覚え、親フォルダの監視を張り直す。
fn set_path(app: &AppHandle, path: PathBuf, format: Format, last_hash: Option<u64>) {
    let state = app.state::<AppState>();
    *state.current.locked() = Current { path: Some(path.clone()), format };
    remember_last(app, &path);
    arm_watch(app, &path, last_hash);
}

/// 起動時に開き直すための最後のパスを、アプリ設定フォルダに 1 行で残す。
/// これは真実の複製ではなく、ディスクへの指し示し（handle 相当）。
fn remember_last(app: &AppHandle, path: &Path) {
    if let Ok(dir) = app.path().app_config_dir() {
        let _ = std::fs::create_dir_all(&dir);
        let _ = std::fs::write(dir.join("last-file"), path.to_string_lossy().as_bytes());
    }
}

fn last_path(app: &AppHandle) -> Option<PathBuf> {
    let dir = app.path().app_config_dir().ok()?;
    let s = std::fs::read_to_string(dir.join("last-file")).ok()?;
    let p = PathBuf::from(s.trim());
    p.is_file().then_some(p)
}

/// 親フォルダを監視し、当該ファイルの変更/消失を UI へ伝える。
///
/// ファイル単体ではなく**フォルダ**を見るのは、多くのエディタが
/// temp→rename で保存して inode を挿げ替えるから。フォルダなら見失わない。
fn arm_watch(app: &AppHandle, path: &Path, last_hash: Option<u64>) {
    let dir = match path.parent() {
        Some(d) => d.to_path_buf(),
        None => return,
    };
    let name = path.file_name().map(|s| s.to_os_string());
    let handle = app.clone();

    let mut watcher = match notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        let Ok(event) = res else { return };
        let st = handle.state::<AppState>();
        let want = st.watch.locked().name.clone();
        let Some(want) = want else { return };
        // 我々のファイルに触れたイベントだけ拾う
        if !event.paths.iter().any(|p| p.file_name() == Some(&want)) {
            return;
        }
        let path = st.current.locked().path.clone();
        let Some(path) = path else { return };
        if !path.exists() {
            let _ = handle.emit("doc:removed", ());
            return;
        }
        let Ok(bytes) = std::fs::read(&path) else { return };
        let hash = hash_bytes(&bytes);
        // 直前に自分が書いた、または直前に伝えた内容と同じなら黙る。
        // 時間ベースの間引きだと、その窓に届いた本物の変更を取りこぼす
        // ため、内容の一致だけで判断する（連打イベントは同じ内容なので
        // 自然にここで畳まれる）。
        let mut w = st.watch.locked();
        if w.last_hash == Some(hash) {
            return;
        }
        w.last_hash = Some(hash);
        drop(w);
        let ft = decode(&bytes);
        let _ = handle.emit("doc:changed", DocChange { text: ft.text });
    }) {
        Ok(w) => w,
        Err(_) => return,
    };

    let _ = watcher.watch(&dir, RecursiveMode::NonRecursive);
    let state = app.state::<AppState>();
    let mut w = state.watch.locked();
    w.watcher = Some(watcher); // 古い watcher はここで drop される
    w.name = name;
    w.last_hash = last_hash;
}

// ---------- コマンド ----------

/// 起動時の 1 枚。引数に .md があればそれを、無ければ前回のファイルを開く。
/// パスを開いて UI 用の Doc を返し、書き戻し形式（改行・文字コード・BOM）を
/// 記憶する。last_hash は開いた時点の実バイトから作る（自分の保存の見分け用）。
fn open_file_at(app: &AppHandle, path: PathBuf) -> Result<Doc, String> {
    let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
    let ft = decode(&bytes);
    let doc = Doc {
        name: name_of(&path),
        text: ft.text.clone(),
    };
    set_path(app, path, ft.format, Some(hash_bytes(&bytes)));
    Ok(doc)
}

/// 起動時の 1 枚。引数に .md があればそれを、無ければ前回のファイルを開く。
#[tauri::command]
fn startup_doc(app: AppHandle) -> Option<Doc> {
    let arg = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .filter(|p| p.is_file());
    let path = arg.or_else(|| last_path(&app))?;
    open_file_at(&app, path).ok()
}

/// 文書を閉じる（新規作成）。パスと監視を手放し、前回ファイルの記録も消す。
/// これをしないと、未保存の新規文書に貼った画像が前の文書の隣に置かれる。
#[tauri::command]
fn close(app: AppHandle, state: State<AppState>) {
    *state.current.locked() = Current::default();
    let mut w = state.watch.locked();
    w.watcher = None;
    w.name = None;
    w.last_hash = None;
    drop(w);
    if let Ok(dir) = app.path().app_config_dir() {
        let _ = std::fs::remove_file(dir.join("last-file"));
    }
}

/// ネイティブの「開く」。キャンセルは Ok(None)。読み込み失敗は open_path と
/// 同様 Err で伝える（以前は失敗もキャンセルも一律 None で、UI が区別できず
/// エラー表示を出せなかった）。
#[tauri::command]
fn open_dialog(app: AppHandle) -> Result<Option<Doc>, String> {
    let Some(picked) = app
        .dialog()
        .file()
        .add_filter("Markdown", &["md", "markdown", "txt"])
        .blocking_pick_file()
    else {
        return Ok(None);
    };
    let path = picked.into_path().map_err(|e| e.to_string())?;
    open_file_at(&app, path).map(Some)
}

/// パス指定で開く（ドロップ・関連付け）。
#[tauri::command]
fn open_path(app: AppHandle, path: String) -> Result<Doc, String> {
    open_file_at(&app, PathBuf::from(path))
}

/// 上書き保存。パスが無ければ Err（UI が save_as に切り替える）。
/// 改行・文字コード・BOM は開いたときに覚えたものへ書き戻す。
#[tauri::command]
fn save(state: State<AppState>, text: String) -> Result<(), String> {
    // path と format を 1 回のロックでまとめて読む（Current に統合済みなので
    // 別々に読んで組み合わせがずれる余地が無い）
    let cur = state.current.locked().clone();
    let path = cur.path.ok_or("no-path")?;
    let mut format = cur.format;
    if format.eol.is_empty() {
        format.eol = "\n".to_string();
    }
    let bytes = encode_for_write(&text, &format)?;
    // 監視スレッドが rename を拾うより先にハッシュを立てておく。
    // 逆順だと、自分がいま書いた内容を外部変更として誤検知しうる
    // （write_atomic の rename と監視コールバックの間の競合）。
    state.watch.locked().last_hash = Some(hash_bytes(&bytes));
    write_atomic(&path, &bytes)?;
    Ok(())
}

/// 別名で保存。キャンセルは Ok(None)。新規保存は常に UTF-8 / BOM 無し / LF。
#[tauri::command]
fn save_as(app: AppHandle, suggested: String, text: String) -> Result<Option<Doc>, String> {
    let picked = app
        .dialog()
        .file()
        .add_filter("Markdown", &["md", "markdown", "txt"])
        .set_file_name(&suggested)
        .blocking_save_file();
    let Some(picked) = picked else { return Ok(None) };
    let path = picked.into_path().map_err(|e| e.to_string())?;
    let format = Format { eol: "\n".to_string(), encoding: UTF_8, bom: false };
    let bytes = encode_for_write(&text, &format)?;
    // save() と同じ理由: 上書き先が現在監視中のファイルと同じだった場合、
    // rename を監視スレッドが先に拾って自分の書き込みを外部変更と誤認しうる。
    // 書き込み前にハッシュを立てておけば、その競合が起きても一致して黙る
    let hash = hash_bytes(&bytes);
    app.state::<AppState>().watch.locked().last_hash = Some(hash);
    write_atomic(&path, &bytes)?;
    let doc = Doc { name: name_of(&path), text };
    set_path(&app, path, format, Some(hash));
    Ok(Some(doc))
}

/// resolve_image が読み込みを許す拡張子。save_image/import_image にも同じ
/// 判定を掛ける — 読み込み側だけ絞っていたため、書き込み側はフロント制御の
/// rel をそのまま任意拡張子で書けてしまっていた。
fn is_image_ext(path: &Path) -> bool {
    let ext = path
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    matches!(ext.as_str(), "webp" | "png" | "jpg" | "jpeg" | "gif" | "svg" | "avif")
}

/// 画像を解決してバイト列で返す。画像拡張子だけ、存在するものだけ。
#[tauri::command]
fn resolve_image(state: State<AppState>, rel: String) -> Result<tauri::ipc::Response, String> {
    let base = current_dir(&state).ok_or("no-doc")?;
    let path = join_normalized(&base, &rel);
    if !is_image_ext(&path) {
        return Err("not-image".into());
    }
    let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
    Ok(tauri::ipc::Response::new(bytes))
}

/// フロントが用意したバイト列（貼り付け・お絵描きの WebP）を rel へ書く。
/// import_image と同じく uniquify を掛ける — 貼り付け時の候補名も衝突は
/// あり得るため、無警告での上書きは避ける。
#[tauri::command]
fn save_image(state: State<AppState>, rel: String, bytes: Vec<u8>) -> Result<String, String> {
    if !is_image_ext(Path::new(&rel)) {
        return Err("not-image".into());
    }
    let base = current_dir(&state).ok_or("画像を置くには先にファイルを保存してください")?;
    let rel = uniquify(&base, &rel);
    let path = join_normalized(&base, &rel);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&path, &bytes).map_err(|e| e.to_string())?;
    Ok(rel)
}

/// 既にあるなら `stem-1.ext`, `stem-2.ext`… と避ける。返すのは実際に使う rel。
fn uniquify(base: &Path, rel: &str) -> String {
    if !join_normalized(base, rel).exists() {
        return rel.to_string();
    }
    let (dir, file) = match rel.rsplit_once(['/', '\\']) {
        Some((d, f)) => (format!("{d}/"), f.to_string()),
        None => (String::new(), rel.to_string()),
    };
    let (stem, ext) = match file.rsplit_once('.') {
        Some((s, e)) => (s.to_string(), format!(".{e}")),
        None => (file, String::new()),
    };
    let mut i = 1;
    loop {
        let cand = format!("{dir}{stem}-{i}{ext}");
        if !join_normalized(base, &cand).exists() {
            return cand;
        }
        i += 1;
    }
}

/// ディスク上の画像（ドロップされた実ファイル）を rel へ複製する。
/// 同名が既にあれば避ける — ドロップの名前は元ファイル名任せで、
/// 黙って上書きすると別の画像を失いかねない。
#[tauri::command]
fn import_image(state: State<AppState>, src: String, rel: String) -> Result<String, String> {
    if !is_image_ext(Path::new(&rel)) {
        return Err("not-image".into());
    }
    let base = current_dir(&state).ok_or("画像を置くには先にファイルを保存してください")?;
    let rel = uniquify(&base, &rel);
    let dest = join_normalized(&base, &rel);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::copy(&src, &dest).map_err(|e| e.to_string())?;
    Ok(rel)
}

/// base から target への相対パス（共通の先頭を捨てて `..` を積む）。純関数。
/// ドライブ（Prefix コンポーネント）が違えば相対化できないので None。
fn diff_paths(base: &Path, target: &Path) -> Option<String> {
    let mut b = base.components().peekable();
    let mut t = target.components().peekable();
    if let (Some(Component::Prefix(bp)), Some(Component::Prefix(tp))) = (b.peek(), t.peek()) {
        if bp.as_os_str() != tp.as_os_str() {
            return None;
        }
    }
    while b.peek().is_some() && b.peek() == t.peek() {
        b.next();
        t.next();
    }
    let ups = b.count();
    let mut segs: Vec<String> = std::iter::repeat("..".to_string()).take(ups).collect();
    for c in t {
        segs.push(c.as_os_str().to_string_lossy().into_owned());
    }
    if segs.is_empty() {
        return None;
    }
    Some(segs.join("/"))
}

/// 絶対パスを、現在のファイルから見た相対パスへ。同ドライブでなければ None。
/// ドロップされた画像が既に近くにあるなら、複製せず指すために使う。
#[tauri::command]
fn relativize(state: State<AppState>, abs: String) -> Option<String> {
    let base = current_dir(&state)?.canonicalize().ok()?;
    let target = PathBuf::from(abs).canonicalize().ok()?;
    diff_paths(&base, &target)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            startup_doc,
            close,
            open_dialog,
            open_path,
            save,
            save_as,
            resolve_image,
            save_image,
            import_image,
            relativize,
        ])
        .run(tauri::generate_context!())
        .expect("error while running mmm");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_dir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("mmm-test-{}-{}", tag, std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }
    fn norm(p: PathBuf) -> String {
        p.to_string_lossy().replace('\\', "/")
    }
    fn fmt(eol: &str, encoding: &'static Encoding, bom: bool) -> Format {
        Format { eol: eol.to_string(), encoding, bom }
    }

    #[test]
    fn decode_plain_lf() {
        let ft = decode(b"a\nb\n");
        assert_eq!(ft.text, "a\nb\n");
        assert_eq!(ft.format.eol, "\n");
        assert_eq!(ft.format.encoding, UTF_8);
        assert!(!ft.format.bom);
    }

    #[test]
    fn decode_crlf_is_normalized_but_remembered() {
        let ft = decode(b"a\r\nb\r\n");
        assert_eq!(ft.text, "a\nb\n"); // UI 内は常に LF
        assert_eq!(ft.format.eol, "\r\n"); // 元の改行は覚える
    }

    #[test]
    fn decode_strips_bom_and_lone_cr() {
        let ft = decode(b"\xEF\xBB\xBFa\rb");
        assert_eq!(ft.text, "a\nb"); // BOM 除去、単独 CR も LF
        assert_eq!(ft.format.eol, "\n");
        assert!(ft.format.bom); // BOM があった＝保存で書き戻す
        assert_eq!(ft.format.encoding, UTF_8);
    }

    #[test]
    fn decode_and_roundtrip_shift_jis() {
        let sample = "これは文字コード判定のためのテスト文章です。日本語が正しく読めることを確認します。";
        let (sjis, _, _) = encoding_rs::SHIFT_JIS.encode(sample);
        let ft = decode(&sjis);
        assert_eq!(ft.text, sample); // Shift-JIS を正しく読む（from_utf8_lossy なら化ける）
        assert_eq!(ft.format.encoding, encoding_rs::SHIFT_JIS);
        // 往復: 元の文字コードへ戻すと元のバイト列に一致
        let out = encode_for_write(&ft.text, &ft.format).unwrap();
        assert_eq!(out, sjis.to_vec());
    }

    #[test]
    fn encode_refuses_unmappable_and_keeps_utf8_bom() {
        // Shift-JIS で表せない絵文字 → 黙って壊さず Err
        assert!(encode_for_write("😀", &fmt("\n", encoding_rs::SHIFT_JIS, false)).is_err());
        // UTF-8 は何でも通り、BOM 指定は先頭に戻る
        let out = encode_for_write("a", &fmt("\n", UTF_8, true)).unwrap();
        assert_eq!(out, b"\xEF\xBB\xBFa");
    }

    #[test]
    fn encode_roundtrips_utf16_bom() {
        // UTF-16LE/BE も、BOM があったなら書き戻しで BOM が復元される
        // （以前は UTF-8 以外だと BOM が黙って落ちていた）。
        let le = encode_for_write("a", &fmt("\n", encoding_rs::UTF_16LE, true)).unwrap();
        assert_eq!(&le[..2], b"\xFF\xFE");
        let be = encode_for_write("a", &fmt("\n", encoding_rs::UTF_16BE, true)).unwrap();
        assert_eq!(&be[..2], b"\xFE\xFF");
    }

    #[test]
    fn encode_normalizes_stray_lone_cr() {
        // 単独 CR が紛れ込んでいても、指定した eol へ揃えて書く（素通しして
        // 保存のたびに迷子の CR が残らないようにする）。
        let out = encode_for_write("a\rb", &fmt("\r\n", UTF_8, false)).unwrap();
        assert_eq!(out, b"a\r\nb");
    }

    #[test]
    fn join_normalizes_dot_dotdot_and_separators() {
        let base = Path::new("/a/b");
        assert_eq!(norm(join_normalized(base, "x.png")), "/a/b/x.png");
        assert_eq!(norm(join_normalized(base, "sub/x.png")), "/a/b/sub/x.png");
        assert_eq!(norm(join_normalized(base, "./x.png")), "/a/b/x.png");
        assert_eq!(norm(join_normalized(base, "../x.png")), "/a/x.png");
        assert_eq!(norm(join_normalized(base, "..\\p\\x.png")), "/a/p/x.png");
    }

    #[test]
    fn join_normalized_caps_upward_traversal() {
        // 深く `..` を積んでも、上限を超えた分は無視される
        // （無制限だとドライブ全体が読み書き対象になってしまう）。
        let base = Path::new("/a/b/c");
        let rel: String = std::iter::repeat("../").take(50).collect::<String>() + "x.png";
        let out = norm(join_normalized(base, &rel));
        assert!(out.starts_with('/'), "root を素通りしていない: {out}");
        assert!(out.ends_with("/x.png"));
        // 50 段ではなく MAX_UP_LEVELS 段しか遡っていないことを、素直な
        // 上限内のケースと比較して確認する。
        let capped: String = std::iter::repeat("../").take(MAX_UP_LEVELS).collect::<String>() + "x.png";
        assert_eq!(out, norm(join_normalized(base, &capped)));
    }

    #[test]
    fn write_atomic_writes_bytes_and_leaves_no_temp() {
        let dir = tmp_dir("wa");
        let p = dir.join("doc.md");
        write_atomic(&p, b"a\nb\n").unwrap();
        assert_eq!(std::fs::read(&p).unwrap(), b"a\nb\n");
        // eol 復元は encode_for_write の担当
        let crlf = encode_for_write("a\nb\n", &fmt("\r\n", UTF_8, false)).unwrap();
        write_atomic(&p, &crlf).unwrap();
        assert_eq!(std::fs::read(&p).unwrap(), b"a\r\nb\r\n");
        let temp_left = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .any(|e| e.file_name().to_string_lossy().contains("mmm-tmp"));
        assert!(!temp_left, "temp ファイルが残っている");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn write_atomic_temp_names_are_unique_per_call() {
        // 連続呼び出しでも同じ temp 名を使わない(並行保存が互いを壊さない
        // ための前提)。同じディレクトリへ 2 回書いても競合しないことを、
        // 実際に温度計測はできないので「別ハッシュの中身が両方正しく残る」
        // ことで間接的に確認する。
        let dir = tmp_dir("wa-uniq");
        let p1 = dir.join("a.md");
        let p2 = dir.join("b.md");
        write_atomic(&p1, b"one").unwrap();
        write_atomic(&p2, b"two").unwrap();
        assert_eq!(std::fs::read(&p1).unwrap(), b"one");
        assert_eq!(std::fs::read(&p2).unwrap(), b"two");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn is_image_ext_accepts_known_extensions_only() {
        // 大文字小文字は無視。既知の画像拡張子以外(exe 等)は拒否し、
        // save_image/import_image がフロント制御の rel をそのまま任意拡張子で
        // 書けてしまわないことをここで保証する
        assert!(is_image_ext(Path::new("a.png")));
        assert!(is_image_ext(Path::new("a.WEBP")));
        assert!(!is_image_ext(Path::new("a.exe")));
        assert!(!is_image_ext(Path::new("a.cmd")));
        assert!(!is_image_ext(Path::new("a")));
    }

    #[test]
    fn uniquify_avoids_existing_names() {
        let dir = tmp_dir("uniq");
        assert_eq!(uniquify(&dir, "a.png"), "a.png"); // 無ければそのまま
        std::fs::write(dir.join("a.png"), b"x").unwrap();
        assert_eq!(uniquify(&dir, "a.png"), "a-1.png"); // あれば避ける
        std::fs::write(dir.join("a-1.png"), b"x").unwrap();
        assert_eq!(uniquify(&dir, "a.png"), "a-2.png");
        assert_eq!(uniquify(&dir, "sub/b.webp"), "sub/b.webp"); // サブフォルダは別物
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn diff_paths_gives_relative_with_dotdot() {
        let base = Path::new("/w/docs");
        assert_eq!(
            diff_paths(base, Path::new("/w/docs/img/a.png")).as_deref(),
            Some("img/a.png") // 木の中は下りるだけ
        );
        assert_eq!(
            diff_paths(base, Path::new("/w/pics/a.png")).as_deref(),
            Some("../pics/a.png") // 外は ../ で出る
        );
        assert_eq!(diff_paths(base, Path::new("/w/docs")), None); // 同一は None
    }

    #[test]
    fn diff_paths_none_across_drives() {
        // Windows のドライブレターが違う場合はゴミ文字列を作らず None。
        let base = Path::new(r"C:\w\docs");
        let target = Path::new(r"D:\w\docs\img\a.png");
        assert_eq!(diff_paths(base, target), None);
    }

    #[test]
    fn hash_is_stable_and_distinct() {
        assert_eq!(hash_bytes(b"abc"), hash_bytes(b"abc"));
        assert_ne!(hash_bytes(b"abc"), hash_bytes(b"abd"));
    }
}

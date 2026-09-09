// 文書の名前。
//
// 名前は状態ではなく**導出**する。保存したファイルには名前があるのでそれを
// 名乗り、まだ無いなら本文の見出しから作る。「無題」という状態変数を持たない
// ので、`# 設計メモ` と打った瞬間からその文書は設計メモと呼ばれる。
//
// 表示にも、保存ダイアログの初期値にも同じものを使う。道具が出す提案は
// **常にファイル名として有効**であること（失敗してから拾いにいかない）。

///|
/// 見出しが無い / 整形して何も残らない文書の名前
pub let empty_name = "empty"

///|
/// 実際の上限は 255（ext4/APFS はバイト、NTFS は UTF-16 単位）。バイトで
/// 測っておけばどれも満たす。`.md` の 3 バイトを残して 250 で打ち切る。
/// 日本語で 83 文字ぶんあり、**普段は誰も触らない安全柵**であって、
/// 見た目を整えるためのものではない
let max_bytes = 250

///|
/// ファイル名に使えない字（いちばん厳しい Windows に合わせる）と制御文字。
/// パス区切りもここに含むので、名前が勝手に階層を作ることはない
fn bad(c : Char) -> Bool {
  match c {
    '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => true
    _ => c.to_int() < 0x20
  }
}

///|
/// UTF-8 で何バイトか
fn utf8_len(c : Char) -> Int {
  let n = c.to_int()
  if n < 0x80 {
    1
  } else if n < 0x800 {
    2
  } else if n < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// 上限を超えないところまで、文字の境界で切る（サロゲートペアを割らない）
fn clamp_bytes(s : String, max : Int) -> String {
  let out = StringBuilder()
  let mut n = 0
  for c in s.iter() {
    let w = utf8_len(c)
    if n + w > max {
      break
    }
    out.write_char(c)
    n += w
  }
  out.to_string()
}

///|
/// MS-DOS 由来の予約名。拡張子を付けても予約のままなので `CON.md` も作れない
fn reserved(s : String) -> Bool {
  let l = s.to_lower()
  match l {
    "con" | "prn" | "aux" | "nul" => true
    _ =>
      l.length() == 4 &&
      (l.has_prefix("com") || l.has_prefix("lpt")) &&
      l[3] >= '1' &&
      l[3] <= '9'
  }
}

///|
/// 末尾の `.` と空白を落とす（Windows は黙って落とすので、こちらで先に落とす）
fn trim_tail(s : String) -> String {
  let mut end = s.length()
  while end > 0 && (s[end - 1] == '.' || s[end - 1] == ' ') {
    end -= 1
  }
  String::unsafe_substring(s, start=0, end~)
}

///|
/// ラベルをファイル名にする。使えない字で分けて `-` で繋ぐので、
/// `設計/検討` は `設計-検討`、`A: B` は `A-B` になる（空白はそのまま。
/// ファイル名として正しいものを削る理由が無い）。
/// 何も残らなければ空文字を返す — 呼び出し側が次の候補へ落ちる
pub fn to_file_name(label : String) -> String {
  let parts : Array[String] = []
  let cur = StringBuilder()
  let flush = () => {
    let s = cur.to_string().trim(chars=" ").to_owned()
    if s != "" {
      parts.push(s)
    }
    cur.reset()
  }
  for c in label.iter() {
    if bad(c) {
      flush()
    } else {
      cur.write_char(c)
    }
  }
  flush()
  let cut = trim_tail(clamp_bytes(parts.join("-"), max_bytes))
  if reserved(cut) {
    cut + "_"
  } else {
    cut
  }
}

///|
/// まだ保存していない文書の名前（拡張子なし）。
/// 最初の木の根を使う（View では根がいちばん大きい見出しで、木は文書順に
/// 並ぶ）。Implicit（label 無し）は空と同じ。整形して何も残らなければ empty
pub fn Survey::name(self : Survey) -> String {
  guard self.doc.roots.get(0) is Some(first) else { return empty_name }
  let name = to_file_name(first.node.label)
  if name == "" {
    empty_name
  } else {
    name
  }
}

///|
/// 文書の拡張子。開く・保存の絞り込みと、ダウンロード名の元を作るところが共に使う
pub let md_exts : Array[String] = [".md", ".markdown", ".txt"]

///|
/// 文書の名前か（拡張子で見る。大文字小文字は問わない）
pub fn is_markdown(name : String) -> Bool {
  let lower = name.to_lower()
  md_exts.any(ext => lower.has_suffix(ext))
}

///|
/// 拡張子を落とした名前。落として空なら `mmm`
pub fn bare(name : String) -> String {
  let lower = name.to_lower()
  for ext in md_exts {
    if lower.has_suffix(ext) {
      let cut = name.char_length() - ext.char_length()
      let out = String::unsafe_substring(name, start=0, end=cut)
      return if out == "" { "mmm" } else { out }
    }
  }
  if name == "" {
    "mmm"
  } else {
    name
  }
}

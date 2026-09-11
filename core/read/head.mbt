// 文書の頭（YAML frontmatter）に置く設定。
//
// **宣言の持ち主は .md 自身**。以前は window.prompt で聞いて IndexedDB に
// 置いていたので、別マシンで開くと「その md の画像がどこにあるか」だけが
// 消えていた（実体はただの .md、と言い切っているのに）。
//
// 「どこからどこまでが頭か」は読み（`View.frontmatter`）が答える。
// ここが答えるのは、その中の 1 行の綴りと、その 1 行を書き換える編集だけ。
//
// **YAML パーサは入れない。** 読んで書き戻すと、他ツールが書いたコメント・
// 引用符・キーの順序が消える。読むのは 1 キー、書くのも 1 行。

///|
/// 頭に置く「画像フォルダの場所」の設定名。**綴りはここ 1 つ**
let image_folder_key = "image-folder"

///|
/// トップレベルのキーの行なら、`:` の後ろ。字下げされた `  image-folder:` は
/// 別のキーの子なので、この文書の設定ではない
fn key_line(line : String) -> String? {
  guard line.has_prefix(image_folder_key) else { return None }
  let mut i = image_folder_key.length()
  while i < line.length() && (line[i] == ' ' || line[i] == '\t') {
    i += 1
  }
  guard i < line.length() && line[i] == ':' else { return None }
  Some(String::unsafe_substring(line, start=i + 1, end=line.length()))
}

///|
/// YAML の値 1 つ。**引用符で始まっていれば、閉じ引用符までが値**
/// （中の ` #` はコメントではない）。それ以外（裸）は ` #` から後ろを
/// コメントとして落とす。この 1 つの規則で 4 つの形すべてを覆う:
/// 裸 / 裸+コメント / 引用符 / 引用符+コメント。
///
/// 「コメントを先に落としてから引用符を剥がす」順だと、`"./My Folder #1/"`
/// のように**引用符の中に ` #` を含む値**を、閉じ引用符の手前で切ってしまい
/// 壊す（quote は空白・`#`・`:` のどれかを含む値を引用符で囲むので、
/// 囲まれた値の中に `#` が来る形は普通に起こる）。逆に「引用符を先に
/// 剥がす」だけだと、引用符の後ろにコメントが続く形（`"..." # main`）を
/// 取りこぼす。**閉じ引用符の位置を実際に探す**ことでどちらも起きない
fn unquote(raw : String) -> String {
  let v = raw.trim(chars=" \t").to_owned()
  guard v.length() > 0 else { return v }
  let q = v[0]
  if q == '"' || q == '\'' {
    // 閉じ引用符を探す。`"` は quote が `\"` / `\\` で書くので、その
    // エスケープぶんは飛ばす（`'` は YAML 側でエスケープを持たない）
    let mut i = 1
    while i < v.length() && v[i] != q {
      if q == '"' && v[i] == '\\' && i + 1 < v.length() {
        i += 1
      }
      i += 1
    }
    if i < v.length() {
      let inner = String::unsafe_substring(v, start=1, end=i)
      return if q == '"' { unescape(inner) } else { inner }
    }
    // 閉じ引用符が無い壊れた記法。ベストエフォートでそのまま返す
    return v
  }
  // 空白に続く `#` から後ろはコメント
  let mut end = v.length()
  for i in 1..<v.length() {
    if v[i] == '#' && (v[i - 1] == ' ' || v[i - 1] == '\t') {
      end = i
      break
    }
  }
  String::unsafe_substring(v, start=0, end~).trim(chars=" \t").to_owned()
}

///|
/// `\"` と `\\` を戻す
fn unescape(s : String) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < s.length() {
    if s[i] == '\\' &&
      i + 1 < s.length() &&
      (s[i + 1] == '"' || s[i + 1] == '\\') {
      i += 1
    }
    out.write_char(s[i].to_char().unwrap())
    i += 1
  }
  out.to_string()
}

///|
/// 値を YAML の 1 行として書く形。囲む必要が無ければ裸で書く
fn quote(value : String) -> String {
  let mut plain = true
  for i in 0..<value.length() {
    let c = value[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '#' || c == ':' {
      plain = false
      break
    }
  }
  guard !plain else { return value }
  let out = StringBuilder()
  out.write_char('"')
  for i in 0..<value.length() {
    let c = value[i]
    if c == '"' || c == '\\' {
      out.write_char('\\')
    }
    out.write_char(c.to_char().unwrap())
  }
  out.write_char('"')
  out.to_string()
}

///|
/// 頭（frontmatter の原文。`---` は含まない）から画像フォルダの宣言を読む。無ければ None
pub fn image_folder(frontmatter : String?) -> String? {
  guard frontmatter is Some(head) else { return None }
  for line in head.split("\n") {
    match key_line(line.to_owned()) {
      Some(v) => return Some(unquote(v))
      None => ()
    }
  }
  None
}

///|
/// 宣言を書き換える編集を 1 つ返す。3 つの場合がある。
/// - キーがある → **その行だけ**差し替える（他のキー・コメント・順序は不変）
/// - 頭はあるがキーが無い → 閉じ `---` の直前に 1 行足す
/// - 頭が無い → 文書の先頭に頭を作る
///
/// 頭の原文は開きの `---` の次の行から始まり、行ごとに `\n` を付けて
/// 繋いだもの（core が読んだライブラリの形）。だから原文の行数ぶんだけ
/// 本文の行を進めれば、その次の行が閉じの `---`
pub fn set_image_folder(
  md : String,
  frontmatter : String?,
  value : String,
) -> @tree.Edit {
  let line = "\{image_folder_key}: \{quote(value)}"
  guard frontmatter is Some(head) else {
    return { from: 0, to: 0, insert: "---\n\{line}\n---\n\n", }
  }
  let lines = md.split("\n").map(l => l.to_owned()).collect()
  let mut at = lines[0].length() + 1
  let count = head.split("\n").count() - 1
  for i in 1..<(1 + count) {
    guard lines.get(i) is Some(raw) else { break }
    if key_line(raw) is Some(_) {
      return { from: at, to: at + raw.length(), insert: line, }
    }
    at += raw.length() + 1
  }
  { from: at, to: at, insert: "\{line}\n", }
}

///|
/// 宣言フォルダの引っ越しに、本文の画像を追従させる操作列。
///
/// 対象は「**いま宣言しているフォルダの下にある**画像」だけ。`./img/` から
/// 動かすなら `./other/b.webp` は動かない。宣言が `./` のときは md の下に
/// ある相対パスが全部対象になるが、それは「画像は md と同じ場所にある」と
/// 宣言している状態なので、意味のとおり。外部 URL は `under` が外す
pub fn retarget(doc : @tree.Doc, from : String, to : String) -> Array[@op.Op] {
  let out : Array[@op.Op] = []
  guard from != to else { return out }
  each_node(doc, n => {
    for b in n.body {
      match b.content {
        Some(Image(alt~, src~, title~)) =>
          match under(src, from) {
            Some(rest) =>
              out.push(
                SetBlock(
                  id=b.id,
                  content=Some(Image(alt~, src=to + rest, title~)),
                  source=None,
                ),
              )
            None => ()
          }
        _ => ()
      }
    }
  })
  out
}

///|
/// `scheme://` で始まるか（URL は md からの相対ではない）
fn has_scheme(s : String) -> Bool {
  guard s.find("://") is Some(i) && i > 0 else { return false }
  for k in 0..<i {
    let c = s[k]
    guard (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') else { return false }
  }
  true
}

///|
/// 宣言の綴りを揃える。空・絶対パス・URL は None（宣言として読めない）。
/// `\` は `/` に、`.` は `./` に、末尾には `/` を揃える
pub fn normalize_path(value : String) -> String? {
  let trimmed = value.trim(chars=" \t\r\n").to_owned()
  guard trimmed != "" else { return None }
  let mut path = trimmed.replace_all(old="\\", new="/")
  if path == "." {
    path = "./"
  }
  guard !path.has_prefix("/") && !has_scheme(path) else { return None }
  Some(if path.has_suffix("/") { path } else { path + "/" })
}

///|
/// `path` が `folder` の下にあるなら、フォルダからの残り。外なら None。
///
/// 同じ場所を指す綴りが `./x` と `x` の 2 通りあるので、**必ず裸に寄せてから**
/// 比べる。md に書くのは `./x`、カード側が持つのは `x` と非対称なため、
/// どちらか片方だけを見ると既定の `./` で必ず外れる。
///
/// URL と絶対パスは md からの相対ではないので、どのフォルダの下でもない。
/// 残りが上へ出る（`..`）ものも下ではない — 宣言が `./` のとき、`../x.webp`
/// まで「md と同じ場所の下」に数えてしまう
pub fn under(path : String, folder : String) -> String? {
  let prefix = @tree.bare_path(folder)
  let rest = @tree.bare_path(path)
  guard !rest.has_prefix("/") && !has_scheme(rest) else { return None }
  guard rest.has_prefix(prefix) else { return None }
  let tail = String::unsafe_substring(
    rest,
    start=prefix.length(),
    end=rest.length(),
  )
  guard tail != "" else { return None }
  for part in tail.split("/") {
    guard part != ".." else { return None }
  }
  Some(tail)
}

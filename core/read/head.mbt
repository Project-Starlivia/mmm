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
/// 対象は「**打ち始めに宣言していたフォルダの下にあった**画像」だけ。`./img/` から
/// 動かすなら `./other/b.webp` は動かない。宣言が `./` のときは md の下に
/// ある相対パスが全部対象になるが、それは「画像は md と同じ場所にある」と
/// 宣言している状態なので、意味のとおり。外部 URL は `under` が外す。
///
/// **判定するのは `base` の綴り、書くのは `now` の木。** 引っ越しは 1 打鍵で
/// 終わらない（`./p/` → `./img/` は `./` を通る）。前の姿を基準にすると、途中の
/// `./` を見て「md の下の相対パス全部」を掴んでしまい、`./other/z.webp` まで
/// 引っ越し先へ連れて行く。**基準を凍らせれば、`./p/` の下だったかどうかを
/// 何回目の打鍵でも同じように問える**（#57）。
///
/// 書き込みは id 付きなので、判定する木と書く木が別でも成り立つ。ただし id は
/// **同じ文書の中でだけ**同じものを指す。だから 2 つの錠を掛ける。
/// - `now` に画像として残っている id だけを出す（途中で段落になった id を塗らない）
/// - **綴りの尻尾が変わっていない id だけを出す。** 追従が書くのはフォルダの
///   付け替えだけなので、尻尾（フォルダから下の残り）はどの段でも同じ。文書を
///   丸ごと貼り替えた後なら別の画像が同じ id に座っているが、尻尾が合わないので
///   触らない — **合っているなら、付け替えても名前は保たれる**
pub fn retarget(
  base : @tree.Doc,
  now : @tree.Doc,
  from : String,
  to : String,
) -> Array[@op.Op] {
  let out : Array[@op.Op] = []
  guard from != to else { return out }
  let was : Map[Int, String] = Map([])
  each_node(base, n => {
    for b in n.body {
      if b.content is Some(Image(src~, ..)) {
        was[b.id] = src
      }
    }
  })
  each_node(now, n => {
    for b in n.body {
      guard b.content is Some(Image(alt~, src=at, title~)) else { continue }
      guard was.get(b.id) is Some(src) &&
        under(src, from) is Some(rest) &&
        at.has_suffix(rest) else {
        continue
      }
      out.push(
        SetBlock(
          id=b.id,
          content=Some(Image(alt~, src=to + rest, title~)),
          source=None,
        ),
      )
    }
  })
  out
}

///|
/// **md からの相対ではない綴りか。** 頭の `/`（絶対パス）と、最初の `/` より前の `:`。
///
/// `:` 1 つで、`https:` のような scheme も `C:` のようなドライブ文字も同時に断てる。
/// `://` だけを見ていたころは、`data:` / `mailto:` / `javascript:` / `tel:` と
/// `C:/win/` / `D:pics` が全部通っていた（#322）。
///
/// 相対の綴りに `:` は現れない — 名前に使えない字だと `app/disk/path.mbt` が
/// 決めているので、mmm が作れるフォルダの名前には入らない
fn rooted(s : String) -> Bool {
  if s.has_prefix("/") {
    return true
  }
  for k in 0..<s.length() {
    let c = s[k]
    if c == '/' {
      return false
    }
    if c == ':' {
      return true
    }
  }
  false
}

///|
/// 宣言の綴りを揃える。**空・絶対パス・URL・ドライブ文字・制御文字は None**
/// （宣言として読めない）。`\` は `/` に、`.` は `./` に、末尾には `/` を揃える。
///
/// **続いた `/` は 1 つに畳む。** `.//` と `./` は同じ場所なのに、畳まないと
/// `.//x.webp` という綴りが本文に入る。それは裸にすると `/x.webp` = 絶対パスに
/// 見えるので `under` がどのフォルダの下でもないと言い、**一度そう書かれた画像は
/// 二度と追従できない**。宣言を `.//` と打つだけで起きる
pub fn normalize_path(value : String) -> String? {
  let trimmed = value.trim(chars=" \t\r\n").to_owned()
  guard trimmed != "" else { return None }
  // **中の制御文字は断る。** 頭（frontmatter）に書くと行が割れ、読み直すと
  // 別の値になる（`./a` + 改行 + `b/` は `./a` として読み直される）
  for k in 0..<trimmed.length() {
    let c = trimmed[k]
    guard c >= ' ' && c != '\u{7f}' else { return None }
  }
  let mut path = trimmed.replace_all(old="\\", new="/")
  if path == "." {
    path = "./"
  }
  // 断ってから畳む。**捨てる値を書き換えてから捨てる理由が無い**
  // （`:` は畳んでも残るので、順そのものはもう効かない）
  guard !rooted(path) else { return None }
  while path.contains("//") {
    path = path.replace_all(old="//", new="/")
  }
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
  guard !rooted(rest) else { return None }
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

///|
/// 頭の原文（`---` の行に挟まれた中身。開きの次の行から閉じの手前まで、行ごとに
/// `\n` 付き）。挟まれていなければ None。
///
/// **読みを 1 回も走らせずに測る。** ここは打鍵ごとに聞かれるので、`survey` を
/// 通す余裕は無い。答えは `survey(md).doc.frontmatter` と一致する（試験がその
/// 一致を押さえる）
fn head_of(md : String) -> String? {
  guard line_at(md, 0) is Some((line, next)) && fence(line) else { return None }
  let body_from = next
  let mut at = next
  while at < md.length() {
    guard line_at(md, at) is Some((line, next)) else { return None }
    if fence(line) {
      let body = String::unsafe_substring(md, start=body_from, end=at)
      // 中身の無い頭（`---` が 2 行続く）はライブラリも頭と読まない
      return if body == "" { None } else { Some(body) }
    }
    at = next
  }
  None
}

///|
/// その行が `---` だけか。**空白とタブは許し、`\r` は許さない** —
/// ライブラリが CRLF の頭を頭と読まないので、それに揃える（ai-docs/markdown.md）
fn fence(line : String) -> Bool {
  line.trim(chars=" \t") == "---"
}

///|
/// `at` から 1 行と、次の行の頭。改行が無ければ最後の行
fn line_at(md : String, at : Int) -> (String, Int)? {
  guard at < md.length() else { return None }
  let mut i = at
  while i < md.length() && md[i] != '\n' {
    i += 1
  }
  Some((String::unsafe_substring(md, start=at, end=i), i + 1))
}

///|
/// 2 つの md が同じ頭を持つか。
///
/// **追従の基準をいつ捨てるかを決める 1 つの問い。** 頭を触らなかった打鍵は
/// 引っ越しの途中ではないので、そこで基準が今の姿に移る。触った打鍵は途中なので
/// 基準を保つ（#57。使うのは src/state.ts の `base`）
pub fn same_head(a : String, b : String) -> Bool {
  head_of(a) == head_of(b)
}

///|
/// 宣言が `base` から引っ越したなら、本文の画像を追従させる編集の列
/// （**順に当てる** — 前の編集を当てた座標で次が言われる）。動いていなければ空。
///
/// `base` は**打ち替えを始めた時の md**（1 打鍵前ではない）。理由は `retarget` に
/// 書いた。ついでに、前の姿を基準にすると `./` から `./img/` へ打つ道が丸ごと
/// 落ちる — 最後の 1 打鍵の手前が `./img` で、`normalize_path` がそれを `./img/` に
/// 揃えるので、`from` と `to` が同じになって誰も動かない。
///
/// **判定は頭の 1 行だけで済む**ので、打鍵ごとに呼んでも読みは走らない。走るのは
/// 実際に引っ越したときだけ。
///
/// **落ち着いた宣言だけを追う。** `set_image_folder` が書くのは `normalize_path` の
/// 出力なので、settled な宣言は必ず `/` で終わる。終わっていない名前を追うと、
/// 打っている途中の綴りが地図でちらつく。基準が凍っているので途中の姿はどれも
/// 宣言と食い違わないが、見せる意味が無い。**代償は「`/` を付けずに止めた宣言は
/// 追わない」**
pub fn follow_declaration(
  base : String,
  now : String,
) -> Array[Array[@tree.Edit]] {
  let out : Array[Array[@tree.Edit]] = []
  guard image_folder(head_of(now)) is Some(typed) && typed.has_suffix("/") else {
    return out
  }
  guard normalize_path(typed) is Some(to) else { return out }
  guard image_folder(head_of(base)).bind(normalize_path) is Some(from) &&
    from != to else {
    return out
  }
  let (base_doc, _) = @tree.build(base)
  let (now_doc, _) = @tree.build(now)
  let mut md = now
  for op in retarget(base_doc, now_doc, from, to) {
    let r = @op.edit(md, op)
    guard r.edits.length() > 0 else { continue }
    out.push(r.edits)
    md = @tree.patched(md, r.edits)
  }
  out
}

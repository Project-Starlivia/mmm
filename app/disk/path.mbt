// 画像の置き場と名前の柵。**どれも純粋** — md に書かれた綴りが宣言の下に収まるか、
// 宣言の綴りとして通るか、置く名前として通るか、置く箱の形。フォルダの札や
// ファイルの読み書きは images.mbt が持ち、ここは字と数だけを見る

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
/// 置く名前の既定 — 時刻の綴り（`2026-09-07-153012`）。`t` は `@web.local_time` の並び
fn stamp(t : FixedArray[Int]) -> String {
  let two = (v : Int) => if v < 10 { "0\{v}" } else { "\{v}" }
  "\{t[0]}-\{two(t[1])}-\{two(t[2])}-\{two(t[3])}\{two(t[4])}\{two(t[5])}"
}

///|
/// 画像を置く箱の形と、答えの読み方。**分かっているところは字、分からないところ
/// だけ欄** — 位置が決まっていれば（宣言、または計算できた）`./pics/` はただの字で、
/// 打てるのは名前だけ。欄の並び順が答えの並び順なので、読み方も同じ場所で決める —
/// 答えは (位置に打った字（欄が無ければ None）, 名前に打った字)
fn image_form(
  place : @parts.Field?,
  declared : String,
  name : @parts.Field,
) -> (Array[@parts.Part], (Array[String]) -> (String?, String)) {
  let shape : Array[@parts.Part] = [
    Text("![]("),
    match place {
      Some(f) => Blank(f)
      None => Text(declared)
    },
    Blank(name),
    Text(".webp)"),
  ]
  let read = (values : Array[String]) => {
    match place {
      Some(f) =>
        (Some(values.get(0).unwrap_or(f.value)), values.get(1).unwrap_or(""))
      None => (None, values.get(0).unwrap_or(""))
    }
  }
  (shape, read)
}

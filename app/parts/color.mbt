// 色。アクセントカラーの綴りの源は style.css の `--accent` だけで、ここは読むだけ

///|
/// 6 桁の hex（`#` は有っても無くても）なら `#rrggbb` に揃える。違えば None
pub fn hex_of(value : String) -> String? {
  let v = value.trim(chars=" \t\r\n").to_owned()
  let body = if v.has_prefix("#") {
    String::unsafe_substring(v, start=1, end=v.length())
  } else {
    v
  }
  guard body.length() == 6 else { return None }
  for i in 0..<6 {
    let c = body[i]
    let ok = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    guard ok else { return None }
  }
  Some("#" + body)
}

///|
/// いまのアクセントカラー。**綴りの源は style.css の `--accent` だけ**で、
/// ここは読むだけ（既定色を他にも書くと、同じ数字が 2 か所になる）。
/// 読んだ値は名乗らせず確かめる — 6 桁の hex でなければ None。
/// 筆にする側（ts の app/draw.ts）も同じ 1 つを読む
pub fn accent(doc : @dom.Document) -> String? {
  hex_of(@web.css_var(doc, "--accent"))
}

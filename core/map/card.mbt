// 中身（Block）→ カード。**分類だけ**の層 — 何をカードとして見せるかを決め、
// 寸法（metric）も DOM も知らない。
//
// md の読みは tree が済ませている。ここが見るのは tree が「これは画像・リンク・
// コード・SVG・水平線・details だ」と言った Block だけで、原文はもう無い。
//
// **カードは自分が出た中身の id を持つ。** 分類は全域ではない（外部の画像・
// http 以外のリンクは落ちる）ので、カードの列は中身の列より短くなりうる。
// 添字で 2 つの列を突き合わせると別のカードを掴む — 実際に掴んでいた（#212）。

///|
/// ラベルの下に積むカード 1 枚。**それが出た中身の id を持つ** —
/// 選ぶ・消す・開くは、枚数ではなくこの id で言う
pub(all) struct Card {
  id : Int
  kind : Kind
} derive(Eq, Debug, ToJson)

///|
/// カードの種類。何をどう見せるかだけを言う
pub(all) enum Kind {
  /// `http(s)` のリンク。題が空ならホスト名が題
  Link(title~ : String, url~ : String)
  /// 相対パスのローカル画像。name はパスの最後の要素
  Image(path~ : String, name~ : String)
  Svg(markup~ : String)
  Code(lang~ : String, lines~ : Array[String])
  /// 装飾の水平線。書かれた場所にそのまま 1 本の線
  Break
  /// `<details>`。GitHub と同じく、閉じていれば summary（無ければ Details）だけ、
  /// 開いていれば中身の字も。開閉は md の `open` に従う（map だけの状態は持たない）
  Details(open~ : Bool, summary~ : String?, lines~ : Array[String])
} derive(Eq, Debug, ToJson)

///|
/// コードのプレビューは何行まで。超えたら最後の行を `…` にする
let code_max_lines = 6

///|
/// `http(s)` のリンクだけ
fn link_card(text : String, href : String) -> Kind? {
  guard href.has_prefix("http://") || href.has_prefix("https://") else {
    return None
  }
  let host = host_of(href)
  guard host != "" else { return None }
  Some(Link(title=if text == "" { host } else { text }, url=href))
}

///|
/// `scheme://` の後ろのホスト名（`new URL(href).hostname` と同じ読み: `/` `?` `#` の
/// 手前まで、userinfo の `@` と port の `:` を落とし、小文字に）
fn host_of(href : String) -> String {
  let start = match href.find("://") {
    Some(i) => i + 3
    None => return ""
  }
  let mut end = href.length()
  for i in start..<href.length() {
    let c = href[i]
    if c == '/' || c == '?' || c == '#' {
      end = i
      break
    }
  }
  let mut auth = slice(href, start, end)
  match auth.rev_find("@") {
    Some(i) => auth = slice(auth, i + 1, auth.length())
    None => ()
  }
  match auth.find(":") {
    Some(i) => auth = slice(auth, 0, i)
    None => ()
  }
  auth.to_lower()
}

///|
/// 相対パスのローカル画像だけ。外部の画像（http / data）は出さない — 外へ通信しない。
/// scheme は 2 文字以上（1 文字は Windows のドライブ `C:\`）。
fn image_card(src : String) -> Kind? {
  guard scheme_len(src) <= 1 else { return None }
  let path = @tree.bare_path(src)
  guard path != "" else { return None }
  Some(Image(path~, name=last_segment(path)))
}

///|
/// 先頭の `scheme:` の scheme の長さ（`[a-z][a-z0-9+.-]*`、大文字も可）。無ければ 0
fn scheme_len(s : String) -> Int {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    let ok = if i == 0 {
      alpha(c)
    } else {
      alpha(c) || (c >= '0' && c <= '9') || c == '+' || c == '.' || c == '-'
    }
    guard ok else { break }
    i += 1
  }
  if i > 0 && i < s.length() && s[i] == ':' {
    i
  } else {
    0
  }
}

///|
fn alpha(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// パスの最後の要素。Windows のパスは `\` 区切りでも来る
fn last_segment(path : String) -> String {
  let mut from = 0
  for i in 0..<path.length() {
    if path[i] == '/' || path[i] == '\\' {
      from = i + 1
    }
  }
  slice(path, from, path.length())
}

///|
/// 字を行に割る。末尾の改行は行にならない。タブは 2 幅。code_max_lines を超えたら
/// 最後の行を `…` にし、空なら 1 行（場所は取る）。コードも details の中身も同じ割り方
fn lines_of(text : String) -> Array[String] {
  guard text != "" else { return [""] }
  let body = match text.strip_suffix("\n") {
    Some(v) => v.to_owned()
    None => text
  }
  let lines = body
    .split("\n")
    .map(l => l.to_owned().replace_all(old="\t", new="  "))
    .collect()
  guard lines.length() > code_max_lines else { return lines }
  let out = []
  for i in 0..<(code_max_lines - 1) {
    out.push(lines[i])
  }
  out.push("…")
  out
}

///|
fn card_of(c : @tree.Content) -> Kind? {
  match c {
    Image(src~, ..) => image_card(src)
    Link(text~, href~, ..) => link_card(text, href)
    Svg(markup) => Some(Svg(markup~))
    Code(info~, text~) => Some(Code(lang=info, lines=lines_of(text)))
    ThematicBreak => Some(Break)
    Details(open~, summary~, body~) =>
      Some(Details(open~, summary~, lines=lines_of(body)))
  }
}

///|
/// ノード 1 つぶんのカード。並びは中身のまま、**枚数は中身の数と揃わない** —
/// カードにならない中身（読み解いていない・外部の画像・http 以外のリンク）は
/// 飛ばす。だからこそ 1 枚ずつが出どころの id を連れる
pub fn cards(blocks : Array[@tree.Block]) -> Array[Card] {
  let out = []
  for b in blocks {
    match b.content.bind(card_of) {
      Some(kind) => out.push({ id: b.id, kind, })
      None => ()
    }
  }
  out
}

///|
/// UTF-16 の位置で切る（サロゲートペアの間で切らないのは呼ぶ側の責任）
fn slice(s : String, from : Int, to : Int) -> String {
  String::unsafe_substring(s, start=from, end=to)
}

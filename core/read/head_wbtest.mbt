// 文書の頭（YAML frontmatter）— その中の 1 行の綴りを読む・書く。
// 「どこからどこまでが頭か」は読みが答えるので、頭の原文は survey で本物から引く。

///|
/// md から宣言を引く
fn folder_of(md : String) -> String? {
  image_folder(survey(md).doc.frontmatter)
}

///|
/// md の宣言を書き換えた後の全文
fn written(md : String, value : String) -> String {
  let e = set_image_folder(md, survey(md).doc.frontmatter, value)
  String::unsafe_substring(md, start=0, end=e.from) +
  e.insert +
  String::unsafe_substring(md, start=e.to, end=md.length())
}

///|
test "image_folder: 頭から値を読む。他のキーが並んでいても" {
  assert_eq(
    folder_of("---\nimage-folder: ./img/\n---\n\n# r\n"),
    Some("./img/"),
  )
  assert_eq(
    folder_of(
      "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n",
    ),
    Some("./img/"),
  )
}

///|
test "image_folder: キーが無い / 頭が無い なら None。入れ子のキーは読まない" {
  assert_eq(folder_of("---\ntitle: メモ\n---\n\n# r\n"), None)
  assert_eq(folder_of("# r\n"), None)
  assert_eq(folder_of("---\nmmm:\n  image-folder: ./img/\n---\n\n# r\n"), None)
}

///|
test "image_folder: 裸 / 裸+コメント / 引用符 / 引用符+コメント の 4 形" {
  assert_eq(
    folder_of("---\nimage-folder: ./img/ # ここ\n---\n\n# r\n"),
    Some("./img/"),
  )
  assert_eq(
    folder_of("---\nimage-folder: \"./My Folder #1/\"\n---\n\n# r\n"),
    Some("./My Folder #1/"),
  )
  assert_eq(
    folder_of("---\nimage-folder: \"./My Folder #1/\" # ここ\n---\n\n# r\n"),
    Some("./My Folder #1/"),
  )
  assert_eq(
    folder_of("---\nimage-folder: './img/'\n---\n\n# r\n"),
    Some("./img/"),
  )
}

///|
test "set_image_folder: キーがあればその行だけ差し替える" {
  let md = "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n"
  assert_eq(
    written(md, "./assets/"),
    "---\ntitle: メモ\nimage-folder: ./assets/\ntags:\n  - a\n---\n\n# r\n",
  )
}

///|
test "set_image_folder: キーが無ければ閉じ --- の直前に足す。開きに空白が続いていても" {
  assert_eq(
    written("---\ntitle: メモ\n---\n\n# r\n", "./img/"),
    "---\ntitle: メモ\nimage-folder: ./img/\n---\n\n# r\n",
  )
  assert_eq(
    written("---  \ntitle: メモ\n---\n\n# r\n", "./img/"),
    "---  \ntitle: メモ\nimage-folder: ./img/\n---\n\n# r\n",
  )
}

///|
test "set_image_folder: 頭が無ければ先頭に作る。空白・#・: を含む値は囲み、要らなければ裸" {
  assert_eq(
    written("# r\n", "./img/"),
    "---\nimage-folder: ./img/\n---\n\n# r\n",
  )
  assert_eq(
    written("# r\n", "./My Images/"),
    "---\nimage-folder: \"./My Images/\"\n---\n\n# r\n",
  )
  assert_eq(
    written("# r\n", "./a#b/"),
    "---\nimage-folder: \"./a#b/\"\n---\n\n# r\n",
  )
}

///|
test "set_image_folder → image_folder は往復する" {
  for
    value in [
      "./img/", "../pics/", "./My Images/", "./a\"b/", "./My Folder #1/",
    ] {
    assert_eq(folder_of(written("# r\n", value)), Some(value))
  }
}

///|
test "retarget: 宣言の下にある画像だけを、新しい宣言の下へ移す操作列" {
  let md = "# r\n\n![a](./img/a.webp)\n\n![b](img/sub/b.png)\n\n![c](./other/c.webp)\n\n![d](https://x/d.png)\n"
  assert_eq(retarget(survey(md).doc, "./img/", "../pics/"), [
    SetBlock(
      id=3,
      content=Some(Image(alt="a", src="../pics/a.webp", title="")),
      source=None,
    ),
    SetBlock(
      id=4,
      content=Some(Image(alt="b", src="../pics/sub/b.png", title="")),
      source=None,
    ),
  ])
}

///|
test "retarget: 宣言が ./ なら本文の相対パスは全部が対象。動いていなければ空" {
  let v = survey("# r\n\n![](a.webp)\n\n![](./s/b.webp)\n\n![](../up.webp)\n").doc
  let srcs = retarget(v, "./", "./img/").map(op => {
    match op {
      SetBlock(content=Some(Image(src~, ..)), source=None, ..) => src
      _ => "?"
    }
  })
  assert_eq(srcs, ["./img/a.webp", "./img/s/b.webp"])
  assert_eq(
    retarget(survey("# r\n\n![](./img/a.webp)\n").doc, "./img/", "./img/"),
    [],
  )
}

///|
test "normalize_path / under" {
  assert_eq(normalize_path(" img "), Some("img/"))
  assert_eq(normalize_path("."), Some("./"))
  assert_eq(normalize_path("a\\b"), Some("a/b/"))
  assert_eq(normalize_path(""), None)
  assert_eq(normalize_path("/abs"), None)
  assert_eq(normalize_path("https://x/"), None)
  assert_eq(under("./img/a.webp", "img/"), Some("a.webp"))
  assert_eq(under("img/s/b.png", "./img/"), Some("s/b.png"))
  assert_eq(under("./other/c.webp", "./img/"), None)
  assert_eq(under("https://x/d.png", "./"), None)
  assert_eq(under("../up.webp", "./"), None)
  assert_eq(under("./img/", "./img/"), None)
}

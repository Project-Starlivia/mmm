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
/// 判定する木と書く木。本文が動いていない間は同じものなので、`doc` 1 つで測れる
fn moved(md : String, from : String, to : String) -> Array[@op.Op] {
  let doc = survey(md).doc
  retarget(doc, doc, from, to)
}

///|
test "retarget: 宣言の下にある画像だけを、新しい宣言の下へ移す操作列" {
  let md = "# r\n\n![a](./img/a.webp)\n\n![b](img/sub/b.png)\n\n![c](./other/c.webp)\n\n![d](https://x/d.png)\n"
  assert_eq(moved(md, "./img/", "../pics/"), [
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
  let srcs = moved(
    "# r\n\n![](a.webp)\n\n![](./s/b.webp)\n\n![](../up.webp)\n", "./", "./img/",
  ).map(op => {
    match op {
      SetBlock(content=Some(Image(src~, ..)), source=None, ..) => src
      _ => "?"
    }
  })
  assert_eq(srcs, ["./img/a.webp", "./img/s/b.webp"])
  assert_eq(moved("# r\n\n![](./img/a.webp)\n", "./img/", "./img/"), [])
}

///|
/// **判定は base、書くのは now。** 本文がすでに途中の姿になっていても、
/// 打ち始めに宣言の下だった画像だけが動く（#57）
test "retarget: base に無かった画像は now に居ても動かない" {
  let base = survey("# r\n\n![](./p/x.webp)\n\n![](./other/z.webp)\n").doc
  // 途中の姿。宣言が `./` を通ったので x は `./x.webp` に、z はそのまま
  let now = survey("# r\n\n![](./x.webp)\n\n![](./other/z.webp)\n").doc
  let srcs = retarget(base, now, "./p/", "./img/").map(op => {
    match op {
      SetBlock(content=Some(Image(src~, ..)), source=None, ..) => src
      _ => "?"
    }
  })
  // z は base で `./p/` の下ではなかったので、now で `./` の下に見えても動かない
  assert_eq(srcs, ["./img/x.webp"])
}

///|
/// 途中で本文の形が変われば、その id はもう画像ではない。**他のブロックを
/// 塗り替えない**（base の id をそのまま信じると段落を画像にしてしまう）
test "retarget: now で画像でなくなった id には書かない" {
  let base = survey("# r\n\n![](./p/x.webp)\n").doc
  let now = survey("# r\n\nただの段落\n").doc
  assert_eq(retarget(base, now, "./p/", "./img/"), [])
}

///|
/// **尻尾が合わない id には書かない。** 文書を丸ごと貼り替えると、同じ id に
/// 別の画像が座る。追従が変えるのはフォルダだけなので尻尾はどの段でも同じ —
/// 合わなければそれは追っている画像ではない（名前を塗り潰さない）
test "retarget: 綴りの尻尾が変わった id には書かない" {
  let base = survey("# r\n\n![](./p/x.webp)\n").doc
  // 同じ id に別の名前の画像。貼り替えた後の姿
  let other = survey("# r\n\n![](./q/a.webp)\n").doc
  assert_eq(retarget(base, other, "./p/", "./img/"), [])
  // 尻尾が同じなら、フォルダがどこであれ追う（途中の姿はこれ）
  let same = survey("# r\n\n![](./x.webp)\n").doc
  assert_eq(retarget(base, same, "./p/", "./img/"), [
    SetBlock(
      id=3,
      content=Some(Image(alt="", src="./img/x.webp", title="")),
      source=None,
    ),
  ])
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

///|
/// **続いた `/` は畳む。** 畳まないと `.//` の宣言が本文に `.//x.webp` を書き、
/// それは裸にすると `/x.webp` = 絶対パスに見えるので `under` が外す —
/// **その画像は二度と追従できなくなる**（#57 を作っている途中に実機で踏んだ）
test "normalize_path: 続いた / は 1 つに畳む" {
  assert_eq(normalize_path(".//"), Some("./"))
  assert_eq(normalize_path(".///"), Some("./"))
  assert_eq(normalize_path("./a//b/"), Some("./a/b/"))
  assert_eq(normalize_path("a//"), Some("a/"))
  assert_eq(normalize_path("//x"), None)
  // **畳むのは断ってから。** 先に畳むと scheme が外れて URL が宣言として通る
  assert_eq(normalize_path("https://x/"), None)
  assert_eq(normalize_path("http://x/y/"), None)
}

///|
/// 畳んだ宣言なら、本文の画像を追える。畳まないと `under` が外す
test "normalize_path: 畳んだ宣言は under が拾える" {
  let folder = normalize_path(".//").unwrap()
  assert_eq(under("./x.webp", folder), Some("x.webp"))
  assert_eq(under("x.webp", folder), Some("x.webp"))
}

///|
/// **安い頭読みは、本物と一致する。** `follow_declaration` が打鍵ごとに呼ばれるので、
/// 読み全部を通さずに頭を測る道が要る（#57）。一致しなくなったらここが鳴る
test "head_of: 安い頭読みは survey と一致する" {
  let shapes = [
    "", "# a\n", "---\n", "---\nk: v\n", "---\nk: v\n---\n", "---\nk: v\n---\n\n# a\n",
    "---\nimage-folder: ./p/\n---\n\n# a\n\n![](./p/x.webp)\n", "---\n---\n# a\n",
    "---\r\nk: v\r\n---\r\n\r\n# a\r\n", "text\n\n---\nk: v\n---\n", "---\nk: v\n--- \n# a\n",
    "---\na: 1\nb: 2\n---\n# a\n",
  ]
  let bad : Array[String] = []
  for md in shapes {
    let real = survey(md).doc.frontmatter
    if head_of(md) != real {
      let show = (v : String?) => {
        match v {
          Some(s) => s.escape()
          None => "無し"
        }
      }
      bad.push(
        "\{md.escape()} → 安い \{show(head_of(md))} / 本物 \{show(real)}",
      )
    }
  }
  json_inspect(bad, content=[])
}

///|
/// 頭を触ったかどうかだけを答える。本文をいくら変えても頭は同じ
test "same_head: 頭を触った打鍵だけが違うと言う" {
  let md = "---\nimage-folder: ./p/\n---\n\n# a\n\n![](./p/x.webp)\n"
  assert_true(same_head(md, md))
  assert_true(same_head(md, md + "\n本文を足した\n"))
  assert_false(same_head(md, md.replace(old="./p/", new="./img/")))
  assert_false(same_head(md, "# a\n"))
  assert_true(same_head("# a\n", "# b\n"))
}

///|
/// 宣言の値だけを打ち替えた md（打鍵 1 回ぶん。本文はそのときの姿のまま）
fn retyped(md : String, value : String) -> String {
  let key = "image-folder: "
  let at = md.find(key).unwrap() + key.length()
  let eol = at +
    String::unsafe_substring(md, start=at, end=md.length()).find("\n").unwrap()
  String::unsafe_substring(md, start=0, end=at) +
  value +
  String::unsafe_substring(md, start=eol, end=md.length())
}

///|
/// 宣言を 1 打鍵ずつ打ち替えていく。**基準は打ち始めの md で凍る** —
/// src/state.ts の `base` field と同じ形
fn typing(base : String, values : Array[String]) -> String {
  let mut now = base
  for value in values {
    now = retyped(now, value)
    for set in follow_declaration(base, now) {
      now = @tree.patched(now, set)
    }
  }
  now
}

///|
/// 文書 1 つ。宣言と、その下の画像・外の画像
fn declared(folder : String, x : String) -> String {
  "---\nimage-folder: \{folder}\n---\n\n# a\n\n![](\{x})\n\n![](./other/z.webp)\n"
}

///|
/// **通った `./` と、宣言された `./` は違う。** 前者は打ち替えの途中に居るだけなので
/// 何も掴まない。後者は「画像は md と同じ場所にある」と言い切っているので md の下は
/// 全部が対象。**基準を凍らせて初めてこの 2 つが分かれる**（#57）
test "follow_declaration: 通った ./ は掴まない。宣言された ./ は掴む" {
  // `./p/` から `./img/` へ。途中で必ず `./` を通る
  assert_eq(
    typing(declared("./p/", "./p/x.webp"), [
      "./p", "./", "./i", "./im", "./img", "./img/",
    ]),
    declared("./img/", "./img/x.webp"),
  )
  // `./` から `./img/` へ。宣言が `./` なので `./other/z.webp` も下に居る
  assert_eq(
    typing(declared("./", "./x.webp"), ["./i", "./im", "./img", "./img/"]),
    "---\nimage-folder: ./img/\n---\n\n# a\n\n![](./img/x.webp)\n\n![](./img/other/z.webp)\n",
  )
}

///|
/// `.//` と打っても切れない。`normalize_path` が畳むので本文に `.//x.webp` が
/// 入らない（入ると `under` が外して二度と追えない）。**宣言の綴りは打った字の
/// まま** — 追従が書き換えるのは本文だけで、頭は書いた人のもの
test "follow_declaration: `.//` と打っても本文は畳まれた綴りで追う" {
  assert_eq(
    typing(declared("./p/", "./p/x.webp"), [
      ".//", ".//i", ".//im", ".//img", ".//img/",
    ]),
    declared(".//img/", "./img/x.webp"),
  )
}

///|
/// **落ち着いた宣言だけを追う。** settled な宣言は `/` で終わる（`set_image_folder` が
/// `normalize_path` の出力を書くので）。途中の綴りで動かすと地図がちらつくだけ
test "follow_declaration: `/` で終わる宣言だけ追う" {
  let base = declared("./p/", "./p/x.webp")
  for typing in ["./i", "./im", "./img", "."] {
    assert_eq(follow_declaration(base, retyped(base, typing)).length(), 0)
  }
  assert_eq(follow_declaration(base, retyped(base, "./img/")).length(), 1)
}

///|
/// 動く理由が無いときは空。**打鍵ごとに呼ばれるので、空で帰る道がいちばん太い**
test "follow_declaration: 引っ越していなければ空" {
  let md = declared("./p/", "./p/x.webp")
  // 同じ宣言
  assert_eq(follow_declaration(md, md).length(), 0)
  // 頭が無い
  assert_eq(follow_declaration("# a\n", "# b\n").length(), 0)
  // 宣言を消した（空は宣言として読めない）
  assert_eq(follow_declaration(md, retyped(md, "")).length(), 0)
  // 宣言の下に画像が無い
  let outside = declared("./p/", "./other/y.webp")
  assert_eq(follow_declaration(outside, retyped(outside, "./img/")).length(), 0)
}

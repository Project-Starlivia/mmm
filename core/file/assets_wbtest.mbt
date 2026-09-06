// 画像の置き場の純粋な算術。フォルダ選択やファイルの読み書きはブラウザの札に
// 聞くしかなく、ここでは見ない。

///|
test "asset_target: 既定の ./ で、./ 付きでも裸でも同じ場所を指す。宣言のぶんを除いた相対を返す" {
  assert_eq(asset_target("./", "a.webp"), Some(["a.webp"]))
  assert_eq(asset_target("./", "./a.webp"), Some(["a.webp"]))
  assert_eq(asset_target("assets/", "assets/a.webp"), Some(["a.webp"]))
  assert_eq(asset_target("assets/", "./assets/a.webp"), Some(["a.webp"]))
  assert_eq(asset_target("./", "sub/a.webp"), Some(["sub", "a.webp"]))
  assert_eq(asset_target("../pics/", "../pics/a.webp"), Some(["a.webp"]))
  assert_eq(
    asset_target("../pics/", "../pics/sub/a.webp"),
    Some(["sub", "a.webp"]),
  )
}

///|
test "asset_target: 宣言の外・絵でないものは受け取らない" {
  assert_eq(asset_target("assets/", "other/a.webp"), None)
  assert_eq(asset_target("assets/", "a.webp"), None)
  assert_eq(asset_target("./", "../a.webp"), None)
  assert_eq(asset_target("./", ""), None)
  assert_eq(asset_target("./", "notes.txt"), None)
  assert_eq(asset_target("./", "sub/id_rsa"), None)
  assert_eq(asset_target("assets/", "assets/.env"), None)
}

///|
test "image_type: 絵の名前からその種類を引く。絵でなければ None" {
  assert_eq(image_type("a.webp"), Some("image/webp"))
  assert_eq(image_type("a.PNG"), Some("image/png"))
  assert_eq(image_type("a.jpeg"), Some("image/jpeg"))
  assert_eq(image_type("notes.txt"), None)
  assert_eq(image_type("id_rsa"), None)
  assert_eq(image_type(".env"), None)
  assert_eq(image_type("a.webp.txt"), None)
}

///|
test "name_problem: 空・. と ..・使えない字を咎め、通る名前は None" {
  assert_eq(name_problem("  "), Some("Give it a name"))
  assert_eq(name_problem("a/../b"), Some("Folder names cannot be . or .."))
  assert_eq(name_problem("a:b"), Some("A file name cannot contain :"))
  assert_eq(name_problem("pics/shot.webp"), None)
  assert_eq(name_parts("pics/shot.WEBP"), ["pics", "shot"])
}

///|
test "md_path: md に書くのは ./ 付き。上へ出る道はそのまま" {
  assert_eq(md_path("x.webp"), "./x.webp")
  assert_eq(md_path("./x.webp"), "./x.webp")
  assert_eq(md_path("../x.webp"), "../x.webp")
}

///|
test "folder_from_doc: resolve の断片（フォルダ → md）を、md から見たフォルダに読み替える" {
  assert_eq(folder_from_doc(["a.md"]), "./")
  assert_eq(folder_from_doc(["notes", "a.md"]), "../")
  assert_eq(folder_from_doc(["a", "b", "c.md"]), "../../")
  assert_eq(folder_from_doc([]), "./")
}

///|
test "folder_problem: 末尾が選んだフォルダの実名と一致すれば通る。違う・./・空・絶対・URL は止める" {
  assert_eq(folder_problem("../pics/", Some("pics")), None)
  assert_eq(folder_problem("../../pics", Some("pics")), None)
  assert_eq(folder_problem("pics", Some("pics")), None)
  assert_eq(
    folder_problem("../images/", Some("pics")),
    Some("The folder you picked is named pics"),
  )
  assert_eq(
    folder_problem("./", Some("pics")),
    Some("The folder you picked is named pics"),
  )
  assert_eq(
    folder_problem("../", Some("pics")),
    Some("The folder you picked is named pics"),
  )
  assert_eq(
    folder_problem("", Some("pics")),
    Some("Use a path relative to the .md"),
  )
  assert_eq(
    folder_problem("/abs/pics", Some("pics")),
    Some("Use a path relative to the .md"),
  )
  assert_eq(
    folder_problem("https://x/pics", Some("pics")),
    Some("Use a path relative to the .md"),
  )
  // 位置が計算できていれば実名は照合せず、相対パスであることだけ見る
  assert_eq(folder_problem("./", None), None)
  assert_eq(folder_problem("../../", None), None)
  assert_eq(
    folder_problem("/abs/", None),
    Some("Use a path relative to the .md"),
  )
}

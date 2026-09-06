// アプリが聞くことの全部。**並べ方はここ 1 つ** — 器（ask.mbt）は聞き方を
// 知らず、聞く場所（main.ts / core/file/assets.mbt）は綴りを持たない。並べて
// 見る道具もここを読む。値が要るものは引数で受ける（聞く時点で決まるもの）。
//
// **欄の検査の言葉はここに来ない。** 「なぜ進めないか」は条件と一体で
// （`core/file/assets.mbt` の `folder_problem` / `name_problem` /
// `image_name_problem`）、切り離すと条件を足したときに言葉を付け忘れる。
// しらせの `failed_words` は「言葉の一覧」だが、こちらは「条件ごとの答え」で
// 別のもの。並べて見る道具は、写すのではなく**その検査を通す**。

///|
/// 未保存の文書を捨てて先へ進むか
pub fn discard() -> Ask {
  ask_of("Discard unsaved changes?", "Discard")
}

///|
/// 画像を置く前に .md を保存してもらう。**壁ではなく駅** — 行程を先に見せる
pub fn place() -> Ask {
  ask_of(
    "Images need a place on disk. Save the .md, then pick a folder.", "Save the .md…",
  )
}

///|
/// 開いた文書に画像があり、まだフォルダを握っていない
pub fn connect(folder : String) -> Ask {
  ask_of(
    "Connect the image folder?",
    "Connect…",
    note=Some("Images here point to \{folder}."),
    cancel=Some("Not now"),
  )
}

///|
/// ディスク上のファイルの名前を変える
pub fn rename(name : String) -> Ask {
  ask_of("New file name", "Rename", parts=[Blank({ value: name, check: None, })])
}

///|
/// 貼る画像の名前。`shape` は「分かっているところは字、分からないところだけ欄」の並び
pub fn image_name(shape : Array[Part], shot : String) -> Ask {
  ask_of("Name this image", "Save", parts=shape, preview=Some(shot))
}

///|
/// 宣言の並び。**分かっているところは字、分からないところだけ欄** — 頭の
/// `image-folder:` は md にそう書かれる字そのもので、打つのは道だけ
fn declaration_parts(field : Field) -> Array[Part] {
  [Text("image-folder:"), Blank(field)]
}

///|
/// 画像フォルダの場所を初めて決める。**どこにあるかではなく、md から見た道**を聞く
/// （宣言は md に書かれるので、md からの相対でないと次に開いたとき辿れない）
pub fn declaration(folder : String, field : Field) -> Ask {
  ask_of(
    "Where is \{folder}, seen from the .md?",
    "Save",
    parts=declaration_parts(field),
  )
}

///|
/// 選び直したフォルダが宣言と食い違った。**打ち替えるか、そのままにするか** —
/// 打ち替えれば本文の画像のパスも一緒に動く
pub fn redeclaration(field : Field) -> Ask {
  ask_of(
    "The folder changed — update the declaration?",
    "Update",
    note=Some("Image paths in the document will follow."),
    cancel=Some("Keep as is"),
    parts=declaration_parts(field),
  )
}

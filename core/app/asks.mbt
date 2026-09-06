// アプリが聞くことの全部。**並べ方はここ 1 つ** — 器（ask.mbt）は聞き方を
// 知らず、聞く場所（main.ts / assets.ts）は綴りを持たない。並べて見る道具も
// ここを読む。値が要るものは引数で受ける（聞く時点で決まるもの）。

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

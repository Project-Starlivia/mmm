// 帯の Files。文書に何かする道はここにまとめる。**画像フォルダもここ** —
// 「この .md の画像がどこに居るか」は文書ぜんぶの設定で、新規 / 開く / 保存と
// 同じ高さのもの。塊は 2 つ（.md と、その画像フォルダ）で、見出しが状態を
// 言い、続く行がそれに対してできること。**絵が付くのは、押せるものだけ。**
//
// 並びは純粋な表。いまの状態（`Files`）を受けて行を返し、押されたら `FileActs` を
// 呼ぶだけ — 文書もファイルも知らない。並べて見る道具は好きな状態を渡す。

///|
/// 改名する相手そのものがディスクに無い（保存したらもう改名する必要が無いので、駅にならない）
let nothing_to_rename = "Save the .md first — nothing on disk to rename yet"

///|
/// その環境が改名を持たない。どのブラウザが、とは言わない（名指しは移り変わる）
pub let no_rename_here = "This browser can't rename files"

///|
/// 改名できない理由。Files の Rename の行と、帯の名乗りの title が同じ言葉を使う。できるなら None
fn rename_problem(can_rename : Bool, saved : Bool) -> String? {
  if !can_rename {
    Some(no_rename_here)
  } else if !saved {
    Some(nothing_to_rename)
  } else {
    None
  }
}

///|
pub(all) struct Files {
  /// ディスク上の名前。まだ無ければ None
  saved_name : String?
  /// 覚えている文書の名前。いま開いているものは含まない
  recent : Array[String]
  can_open : Bool
  can_save : Bool
  can_rename : Bool
  can_choose_folder : Bool
  /// 画像フォルダの状態の一言
  folder : String
}

///|
pub(all) struct FileActs {
  new_file : () -> Unit
  open : () -> Unit
  open_recent : (Int) -> Unit
  save : () -> Unit
  save_as : () -> Unit
  rename : () -> Unit
  choose_folder : () -> Unit
}

///|
/// 沈む理由。押せるなら No
fn unless(ok : Bool, why : String) -> @parts.Disabled {
  if ok {
    No
  } else {
    Why(why)
  }
}

///|
pub fn files_menu(s : Files, a : FileActs) -> Array[@parts.Entry] {
  let access = @parts.no_file_access
  [
    Caption(s.saved_name.unwrap_or("not saved yet"), None),
    Run(
      @parts.row("New", key=Some("Mod+Alt+N"), mark=Some("file-plus")),
      a.new_file,
    ),
    Run(
      @parts.row(
        "Open",
        key=Some("Mod+O"),
        mark=Some("folder-open"),
        disabled=unless(s.can_open, access),
      ),
      a.open,
    ),
    // 覚えている文書。**選ぶのは人**（起動時に勝手に開き直すのはやめた）
    Sub(
      @parts.row(
        "Recent",
        mark=Some("clock"),
        disabled=unless(s.recent.length() > 0, "Nothing opened yet"),
      ),
      s.recent.mapi((i, name) => Run(@parts.row(name), () => (a.open_recent)(i))),
      None,
    ),
    Run(
      @parts.row(
        "Save",
        key=Some("Mod+S"),
        mark=Some("save"),
        disabled=unless(s.can_save, access),
      ),
      a.save,
    ),
    // 「as」は Save と同じ操作の別名なので、絵は主の行にだけ付ける
    Run(
      @parts.row(
        "Save as",
        key=Some("Mod+Shift+S"),
        disabled=unless(s.can_save, access),
      ),
      a.save_as,
    ),
    Run(
      @parts.row(
        "Rename",
        mark=Some("pencil"),
        disabled=match rename_problem(s.can_rename, s.saved_name is Some(_)) {
          Some(why) => Why(why)
          None => No
        },
      ),
      a.rename,
    ),
    Caption(s.folder, None),
    // **保存していないことでは沈めない。** 押した先で保存まで案内する（駅）。
    // 沈むのは、この環境がフォルダを選べないときだけ
    Run(
      @parts.row(
        "Choose folder",
        mark=Some("folder"),
        disabled=unless(s.can_choose_folder, access),
      ),
      a.choose_folder,
    ),
  ]
}

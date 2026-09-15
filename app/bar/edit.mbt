// 帯の Edit。本文を変える操作のうち、どこから押しても同じ相手に効くもの。
// **いまは Undo / Redo だけ** — 履歴は md と Mindmap で 1 本なので、どちらの
// ペインを持っていても行き先が変わらない。
//
// 並びは純粋な表（files.mbt と同じ作り）。押されたら `EditActs` を呼ぶだけ

///|
pub(all) struct EditActs {
  undo : () -> Unit
  redo : () -> Unit
}

///|
pub fn edit_menu(a : EditActs) -> Array[@parts.Entry] {
  [
    Run(@parts.row("Undo", key=Some("Mod+Z"), mark=Some("undo-2")), a.undo),
    Run(
      @parts.row("Redo", key=Some("Mod+Shift+Z"), mark=Some("redo-2")),
      a.redo,
    ),
  ]
}

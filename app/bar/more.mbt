// 帯の `⋯`。低頻度だが消したくないものの受け皿。3 つの塊 — 戻す / 見た目と手触り / 外に開く。
//
// 並びは純粋な表（files.mbt と同じ作り）。いまの状態を受けて行を返し、
// 押されたら `MoreActs` を呼ぶだけ。外に開く先はここが知っていて、開くのは `visit`

///|
/// リポジトリの行き先。ここ 1 か所
let repo = "https://github.com/Project-Starlivia/mmm"

///|
pub(all) struct More {
  light : Bool
  /// 掴みやすさ（Easy grab）が入っているか
  grab : Bool
  /// リンクにまつわる押す前の但し書き。届いたら行に付く
  link_caveat : @parts.Caveat
}

///|
pub(all) struct MoreActs {
  undo : () -> Unit
  redo : () -> Unit
  pick_color : () -> Unit
  toggle_theme : () -> Unit
  toggle_grab : () -> Unit
  /// 写せたか。写せたことは押した行の絵が言う
  copy_link : ((Bool) -> Unit) -> Unit
  /// 外の場所（URL）を別のタブで開く
  visit : (String) -> Unit
}

///|
pub fn more_menu(s : More, a : MoreActs) -> Array[@parts.Entry] {
  [
    Run(@parts.row("Undo", key=Some("Mod+Z"), mark=Some("undo-2")), a.undo),
    Run(
      @parts.row("Redo", key=Some("Mod+Shift+Z"), mark=Some("redo-2")),
      a.redo,
    ),
    Sep,
    Run(@parts.row("Accent color", mark=Some("palette")), a.pick_color),
    // 絵は「押すと何になるか」（切り替えた先）を言う。字と同じ向き。
    // **閉じない**（`Flip`）— 変わったのは画面の見え方そのものなので、
    // 押した場所から確かめられるし、行がその場で次の状態を名乗る
    Flip(
      @parts.row(
        if s.light {
          "Dark theme"
        } else {
          "Light theme"
        },
        mark=Some(if s.light { "moon" } else { "sun" }),
      ),
      a.toggle_theme,
    ),
    // 見た目は変えず、叩ける範囲を箱の外まで広げる。絵も切り替えた先 — 広げるなら破線の箱、戻すなら照準
    Flip(
      @parts.row(
        if s.grab {
          "Exact hit"
        } else {
          "Easy grab"
        },
        mark=Some(if s.grab { "crosshair" } else { "square-dashed" }),
      ),
      a.toggle_grab,
    ),
    Sep,
    // 但し書きは待たずに開いて、届いたら埋まる（測るのに gzip が要る）
    Done(
      @parts.row("Copy link", mark=Some("link"), caveat=Some(s.link_caveat)),
      a.copy_link,
    ),
    Sep,
    Run(@parts.row("Shortcuts", mark=Some("keyboard")), () => {
      (a.visit)(repo + "/blob/main/docs/shortcuts.md")
    }),
    Run(@parts.row("GitHub", mark=Some("mark-github")), () => (a.visit)(repo)),
  ]
}

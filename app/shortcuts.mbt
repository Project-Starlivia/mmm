// アプリ全体のキー。ペインの中のキーはそれぞれのペインが持つので、ここに
// 居るのは「どこにフォーカスがあっても効くもの」だけ。
//
// なぜこの組み合わせなのか:
// - `Mod+N` はブラウザの「新規ウィンドウ」に吸われてページまで来ないので、
//   新規は `Mod+Alt+N`
// - ペインの表示切り替えは `Alt+数字`。矢印は使えない（`Ctrl+←→` はテキスト欄の
//   単語移動で、書いている最中に一番使う）。`Ctrl+数字`（タブ切替）/ `Ctrl+J`
//   （ダウンロード）/ `Ctrl+Shift+R`（再読込）はブラウザの予約で、`Ctrl+\` は
//   JIS 配列で物理位置が変わる。消去法で残るのが `Alt+数字`
// - 書き出しは `Mod+E`。`E` はブラウザに予約されておらず（`Ctrl+S`/`Ctrl+O`
//   と同じく preventDefault で上書きできる）、JIS 配列でも物理位置が動かない

///|
/// キーで呼ぶもの
pub(all) struct Shortcuts {
  /// 保存。真なら別名で
  save : (Bool) -> Unit
  open : () -> Unit
  create : () -> Unit
  /// 隠れているペインを出して、フォーカスを移す
  toggle_pane : () -> Unit
  /// そのペインの表示 / 非表示
  toggle_pane_vis : (Pane) -> Unit
  undo : () -> Unit
  redo : () -> Unit
  /// いまの出し方で即書き出し。真なら出し方を選び直すメニューを開く
  export_map : (Bool) -> Unit
}

///|
/// その場の入力欄（ラベル欄など）にフォーカスが在るか。ネイティブの欄は自分の
/// Undo/Redo を持つので、そこでは全体のショートカットに譲る（docs/shortcuts.md）
fn in_field(e : @core.Any) -> Bool {
  let tag : String? = @core.identity_option(e._get("target")._get("tagName"))
  match tag {
    Some("INPUT") | Some("TEXTAREA") => true
    _ => false
  }
}

///|
/// 答えを待つ窓（`<dialog>`。たずね・お絵描き）の中か。窓が開いている間は
/// 窓がキーを持つ — 文書の undo や保存が、窓の下で動いてはいけない
fn in_dialog(e : @core.Any) -> Bool {
  @web.target_in(e, "dialog") is Some(_)
}

///|
fn init_shortcuts(doc : @dom.Document, deps : Shortcuts) -> Unit {
  // capture で拾う。CodeMirror などが先に食べてしまう前に決める
  @web.on_window(
    doc,
    "keydown",
    e => {
      let k = @web.keyboard(e)
      if k.isComposing || k.keyCode == 229 || in_dialog(e) {
        return
      }
      // **md ペインの Escape は帯へ抜ける。** Tab は字下げに使うので、
      // キーボードだけで帯やブラウザへ戻る道が他に無い（WCAG 2.1.2）。
      // 欄（ラベル・カードの編集）は自分の Escape を持つので譲る。
      // 地図は選択を解いてから抜けるので、自分の表（map/keys.mbt）が持つ
      if k.key == "Escape" &&
        !k.ctrlKey &&
        !k.metaKey &&
        !k.altKey &&
        !k.shiftKey &&
        !in_field(e) &&
        @web.target_in(e, "#md-pane") is Some(_) {
        @web.prevent(e)
        @web.stop(e)
        focus_bar(doc)
        return
      }
      guard k.ctrlKey || k.metaKey else { return }
      match k.key.to_lower() {
        "s" => {
          @web.prevent(e)
          (deps.save)(k.shiftKey) // Shift = 別名で保存
        }
        "n" =>
          if k.altKey {
            @web.prevent(e)
            (deps.create)()
          }
        "o" => {
          @web.prevent(e)
          (deps.open)()
        }
        "/" => {
          @web.prevent(e)
          (deps.toggle_pane)()
        }
        "e" => {
          @web.prevent(e)
          (deps.export_map)(k.shiftKey) // Shift = 出し方を選び直す
        }
        "z" | "y" =>
          if !in_field(e) {
            @web.prevent(e)
            @web.stop(e)
            if k.key.to_lower() == "y" || k.shiftKey {
              (deps.redo)()
            } else {
              (deps.undo)()
            }
          }
        _ => ()
      }
    },
    capture=true,
  )
  @web.on_window(doc, "keydown", e => {
    let k = @web.keyboard(e)
    if k.isComposing || k.keyCode == 229 {
      return
    }
    guard k.altKey && !k.ctrlKey && !k.metaKey else { return }
    if in_field(e) || in_dialog(e) {
      return // 欄の中では Alt+数字も欄自身に譲る
    }
    let pane = match k.key {
      "1" => Some(Md)
      "2" => Some(Map)
      _ => None
    }
    guard pane is Some(p) else { return }
    @web.prevent(e)
    (deps.toggle_pane_vis)(p)
  })
}

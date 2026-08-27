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
//   と同じく preventDefault で上書きできる）、JIS 配列でも物理位置が動かない。
//   `Shift` で出し方を選び直すのは `Mod+S`/`Mod+Shift+S` と同じ形

export function initShortcuts(deps: {
  save: (asNew: boolean) => void;
  open: () => void;
  create: () => void;
  /** 隠れているペインを出して、フォーカスを移す */
  togglePane: () => void;
  /** そのペインの表示/非表示 */
  togglePaneVis: (which: "md" | "map") => void;
  undo: () => void;
  redo: () => void;
  /** 素の Mod+E はいまの出し方で即書き出し、Shift はラジアルメニューで選び直す */
  export: (pickWay: boolean) => void;
  /**
   * その場の入力欄（ラベル / カード）が開いているか。開いている間の
   * `Mod+Z` は**その欄のネイティブな undo**に任せる — 文書の undo を
   * 割り込ませると、開いたままの入力欄が指す範囲だけが古くなり、
   * 確定で別の場所を上書きしてしまう
   */
  isEditing: () => boolean;
}): void {
  // capture で拾う。CodeMirror などが先に食べてしまう前に決める
  window.addEventListener(
    "keydown",
    (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      if (!(e.ctrlKey || e.metaKey)) return;
      const key = e.key.toLowerCase();
      if (key === "s") {
        e.preventDefault();
        deps.save(e.shiftKey); // Shift = 別名で保存
      } else if (key === "n" && e.altKey) {
        e.preventDefault();
        deps.create();
      } else if (key === "o") {
        e.preventDefault();
        deps.open();
      } else if (key === "/") {
        e.preventDefault();
        deps.togglePane();
      } else if (key === "e") {
        e.preventDefault();
        deps.export(e.shiftKey);
      } else if (key === "z" || key === "y") {
        if (deps.isEditing()) return;
        e.preventDefault();
        e.stopPropagation();
        if (key === "y" || e.shiftKey) deps.redo();
        else deps.undo();
      }
    },
    { capture: true },
  );

  window.addEventListener("keydown", (e) => {
    if (e.isComposing || e.keyCode === 229) return;
    if (!e.altKey || e.ctrlKey || e.metaKey) return;
    // 表から引くと値が `string` になり、`as` で締め直すことになる。
    // 2 つしか無いのだから、そのまま書けば型が分かる
    const pane = e.key === "1" ? "md" : e.key === "2" ? "map" : null;
    if (!pane) return;
    e.preventDefault();
    deps.togglePaneVis(pane);
  });
}

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

/** その場の入力欄（ラベル欄など）にフォーカスが在るか。ネイティブの欄は自分の
 *  Undo/Redo を持つので、そこでは全体のショートカットに譲る（docs/shortcuts.md） */
const inField = (e: KeyboardEvent): boolean =>
  e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement;

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
  /** いまの出し方で即書き出し */
  export: () => void;
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
        deps.export();
      } else if ((key === "z" || key === "y") && !inField(e)) {
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
    if (inField(e)) return; // 欄の中では Alt+数字も欄自身に譲る
    // 表から引くと値が `string` になり、`as` で締め直すことになる。
    // 2 つしか無いのだから、そのまま書けば型が分かる
    const pane = e.key === "1" ? "md" : e.key === "2" ? "map" : null;
    if (!pane) return;
    e.preventDefault();
    deps.togglePaneVis(pane);
  });
}

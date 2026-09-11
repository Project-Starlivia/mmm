// 入口。**ts に残るのは CodeMirror（md ペイン）だけ** — 文書の真実はその中の文字列で、
// 文書から導けるもの（core の読み・地図の選択の位置・持ち主・選択）は EditorState の
// field（state.ts）に居る。束ねるのは core（app/app.mbt）で、ここは CodeMirror の読み書きを
// 閉包で渡し、1 トランザクションごとにサイクルを回すだけ。

// style.css は index.html の <link> で読む（FOUC を避けるため head 側）
import * as core from "./app.ts";
import * as st from "./state.ts";
import { MdEditor } from "./editor.ts";
import { languageEpoch, onLanguageReady, tokenize, tokenizeBlock } from "./highlight.ts";

const pane = document.getElementById("md-pane");
if (!(pane instanceof HTMLElement)) throw new Error("#md-pane が無い");

// 1 トランザクション = 1 サイクル。木が変わったかは field の同一性で分かる（prev が null なら
// 文書を丸ごと入れ替えた）。組んでいる最中のトランザクション（テーマの初期値）はまだ受け手が無い —
// 最初のサイクルは boot の set_text が回す
let app: core.App | null = null;
const editor = new MdEditor(pane, (s, prev) => {
  if (app === null) return;
  const t = s.field(st.tree);
  core.cycle(app, prev === null ? null : prev.field(st.tree), prev === null || prev.field(st.tree) !== t);
});

app = core.main({
  text: () => editor.text(),
  survey: () => editor.state.field(st.tree),
  holder: () => editor.state.field(st.holder),
  selection: () => core.selection(editor.state.field(st.choice)),
  picked: () => core.card(editor.state.field(st.choice)),
  setText: (t) => editor.setText(t),
  apply: (sets, held, focus) => editor.apply(sets, held ? focus : undefined),
  select: (a) => editor.select(a),
  hold: (h, a) => editor.hold(h, a),
  reveal: (pos) => editor.reveal(pos),
  undo: () => editor.undo(),
  redo: () => editor.redo(),
  focus: () => editor.focus(),
  setTheme: (dark) => editor.setTheme(dark),
  showHint: (on) => editor.showHint(on),
  tokens: tokenize,
  tokensBlock: tokenizeBlock,
  epoch: languageEpoch,
  onLanguageReady,
});

core.boot(app);

// Markdown のペイン。CodeMirror 6。**文書の真実はこの中の文字列**で、履歴も
// CodeMirror が持つ。打鍵のたびに `onChange(text)` で全文を渡し、受け手が
// core に読ませて map を描き直す（サイクルは 1 本。読みは決して書かない）。

import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers } from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
  redo as cmRedo,
  undo as cmUndo,
} from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { languages } from "./map/highlight.ts";
import { defaultHighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { oneDarkHighlightStyle, oneDarkTheme } from "@codemirror/theme-one-dark";
import { paneHint } from "./app/hint.ts";

/**
 * CodeMirror へは **`dark` かどうかだけ**を渡す（自身の既定のスタイルが
 * それで振れる）。**色は 1 つも持たない** — 地もキャレットも style.css の
 * `#md-pane` の並びが決める。
 */
const tweaks = (dark: boolean) => EditorView.theme({}, { dark });

const DARK_EXT = [oneDarkTheme, tweaks(true), syntaxHighlighting(oneDarkHighlightStyle)];
const LIGHT_EXT = [tweaks(false), syntaxHighlighting(defaultHighlightStyle)];

export class MdEditor {
  readonly view: EditorView;
  private themeComp = new Compartment();
  private dark = true;
  /** まだノードが 1 つも無いときに出る言い出し。出す／引っ込めるを決めるのは main.ts */
  private hint: HTMLDivElement;
  private onChange: (text: string) => void;

  constructor(parent: HTMLElement, onChange: (text: string) => void) {
    this.onChange = onChange;
    // 空のときの言い出し。**マップと同じ器**（app/hint.ts）を、同じように
    // ペインの真ん中へ浮かべる — CodeMirror の `placeholder` は 1 行目の
    // 頭に出るので、対のもう片方（マップの中央）と上下も寄せも揃わない。
    // 見えるのはこちらで、読み上げには下の `aria-placeholder` が答える
    this.hint = paneHint("Write a ", "# heading", " to start");
    parent.append(this.hint);
    this.view = new EditorView({ parent, state: this.state("") });
  }

  /** 文書 1 つぶんの状態。丸ごと入れ替えるときは履歴も一緒に捨てる（前の文書へ undo で戻らない） */
  private state(doc: string): EditorState {
    return EditorState.create({
      doc,
      extensions: [
        lineNumbers(),
        history(),
        // 見た目は上の `.pane-hint` が持つので、ここは読み上げにだけ答える
        EditorView.contentAttributes.of({ "aria-placeholder": "Write a # heading to start" }),
        // フェンスの中も言語で色を付ける。言語一覧はマップのコードカードと
        // 同じものを渡す — 同じフェンスが 2 つの窓で違う色になると、
        // 食い違ったときに理由が説明できない。読み込みは CodeMirror が持つ
        markdown({ codeLanguages: languages }),
        this.themeComp.of(this.dark ? DARK_EXT : LIGHT_EXT),
        EditorView.lineWrapping,
        keymap.of([indentWithTab, ...defaultKeymap, ...historyKeymap]),
        EditorView.updateListener.of((u) => {
          if (u.docChanged) this.onChange(u.state.doc.toString());
        }),
      ],
    });
  }

  text(): string {
    return this.view.state.doc.toString();
  }

  /** 白紙の言い出しを出す／引っ込める。判定は main.ts が持つ（マップ側と同じ 1 つの判断） */
  showHint(on: boolean): void {
    this.hint.style.display = on ? "flex" : "none";
  }

  /** 文書を丸ごと入れ替える（開く / 新規）。履歴も新しくなる。setState は listener を呼ばないので自分で言う */
  setText(text: string): void {
    this.view.setState(this.state(text));
    this.onChange(text);
  }

  undo(): void {
    cmUndo(this.view);
  }

  redo(): void {
    cmRedo(this.view);
  }

  focus(): void {
    this.view.focus();
  }

  setTheme(dark: boolean): void {
    this.dark = dark;
    this.view.dispatch({ effects: this.themeComp.reconfigure(dark ? DARK_EXT : LIGHT_EXT) });
  }
}

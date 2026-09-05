// Markdown のペイン。CodeMirror 6。**文書の真実はこの中の文字列**で、履歴も
// CodeMirror が持つ。打鍵のたびに `onChange(text)` で全文を渡し、受け手が
// core に読ませて map を描き直す（サイクルは 1 本。読みは決して書かない）。

import { ChangeSet, Compartment, EditorState, StateEffect, StateField } from "@codemirror/state";
import { Decoration, type DecorationSet, EditorView, keymap, lineNumbers } from "@codemirror/view";
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
import type * as core from "./coreApi.ts";
import type { Range } from "./caret.ts";

/**
 * CodeMirror へは **`dark` かどうかだけ**を渡す（自身の既定のスタイルが
 * それで振れる）。**色は 1 つも持たない** — 地もキャレットも style.css の
 * `#md-pane` の並びが決める。
 */
const tweaks = (dark: boolean) => EditorView.theme({}, { dark });

const DARK_EXT = [oneDarkTheme, tweaks(true), syntaxHighlighting(oneDarkHighlightStyle)];
const LIGHT_EXT = [tweaks(false), syntaxHighlighting(defaultHighlightStyle)];

/** 地図で選んでいる範囲。実選択にするとカーソルを奪うので、装飾で塗る（spec.md「二つをまたぐ印」） */
const setHighlights = StateEffect.define<Range[]>();
const highlightMark = Decoration.mark({ class: "cm-mmm-selected" });
const highlightField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    let next = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (e.is(setHighlights)) {
        next = Decoration.set(
          e.value.filter((r) => r.to > r.from).map((r) => highlightMark.range(r.from, r.to)),
          true,
        );
      }
    }
    return next;
  },
  provide: (f) => EditorView.decorations.from(f),
});

export class MdEditor {
  readonly view: EditorView;
  private themeComp = new Compartment();
  private dark = true;
  /** まだノードが 1 つも無いときに出る言い出し。出す／引っ込めるを決めるのは main.ts */
  private hint: HTMLDivElement;
  private onChange: (text: string, edits: core.Edit[]) => void;
  private onCaret: (ranges: Range[]) => void;

  constructor(
    parent: HTMLElement,
    onChange: (text: string, edits: core.Edit[]) => void,
    onCaret: (ranges: Range[]) => void,
  ) {
    this.onChange = onChange;
    this.onCaret = onCaret;
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
        highlightField,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) {
            // 何がどう変わったかを、前の座標の編集列にして渡す。選択の持ち越しが使う
            const edits: core.Edit[] = [];
            u.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
              edits.push({ from: fromA, to: toA, insert: inserted.toString() });
            });
            this.onChange(u.state.doc.toString(), edits);
          }
          if (u.docChanged || u.selectionSet || u.focusChanged) this.onCaret(this.caret());
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

  /** 文書を丸ごと入れ替える（開く / 新規）。履歴も新しくなる。setState は listener を呼ばないので自分で言う。
   *  編集列は全文の置き換え — 前の文書の目印は全部死ぬ */
  setText(text: string): void {
    const before = this.view.state.doc.length;
    this.view.setState(this.state(text));
    // CodeMirror は内部を常に LF で持つので、真実は引数でなく doc（core.md「改行」）。
    // CRLF の文書を渡すと EditorState.create が \r\n?|\n で割って LF の行として
    // 保つので、以降 doc.toString() は引数と食い違う
    const doc = this.view.state.doc.toString();
    this.onChange(doc, [{ from: 0, to: before, insert: doc }]);
    this.onCaret(this.caret());
  }

  /**
   * 操作の編集列を 1 トランザクションで当てる。undo は 1 手になる。sync はこの中で走る。
   * 編集列を 2 つ以上渡せば**順に**当てる（後の列の座標は前の列を当てた後の md）—
   * 続けて映した操作の組が 1 手になる
   */
  apply(...sets: core.Edit[][]): void {
    let changes = ChangeSet.empty(this.view.state.doc.length);
    for (const set of sets) changes = changes.compose(ChangeSet.of(set, changes.newLength));
    this.view.dispatch({ changes });
  }

  /** 地図で選んでいる範囲を、こちらの行にも映す */
  highlight(ranges: Range[]): void {
    this.view.dispatch({ effects: setHighlights.of(ranges) });
  }

  /** その位置を中央へ。地図で選び直したときだけ呼ぶ（打鍵のたびに寄せると手元が揺れる） */
  reveal(pos: number): void {
    if (pos < 0 || pos > this.view.state.doc.length) return;
    this.view.dispatch({ effects: EditorView.scrollIntoView(pos, { y: "center" }) });
  }

  /**
   * いまのカーソルと選択の範囲（複数カーソルならその数だけ）。**このペインに
   * フォーカスが無ければ空** — 「いまどこを書いているか」はここに居るあいだだけの事実
   */
  caret(): Range[] {
    if (!this.view.hasFocus) return [];
    return this.view.state.selection.ranges.map((r) => ({ from: r.from, to: r.to }));
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

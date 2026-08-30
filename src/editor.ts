// Markdown pane: CodeMirror 6 without its own history. Every user edit is
// forwarded to the core (both panes share one undo stack); edits coming from
// the core are dispatched with the `fromCore` annotation so they are not
// forwarded back (no echo loop).

import {
  Annotation,
  Compartment,
  EditorState,
  StateEffect,
  StateField,
} from "@codemirror/state";
import {
  Decoration,
  type DecorationSet,
  EditorView,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { defaultKeymap, indentWithTab } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { languages } from "./map/highlight.ts";
import {
  defaultHighlightStyle,
  syntaxHighlighting,
} from "@codemirror/language";
import { oneDarkHighlightStyle, oneDarkTheme } from "@codemirror/theme-one-dark";
import type { EditOp } from "./coreApi.ts";
import { paneHint } from "./app/hint.ts";

// 地の色はここに持たない。ペインが敷くものを style.css が宣言する
const darkTweaks = EditorView.theme(
  {
    ".cm-content": { caretColor: "var(--accent)" },
    ".cm-cursor": { borderLeftColor: "var(--accent)" },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
      backgroundColor: "color-mix(in srgb, var(--accent) 30%, transparent)",
    },
    ".cm-activeLine": { backgroundColor: "rgba(255, 255, 255, 0.03)" },
  },
  { dark: true },
);

const lightTweaks = EditorView.theme(
  {
    ".cm-content": { caretColor: "var(--accent)" },
    ".cm-cursor": { borderLeftColor: "var(--accent)" },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
      backgroundColor: "color-mix(in srgb, var(--accent) 22%, transparent)",
    },
    ".cm-activeLine": { backgroundColor: "rgba(0, 0, 0, 0.04)" },
  },
  { dark: false },
);

const DARK_EXT = [
  oneDarkTheme,
  darkTweaks,
  syntaxHighlighting(oneDarkHighlightStyle),
];
const LIGHT_EXT = [lightTweaks, syntaxHighlighting(defaultHighlightStyle)];

const fromCore = Annotation.define<boolean>();

const setHighlights = StateEffect.define<{ from: number; to: number }[]>();

const highlightMark = Decoration.mark({ class: "cm-mmm-selected" });

const highlightField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (e.is(setHighlights)) {
        // 第 2 引数は「並べ替えてから受け取れ」。選択は Set なので**入れた順**
        // で、Mod+クリックで文書順と逆に選ぶと from が降順で届く。
        // CodeMirror は昇順を要求して例外を投げ、ハイライトが丸ごと死ぬ
        deco = Decoration.set(
          e.value
            .filter((r) => r.from < r.to)
            .map((r) => highlightMark.range(r.from, r.to)),
          true,
        );
      }
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});

export class MdEditor {
  readonly view: EditorView;
  private themeComp = new Compartment();
  /** まだノードが 1 つも無いときに出る言い出し。出す／引っ込めるを決めるのは
   *  applySnap（main.ts）で、マップ側の同じ言い出しと 1 つの判断を共有する */
  private hint: HTMLDivElement;

  constructor(
    parent: HTMLElement,
    onUserEdits: (edits: EditOp[], userEvent: string) => void,
  ) {
    // 空のときの言い出し。**マップと同じ器**（app/hint.ts）を、同じように
    // ペインの真ん中へ浮かべる — CodeMirror の `placeholder` は 1 行目の
    // 頭に出るので、対のもう片方（マップの中央）と上下も寄せも揃わない。
    // 見えるのはこちらで、読み上げには下の `aria-placeholder` が答える
    this.hint = paneHint("Write a ", "# heading", " to start");
    parent.append(this.hint);

    this.view = new EditorView({
      parent,
      state: EditorState.create({
        doc: "",
        extensions: [
          lineNumbers(),
          // 見た目は上の `.pane-hint` が持つので、ここは読み上げにだけ答える
          EditorView.contentAttributes.of({
            "aria-placeholder": "Write a # heading to start",
          }),
          highlightField,
          // フェンスの中も言語で色を付ける。言語一覧はマップのコードカードと
          // 同じものを渡す — 同じフェンスが 2 つの窓で違う色になると、
          // 食い違ったときに理由が説明できない。読み込みは CodeMirror が持つ
          markdown({ codeLanguages: languages }),
          this.themeComp.of(DARK_EXT),
          EditorView.lineWrapping,
          keymap.of([indentWithTab, ...defaultKeymap]),
          EditorView.domEventHandlers({
            // boundary marker so two separate IME compositions never merge
            // into one undo entry
            compositionend: () => {
              onUserEdits([], "compose.end");
              return false;
            },
          }),
          EditorView.updateListener.of((u) => {
            if (!u.docChanged) return;
            for (const tr of u.transactions) {
              if (!tr.docChanged || tr.annotation(fromCore)) continue;
              let userEvent = "";
              for (const kind of [
                "input.type.compose", // must precede its prefix "input.type"
                "input.type",
                "delete.backward",
                "delete",
                "input.paste",
                "move.drop",
                "input",
              ]) {
                if (tr.isUserEvent(kind)) {
                  userEvent = kind;
                  break;
                }
              }
              const edits: EditOp[] = [];
              tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
                edits.push({
                  from: fromA,
                  to: toA,
                  insert: inserted.toString(),
                });
              });
              onUserEdits(edits, userEvent);
            }
          }),
        ],
      }),
    });
  }

  /**
   * 白紙の言い出しを出す／引っ込める。**判定はここが持たない** —
   * 「まだ 1 つもノードが無いか」はコアのスナップショットが答えることで、
   * md ペインからは見えない。呼ぶのは applySnap（main.ts）1 か所で、
   * マップ側の同じ言い出しと**同じ 1 つの判断**から両方が動く。
   */
  showHint(on: boolean): void {
    this.hint.style.display = on ? "flex" : "none";
  }

  /** Replace the entire document (file open / new). */
  setText(text: string): void {
    this.view.dispatch({
      changes: { from: 0, to: this.view.state.doc.length, insert: text },
      annotations: fromCore.of(true),
    });
  }

  /** Apply core-originated edit sets, in order. */
  applySets(sets: EditOp[][]): void {
    for (const set of sets) {
      if (set.length === 0) continue;
      this.view.dispatch({
        changes: set.map((e) => ({ from: e.from, to: e.to, insert: e.insert })),
        annotations: fromCore.of(true),
      });
    }
  }

  /** マップで選ばれている範囲を、こちらの行にも映す。 */
  highlight(ranges: { from: number; to: number }[]): void {
    this.view.dispatch({ effects: setHighlights.of(ranges) });
  }

  reveal(pos: number): void {
    if (pos < 0 || pos > this.view.state.doc.length) return;
    this.view.dispatch({
      effects: EditorView.scrollIntoView(pos, { y: "center" }),
    });
  }

  focus(): void {
    this.view.focus();
  }

  setTheme(dark: boolean): void {
    this.view.dispatch({
      effects: this.themeComp.reconfigure(dark ? DARK_EXT : LIGHT_EXT),
    });
  }
}

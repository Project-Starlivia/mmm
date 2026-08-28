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
import type { Span } from "./caret.ts";

/**
 * CodeMirror へは **`dark` かどうかだけ**を渡す（自身の既定のスタイルが
 * それで振れる）。**色は 1 つも持たない** — 地もキャレットも style.css の
 * `#md-pane` の並びが決める。
 *
 * ここに色を書いていた頃は、書いたとおりにならなかった。選択・カーソル・
 * アクティブ行の色は `drawSelection()` も `highlightActiveLine()` も入れて
 * いないため要素が 1 つも作られず、地とキャレットはダークで後から当たる
 * `oneDarkTheme` に負けていた（md ペインだけ地が `#282c34` になり、
 * ガターの `--panel` と割れていた）。CSS の側で当てれば普通の詳細度で
 * 勝てるので、色の置き場所を 1 つに寄せた。
 */
const tweaks = (dark: boolean) => EditorView.theme({}, { dark });

const DARK_EXT = [
  oneDarkTheme,
  tweaks(true),
  syntaxHighlighting(oneDarkHighlightStyle),
];
const LIGHT_EXT = [tweaks(false), syntaxHighlighting(defaultHighlightStyle)];

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

  constructor(
    parent: HTMLElement,
    onUserEdits: (edits: EditOp[], userEvent: string) => void,
    /** カーソルか選択が動いた（値の意味は下の `caret()`）。よそへ移った
     *  瞬間も呼ばれるので、受け手は印を消せる */
    onCaret: (spans: Span[]) => void,
  ) {
    this.view = new EditorView({
      parent,
      state: EditorState.create({
        doc: "",
        extensions: [
          lineNumbers(),
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
            if (u.docChanged) {
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
            }
            // カーソルの居場所。文書が変わったときは**送り終えた後で**言う —
            // 受け手は新しいテキストのオフセットとして読むため
            if (u.docChanged || u.selectionSet || u.focusChanged) {
              onCaret(this.caret());
            }
          }),
        ],
      }),
    });
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

  /**
   * いまのカーソルと選択の範囲（複数カーソルならその数だけ。ただの
   * カーソルは `from === to` の点）。**このペインにフォーカスが無ければ空** —
   * 「いまどこを書いているか」はここに居るあいだだけの事実で、窓ごと
   * 裏に回っているときも同じ（`hasFocus` がそこまで見てくれる）。
   *
   * 普段は動くたびに `onCaret` が言うが、**文書を丸ごと入れ替えたときだけ**
   * 呼ぶ側から聞き直す必要がある（`setText` が走る時点では、受け手の
   * ノードがまだ前の文書のもの）。
   */
  caret(): Span[] {
    if (!this.view.hasFocus) return [];
    return this.view.state.selection.ranges.map((r) => ({ from: r.from, to: r.to }));
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

// lab の 2 つの画面（読み書き / 反映）が共に使うもの — md の入力欄と見本。
//
// ここも**見るための道具**で、解釈は持たない。

import { EditorView, keymap, lineNumbers } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { oneDark } from "@codemirror/theme-one-dark";

/** 見て回りたくなる形を、最初から手元に置いておく。 */
export const SAMPLES: [string, string][] = [
  ["見出しだけ", "# root\n\n## a\n\n## b\n"],
  ["深さ 3", "# root\n\n## a\n\n### x\n\n## b\n"],
  ["飛び", "# root\n\n### x\n"],
  ["木 2 本", "# a\n\n# b\n"],
  ["根が無い", "## a\n\n## b\n"],
  ["字下げコード", "# a\n    # x\n"],
  ["項目", "- root\n  - a\n  - b\n"],
  ["区切り", "# r\n\n## a\n\n---\n\n## b\n"],
  ["飾りの線", "# r\n\n***\n\n## a\n"],
  ["畳み", "# r\n\n<details>\n\n## a\n\n</details>\n"],
  ["封筒", "---\nk: v\n---\n\n# a\n"],
  ["7 個以上の #", "###### f\n\n####### g\n"],
];

/** 名乗らせず確かめる（外れていても誰も気づけないため）。 */
export function pick<T extends Element>(id: string, kind: new () => T): T {
  const el = document.getElementById(id);
  if (!(el instanceof kind)) throw new Error(`#${id} が ${kind.name} ではない`);
  return el;
}

/** md の入力欄。打つたびに onChange。中身は localStorage の key に残す。 */
export function mountEditor(
  key: string,
  onChange: (text: string) => void,
): EditorView {
  const editor = new EditorView({
    parent: pick("md", HTMLDivElement),
    state: EditorState.create({
      doc: localStorage.getItem(key) ?? SAMPLES[0][1],
      extensions: [
        lineNumbers(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        markdown(),
        oneDark,
        EditorView.lineWrapping,
        EditorView.updateListener.of((v) => {
          if (v.docChanged) {
            localStorage.setItem(key, v.state.doc.toString());
            onChange(v.state.doc.toString());
          }
        }),
      ],
    }),
  });
  const samples = pick("samples", HTMLDivElement);
  for (const [name, text] of SAMPLES) {
    const b = document.createElement("button");
    b.textContent = name;
    b.addEventListener("click", () => {
      editor.dispatch({
        changes: { from: 0, to: editor.state.doc.length, insert: text },
      });
      editor.focus();
    });
    samples.append(b);
  }
  return editor;
}

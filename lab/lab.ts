// md を打つたびに mdAst・mmmTree・View と、書き戻した md を出す。
//
// ここは**見るための道具**なので、解釈は 1 つも持たない。
// 規則はすべて core にあり、この画面はその出力を並べるだけ。

import { EditorView, keymap, lineNumbers } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { oneDark } from "@codemirror/theme-one-dark";
import * as mbt from "../core/_build/js/release/build/tree/js/js.js";
import { paintAst, paintTree } from "./paint.ts";

/** 見て回りたくなる形を、最初から手元に置いておく。 */
const SAMPLES: [string, string][] = [
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
  ["frontmatter", "---\nk: v\n---\n\n# a\n"],
  ["7 個以上の #", "###### f\n\n####### g\n"],
];

/** 名乗らせず確かめる（外れていても誰も気づけないため）。 */
function pick<T extends Element>(id: string, kind: new () => T): T {
  const el = document.getElementById(id);
  if (!(el instanceof kind)) throw new Error(`#${id} が ${kind.name} ではない`);
  return el;
}

const out = {
  ast: pick("ast", HTMLPreElement),
  check: pick("check", HTMLPreElement),
  json: pick("json", HTMLPreElement),
  view: pick("view", HTMLPreElement),
  back: pick("back", HTMLPreElement),
  out: pick("out", HTMLPreElement),
};

function show(text: string): void {
  out.ast.replaceChildren(paintAst(mbt.mdAstSig(text)));
  const flaws = mbt.mmmCheck(text);
  out.check.textContent = flaws === "[]" ? "健全" : flaws;
  out.check.classList.toggle("flawed", flaws !== "[]");
  out.json.replaceChildren(paintTree(mbt.mmmTreeJson(text)));
  out.view.replaceChildren(paintTree(mbt.mmmViewJson(text)));
  out.back.replaceChildren(paintAst(mbt.mmmUnbuildSig(text)));
  out.out.textContent = mbt.mmmSerialize(text);
  localStorage.setItem("mmm-lab", text);
}

const editor = new EditorView({
  parent: pick("md", HTMLDivElement),
  state: EditorState.create({
    doc: localStorage.getItem("mmm-lab") ?? SAMPLES[0][1],
    extensions: [
      lineNumbers(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      markdown(),
      oneDark,
      EditorView.lineWrapping,
      EditorView.updateListener.of((v) => {
        if (v.docChanged) show(v.state.doc.toString());
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

show(editor.state.doc.toString());

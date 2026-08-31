// md を打つたびに、AST の指紋・木の指紋・木ぜんぶを出す。
//
// ここは**見るための道具**なので、解釈は 1 つも持たない。
// 規則はすべて core にあり、この画面はその出力を並べるだけ。

import * as mbt from "../core/_build/js/release/build/tree/js/js.js";

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
  ["封筒", "---\nk: v\n---\n\n# a\n"],
  ["7 個以上の #", "###### f\n\n####### g\n"],
];

const md = pick<HTMLTextAreaElement>("md", HTMLTextAreaElement);
const out = {
  ast: pick<HTMLPreElement>("ast", HTMLPreElement),
  sig: pick<HTMLPreElement>("sig", HTMLPreElement),
  json: pick<HTMLPreElement>("json", HTMLPreElement),
};

/** 名乗らせず確かめる（外れていても誰も気づけないため）。 */
function pick<T extends Element>(id: string, kind: new () => T): T {
  const el = document.getElementById(id);
  if (!(el instanceof kind)) throw new Error(`#${id} が ${kind.name} ではない`);
  return el;
}

function show(): void {
  const text = md.value;
  out.ast.textContent = mbt.astSig(text);
  out.sig.textContent = mbt.treeSig(text);
  out.json.textContent = pretty(mbt.treeJson(text));
  localStorage.setItem("mmm-lab", text);
}

/** JSON を畳まずに読めるだけの整形。 */
function pretty(s: string): string {
  try {
    return JSON.stringify(JSON.parse(s), null, 2);
  } catch {
    return s;
  }
}

const samples = pick<HTMLDivElement>("samples", HTMLDivElement);
for (const [name, text] of SAMPLES) {
  const b = document.createElement("button");
  b.textContent = name;
  b.addEventListener("click", () => {
    md.value = text;
    show();
    md.focus();
  });
  samples.append(b);
}

md.value = localStorage.getItem("mmm-lab") ?? SAMPLES[0][1];
md.addEventListener("input", show);
show();

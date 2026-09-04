// 木のノード 1 つを変え、前後の木を比べて md に映した結果を出す。
//
// 変え方も比較も core（trial / reflect）が持つ。ここは編集列を色で見せるだけ。

import * as mbt from "../core/_build/js/release/build/tree/js/js.js";
import { paintAst, paintTree } from "./paint.ts";
import { mountEditor, pick } from "./shared.ts";

const out = {
  spans: pick("spans", HTMLPreElement),
  json: pick("json", HTMLPreElement),
  edits: pick("edits", HTMLPreElement),
  verdict: pick("verdict", HTMLSpanElement),
  out: pick("out", HTMLPreElement),
};
const knobs = {
  id: pick("id", HTMLInputElement),
  how: pick("how", HTMLSelectElement),
};

interface Edit {
  from: number;
  to: number;
  insert: string;
}

/** 前の md に編集列を重ねて描く。消えた字は del、差した字は ins。 */
function paintEdits(md: string, edits: Edit[]): DocumentFragment {
  const f = document.createDocumentFragment();
  let pos = 0;
  for (const e of edits) {
    f.append(md.slice(pos, e.from));
    if (e.to > e.from) {
      const d = document.createElement("del");
      d.textContent = md.slice(e.from, e.to);
      f.append(d);
    }
    if (e.insert !== "") {
      const i = document.createElement("ins");
      i.textContent = e.insert;
      f.append(i);
    }
    pos = e.to;
  }
  f.append(md.slice(pos));
  return f;
}

function show(md: string): void {
  out.spans.replaceChildren(paintAst(mbt.mmmSpansSig(md)));
  out.json.replaceChildren(paintTree(mbt.mmmTreeJson(md)));
  const raw = mbt.mmmTrial(md, Number(knobs.id.value), knobs.how.value);
  if (raw === "") return;
  const trial: { edits: Edit[]; out: string } = JSON.parse(raw);
  out.edits.textContent = JSON.stringify(trial.edits, null, 1);
  const whole =
    trial.edits.length === 1 &&
    trial.edits[0].from === 0 &&
    trial.edits[0].to === md.length;
  out.verdict.textContent = whole
    ? "1 箇所 — 文書ぜんぶ"
    : `${trial.edits.length} 箇所`;
  out.verdict.classList.toggle("whole", whole);
  out.out.replaceChildren(paintEdits(md, trial.edits));
}

const editor = mountEditor("mmm-lab", show);
for (const k of Object.values(knobs)) {
  k.addEventListener("input", () => show(editor.state.doc.toString()));
}
show(editor.state.doc.toString());

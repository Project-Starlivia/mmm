// md を打つたびに mdAst・mmmTree・View と、書き戻した md を出す。
//
// ここは**見るための道具**なので、解釈は 1 つも持たない。
// 規則はすべて core にあり、この画面はその出力を並べるだけ。

import * as mbt from "../core/_build/js/release/build/tree/js/js.js";
import { paintAst, paintTree } from "./paint.ts";
import { mountEditor, pick } from "./shared.ts";

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
}

const editor = mountEditor("mmm-lab", show);
show(editor.state.doc.toString());

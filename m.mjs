import * as fs from "node:fs";
import * as mbt from "./core/_build/js/release/build/tree/js/js.js";

const unlit = (s) => {
  let v = s;
  for (let i = 0; i < 3; i++) {
    try {
      const p = JSON.parse(v);
      if (typeof p !== "string") return v;
      v = p;
    } catch { return v; }
  }
  return v;
};

const audit = JSON.parse(fs.readFileSync("audit.json", "utf8"));
const pick = process.argv.slice(2).map(Number);
for (const i of pick) {
  const f = audit[i];
  const md = unlit(f.md);
  console.log("=== " + i + " [" + f.kind + "] " + f.title);
  console.log("md   : " + JSON.stringify(md).slice(0, 150));
  let tree;
  try { tree = mbt.mmmTreeJson(md); } catch (e) { console.log("CRASH: " + e); continue; }
  console.log("tree : " + tree.slice(0, 400));
  console.log("check: " + mbt.mmmCheck(md));
  console.log("want : " + f.want.slice(0, 200));
  console.log();
}

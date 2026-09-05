// 表を読んで枠を敷き詰める。行 = 部品 × 状態、列 = dark / light。
// 見た目は src/style.css のまま。ここは枠を作って呼ぶだけ。

import "../../src/style.css";
import { PARTS } from "./parts.ts";

/** 名乗らせず確かめる */
function pick<T extends Element>(id: string, kind: new () => T): T {
  const el = document.getElementById(id);
  if (!(el instanceof kind)) throw new Error(`#${id} が ${kind.name} ではない`);
  return el;
}

const DEFAULT_HEIGHT = 240;

const grid = pick("grid", HTMLElement);

for (const p of PARTS) {
  const sec = document.createElement("section");
  sec.id = p.name;
  const h = document.createElement("h2");
  h.textContent = p.name;
  sec.append(h);
  for (const [state, build] of Object.entries(p.states)) {
    const row = document.createElement("div");
    row.className = "row";
    const label = document.createElement("span");
    label.className = "state";
    label.textContent = state;
    row.append(label);
    for (const theme of ["dark", "light"] as const) {
      const cell = document.createElement("div");
      cell.className = theme === "light" ? "cell light" : "cell";
      cell.style.height = `${p.height ?? DEFAULT_HEIGHT}px`;
      cell.title = `${p.name} / ${state} / ${theme}`;
      cell.append(build());
      row.append(cell);
    }
    sec.append(row);
  }
  grid.append(sec);
}

// ペインの表示/非表示 (コードとノードのビュー) とスプリッタ。
// 「両方消えた」状態は作らない。片方を消したら残りが受け皿になる。
// どちらを出しているかは覚えない — 毎回、両方から始まる。
//
// **開閉の矢印は分割線にくっつける。** 前は md の右下・マップの左下と
// 別々の角に置いていて、片方だけスクロールバーを避けて内側へ寄っていた
// せいで、2 つの位置がずれて見えた。**分割線（splitter）を隠さずに
// 置き続ける** — 片方のペインを消しても flex がその境目まで splitter を
// 押し出すので、矢印はいつも同じ 1 か所（境目）に居られる。
//
// **矢印の向きが状態を言う** — 開いていれば消える先、消えていれば
// 出てくる先を指す。字は要らない。

import { icon } from "../icons.ts";
import { paneTool } from "./paneTool.ts";

export function initPanes(args: {
  mdPane: HTMLElement;
  mapPane: HTMLElement;
  panesEl: HTMLElement;
  splitter: HTMLElement;
  /** md 側のフォーカスは CodeMirror が持つので注入 */
  focusEditor: () => void;
}): {
  togglePane: () => void;
  togglePaneVis: (which: "md" | "map") => void;
} {
  const { mdPane, mapPane, panesEl, splitter } = args;
  let paneVis = { md: true, map: true };

  const arrows = paneTool("pane-switch");
  const arrowMd = arrowButton();
  const arrowMap = arrowButton();
  arrows.append(arrowMd, arrowMap);
  splitter.append(arrows);

  const applyPaneVis = (v: { md: boolean; map: boolean }): void => {
    if (!v.md && !v.map) v = { md: true, map: true };
    paneVis = v;
    mdPane.classList.toggle("pane-off", !v.md);
    mapPane.classList.toggle("pane-off", !v.map);
    panesEl.classList.toggle("no-map", !v.map);
    panesEl.classList.toggle("no-md", !v.md);
    // 開いていれば消える先（外向き）、消えていれば出てくる先（内向き）を指す
    pointArrow(arrowMd, v.md ? "left" : "right");
    arrowMd.title = v.md ? "Hide the Markdown pane (Alt+1)" : "Show the Markdown pane (Alt+1)";
    pointArrow(arrowMap, v.map ? "right" : "left");
    arrowMap.title = v.map ? "Hide the map pane (Alt+2)" : "Show the map pane (Alt+2)";
    // focus must not stay in a hidden pane
    if (!v.md && mdPane.contains(document.activeElement)) mapPane.focus();
    if (!v.map && mapPane.contains(document.activeElement)) args.focusEditor();
  };

  const togglePaneVis = (which: "md" | "map"): void => {
    const next = { ...paneVis, [which]: !paneVis[which] };
    // never end up with zero panes: hiding the last one shows the other
    if (!next.md && !next.map) next[which === "md" ? "map" : "md"] = true;
    applyPaneVis(next);
  };

  arrowMd.addEventListener("click", () => togglePaneVis("md"));
  arrowMap.addEventListener("click", () => togglePaneVis("map"));

  // Mod+/: jump to the other pane, revealing it if hidden
  const togglePane = (): void => {
    if (mdPane.contains(document.activeElement)) {
      if (!paneVis.map) applyPaneVis({ ...paneVis, map: true });
      mapPane.focus();
    } else {
      if (!paneVis.md) applyPaneVis({ ...paneVis, md: true });
      args.focusEditor();
    }
  };

  for (const pane of [mdPane, mapPane]) {
    pane.addEventListener("focusin", () => pane.classList.add("pane-focused"));
    pane.addEventListener("focusout", () => pane.classList.remove("pane-focused"));
  }

  // ---- スプリッタ ----
  // 幅を変えるだけ。開閉は境目の矢印と Alt+1 / Alt+2、Mod+/ が持つ。
  // 片方が消えているときは動かす幅が無いので、掴んでも何もしない
  splitter.addEventListener("pointerdown", (e) => {
    if (!paneVis.md || !paneVis.map) return;
    splitter.classList.add("dragging");
    splitter.setPointerCapture(e.pointerId);
    const onMove = (ev: PointerEvent): void => {
      const total = panesEl.getBoundingClientRect();
      const pct = Math.min(
        80,
        Math.max(15, ((ev.clientX - total.left) / total.width) * 100),
      );
      document.documentElement.style.setProperty("--md-width", `${pct}%`);
    };
    const onUp = (): void => {
      splitter.classList.remove("dragging");
      splitter.removeEventListener("pointermove", onMove);
      splitter.removeEventListener("pointerup", onUp);
      splitter.removeEventListener("pointercancel", onUp);
    };
    splitter.addEventListener("pointermove", onMove);
    splitter.addEventListener("pointerup", onUp);
    splitter.addEventListener("pointercancel", onUp);
  });

  // 点き具合を最初に一度そろえる（既定でも必ず通す）
  applyPaneVis(paneVis);

  return { togglePane, togglePaneVis };
}

function arrowButton(): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.append(icon("chevron"));
  return button;
}

/** 絵は 1 つだけ（下向き）なので、左右は回して作る */
function pointArrow(button: HTMLButtonElement, dir: "left" | "right"): void {
  const svg = button.querySelector(".icon");
  svg?.classList.toggle("point-left", dir === "left");
  svg?.classList.toggle("point-right", dir === "right");
}

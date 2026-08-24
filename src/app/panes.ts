// ペインの表示/非表示 (コードとノードのビュー) とスプリッタ。
// 「両方消えた」状態は作らない。片方を消したら残りが受け皿になる。
// どちらを出しているかは覚えない — 毎回、両方から始まる。

export function initPanes(args: {
  mdPane: HTMLElement;
  mapPane: HTMLElement;
  panesEl: HTMLElement;
  splitter: HTMLElement;
  mdButton: HTMLButtonElement;
  mapButton: HTMLButtonElement;
  /** md 側のフォーカスは CodeMirror が持つので注入 */
  focusEditor: () => void;
}): {
  togglePane: () => void;
  togglePaneVis: (which: "md" | "map") => void;
} {
  const { mdPane, mapPane, panesEl, splitter, mdButton, mapButton } = args;
  let paneVis = { md: true, map: true };

  const applyPaneVis = (v: { md: boolean; map: boolean }): void => {
    if (!v.md && !v.map) v = { md: true, map: true };
    paneVis = v;
    mdPane.classList.toggle("pane-off", !v.md);
    mapPane.classList.toggle("pane-off", !v.map);
    splitter.classList.toggle("pane-off", !v.md || !v.map);
    panesEl.classList.toggle("no-map", !v.map);
    // 押されているかどうかが、見た目で分かること
    mdButton.classList.toggle("on", v.md);
    mdButton.classList.toggle("off", !v.md);
    mdButton.setAttribute("aria-pressed", String(v.md));
    mapButton.classList.toggle("on", v.map);
    mapButton.classList.toggle("off", !v.map);
    mapButton.setAttribute("aria-pressed", String(v.map));
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

  mdButton.addEventListener("click", () => togglePaneVis("md"));
  mapButton.addEventListener("click", () => togglePaneVis("map"));

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
  // 幅を変えるだけ。開閉は MD / マップ ボタンと Mod+/ が持つ
  splitter.addEventListener("pointerdown", (e) => {
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

  // ボタンのオン/オフ表示を初期化するため、既定でも必ず一度通す
  applyPaneVis({ md: true, map: true });

  return { togglePane, togglePaneVis };
}

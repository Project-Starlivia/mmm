// ペインの表示/非表示 (コードとノードのビュー) とスプリッタ。
// 「両方消えた」状態は作らない。片方を消したら残りが受け皿になる。
// どちらを出しているかは覚えない — 毎回、両方から始まる。
//
// **切り替えのボタンはここが建てる。** 帯に出す気は無い（そのペインにだけ
// 効くものなので、そのペインの中に住む）。境目を挟んで向かい合う 2 つで、
// **どちらも指したほうを動かす** — md の右下がマップ、マップの左下が MD。
// 自分を消すボタンにすると、消えた先に戻す手が無くなる。

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

  // 名前は**指す先**。md の中のボタンはマップを出し入れするので `Map`
  const swMap = paneSwitch("switch-map", "Map", "Toggle the map pane (Alt+2)");
  const swMd = paneSwitch("switch-md", "MD", "Toggle the Markdown pane (Alt+1)");
  mdPane.append(swMap.box);
  mapPane.append(swMd.box);

  const applyPaneVis = (v: { md: boolean; map: boolean }): void => {
    if (!v.md && !v.map) v = { md: true, map: true };
    paneVis = v;
    mdPane.classList.toggle("pane-off", !v.md);
    mapPane.classList.toggle("pane-off", !v.map);
    splitter.classList.toggle("pane-off", !v.md || !v.map);
    panesEl.classList.toggle("no-map", !v.map);
    // 点いている = その先が出ている
    swMap.button.classList.toggle("on", v.map);
    swMd.button.classList.toggle("on", v.md);
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

  swMap.button.addEventListener("click", () => togglePaneVis("map"));
  swMd.button.addEventListener("click", () => togglePaneVis("md"));

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
  // 幅を変えるだけ。開閉は隅のボタンと Alt+1 / Alt+2、Mod+/ が持つ
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

  // 点き具合を最初に一度そろえる（既定でも必ず通す）
  applyPaneVis(paneVis);

  return { togglePane, togglePaneVis };
}

/** 隅に浮く 1 つボタン。器と中身を返す（点け消しは呼ぶ側が持つ） */
function paneSwitch(
  id: string,
  label: string,
  title: string,
): { box: HTMLElement; button: HTMLButtonElement } {
  const box = document.createElement("div");
  box.id = id;
  box.className = "pane-tool";
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.title = title;
  box.append(button);
  return { box, button };
}

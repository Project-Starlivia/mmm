// ペインの表示/非表示 (コードとノードのビュー) とスプリッタ。
//
// **見え方は「分割線の居場所」ひとつで言い切れる。** 「両方消えた」は
// 作らないので、辿り着ける形は 3 つしかなく、左から順に並べると
// そのまま分割線を左右に動かす話になる（`SPOTS`）。
//
// だから**矢印は向きを変えない**。`‹` はいつでも「分割線を左へ 1 つ」、
// `›` はいつでも「右へ 1 つ」で、いま押せるかどうかだけが変わる
// （端では止まる）。以前は md 用 / マップ用の 2 本が状態で向きを反転して
// いて、両方開いていると `‹` の下に `›` が出る — 押すと閉じるのに
// 広がって見え、どちらがどちらかも並び順を覚えるしかなかった。
//
// どちらを出しているかは覚えない — 毎回、両方から始まる。

import { icon } from "../icons.ts";
import { paneTool } from "./paneTool.ts";

/**
 * 分割線の居場所。左端 = md が無い / 真ん中 = 両方 / 右端 = マップが無い。
 *
 * **名前は「その姿」であって「その一手」ではない。** 矢印が言うべきなのは
 * 押した先で何が見えているかで、何を出すのか隠すのかではない — 出す/隠すで
 * 言うと、同じ 3 か所を行き来する話が 4 通りの動詞に散る。姿に名前を付ければ
 * **数は 3 つ**で、居場所の定義と同じ行に住む。
 *
 * **画面に `pane` とは書かない。** 見えているものの名前は Markdown と
 * Mindmap の 2 つで、`pane` は器の呼び名（＝こちらの都合）でしかない。
 * 真ん中だけ両方を並べるのは、「両方」と言うために要る語が他に無いから
 * — 器の名前を借りるくらいなら、中身の名前を 2 つ並べる。
 */
const SPOTS = [
  { md: false, map: true, name: "Mindmap only" },
  { md: true, map: true, name: "Markdown + Mindmap" },
  { md: true, map: false, name: "Markdown only" },
] as const;

type Vis = { md: boolean; map: boolean };

const spotOf = (v: Vis): number =>
  SPOTS.findIndex((s) => s.md === v.md && s.map === v.map);

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
  let paneVis: Vis = { md: true, map: true };

  const arrows = paneTool("pane-switch");
  const goLeft = arrowButton("left");
  const goRight = arrowButton("right");
  arrows.append(goLeft, goRight);
  splitter.append(arrows);

  const applyPaneVis = (v: Vis): void => {
    if (!v.md && !v.map) v = { md: true, map: true };
    paneVis = v;
    mdPane.classList.toggle("pane-off", !v.md);
    mapPane.classList.toggle("pane-off", !v.map);
    panesEl.classList.toggle("no-map", !v.map);
    panesEl.classList.toggle("no-md", !v.md);
    // 端では、その先が無いので押せない
    const spot = spotOf(v);
    goLeft.disabled = spot <= 0;
    goRight.disabled = spot >= SPOTS.length - 1;
    // 絵しか持たない矢印。名前は動くたび変わる — 押す前に何が起きるかを
    // 言い切る文言が、そのままアクセシブルネームにもなる
    goLeft.title = SPOTS[spot - 1]?.name ?? "";
    goLeft.setAttribute("aria-label", goLeft.title);
    goRight.title = SPOTS[spot + 1]?.name ?? "";
    goRight.setAttribute("aria-label", goRight.title);
    // focus must not stay in a hidden pane
    if (!v.md && mdPane.contains(document.activeElement)) mapPane.focus();
    if (!v.map && mapPane.contains(document.activeElement)) args.focusEditor();
  };

  /** 分割線を 1 つ動かす。端は動かない */
  const slide = (step: -1 | 1): void => {
    const next = SPOTS[spotOf(paneVis) + step];
    if (next) applyPaneVis({ ...next });
  };

  const togglePaneVis = (which: "md" | "map"): void => {
    const next = { ...paneVis, [which]: !paneVis[which] };
    // never end up with zero panes: hiding the last one shows the other
    if (!next.md && !next.map) next[which === "md" ? "map" : "md"] = true;
    applyPaneVis(next);
  };

  goLeft.addEventListener("click", () => slide(-1));
  goRight.addEventListener("click", () => slide(1));

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
  // 両方出ているときは幅を変えるだけ。開閉は境目の矢印と Alt+1 / Alt+2、
  // Mod+/ が持つ。
  //
  // **片方だけのときは、押せば分割へ戻る。** 動かす幅が無いので掴んでも
  // 何もできないが、縁に寄った分割線はそこに見えている — 戻すための
  // 取っ手として使えるほうが、細い矢印 1 つを狙わせるより易しい
  splitter.addEventListener("pointerdown", (e) => {
    if (!paneVis.md || !paneVis.map) {
      applyPaneVis({ md: true, map: true });
      return;
    }
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

  // 押せる / 押せないを最初に一度そろえる（既定でも必ず通す）
  applyPaneVis(paneVis);

  return { togglePane, togglePaneVis };
}

/** 絵は下向きの chevron 1 つだけ。左右は回して作る（線を増やさない） */
function arrowButton(dir: "left" | "right"): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  const svg = icon("chevron-down");
  svg.classList.add(dir === "left" ? "point-left" : "point-right");
  button.append(svg);
  return button;
}

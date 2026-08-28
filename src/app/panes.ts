// ペインの表示/非表示 (コードとノードのビュー) とスプリッタ。
//
// **見え方は「分割線の居場所」ひとつで言い切れる。** 「両方消えた」は
// 作らないので、辿り着ける形はたかだか 3 つ（狭ければ 2 つ）で、左から
// 順に並べるとそのまま分割線を左右に動かす話になる（`spotsFor`）。
//
// だから**矢印は向きを変えない**。`‹` はいつでも「分割線を左へ 1 つ」、
// `›` はいつでも「右へ 1 つ」で、いま押せるかどうかだけが変わる
// （端では止まる）。以前は md 用 / マップ用の 2 本が状態で向きを反転して
// いて、両方開いていると `‹` の下に `›` が出る — 押すと閉じるのに
// 広がって見え、どちらがどちらかも並び順を覚えるしかなかった。
//
// どちらを出しているかは覚えない — 毎回、両方から始まる。
//
// **狭いときは「両方」が居場所から消える。** 並べられない幅で「両方」を
// 残すと、CSS が片方を隠して**状態が 2 つになり食い違う** — 矢印は行けない
// 場所を指し、`disabled` は画面に無い世界を説明する。

import { icon } from "../icons.ts";
import { paneTool } from "./paneTool.ts";

/** 見えているペイン。**「両方消えた」は作らない** */
export interface Vis {
  md: boolean;
  map: boolean;
}

/**
 * 分割線の居場所。左端 = md が無い / 真ん中 = 両方 / 右端 = マップが無い。
 * **狭いときは真ん中が消えて 2 つになる** — 左から右へ並ぶ順は変わらない
 * ので、`‹` は狭くても「分割線を左へ 1 つ」のまま。
 */
export function spotsFor(narrow: boolean): readonly Vis[] {
  const mapOnly: Vis = { md: false, map: true };
  const mdOnly: Vis = { md: true, map: false };
  return narrow ? [mapOnly, mdOnly] : [mapOnly, { md: true, map: true }, mdOnly];
}

/**
 * 要求された見え方を、いまの居場所へ射影する。**居場所に無い形は 2 つだけ** —
 * 「両方消えた」と、狭いときの「両方」。どちらも**マップを必ず残し、md は
 * 残せるなら残す**（この道具がマップのために在るから）。
 */
export function project(v: Vis, list: readonly Vis[]): Vis {
  const hit = list.find((s) => s.md === v.md && s.map === v.map);
  if (hit) return hit;
  return list.find((s) => s.md && s.map) ?? list[0];
}

const spotOf = (list: readonly Vis[], v: Vis): number =>
  list.findIndex((s) => s.md === v.md && s.map === v.map);

/**
 * `which` を出す / 引っ込める一手の行き先。**`project` のフォールバックには
 * 任せない** — あちらは「行き先を言っていない要求」（境目をまたいだ・
 * 両方消えた）専用で、常にマップへ丸めてしまうので、「md を出したい」
 * のような名指しの要求に使うと要求そのものが無視される。
 *
 * 決め方は 2 つだけ:
 * - **引っ込める。** 最後の 1 枚（もう片方が既に消えている）なら
 *   「両方消えた」は作らないので、「もう片方を出す」一手として読む —
 *   幅に関係なく、消される側の逆が残る。もう片方も出ていれば、ただ
 *   その 1 枚だけを消す。
 * - **出す。** 居場所が 2 つ（狭い）なら「両方」という置き場が無いので、
 *   そのペイン 1 枚だけになる。3 つ（広い）なら相方はそのまま、その
 *   ペインを足すだけ。
 */
export function toggled(v: Vis, which: "md" | "map", list: readonly Vis[]): Vis {
  const other = which === "md" ? "map" : "md";
  if (v[which]) {
    if (!v[other]) return { md: which === "map", map: which === "md" };
    return { ...v, [which]: false };
  }
  return list.length === 3 ? { ...v, [which]: true } : { md: which === "md", map: which === "map" };
}

/** その一手で何が起きるかを言う（矢印は向きを変えないので、言葉が担う） */
function describe(from: Vis | undefined, to: Vis | undefined): string {
  if (!from || !to) return "";
  // 狭いときは両方が入れ替わる。そのときは**行き先の名前**を言う
  if (from.md !== to.md && from.map !== to.map) {
    return to.md ? "Show the Markdown pane" : "Show the map";
  }
  if (from.md !== to.md) {
    return to.md ? "Show the Markdown pane" : "Hide the Markdown pane";
  }
  return to.map ? "Show the map" : "Hide the map";
}

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

  // **`720px` を 2 か所に置かない。** メディアクエリでは CSS 変数を使えないので、
  // 唯一の源を JS に置き、CSS は `<html class="narrow">` を見る
  const NARROW = "(max-width: 720px)";
  const narrow = window.matchMedia(NARROW);
  const spots = (): readonly Vis[] => spotsFor(narrow.matches);

  const arrows = paneTool("pane-switch");
  const goLeft = arrowButton("left");
  const goRight = arrowButton("right");
  arrows.append(goLeft, goRight);
  splitter.append(arrows);

  const applyPaneVis = (want: Vis): void => {
    const list = spots();
    const v = project(want, list);
    paneVis = v;
    document.documentElement.classList.toggle("narrow", narrow.matches);
    mdPane.classList.toggle("pane-off", !v.md);
    mapPane.classList.toggle("pane-off", !v.map);
    panesEl.classList.toggle("no-map", !v.map);
    panesEl.classList.toggle("no-md", !v.md);
    // 端では、その先が無いので押せない
    const spot = spotOf(list, v);
    goLeft.disabled = spot <= 0;
    goRight.disabled = spot >= list.length - 1;
    goLeft.title = describe(list[spot], list[spot - 1]);
    goRight.title = describe(list[spot], list[spot + 1]);
    // focus must not stay in a hidden pane
    if (!v.md && mdPane.contains(document.activeElement)) mapPane.focus();
    if (!v.map && mapPane.contains(document.activeElement)) args.focusEditor();
  };

  /** 分割線を 1 つ動かす。端は動かない */
  const slide = (step: -1 | 1): void => {
    const list = spots();
    const next = list[spotOf(list, paneVis) + step];
    if (next) applyPaneVis({ ...next });
  };

  const togglePaneVis = (which: "md" | "map"): void => {
    applyPaneVis(toggled(paneVis, which, spots()));
  };

  goLeft.addEventListener("click", () => slide(-1));
  goRight.addEventListener("click", () => slide(1));

  // Mod+/: jump to the other pane, revealing it if hidden
  const togglePane = (): void => {
    if (mdPane.contains(document.activeElement)) {
      if (!paneVis.map) applyPaneVis(toggled(paneVis, "map", spots()));
      mapPane.focus();
    } else {
      if (!paneVis.md) applyPaneVis(toggled(paneVis, "md", spots()));
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
    // 狭いときは分割そのものが無い。掴む先も、戻る先も無い
    if (narrow.matches) return;
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

  // 幅が境目をまたいだら、いまの見え方を新しい居場所へ射影し直す
  narrow.addEventListener("change", () => applyPaneVis(paneVis));

  // 押せる / 押せないを最初に一度そろえる（既定でも必ず通す）
  applyPaneVis(paneVis);

  return { togglePane, togglePaneVis };
}

/** 絵は下向きの chevron 1 つだけ。左右は回して作る（線を増やさない） */
function arrowButton(dir: "left" | "right"): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  const svg = icon("chevron");
  svg.classList.add(dir === "left" ? "point-left" : "point-right");
  button.append(svg);
  return button;
}

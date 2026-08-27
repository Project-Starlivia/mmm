// 選んでいるノードの上下左右に出る `+`。
//
// **選択の anchor は常に高々 1 つ**なので、置き場所も 1 つでよい
// （map/pick.ts の「選んだカードの枠と ×」と同じ立場）。
//
// **向きと木の意味を一致させる。** マップは左から右へ伸びるので、右が子・
// 左が親・上下が兄弟。4 つ揃って初めて、覚えるものが「向き」1 つで済む。
//
// 以前はホバーで 1 つだけ出て、押すと 4 項目のメニューが開いていた。押しに
// 行くとホバーが外れて押せず、そもそも指にホバーは無い。

import type { Rect } from "./geometry.ts";
import { svgEl } from "./svg.ts";

export type AddDir = "child" | "below" | "above" | "parent";

/** world 座標の置き場所（ボタンの中心） */
export interface AddSpot {
  dir: AddDir;
  x: number;
  y: number;
}

/**
 * その箱の周りの置き場所。`gap` は箱の縁から中心までの world 距離
 * （**画面 px を `k` で割ったものを渡す** — ボタンの大きさは倍率に
 * 引きずられないため）。`canParent` が false なら親の口を出さない。
 */
export function addSpots(b: Rect, gap: number, canParent: boolean): AddSpot[] {
  const cx = b.x + b.w / 2;
  const cy = b.y + b.h / 2;
  const spots: AddSpot[] = [
    { dir: "child", x: b.x + b.w + gap, y: cy },
    { dir: "above", x: cx, y: b.y - gap },
    { dir: "below", x: cx, y: b.y + b.h + gap },
  ];
  if (canParent) spots.push({ dir: "parent", x: b.x - gap, y: cy });
  return spots;
}

/** 縁から中心までの画面距離 */
const GAP = 26;
/** 指の的。見えている丸（R）より広く取る */
const HIT = 22;
/** 見えている丸の半径。的いっぱいの丸を 4 つ並べると、ノードより目立つ */
const R = 9;
/** 十字の腕の長さ */
const ARM = 4;

export class AddButtons {
  /** viewport（world 座標）に入れる。ノード層より上に置くこと */
  readonly el = svgEl("g", { id: "add-buttons", visibility: "hidden" });

  /**
   * `b` の周りに置く。`k` はいまの倍率で、**打ち消して**画面上の大きさを
   * 一定に保つ（`MIN_ZOOM` まで引いても押せる粒でなくならない）。
   */
  show(b: Rect, k: number, canParent: boolean): void {
    this.el.setAttribute("visibility", "visible");
    this.el.replaceChildren();
    for (const spot of addSpots(b, GAP / k, canParent)) {
      const btn = svgEl("g", {
        class: "add-btn",
        "data-add": spot.dir,
        transform: `translate(${spot.x} ${spot.y}) scale(${1 / k})`,
      });
      // `svgEl` は数も受ける。**呼ぶ側に `String(...)` を書かせない**
      // （map/svg.ts の明文の規約 — 意味を持たない皮を積まない）
      btn.append(
        // 的は見た目より広い。指は 9px の丸の縁を正確には狙えない
        svgEl("circle", { class: "hit", r: HIT }),
        svgEl("circle", { class: "face", r: R }),
        svgEl("line", { x1: -ARM, y1: 0, x2: ARM, y2: 0 }),
        svgEl("line", { x1: 0, y1: -ARM, x2: 0, y2: ARM }),
      );
      this.el.append(btn);
    }
  }

  hide(): void {
    this.el.setAttribute("visibility", "hidden");
    // 隠れていても当たり判定は残るので、中身ごと捨てる
    this.el.replaceChildren();
  }
}

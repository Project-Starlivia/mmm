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

import { type Rect, leftOf, rightOf } from "./geometry.ts";
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
 *
 * 子への線が出る場所・親からの線が入る場所は geometry.ts の `rightOf`/
 * `leftOf` が唯一の出所（`rightOf` のコメントが、まさにこの呼び出しを
 * 見越している）。ここで座標を計算し直さない。
 */
export function addSpots(b: Rect, gap: number, canParent: boolean): AddSpot[] {
  const cx = b.x + b.w / 2;
  const r = rightOf(b);
  const spots: AddSpot[] = [
    { dir: "child", x: r.x + gap, y: r.y },
    { dir: "above", x: cx, y: b.y - gap },
    { dir: "below", x: cx, y: b.y + b.h + gap },
  ];
  if (canParent) {
    const l = leftOf(b);
    spots.push({ dir: "parent", x: l.x - gap, y: l.y });
  }
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

/** 常に作る 4 つの向き（DOM を作る順） */
const ALL_DIRS: AddDir[] = ["child", "above", "below", "parent"];

export class AddButtons {
  /** viewport（world 座標）に入れる。ノード層より上に置くこと */
  readonly el = svgEl("g", { id: "add-buttons", visibility: "hidden" });
  /**
   * 4 つとも先に作って持っておく。**選ぶたびに作り直さない** —
   * map/pick.ts が生まれた理由そのもの（カードを選ぶだけでノードの中身が
   * 丸ごと作り直され、コードが無言で再トークナイズされていた）と同じ罠を
   * ここでも踏まない。`show` は毎回呼ばれる（パン・ズームのたびに
   * `updateAdds` が走る）ので、作り直しは的の数ぶん無駄な DOM 生成になる。
   */
  private groups = new Map<AddDir, SVGGElement>();

  constructor() {
    for (const dir of ALL_DIRS) {
      const btn = svgEl("g", { class: "add-btn", visibility: "hidden" });
      // `svgEl` は数も受ける。**呼ぶ側に `String(...)` を書かせない**
      // （map/svg.ts の明文の規約 — 意味を持たない皮を積まない）
      btn.append(
        // 的は見た目より広い。指は 9px の丸の縁を正確には狙えない
        svgEl("circle", { class: "hit", r: HIT }),
        svgEl("circle", { class: "face", r: R }),
        svgEl("line", { x1: -ARM, y1: 0, x2: ARM, y2: 0 }),
        svgEl("line", { x1: 0, y1: -ARM, x2: 0, y2: ARM }),
      );
      this.groups.set(dir, btn);
      this.el.append(btn);
    }
  }

  /**
   * `b` の周りに置く。`k` はいまの倍率で、**打ち消して**画面上の大きさを
   * 一定に保つ（`MIN_ZOOM` まで引いても押せる粒でなくならない）。
   * 作り直すのは向き・位置ではなく、既に居る 4 つの transform と表示だけ。
   */
  show(b: Rect, k: number, canParent: boolean): void {
    this.el.setAttribute("visibility", "visible");
    // 置き場所の算術は canParent に関わらず 4 つとも引く。出す/隠すは
    // このあとの表示切り替えだけの仕事にする（算術と見た目を混ぜない）
    for (const spot of addSpots(b, GAP / k, true)) {
      const btn = this.groups.get(spot.dir);
      if (!btn) continue;
      const on = spot.dir !== "parent" || canParent;
      btn.setAttribute("visibility", on ? "visible" : "hidden");
      btn.setAttribute("transform", `translate(${spot.x} ${spot.y}) scale(${1 / k})`);
      // `data-add` はヒットテストの入口（bindClick/bindPointer が探す）。
      // ルートの親口のように隠れている的は、押せてはいけない
      if (on) btn.setAttribute("data-add", spot.dir);
      else btn.removeAttribute("data-add");
    }
  }

  hide(): void {
    this.el.setAttribute("visibility", "hidden");
    // 隠れていても当たり判定は残るので、押せなくしておく
    for (const btn of this.groups.values()) btn.removeAttribute("data-add");
  }
}

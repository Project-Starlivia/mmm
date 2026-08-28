// 選んでいるノードの上下左右に出る `+`。
//
// **選択の anchor は常に高々 1 つ**なので、置き場所も 1 つでよい
// （map/pick.ts の「選んだカードの枠と ×」と同じ立場）。
//
// **向きと木の意味を一致させる。** 子はその枝が育つ辺に、親はその枝が
// 入ってくる辺に、上下が兄弟。左右どちらが子でどちらが親かは枝ごとの
// 向き（`dirOf`）で決まる — **鏡映は geometry.ts の `growthEdgeOf` /
// `entryEdgeOf` だけが知っていて、ここでは `dir === 1` を書かない**。
//
// 以前はホバーで 1 つだけ出て、押すと 4 項目のメニューが開いていた。押しに
// 行くとホバーが外れて押せず、そもそも指にホバーは無い。

import { type Rect, entryEdgeOf, growthEdgeOf } from "./geometry.ts";
import { svgEl } from "./svg.ts";

export type AddDir = "child" | "below" | "above" | "parent";

/** world 座標の置き場所（ボタンの中心） */
export interface AddSpot {
  dir: AddDir;
  x: number;
  y: number;
}

/**
 * その箱の周りの置き場所。`gap` は箱の縁から中心までの world 距離で、
 * `x` が左右（子・親）、`y` が上下（兄弟）— **左右と上下で値が違う**ので
 * 1 つの数では言えない（下記 `GAP_X` / `GAP_Y`）。**画面 px を `k` で
 * 割ったものを渡す** — ボタンの大きさは倍率に引きずられないため。
 * `canParent` が false なら親の口を出さない。`dir` はその枝の育つ向き
 * （右 = 1 / 左 = -1、`layout.ts` の `dirOf`）。
 *
 * 子への線が出る場所・親からの線が入る場所は geometry.ts の
 * `growthEdgeOf` / `entryEdgeOf` が唯一の出所。左右の入れ替え（鏡映）は
 * そちらに任せ、ここでは `dir` を渡して結果をそのまま使うだけ。
 */
export function addSpots(
  b: Rect,
  gap: { x: number; y: number },
  canParent: boolean,
  dir: 1 | -1,
): AddSpot[] {
  const cx = b.x + b.w / 2;
  const growth = growthEdgeOf(b, dir);
  const spots: AddSpot[] = [
    { dir: "child", x: growth.x + gap.x * dir, y: growth.y },
    { dir: "above", x: cx, y: b.y - gap.y },
    { dir: "below", x: cx, y: b.y + b.h + gap.y },
  ];
  if (canParent) {
    const entry = entryEdgeOf(b, dir);
    spots.push({ dir: "parent", x: entry.x - gap.x * dir, y: entry.y });
  }
  return spots;
}

/**
 * 縁から中心までの画面距離。左右と上下で別の値にする — layout.ts の
 * `GAP` が言うとおり、親子の横の通り道は 45px あるが兄弟の縦の間隔は
 * 10px しかない。横の 26px は通り道の中に収まるが、縦にそのまま使うと
 * 半径 9px の丸が隣の兄弟の箱に食い込む。
 */
/** 左右（子・親）: 縁から中心まで 26px 外へ */
const GAP_X = 26;
/**
 * 上下（兄弟）: 縁ちょうどに中心を置く。**丸は内と外へ半分ずつ**張り出す。
 *
 * 外へ出るのは常に画面 `R` px = world で `R / k`。兄弟の縦間隔は world で
 * `layout.ts` の `GAP.y`（= 10）固定なので、**食い込まないのは
 * `k >= R / GAP.y`（= 0.9）のときだけ。**それより引くと上下の丸が隣の兄弟に
 * 重なる（`MIN_ZOOM` で画面 7.5px ほど）。
 *
 * **承知のうえで取っている。**外へ出す量を減らす道は無く（`GAP_Y` を負にすると
 * 丸が箱の中へ沈んで縁が読めない）、丸を縮めれば引いたときに押せない粒になる。
 * 引き切った地図で兄弟の縁がわずかに触れることより、**どの倍率でも押せる**
 * ほうを取る。`GAP_Y` を動かすなら、直すのは重なりではなくこの取捨。
 */
const GAP_Y = 0;
/** 指の的。見えている丸（R）より広く取る */
const HIT = 22;
/** 見えている丸の半径。的いっぱいの丸を 4 つ並べると、ノードより目立つ */
const R = 9;
/** 十字の腕の長さ */
const ARM = 4;

/** 1 つぶんの `<g>` を作る。的・見えている丸・十字の線 2 本、向きは固定 */
function makeButton(dir: AddDir): SVGGElement {
  const btn = svgEl("g", { class: "add-btn", "data-add": dir });
  // `svgEl` は数も受ける。**呼ぶ側に `String(...)` を書かせない**
  // （map/svg.ts の明文の規約 — 意味を持たない皮を積まない）
  btn.append(
    // 的は見た目より広い。指は 9px の丸の縁を正確には狙えない
    svgEl("circle", { class: "hit", r: HIT }),
    svgEl("circle", { class: "face", r: R }),
    svgEl("line", { x1: -ARM, y1: 0, x2: ARM, y2: 0 }),
    svgEl("line", { x1: 0, y1: -ARM, x2: 0, y2: ARM }),
  );
  return btn;
}

export class AddButtons {
  /** viewport（world 座標）に入れる。ノード層より上に置くこと */
  readonly el = svgEl("g", { id: "add-buttons", visibility: "hidden" });
  /**
   * 4 つとも先に作って持っておく。**選ぶたびに作り直さない** —
   * map/pick.ts が生まれた理由そのもの（カードを選ぶだけでノードの中身が
   * 丸ごと作り直され、コードが無言で再トークナイズされていた）と同じ罠を
   * ここでも踏まない。`show` は毎回呼ばれる（パン・ズームのたびに
   * `updateAdds` が走る）ので、作り直しは的の数ぶん無駄な DOM 生成になる。
   *
   * `Record` で持つ（`Map` にしない）。4 つの向きぶん過不足なく埋めて
   * 型で持つので、「無かったら」を書かずに済む — 実際に無いことはない。
   */
  private groups: Record<AddDir, SVGGElement> = {
    child: makeButton("child"),
    above: makeButton("above"),
    below: makeButton("below"),
    parent: makeButton("parent"),
  };

  constructor() {
    this.el.append(
      this.groups.child,
      this.groups.above,
      this.groups.below,
      this.groups.parent,
    );
  }

  /**
   * `b` の周りに置く。`k` はいまの倍率で、**打ち消して**画面上の大きさを
   * 一定に保つ（`MIN_ZOOM` まで引いても押せる粒でなくならない）。
   * 作り直すのは向き・位置ではなく、既に居る 4 つの transform と表示だけ。
   *
   * 出す子には `visibility: inherit` を与える —「見えている」を子に書き込むと、
   * あとで `hide()` がコンテナだけを隠しても、子に残った明示の `visible` が
   * 継承より優先されて描かれ続ける（CSS の visibility は先祖のではなく自分の
   * 値を見る）。子は「隠す/隠さない」の 2 値だけを持ち、「見せる」判断は
   * コンテナの 1 か所に集める。
   */
  show(b: Rect, k: number, canParent: boolean, dir: 1 | -1): void {
    this.el.setAttribute("visibility", "visible");
    // 置き場所の算術は canParent に関わらず 4 つとも引く。出す/隠すは
    // このあとの表示切り替えだけの仕事にする（算術と見た目を混ぜない）
    for (const spot of addSpots(b, { x: GAP_X / k, y: GAP_Y / k }, true, dir)) {
      const btn = this.groups[spot.dir];
      const on = spot.dir !== "parent" || canParent;
      btn.setAttribute("visibility", on ? "inherit" : "hidden");
      btn.setAttribute("transform", `translate(${spot.x} ${spot.y}) scale(${1 / k})`);
    }
  }

  /**
   * コンテナを隠すだけ。子には触らない — `inherit` な子はコンテナに連れられて
   * 隠れ、`hidden` 固定の子（親の口が無いときの `parent`）はそのまま隠れている。
   * `visibility: hidden` は当たり判定にも乗らないので、`data-add`（コンストラクタで
   * 一度だけ付ける）を都度外し・付け直す必要はない。
   */
  hide(): void {
    this.el.setAttribute("visibility", "hidden");
  }
}

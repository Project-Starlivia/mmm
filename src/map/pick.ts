// 選んでいるカードに被せる枠と、その角の × ボタン。
//
// **選ばれているカードは常に高々 1 枚**なので、置き場所も 1 つでよい。
// ノードの子要素として作ると、選ぶ / 外すたびにそのノードの中身が丸ごと
// 作り直され、**コードカードを選ぶだけでコードが再トークナイズされる**。
// 落とし先の線（drop-line）と同じく、world 座標に浮かぶ 1 個の印にすれば、
// 描画はカードの選択を知らなくてよくなる。

import type { Rect } from "./geometry.ts";
import { svgEl } from "./svg.ts";

/** × の中心からの腕の長さと、その当たり判定の半径 */
const ARM = 2.5;
const HIT_R = 7;

export class CardPick {
  /** viewport（world 座標）に入れる。ノード層より上に置くこと */
  readonly el = svgEl("g", { id: "card-pick", visibility: "hidden" });
  private frame = svgEl("rect", { class: "frame" });
  /** 角の ×。押せば Delete（操作と同じ名） */
  private delete = svgEl("g", { class: "delete" });
  private circle = svgEl("circle", { r: HIT_R });
  private strokes = [svgEl("line"), svgEl("line")];

  constructor() {
    this.delete.append(this.circle, ...this.strokes);
    this.el.append(this.frame, this.delete);
  }

  /**
   * `rect` にぴったり被せる。`id` は × を押されたときに誰を消すかで、
   * `data-delete` として出す（当たり判定は座標から辿るため）。
   * `rect` が null なら隠す（畳まれた・範囲外）。
   */
  show(id: number, rect: Rect | null): void {
    if (!rect) {
      this.hide();
      return;
    }
    this.el.setAttribute("visibility", "visible");
    this.frame.setAttribute("x", String(rect.x));
    this.frame.setAttribute("y", String(rect.y));
    this.frame.setAttribute("width", String(rect.w));
    this.frame.setAttribute("height", String(rect.h));
    // × は角そのものに載せる。枠線がボタンの中心を通る位置
    const cx = rect.x + rect.w;
    const cy = rect.y;
    this.delete.setAttribute("data-delete", String(id));
    this.circle.setAttribute("cx", String(cx));
    this.circle.setAttribute("cy", String(cy));
    // × は文字ではなく線で引く。字だと書体で中心も太さも揺れる
    for (const [i, [dx, dy]] of [
      [1, 1],
      [1, -1],
    ].entries()) {
      const line = this.strokes[i];
      line.setAttribute("x1", String(cx - ARM * dx));
      line.setAttribute("y1", String(cy - ARM * dy));
      line.setAttribute("x2", String(cx + ARM * dx));
      line.setAttribute("y2", String(cy + ARM * dy));
    }
  }

  hide(): void {
    this.el.setAttribute("visibility", "hidden");
    // 隠れていても当たり判定の印は残るので、消しておく
    this.delete.removeAttribute("data-delete");
  }
}

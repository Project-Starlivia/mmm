// ラジアルメニュー。中身は持たない — 並べるものは呼ぶ側が渡す（ContextMenu と
// 同じ立場）。開く場所だけが違う: ボタンや右クリックのような「押した場所」が
// 無いキーボード操作（Mod+Shift+E）から出すので、いちばん手が近い「今どこを
// 見ているか」＝カーソル位置に開く。自前で pointermove を拾って覚えておく。

import { type IconName, icon } from "../icons.ts";

const SVG_NS = "http://www.w3.org/2000/svg";

const OUTER = 100; // 外周の半径
const HUB = 36; // 中心の穴の半径。ここを押すと選ばずに閉じる
const MARGIN = 8; // 画面の縁からこれだけは離す

export interface RadialEntry {
  mark: IconName;
  label: string;
  run: () => void;
}

const rad = (deg: number): number => (deg * Math.PI) / 180;

/** 0°=上、時計回りでの 1 点。中心 (cx, cy) から半径 r、角度 deg */
function pointAt(cx: number, cy: number, r: number, deg: number): { x: number; y: number } {
  return { x: cx + r * Math.sin(rad(deg)), y: cy - r * Math.cos(rad(deg)) };
}

export class RadialMenu {
  private svg = document.createElementNS(SVG_NS, "svg");
  private pointer = { x: window.innerWidth / 2, y: window.innerHeight / 2 };

  constructor() {
    this.svg.classList.add("radial-menu");
    this.svg.style.display = "none";
    document.body.append(this.svg);

    // 開いていないあいだも拾っておく — 開いた瞬間には答えが要る
    window.addEventListener("pointermove", (e) => {
      this.pointer = { x: e.clientX, y: e.clientY };
    });
    document.addEventListener("pointerdown", (e) => {
      if (!(e.target instanceof Node) || !this.svg.contains(e.target)) this.hide();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.hide();
    });
    window.addEventListener("blur", () => this.hide());
  }

  /** そのときのカーソル位置に開く。画面外へはみ出すときは内側へ寄せる */
  show(entries: readonly RadialEntry[]): void {
    const cx = Math.min(
      Math.max(this.pointer.x, OUTER + MARGIN),
      window.innerWidth - OUTER - MARGIN,
    );
    const cy = Math.min(
      Math.max(this.pointer.y, OUTER + MARGIN),
      window.innerHeight - OUTER - MARGIN,
    );

    this.svg.replaceChildren();
    this.svg.setAttribute("width", String(window.innerWidth));
    this.svg.setAttribute("height", String(window.innerHeight));

    const per = 360 / entries.length;
    const large = per > 180 ? 1 : 0;
    for (const [i, entry] of entries.entries()) {
      const start = i * per - per / 2;
      const end = start + per;
      const oStart = pointAt(cx, cy, OUTER, start);
      const oEnd = pointAt(cx, cy, OUTER, end);
      const iEnd = pointAt(cx, cy, HUB, end);
      const iStart = pointAt(cx, cy, HUB, start);

      const g = document.createElementNS(SVG_NS, "g");
      g.classList.add("entry");
      g.addEventListener("click", () => {
        this.hide();
        entry.run();
      });

      const sector = document.createElementNS(SVG_NS, "path");
      sector.classList.add("sector");
      sector.setAttribute(
        "d",
        `M${oStart.x},${oStart.y} A${OUTER},${OUTER} 0 ${large} 1 ${oEnd.x},${oEnd.y} ` +
          `L${iEnd.x},${iEnd.y} A${HUB},${HUB} 0 ${large} 0 ${iStart.x},${iStart.y} Z`,
      );
      g.append(sector);

      const mid = i * per;
      const iconAt = pointAt(cx, cy, (OUTER + HUB) / 2 - 12, mid);
      const labelAt = pointAt(cx, cy, (OUTER + HUB) / 2 + 18, mid);

      const ic = icon(entry.mark);
      ic.setAttribute("x", String(iconAt.x - 10));
      ic.setAttribute("y", String(iconAt.y - 10));
      ic.setAttribute("width", "20");
      ic.setAttribute("height", "20");
      g.append(ic);

      const text = document.createElementNS(SVG_NS, "text");
      text.setAttribute("x", String(labelAt.x));
      text.setAttribute("y", String(labelAt.y));
      text.setAttribute("text-anchor", "middle");
      text.setAttribute("dominant-baseline", "central");
      text.textContent = entry.label;
      g.append(text);

      this.svg.append(g);
    }

    const hub = document.createElementNS(SVG_NS, "circle");
    hub.classList.add("hub");
    hub.setAttribute("cx", String(cx));
    hub.setAttribute("cy", String(cy));
    hub.setAttribute("r", String(HUB));
    hub.addEventListener("click", () => this.hide());
    this.svg.append(hub);

    this.svg.style.display = "block";
  }

  hide(): void {
    this.svg.style.display = "none";
  }
}

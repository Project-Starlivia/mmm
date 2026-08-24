// マップの DOM を差分で更新する層。**何を描くかは決めない** — レイアウトと
// 選択の状態を受け取って、SVG をそれに合わせるだけ。
//
// 毎レンダで全消しして作り直していた頃は、1 打鍵ごとに数万個の SVG 要素を
// 生成・破棄していて、それが入力遅延の実体だった。位置(transform)と class は
// 毎回書き換えても安いが、**要素の生成と破棄は高い**ので、そこだけを
// 「中身が変わったノード」に絞る。

import type { CardRef, CardRow } from "./cards.ts";
import type { NodeInfo } from "../coreApi.ts";
import {
  CODE_LINE,
  CODE_PAD,
  cardBleed,
  cardInset,
  rowH,
} from "./cards.ts";
import { type Box, type Layout, edgeEnds } from "./layout.ts";
import { edgePath } from "./edge.ts";
import { languageEpoch, tokenize } from "./highlight.ts";
import {
  ROW_NORMAL,
  displayLabel,
  hiddenLabel,
  rowOf,
  rowTop,
} from "./metrics.ts";
import { svgEl } from "./svg.ts";

/** 1 回の描き直しに要るもの */
export interface Scene {
  layout: Layout;
  selection: Set<number>;
  /** 掴んでいる部分木（薄く描く） */
  dragging: ReadonlySet<number>;
  /** ドロップ中の一時的な印 */
  dropMarks: Map<number, "drop-child" | "drop-parent">;
  /** 選ばれているカード */
  picked: CardRef | null;
  /** ローカル画像の objectURL（まだ読めていなければ null） */
  imageUrl: (path: string) => string | null;
}

/** そのカードが選ばれているか */
const isPicked = (picked: CardRef | null, node: number, index: number): boolean =>
  picked !== null && picked.node === node && picked.index === index;

/**
 * ノードの中身を作り直すかどうかの判定材料。値をそのまま持って、そのまま
 * 比べる（畳んだ文字列にしない — 下記 sameShape）。
 */
interface NodeShape {
  w: number;
  h: number;
  hidden: boolean;
  buried: number;
  epoch: number;
  label: string;
  rows: CardRow[];
  /** rows と同じ並びで、画像だけ解決済みの URL（他は null） */
  urls: (string | null)[];
  /** 選ばれているカードの枚数目。無ければ -1 */
  picked: number;
}

/** カード 1 枚が、描き直しを要するほど変わったか */
function sameRow(a: CardRow, b: CardRow): boolean {
  if (a.kind === "link" && b.kind === "link") {
    return a.link.title === b.link.title && a.link.url === b.link.url;
  }
  if (a.kind === "svg" && b.kind === "svg") return a.markup === b.markup;
  if (a.kind === "img" && b.kind === "img") return a.path === b.path;
  if (a.kind === "code" && b.kind === "code") {
    return (
      a.lang === b.lang &&
      a.lines.length === b.lines.length &&
      a.lines.every((l, i) => l === b.lines[i])
    );
  }
  return false;
}

/** 前回と同じなら、その要素はそのまま置いておける */
function sameShape(a: NodeShape | undefined, b: NodeShape): boolean {
  if (
    a === undefined ||
    a.w !== b.w ||
    a.h !== b.h ||
    a.hidden !== b.hidden ||
    a.buried !== b.buried ||
    a.epoch !== b.epoch ||
    a.label !== b.label ||
    a.picked !== b.picked ||
    a.rows.length !== b.rows.length
  ) {
    return false;
  }
  for (let i = 0; i < a.rows.length; i++) {
    if (a.urls[i] !== b.urls[i] || !sameRow(a.rows[i], b.rows[i])) return false;
  }
  return true;
}

export class MapRenderer {
  readonly edgeLayer = svgEl("g");
  readonly nodeLayer = svgEl("g");

  // 差分更新用: id → DOM
  private nodeEls = new Map<number, SVGGElement>();
  private edgeEls = new Map<number, SVGPathElement>();
  private nodeShape = new Map<number, NodeShape>(); // 内側を作り直す判定用
  // 直前に書いた transform / class。同じ値の setAttribute はスタイル無効化を
  // 起こすだけ無駄なので書かない（プロファイル上いちばん重い JS 呼び出しだった）
  private nodeTf = new Map<number, string>();
  private nodeCls = new Map<number, string>();
  private edgeD = new Map<number, string>();
  private domOrderSig = ""; // DOM の並び（= 重なり順）を直す判定用

  /** id を指定して要素を引く（ドラッグ中の一時的な印を付けるのに使う） */
  nodeEl(id: number): SVGGElement | undefined {
    return this.nodeEls.get(id);
  }

  edgeEl(id: number): SVGPathElement | undefined {
    return this.edgeEls.get(id);
  }

  /**
   * レイアウトを丸ごと見直さない軽い塗り替え（矩形選択の途中で使う）。
   * 選択そのものは持たない — 何が選ばれているかは呼び出し側が決める。
   */
  refreshSelection(sel: Set<number>): void {
    for (const [id, g] of this.nodeEls) {
      g.classList.toggle("selected", sel.has(id));
      // class を直接触ったらキャッシュも合わせる。放置すると次の draw が
      // 「同じだから書かない」と判断して、DOM とズレたままになる
      this.nodeCls.set(id, g.getAttribute("class") ?? "");
    }
  }

  private shapeOf(n: NodeInfo, b: Box, buried: number, p: Scene): NodeShape {
    return {
      w: b.w,
      h: b.h,
      hidden: n.hidden,
      buried,
      // 言語の読み込みは後から効くので、世代も見る
      epoch: languageEpoch(),
      label: n.label,
      rows: b.rows,
      // 画像は「まだ読めていない」から「読めた」へ後から変わる
      urls: b.rows.map((r) => (r.kind === "img" ? p.imageUrl(r.path) : null)),
      picked: b.rows.findIndex((_, i) => isPicked(p.picked, n.id, i)),
    };
  }

  /** 場面を DOM に写す。文書順（= 重なり順）も合わせる。 */
  draw(p: Scene): void {
    const L = p.layout;
    const order = L.visible.map((n) => n.id);
    // ---- DOM を差分更新する ----
    // 位置(transform)と class は毎回書き換えても安い。高いのは要素の生成と
    // 破棄なので、そこは「中身が変わったノードだけ」に絞る。
    const sel = p.selection;
    const seen = new Set<number>();

    for (const n of L.visible) {
      const b = L.boxes.get(n.id);
      if (!b) continue;
      seen.add(n.id);

      // --- エッジ（親への曲線）---
      const ends = edgeEnds(L, n.id);
      if (ends) {
        let path = this.edgeEls.get(n.id);
        if (!path) {
          path = svgEl("path", { class: "edge" });
          this.edgeLayer.append(path);
          this.edgeEls.set(n.id, path);
        }
        const d = edgePath(ends.from, ends.to);
        if (this.edgeD.get(n.id) !== d) {
          path.setAttribute("d", d);
          this.edgeD.set(n.id, d);
        }
      } else {
        const stale = this.edgeEls.get(n.id);
        if (stale) {
          stale.remove();
          this.edgeEls.delete(n.id);
          this.edgeD.delete(n.id);
        }
      }

      // --- ノード本体 ---
      let g = this.nodeEls.get(n.id);
      if (!g) {
        g = svgEl("g");
        g.dataset.id = String(n.id);
        this.nodeLayer.append(g);
        this.nodeEls.set(n.id, g);
        this.nodeShape.delete(n.id); // 新規なので必ず中身を作る
      }
      const dropMark = p.dropMarks.get(n.id);
      const cls =
        "node" +
        (n.depth === 1 ? " root" : "") +
        (b.rows.length > 0 ? " link-card" : "") +
        (n.hidden ? " hidden-node" : "") +
        (sel.has(n.id) ? " selected" : "") +
        (p.dragging.has(n.id) ? " dragging" : "") +
        (dropMark ? ` ${dropMark}` : "");
      if (this.nodeCls.get(n.id) !== cls) {
        g.setAttribute("class", cls);
        this.nodeCls.set(n.id, cls);
      }
      const tf = `translate(${b.x} ${b.y})`;
      if (this.nodeTf.get(n.id) !== tf) {
        g.setAttribute("transform", tf);
        this.nodeTf.set(n.id, tf);
      }

      const buried = L.buriedCount.get(n.id) ?? 0;
      const shape = this.shapeOf(n, b, buried, p);
      if (sameShape(this.nodeShape.get(n.id), shape)) continue; // 中身は据え置き
      this.nodeShape.set(n.id, shape);
      g.replaceChildren();
      g.append(
        svgEl("rect", {
          class: "box",
          width: String(b.w),
          height: String(b.h),
          rx: n.hidden ? "4" : "8",
        }),
      );
      const label = svgEl("text", {
        class: "label" + (n.label === "" ? " empty" : ""),
        x: String(rowOf(n).padX),
        y: String(rowOf(n).rowH / 2),
        // font-size は CSS ではなく属性で入れる（同じ数字を 2 箇所に置かない）
        "font-size": String(rowOf(n).fontPx),
      });
      label.textContent = n.hidden
        ? hiddenLabel(n, buried)
        : displayLabel(n.label);
      const t = svgEl("title");
      t.textContent = n.hidden
        ? `${n.label}${buried ? `\n（${buried} 件を折り畳み中。Shift+H で戻す）` : "\n（非表示。Shift+H で戻す）"}`
        : n.label;
      g.append(label, t);
      // card rows (links / images) from the attached content, stacked
      // under the label
      for (let rowIndex = 0; rowIndex < b.rows.length; rowIndex++) {
        const r = b.rows[rowIndex];
        const spot = `${n.id},${rowIndex}`;
        const rowY = rowTop(b.rows, rowIndex);
        // 中身の置き場所。選択の枠も入力欄（cardRect）もここに合わせる
        const inset = cardInset(r);
        const bleed = cardBleed(r);
        const y = rowY + inset;
        const x = ROW_NORMAL.padX - bleed;
        const w = b.w - ROW_NORMAL.padX * 2 + bleed * 2;
        const h = rowH(r) - inset * 2;
        g.append(
          svgEl("line", {
            class: "card-sep",
            x1: String(ROW_NORMAL.padX - 4),
            y1: String(rowY),
            x2: String(b.w - ROW_NORMAL.padX + 4),
            y2: String(rowY),
          }),
        );
        if (r.kind === "link") {
          // 当たり判定の面。他の 3 種は絵や背景がその役をするが、リンクは
          // 文字しか描かないので、行いっぱいの透明な面を敷く
          const hit = svgEl("rect", {
            class: "link-hit",
            "data-card": spot,
            x: String(ROW_NORMAL.padX),
            y: String(y),
            width: String(w),
            height: String(h),
          });
          const title = svgEl("text", {
            class: "link-row",
            x: String(ROW_NORMAL.padX),
            y: String(y + h / 2),
          });
          title.textContent = r.link.title;
          const tt = svgEl("title");
          tt.textContent = r.link.url;
          const open = svgEl("text", {
            class: "link-open",
            // 枠の内側に収める。外へ出すと、選択の枠が本体より小さく見える
            x: String(x + w),
            y: String(y + h / 2),
            "text-anchor": "end",
          });
          open.textContent = "↗";
          open.setAttribute("data-url", r.link.url);
          g.append(hit, title, tt, open);
        } else if (r.kind === "svg") {
          const img = svgEl("image", {
            "data-card": spot,
            x: String(ROW_NORMAL.padX),
            y: String(y),
            width: String(w),
            height: String(h),
            preserveAspectRatio: "xMidYMid meet",
          });
          img.setAttribute(
            "href",
            `data:image/svg+xml;charset=utf-8,${encodeURIComponent(r.markup)}`,
          );
          g.append(img);
        } else if (r.kind === "code") {
          // 背景は左右にも張り出す（コードは箱の縁まで塗る）。張り出しは
          // 共有の x / w に織り込み済みなので、ここで足し直さない
          const bg = svgEl("rect", {
            class: "code-bg",
            "data-card": spot,
            x: String(x),
            y: String(y),
            width: String(w),
            height: String(h),
            rx: "5",
          });
          if (r.lang !== "") {
            const tt = svgEl("title");
            tt.textContent = r.lang;
            bg.append(tt);
          }
          g.append(bg);
          const tokens = tokenize(r.lines, r.lang);
          for (let i = 0; i < r.lines.length; i++) {
            const ln = svgEl("text", {
              class: "code-line",
              "data-card": spot,
              x: String(ROW_NORMAL.padX + 1),
              y: String(rowY + CODE_PAD + i * CODE_LINE + CODE_LINE / 2),
            });
            // 幅の判断は素の文字列で行い、色の付いた塊をそこへ合わせる
            for (const t of tokens[i]) {
              const span = svgEl("tspan", t.cls === "" ? {} : { class: t.cls });
              span.textContent = t.text;
              ln.append(span);
            }
            g.append(ln);
          }
        } else {
          const url = p.imageUrl(r.path);
          if (url !== null) {
            const img = svgEl("image", {
              "data-card": spot,
              x: String(ROW_NORMAL.padX),
              y: String(y),
              width: String(w),
              height: String(h),
              preserveAspectRatio: "xMidYMid meet",
            });
            img.setAttribute("href", url);
            g.append(img);
          } else {
            // not loadable yet (permission pending / file missing):
            // stable-size placeholder so the layout doesn't jump on load
            g.append(
              svgEl("rect", {
                class: "img-ph",
                "data-card": spot,
                x: String(ROW_NORMAL.padX),
                y: String(y),
                width: String(w),
                height: String(h),
                rx: "6",
              }),
            );
            const ph = svgEl("text", {
              class: "img-name",
              "data-card": spot,
              x: String(b.w / 2),
              y: String(y + h / 2),
              "text-anchor": "middle",
            });
            ph.textContent = r.name;
            g.append(ph);
          }
        }
        if (isPicked(p.picked, n.id, rowIndex)) {
          g.append(
            svgEl("rect", {
              class: "card-picked",
              x: String(x),
              y: String(y),
              width: String(w),
              height: String(h),
              rx: "6",
            }),
          );
          // × は角そのものに載せる。枠線がボタンの中心を通る位置
          const cx = x + w;
          const cy = y;
          const arm = 2.5; // 中心からの腕の長さ
          const kill = svgEl("g", { class: "card-kill", "data-kill": spot });
          kill.append(svgEl("circle", { cx: String(cx), cy: String(cy), r: "7" }));
          // × は文字ではなく線で引く。字だと書体で中心も太さも揺れる
          for (const [dx, dy] of [
            [1, 1],
            [1, -1],
          ]) {
            kill.append(
              svgEl("line", {
                x1: String(cx - arm * dx),
                y1: String(cy - arm * dy),
                x2: String(cx + arm * dx),
                y2: String(cy + arm * dy),
              }),
            );
          }
          g.append(kill);
        }
      }
    }

    // 見えなくなったノード / エッジを片付ける
    for (const [id, el] of this.nodeEls) {
      if (seen.has(id)) continue;
      el.remove();
      this.nodeEls.delete(id);
      this.nodeShape.delete(id);
      this.nodeTf.delete(id);
      this.nodeCls.delete(id);
    }
    for (const [id, el] of this.edgeEls) {
      if (seen.has(id)) continue;
      el.remove();
      this.edgeEls.delete(id);
      // 値キャッシュも一緒に捨てる。残すと、折り畳んで戻したときに
      // 「テキストが元通り = 署名も元通り」で書き換えがスキップされ、
      // 作り直した空の <path> に d が入らないままエッジが消える
      this.edgeD.delete(id);
    }

    // DOM の並び = 重なり順。文書順が変わったときだけ並べ直す
    // （既存要素の append は「移動」であって作り直しではない）
    const orderSig = order.join(",");
    if (orderSig !== this.domOrderSig) {
      for (const id of order) {
        const el = this.nodeEls.get(id);
        if (el) this.nodeLayer.append(el);
      }
      this.domOrderSig = orderSig;
    }


  }
}

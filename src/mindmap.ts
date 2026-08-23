// Mindmap pane: SVG rendering + Figma-style pan/zoom/selection (spec 3.3),
// drag re-parenting with a mandatory drop indicator (spec 3.3.2), and an
// HTML overlay input for label editing (IME-safe).
//
// Layout: every tree grows from left to right.

import type { NodeInfo } from "./coreApi";
import {
  centerOf,
  distToSeg,
  exitPoint,
  midOfPolyline,
} from "./map/geometry";
import { edgeDraw, edgeHintPath, edgeSegs, flattenSegs } from "./map/edge";
import { CODE_LINE, CODE_PAD, IMG_H, IMG_ROW, LINK_ROW } from "./map/cards";
import {
  MONO_FONT,
  ROW_NORMAL,
  clipLabel,
  displayLabel,
  hiddenLabel,
  measure,
  rowOf,
} from "./map/metrics";
import { type Box, GAP, layoutMap } from "./map/layout";
import { exportMapSvg } from "./map/export";

export interface MapHost {
  /** current document nodes, document order */
  nodes(): NodeInfo[];
  /** full markdown text (for reading attached content) */
  docText(): string;
  /** objectURL for a local image path (relative to the md); null while
   * loading / until folder permission is granted */
  imageUrl(path: string): string | null;
  chooseImageFolder(): void;
  selection(): Set<number>;
  anchor(): number;
  setSelection(ids: number[], anchor: number, reveal?: boolean): void;
  clearSelection(): void;

  addChild(id: number): void; // creates + enters edit mode
  addSibling(id: number): void; // below current
  addSiblingBefore(id: number): void; // above current
  addParent(id: number): void; // wrap current
  addRoot(): void;
  rename(id: number, label: string, tag: string): void;
  commitEdit(): void;
  deleteSelection(): void;
  indentSelection(): void;
  outdentSelection(): void;
  reorder(id: number, dir: -1 | 1): void;
  toggleHidden(id: number): void; // comment-out hide/show for the subtree
  /**
   * pos 0 = target の子にする
   * pos 1 = target の直前へ挿入 / pos 2 = target の直後へ挿入
   * pos 3 = target の親として割り込む（A→B の線へのドロップ）
   */
  move(ids: number[], target: number, pos: 0 | 1 | 2 | 3): void;
  copySelection(cut: boolean): void;
  paste(): void;
  editRequested(id: number): void;
  undo(): void;
  redo(): void;
}

const SVG_NS = "http://www.w3.org/2000/svg";

function svgEl<K extends keyof SVGElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
): SVGElementTagNameMap[K] {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  return el;
}

export class MindMap {
  private pane: HTMLElement;
  private host: MapHost;
  private svg: SVGSVGElement;
  private viewport: SVGGElement;
  private edgeLayer: SVGGElement;
  private nodeLayer: SVGGElement;
  private dropLine: SVGLineElement;
  private dropHint: SVGPathElement; // どの親につくかを示す予告の曲線
  private plusBtn: SVGGElement;
  private rubber: HTMLDivElement;
  private editor: HTMLInputElement;
  private hint: HTMLDivElement;
  private menu: HTMLDivElement;

  private tx = 60;
  private ty = 60;
  private k = 1;

  private boxes = new Map<number, Box>();
  private order: number[] = []; // ids in document order
  // 差分更新用: id → DOM。以前は毎レンダで全消ししていたので、1 打鍵ごとに
  // 数万個の SVG 要素を作り直していた（それが入力遅延の実体だった）
  private nodeEls = new Map<number, SVGGElement>();
  private edgeEls = new Map<number, SVGPathElement>();
  private nodeSig = new Map<number, string>(); // 内側を作り直す判定用
  // 直前に書いた transform / class。同じ値の setAttribute はスタイル無効化を
  // 起こすだけ無駄なので書かない（プロファイル上いちばん重い JS 呼び出しだった）
  private nodeTf = new Map<number, string>();
  private nodeCls = new Map<number, string>();
  private edgeD = new Map<number, string>();
  private domOrderSig = ""; // DOM の並び（= 重なり順）を直す判定用
  private parentOf = new Map<number, number>(); // 子 → 親（線の判定用）
  private fanOf = new Map<number, number>(); // 付け根のずらし量(px)

  // interaction state
  private spaceDown = false;
  // ドラッグ中の最後のポインタ位置。Shift の押し外しだけで判定を
  // 出し直したいので覚えておく
  private lastPointer: { x: number; y: number } | null = null;
  private panning: { px: number; py: number; ox: number; oy: number } | null =
    null;
  private rubberStart: { x: number; y: number } | null = null;
  private dragCand: { id: number; px: number; py: number } | null = null;
  private dragging: { ids: number[]; subtree: Set<number> } | null = null;
  // pos 3 = その相手の親として割り込む（A→B の線へのドロップ）
  private dropTarget: {
    id: number;
    pos: 0 | 1 | 2 | 3;
  } | null = null;
  // ドロップ中の一時的なノード印。render() のクラス計算にも合流させて
  // あるので、ドラッグ中に他の理由で render() が走っても消えない
  // （直接 classList を触るだけだと、render() が自分の知らないクラスごと
  // class 属性を上書きして印を消してしまう）。
  private dropMarks = new Map<number, "drop-child" | "drop-parent">();
  private dropEdgeId: number | null = null;
  private hoverId = -1;

  // editing state
  editingId = -1;
  editingTag = "";
  private composing = false; // IME 変換中は文書へ書き込まない
  private fitPending = false;

  constructor(pane: HTMLElement, host: MapHost) {
    this.pane = pane;
    this.host = host;

    this.svg = svgEl("svg", { id: "map-svg" });
    this.viewport = svgEl("g");
    this.edgeLayer = svgEl("g");
    this.nodeLayer = svgEl("g");
    this.dropLine = svgEl("line", { id: "drop-line", visibility: "hidden" });
    this.dropHint = svgEl("path", { id: "drop-hint", visibility: "hidden" });
    // crosshair drawn with lines so the glyph is perfectly centered
    const makePlus = (): SVGGElement => {
      const btn = svgEl("g", { class: "plus-btn", visibility: "hidden" });
      btn.append(
        svgEl("circle", { r: "9" }),
        svgEl("line", { x1: "-4", y1: "0", x2: "4", y2: "0" }),
        svgEl("line", { x1: "0", y1: "-4", x2: "0", y2: "4" }),
      );
      return btn;
    };
    this.plusBtn = makePlus();
    this.viewport.append(
      this.edgeLayer,
      this.nodeLayer,
      this.dropHint,
      this.dropLine,
      this.plusBtn,
    );
    this.svg.append(this.viewport);
    pane.append(this.svg);

    this.rubber = document.createElement("div");
    this.rubber.id = "rubber";
    pane.append(this.rubber);

    this.editor = document.createElement("input");
    this.editor.id = "node-editor";
    this.editor.spellcheck = false;
    pane.append(this.editor);

    this.hint = document.createElement("div");
    this.hint.id = "map-hint";
    this.hint.innerHTML =
      "Enter で最初のノードを作成<br>（または左のエディタに # 見出しを書く）";
    this.hint.style.display = "none";
    pane.append(this.hint);

    this.menu = document.createElement("div");
    this.menu.id = "ctx-menu";
    document.body.append(this.menu);

    this.bindEvents();
    this.applyTransform();
    // a fitView requested while the pane had no size runs once it gets one
    new ResizeObserver(() => {
      if (this.fitPending) this.fitView();
    }).observe(pane);
  }

  // ---------- coordinates ----------

  private toWorld(clientX: number, clientY: number): { x: number; y: number } {
    const r = this.pane.getBoundingClientRect();
    return {
      x: (clientX - r.left - this.tx) / this.k,
      y: (clientY - r.top - this.ty) / this.k,
    };
  }

  private applyTransform(): void {
    this.viewport.setAttribute(
      "transform",
      `translate(${this.tx} ${this.ty}) scale(${this.k})`,
    );
    this.pane.style.backgroundPosition = `${this.tx}px ${this.ty}px`;
    const cell = 18 * this.k;
    this.pane.style.backgroundSize = `${cell}px ${cell}px`;
    this.positionEditor();
  }

  // ---------- layout & render ----------

  render(): void {
    const nodes = this.host.nodes();
    this.hint.style.display = nodes.length === 0 ? "flex" : "none";

    const L = layoutMap(nodes, this.host.docText());
    const { visible, boxes, hiddenKids, fanOf } = L;
    this.boxes = boxes;
    this.order = L.order;
    this.parentOf = L.parentOf;
    this.fanOf = fanOf;
    // ドラッグ中に別ペインの編集などで木が変わることがある。掴んでいた
    // ノードが消えていたらドラッグごと畳む（消えた id を指したまま
    // ドロップすると、無関係なノードが動く）
    if (this.dragging && this.dragging.ids.some((id) => !boxes.has(id))) {
      this.stopDragVisuals();
      this.dragCand = null;
    }
    // 編集中のノードが消えた/畳まれて見えなくなったら入力欄を閉じる。
    // endEdit を通すことで、フォーカスもマップに戻る（放っておくと body に
    // 落ちて、以降のキーボード操作が全部死んでいた）
    if (this.editingId !== -1 && !boxes.has(this.editingId)) {
      this.endEdit();
    }

    // ---- DOM を差分更新する ----
    // 位置(transform)と class は毎回書き換えても安い。高いのは要素の生成と
    // 破棄なので、そこは「中身が変わったノードだけ」に絞る。
    const sel = this.host.selection();
    const seen = new Set<number>();

    for (const n of visible) {
      const b = boxes.get(n.id);
      if (!b) continue;
      seen.add(n.id);

      // --- エッジ（親への曲線）---
      if (n.parent !== -1 && boxes.has(n.parent)) {
        const p = boxes.get(n.parent)!;
        let path = this.edgeEls.get(n.id);
        if (!path) {
          path = svgEl("path", { class: "edge" });
          this.edgeLayer.append(path);
          this.edgeEls.set(n.id, path);
        }
        const e = exitPoint(p, 1, 0);
        const fan = fanOf.get(n.id) ?? 0;
        const g = edgeDraw(
          { x: e.x, y: e.y + fan },
          exitPoint(b, -1, 0),
        );
        // 太さは EDGE.width で固定だが、d が変われば結局書き直すので、まとめて
        // 差分を見る
        const sig = `${g.width}|${g.d}`;
        if (this.edgeD.get(n.id) !== sig) {
          path.setAttribute("d", g.d);
          path.style.strokeWidth = String(g.width);
          this.edgeD.set(n.id, sig);
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
        this.nodeSig.delete(n.id); // 新規なので必ず中身を作る
      }
      const dropMark = this.dropMarks.get(n.id);
      const cls =
        "node" +
        (n.depth === 1 ? " root" : "") +
        (b.rows.length > 0 ? " link-card" : "") +
        (n.hidden ? " hidden-node" : "") +
        (sel.has(n.id) ? " selected" : "") +
        (this.dragging?.subtree.has(n.id) ? " dragging" : "") +
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

      // 同じ render の中に「折り畳まれた id の集合」の buried もあるので、
      // こちらは件数と分かる名前にする
      const buriedCount = hiddenKids.get(n.id) ?? 0;
      const sig = this.contentSig(n, b, buriedCount);
      if (this.nodeSig.get(n.id) === sig) continue; // 中身は据え置き
      this.nodeSig.set(n.id, sig);
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
        ? hiddenLabel(n, buriedCount)
        : clipLabel(displayLabel(n.label));
      const t = svgEl("title");
      t.textContent = n.hidden
        ? `${n.label}${buriedCount ? `\n（${buriedCount} 件を折り畳み中。Shift+H で戻す）` : "\n（非表示。Shift+H で戻す）"}`
        : n.label;
      g.append(label, t);
      // card rows (links / images) from the attached content, stacked
      // under the label
      let rowY = ROW_NORMAL.rowH;
      for (const r of b.rows) {
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
          const title = svgEl("text", {
            class: "link-row",
            x: String(ROW_NORMAL.padX),
            y: String(rowY + LINK_ROW / 2),
          });
          title.textContent = clipLabel(r.link.title);
          const tt = svgEl("title");
          tt.textContent = r.link.url;
          const open = svgEl("text", {
            class: "link-open",
            x: String(b.w - ROW_NORMAL.padX + 6),
            y: String(rowY + LINK_ROW / 2),
            "text-anchor": "end",
          });
          open.textContent = "↗";
          open.setAttribute("data-url", r.link.url);
          g.append(title, tt, open);
          rowY += LINK_ROW;
        } else if (r.kind === "svg") {
          const img = svgEl("image", {
            x: String(ROW_NORMAL.padX),
            y: String(rowY + 6),
            width: String(b.w - ROW_NORMAL.padX * 2),
            height: String(IMG_H),
            preserveAspectRatio: "xMidYMid meet",
          });
          img.setAttribute(
            "href",
            `data:image/svg+xml;charset=utf-8,${encodeURIComponent(r.markup)}`,
          );
          g.append(img);
          rowY += IMG_ROW;
        } else if (r.kind === "code") {
          const h = r.lines.length * CODE_LINE + CODE_PAD * 2;
          const bg = svgEl("rect", {
            class: "code-bg",
            x: String(ROW_NORMAL.padX - 5),
            y: String(rowY + 5),
            width: String(b.w - (ROW_NORMAL.padX - 5) * 2),
            height: String(h - 10),
            rx: "5",
          });
          if (r.lang !== "") {
            const tt = svgEl("title");
            tt.textContent = r.lang;
            bg.append(tt);
          }
          g.append(bg);
          for (let i = 0; i < r.lines.length; i++) {
            const ln = svgEl("text", {
              class: "code-line",
              x: String(ROW_NORMAL.padX + 1),
              y: String(rowY + CODE_PAD + i * CODE_LINE + CODE_LINE / 2),
            });
            ln.textContent = clipLabel(r.lines[i], MONO_FONT);
            g.append(ln);
          }
          rowY += h;
        } else {
          const url = this.host.imageUrl(r.path);
          if (url !== null) {
            const img = svgEl("image", {
              x: String(ROW_NORMAL.padX),
              y: String(rowY + 6),
              width: String(b.w - ROW_NORMAL.padX * 2),
              height: String(IMG_H),
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
                "data-image": r.path,
                x: String(ROW_NORMAL.padX),
                y: String(rowY + 6),
                width: String(b.w - ROW_NORMAL.padX * 2),
                height: String(IMG_H),
                rx: "6",
              }),
            );
            const ph = svgEl("text", {
              class: "img-name",
              "data-image": r.path,
              x: String(b.w / 2),
              y: String(rowY + 6 + IMG_H / 2),
              "text-anchor": "middle",
            });
            ph.textContent = r.name;
            g.append(ph);
          }
          rowY += IMG_ROW;
        }
      }
    }

    // 見えなくなったノード / エッジを片付ける
    for (const [id, el] of this.nodeEls) {
      if (seen.has(id)) continue;
      el.remove();
      this.nodeEls.delete(id);
      this.nodeSig.delete(id);
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
    const orderSig = this.order.join(",");
    if (orderSig !== this.domOrderSig) {
      for (const id of this.order) {
        const el = this.nodeEls.get(id);
        if (el) this.nodeLayer.append(el);
      }
      this.domOrderSig = orderSig;
    }

    this.updatePlus();
    this.positionEditor();
  }

  private contentSig(n: NodeInfo, b: Box, buried: number): string {
    // 値どうしは本文に出ない制御文字で区切る。連結だけだと
    // lang "ts"+行 "x" と lang "t"+行 "sx" のような別内容が同じ署名になる
    const SEP = "\u0000";
    let s = `${b.w}|${b.h}|${n.hidden ? 1 : 0}|${buried}|${n.label}`;
    for (const r of b.rows) {
      if (r.kind === "link") s += `|L${r.link.title}${SEP}${r.link.url}`;
      else if (r.kind === "svg") s += `|S${r.markup}`;
      else if (r.kind === "code") s += `|C${r.lang}${SEP}${r.lines.join(SEP)}`;
      else s += `|I${r.path}${SEP}${this.host.imageUrl(r.path) ?? ""}`;
    }
    return s;
  }

  /** Center the whole tree in the pane (file open / initial view). If the
   * pane has no size yet (hidden / pre-layout boot), defer until it does. */
  fitView(): void {
    if (this.boxes.size === 0) return;
    const r = this.pane.getBoundingClientRect();
    if (r.width < 80 || r.height < 80) {
      this.fitPending = true;
      return;
    }
    this.fitPending = false;
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    for (const b of this.boxes.values()) {
      x0 = Math.min(x0, b.x);
      y0 = Math.min(y0, b.y);
      x1 = Math.max(x1, b.x + b.w);
      y1 = Math.max(y1, b.y + b.h);
    }
    const m = 60;
    const kx = (r.width - m * 2) / Math.max(1, x1 - x0);
    const ky = (r.height - m * 2) / Math.max(1, y1 - y0);
    this.k = Math.max(0.15, Math.min(1, kx, ky));
    this.tx = r.width / 2 - ((x0 + x1) / 2) * this.k;
    this.ty = r.height / 2 - ((y0 + y1) / 2) * this.k;
    this.applyTransform();
  }

  /** 一時的な UI 状態（選択・ドロップ印）を除いた、書き出し用の SVG。
   * computed style を属性にインライン化し、画像サムネイルは data URL で
   * 埋め込むので、この結果だけで単体表示できる（ダウンロード/ラスタライズ用）。
   * 地図が空なら null。 */
  exportSvg(): Promise<SVGSVGElement | null> {
    return exportMapSvg({
      boxes: this.boxes.values(),
      edgeLayer: this.edgeLayer,
      nodeLayer: this.nodeLayer,
      pane: this.pane,
    });
  }

  /** 子 id から、その親へのエッジの幾何を出す（付け根のずらしも込み） */
  private edgeGeomOf(
    id: number,
  ): { a: { x: number; y: number }; du: number; dv: number } | null {
    const b = this.boxes.get(id);
    const pid = this.parentOf.get(id);
    const p = pid !== undefined ? this.boxes.get(pid) : undefined;
    if (!b || !p) return null;
    const e = exitPoint(p, 1, 0);
    const fan = this.fanOf.get(id) ?? 0;
    const a = { x: e.x, y: e.y + fan };
    const z = exitPoint(b, -1, 0);
    return {
      a,
      du: z.x - a.x,
      dv: z.y - a.y,
    };
  }

  /** エッジを world 座標の折れ線にする（線への当たり判定と印の位置に使う） */
  private edgePolyline(id: number): { x: number; y: number }[] | null {
    const g = this.edgeGeomOf(id);
    if (!g) return null;
    return flattenSegs(edgeSegs(g.du, g.dv), 8).map((q) => ({
      x: g.a.x + q[0],
      y: g.a.y + q[1],
    }));
  }

  /** id を指定して一時的な class を付ける（DOM を舐めずに済む） */
  private markNode(id: number, cls: "dragging" | "drop-child" | "drop-parent"): void {
    this.nodeEls.get(id)?.classList.add(cls);
    if (cls === "drop-child" || cls === "drop-parent") {
      this.dropMarks.set(id, cls);
    }
  }

  /**
   * ドロップの一時印を外す。何十何百ノードあっても、印が付いているのは
   * 常に高々数個（マウス移動のたびに呼ぶので、ここは印を持つ id だけを
   * 触る — 全ノードを舐めていた頃は大きな地図でドラッグ中の毎移動が重かった）。
   * alsoDragging はドラッグ終了時だけ true にし、掴んでいた部分木の
   * dragging も一緒に外す。
   */
  private clearDropMarks(alsoDragging: boolean): void {
    for (const [id, cls] of this.dropMarks) {
      this.nodeEls.get(id)?.classList.remove(cls);
    }
    this.dropMarks.clear();
    if (this.dropEdgeId !== null) {
      this.edgeEls.get(this.dropEdgeId)?.classList.remove("drop-edge");
      this.dropEdgeId = null;
    }
    if (alsoDragging && this.dragging) {
      for (const id of this.dragging.subtree) {
        this.nodeEls.get(id)?.classList.remove("dragging");
      }
    }
  }

  /** Pan so the given node is visible (used after keyboard nav / creation). */
  ensureVisible(id: number): void {
    const b = this.boxes.get(id);
    if (!b) return;
    const r = this.pane.getBoundingClientRect();
    const sx = b.x * this.k + this.tx;
    const sy = b.y * this.k + this.ty;
    const sw = b.w * this.k;
    const sh = b.h * this.k;
    const m = 40;
    if (sx < m) this.tx += m - sx;
    else if (sx + sw > r.width - m) this.tx -= sx + sw - (r.width - m);
    if (sy < m) this.ty += m - sy;
    else if (sy + sh > r.height - m) this.ty -= sy + sh - (r.height - m);
    this.applyTransform();
  }

  // ---------- label editing ----------

  beginEdit(id: number, tag: string): void {
    const b = this.boxes.get(id);
    if (!b) return;
    this.editingId = id;
    this.editingTag = tag;
    this.editor.value = b.n.label;
    this.editor.style.display = "block";
    this.positionEditor();
    this.editor.focus();
    // never select-all; caret at the end
    const pos = this.editor.value.length;
    this.editor.setSelectionRange(pos, pos);
  }

  /** 入力欄の現在値を文書へ反映する（変換確定後にだけ呼ぶ）。 */
  private commitEditorValue(): void {
    if (this.editingId === -1) return;
    this.host.rename(this.editingId, this.editor.value, this.editingTag);
    this.positionEditor();
  }

  endEdit(): void {
    // 変換中に Esc / Enter で抜けた場合、未確定ぶんを取りこぼさない
    if (this.composing) {
      this.composing = false;
      this.commitEditorValue();
    }
    this.editingId = -1;
    this.editingTag = "";
    this.editor.style.display = "none";
    this.pane.focus();
  }

  isEditing(): boolean {
    return this.editingId !== -1;
  }

  private positionEditor(): void {
    if (this.editingId === -1) return;
    const b = this.boxes.get(this.editingId);
    if (!b) return;
    // The input has to sit EXACTLY on the node's label row (mmm.md その３:
    // 編集時入力欄右に空白がある). Everything below is computed in world
    // units first and scaled once, because the input's padding and border
    // are CSS pixels that do NOT scale with the zoom — leaving them fixed is
    // what made the input and the box disagree at any zoom other than 1.
    const BORDER = 2; // #node-editor の枠（拡大しない）
    // ラベル行の寸法は rowOf() が唯一の定義。SVG 側と同じものを使うので
    // 通常ノードでも折り畳んだノードでも文字位置がずれない
    const row = rowOf(b.n);
    // box-sizing: border-box なので文字は left+border+padding から始まる。
    // left を border ぶん外へずらしてあるぶんが打ち消すので、padding は
    // SVG ラベルの x（= row.padX）をそのままスケールした値でよい
    const padW = Math.max(row.padX * this.k, 2);
    // 文字が箱より長くなったら伸びる。短いときは箱にぴったり重なる
    const textWorld = measure(row.font, this.editor.value) + row.padX * 2;
    const wWorld = Math.max(b.w, textWorld);
    this.editor.style.left = `${b.x * this.k + this.tx - BORDER}px`;
    this.editor.style.top = `${b.y * this.k + this.ty - BORDER}px`;
    this.editor.style.width = `${wWorld * this.k + BORDER * 2}px`;
    this.editor.style.height = `${row.rowH * this.k + BORDER * 2}px`;
    this.editor.style.paddingLeft = `${padW}px`;
    this.editor.style.paddingRight = `${padW}px`;
    this.editor.style.fontSize = `${row.fontPx * this.k}px`;
  }

  // ---------- hover plus button ----------

  private updatePlus(): void {
    const b = this.hoverId !== -1 ? this.boxes.get(this.hoverId) : undefined;
    if (!b || this.dragging || this.isEditing()) {
      this.plusBtn.setAttribute("visibility", "hidden");
      return;
    }
    this.plusBtn.setAttribute("visibility", "visible");
    const p = exitPoint(b, 1, 0);
    this.plusBtn.setAttribute(
      "transform",
      `translate(${p.x + 14} ${p.y})`,
    );
  }

  // ---------- events ----------

  private bindEvents(): void {
    const pane = this.pane;

    // Shift を押す/離すだけで、指を動かさずに判定を切り替えたい
    const onDragMod = (e: KeyboardEvent): void => {
      if (!this.dragging || !this.lastPointer) return;
      if (e.key !== "Shift") return;
      this.updateDrop(this.lastPointer.x, this.lastPointer.y, e.type === "keydown");
    };
    window.addEventListener("keydown", onDragMod);
    window.addEventListener("keyup", onDragMod);
    window.addEventListener("keydown", (e) => {
      if (
        e.code === "Space" &&
        !this.isEditing() &&
        document.activeElement === pane
      ) {
        this.spaceDown = true;
        pane.style.cursor = "grab";
        e.preventDefault();
      }
    });
    window.addEventListener("keyup", (e) => {
      if (e.code === "Space") {
        this.spaceDown = false;
        if (!this.panning) pane.style.cursor = "";
      }
    });

    pane.addEventListener(
      "wheel",
      (e) => {
        e.preventDefault();
        if (e.ctrlKey || e.metaKey) {
          // zoom anchored at the cursor (spec 3.3)
          const r = pane.getBoundingClientRect();
          const cx = e.clientX - r.left;
          const cy = e.clientY - r.top;
          const factor = Math.exp(-e.deltaY * 0.0022);
          const nk = Math.min(3, Math.max(0.15, this.k * factor));
          const real = nk / this.k;
          this.tx = cx - (cx - this.tx) * real;
          this.ty = cy - (cy - this.ty) * real;
          this.k = nk;
        } else if (e.shiftKey) {
          this.tx -= e.deltaY !== 0 ? e.deltaY : e.deltaX;
        } else {
          this.tx -= e.deltaX;
          this.ty -= e.deltaY;
        }
        this.applyTransform();
      },
      { passive: false },
    );

    // the + button and link-open glyph stop pointerdown propagation, so
    // this handler only ever sees pane/node/editor presses
    pane.addEventListener("pointerdown", (e) => {
      // clicks inside the label editor place the cursor; they must not
      // commit the edit
      if (e.target === this.editor) return;
      if (this.isEditing()) this.host.commitEdit();
      this.hideMenu();
      pane.focus();

      // パンは 2 つ入り口を持つ: 中クリックはマウスだけで完結し、
      // Space+ドラッグはキーボードに手がある時に届く。担当する手が
      // 違うので、片方だけでは塞がる場面がある
      if (e.button === 1 || (e.button === 0 && this.spaceDown)) {
        this.panning = {
          px: e.clientX,
          py: e.clientY,
          ox: this.tx,
          oy: this.ty,
        };
        pane.style.cursor = "grabbing";
        pane.setPointerCapture(e.pointerId);
        e.preventDefault();
        return;
      }
      if (e.button !== 0) return;

      const id = this.nodeAt(e.clientX, e.clientY);
      if (id !== -1) {
        this.dragCand = { id, px: e.clientX, py: e.clientY };
        pane.setPointerCapture(e.pointerId);
      } else {
        // empty space: rubber band (spec 3.3)
        const r = pane.getBoundingClientRect();
        this.rubberStart = { x: e.clientX - r.left, y: e.clientY - r.top };
        pane.setPointerCapture(e.pointerId);
      }
    });

    pane.addEventListener("pointermove", (e) => {
      if (this.panning) {
        this.tx = this.panning.ox + e.clientX - this.panning.px;
        this.ty = this.panning.oy + e.clientY - this.panning.py;
        this.applyTransform();
        return;
      }
      if (this.rubberStart) {
        const r = pane.getBoundingClientRect();
        const x2 = e.clientX - r.left;
        const y2 = e.clientY - r.top;
        const x = Math.min(this.rubberStart.x, x2);
        const y = Math.min(this.rubberStart.y, y2);
        const w = Math.abs(x2 - this.rubberStart.x);
        const h = Math.abs(y2 - this.rubberStart.y);
        Object.assign(this.rubber.style, {
          display: "block",
          left: `${x}px`,
          top: `${y}px`,
          width: `${w}px`,
          height: `${h}px`,
        });
        const w1 = this.toWorld(e.clientX, e.clientY);
        const w0 = this.toWorld(
          this.rubberStart.x + r.left,
          this.rubberStart.y + r.top,
        );
        const rx0 = Math.min(w0.x, w1.x);
        const ry0 = Math.min(w0.y, w1.y);
        const rx1 = Math.max(w0.x, w1.x);
        const ry1 = Math.max(w0.y, w1.y);
        const hit: number[] = [];
        for (const id of this.order) {
          const b = this.boxes.get(id);
          if (!b) continue;
          if (b.x < rx1 && b.x + b.w > rx0 && b.y < ry1 && b.y + b.h > ry0) {
            hit.push(id);
          }
        }
        // only when the hit set actually changed — and without md-pane
        // auto-scroll, which would make the editor jump around mid-drag
        const cur = this.host.selection();
        if (hit.length !== cur.size || hit.some((id) => !cur.has(id))) {
          this.host.setSelection(
            hit,
            hit.length ? hit[hit.length - 1] : -1,
            false,
          );
        }
        return;
      }
      if (this.dragCand && !this.dragging) {
        const dx = e.clientX - this.dragCand.px;
        const dy = e.clientY - this.dragCand.py;
        // generous threshold so the second press of a double-click never
        // turns into a drag
        if (dx * dx + dy * dy > 64) this.startDrag();
      }
      if (this.dragging) {
        this.lastPointer = { x: e.clientX, y: e.clientY };
        this.updateDrop(e.clientX, e.clientY, e.shiftKey);
      }
    });

    pane.addEventListener("pointerup", (e) => {
      if (this.panning) {
        this.panning = null;
        pane.style.cursor = this.spaceDown ? "grab" : "";
        return;
      }
      if (this.rubberStart) {
        const moved =
          this.rubber.style.display === "block" &&
          (parseFloat(this.rubber.style.width) > 3 ||
            parseFloat(this.rubber.style.height) > 3);
        this.rubber.style.display = "none";
        this.rubberStart = null;
        if (!moved && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
          this.host.clearSelection();
        }
        return;
      }
      if (this.dragging) {
        // 離す直前にも判定し直す（Shift を押したまま指を動かさず離したとき用）
        if (this.lastPointer) {
          this.updateDrop(e.clientX, e.clientY, e.shiftKey);
        }
        const drop = this.dropTarget;
        const ids = this.dragging.ids;
        this.stopDragVisuals();
        if (drop) this.host.move(ids, drop.id, drop.pos);
        this.dragCand = null;
        return;
      }
      if (this.dragCand) {
        // plain click on a node: selection (spec 3.3 / 3.3.1)
        const id = this.dragCand.id;
        this.dragCand = null;
        const sel = this.host.selection();
        const mod = e.ctrlKey || e.metaKey;
        if (e.shiftKey && this.host.anchor() !== -1) {
          const a = this.order.indexOf(this.host.anchor());
          const b = this.order.indexOf(id);
          if (a !== -1 && b !== -1) {
            const [lo, hi] = a < b ? [a, b] : [b, a];
            // display order = document order = md line order (spec 3.3.1)
            this.host.setSelection(
              this.order.slice(lo, hi + 1),
              this.host.anchor(),
            );
          }
        } else if (mod) {
          const next = new Set(sel);
          if (next.has(id)) next.delete(id);
          else next.add(id);
          this.host.setSelection(
            [...next],
            next.has(id) ? id : this.host.anchor(),
          );
        } else {
          this.host.setSelection([id], id);
        }
      }
    });

    pane.addEventListener("pointercancel", () => {
      // pen/touch cancellation must not leave a drag/pan/rubber stuck
      this.panning = null;
      this.rubberStart = null;
      this.rubber.style.display = "none";
      this.dragCand = null;
      if (this.dragging) this.stopDragVisuals();
      pane.style.cursor = "";
    });

    pane.addEventListener("dblclick", (e) => {
      // double-clicking the ↗ glyph opens the link; don't also start editing
      if ((e.target as Element).classList?.contains("link-open")) return;
      // hit-test by position: pointer capture retargets the event to the
      // pane, so e.target never points at the node that was clicked
      const id = this.nodeAt(e.clientX, e.clientY);
      if (id === -1) return;
      e.preventDefault();
      this.dragCand = null;
      if (this.dragging) this.stopDragVisuals();
      this.host.editRequested(id);
    });

    pane.addEventListener("pointerover", (e) => {
      const nodeG = (e.target as Element).closest?.(
        "g.node",
      ) as SVGGElement | null;
      const next = nodeG
        ? Number(nodeG.dataset.id)
        : this.overPlus(e)
          ? this.hoverId
          : -1;
      if (next !== this.hoverId) {
        this.hoverId = next;
        this.updatePlus();
      }
    });

    this.plusBtn.addEventListener("pointerdown", (e) => {
      e.stopPropagation();
    });
    this.plusBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      if (this.hoverId === -1) return;
      this.host.addChild(this.hoverId);
    });

    // open link cards
    this.nodeLayer.addEventListener("click", (e) => {
      const t = e.target as Element;
      if (t.closest?.("[data-image]")) {
        this.host.chooseImageFolder();
        return;
      }
      if (!t.classList?.contains("link-open")) return;
      const url = t.getAttribute("data-url");
      if (url) window.open(url, "_blank", "noopener,noreferrer");
    });
    this.nodeLayer.addEventListener("pointerdown", (e) => {
      if ((e.target as Element).classList?.contains("link-open")) {
        e.stopPropagation();
      }
    });

    pane.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      const id = this.nodeAt(e.clientX, e.clientY);
      if (id === -1) {
        this.hideMenu();
        return;
      }
      if (!this.host.selection().has(id)) this.host.setSelection([id], id);
      this.showMenu(e.clientX, e.clientY);
    });

    // node label editor: Enter / Esc / Mod+Enter all COMMIT (mmm.md そのに:
    // enter決定。キャンセルは存在しない); Tab does nothing
    // IME の変換中は文書へ書き込まない。
    // 変換中の中間候補まで rename すると、(a) 未確定の文字列が「唯一の真実」
    // であるはずの markdown に流れ込み、(b) 候補が変わるたびに全再描画が走る。
    // 変換中に外から value を書き換えるのは日本語入力を壊す代表的なパターン
    // なので、確定するまで待って compositionend で 1 回だけ反映する。
    // 入力欄の見た目（幅）だけは変換中も追従させる。
    this.editor.addEventListener("compositionstart", () => {
      this.composing = true;
    });
    this.editor.addEventListener("compositionend", () => {
      this.composing = false;
      this.commitEditorValue();
    });
    this.editor.addEventListener("input", (e) => {
      if (this.composing || (e as InputEvent).isComposing) {
        this.positionEditor();
        return;
      }
      this.commitEditorValue();
    });
    this.editor.addEventListener("keydown", (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      e.stopPropagation();
      if (e.key === "Escape" || e.key === "Enter") {
        this.host.commitEdit();
        e.preventDefault();
      } else if (e.key === "Tab") {
        e.preventDefault();
      }
    });
    this.editor.addEventListener("blur", () => {
      if (this.editingId !== -1) this.host.commitEdit();
    });

    // keyboard, select mode
    pane.addEventListener("keydown", (e) => this.onKeydown(e));

    // the context menu must close on any interaction elsewhere, not just
    // inside the map pane
    document.addEventListener("pointerdown", (e) => {
      if (!this.menu.contains(e.target as Node)) this.hideMenu();
    });
    window.addEventListener("blur", () => this.hideMenu());
  }

  private overPlus(e: Event): boolean {
    return !!(e.target as Element).closest?.(".plus-btn");
  }

  /** Node whose box contains the given client position, or -1. Iterates in
   * reverse document order so the topmost-drawn box wins when boxes touch. */
  /** その点にあるノード（無ければ -1）。落ちてきたものの宛先を決めるのに使う */
  nodeAt(clientX: number, clientY: number): number {
    const w = this.toWorld(clientX, clientY);
    for (let i = this.order.length - 1; i >= 0; i--) {
      const b = this.boxes.get(this.order[i]);
      if (!b) continue;
      if (w.x >= b.x && w.x <= b.x + b.w && w.y >= b.y && w.y <= b.y + b.h) {
        return this.order[i];
      }
    }
    return -1;
  }

  // ---------- keyboard (select mode) ----------

  private onKeydown(e: KeyboardEvent): void {
    if (e.isComposing || e.keyCode === 229) return;
    if (this.isEditing()) return;
    const mod = e.ctrlKey || e.metaKey;
    const anchor = this.host.anchor();
    const sel = this.host.selection();
    const nodes = this.host.nodes();
    // CapsLock reports letters as capitals WITHOUT shiftKey, so a plain `h`
    // would arrive as `H` and silently comment out the subtree.
    // Treat a capital that arrived without Shift as the lowercase key.
    const key =
      !e.shiftKey && e.key.length === 1 && e.key >= "A" && e.key <= "Z"
        ? e.key.toLowerCase()
        : e.key;

    // comment-out hide/show for the subtree (= collapse)
    if (key === "H" && !mod && !e.altKey && anchor !== -1) {
      this.host.toggleHidden(anchor);
      e.preventDefault();
      return;
    }
    // edit the label
    if (key === "Enter" && mod) {
      if (nodes.length === 0) this.host.addRoot();
      else if (anchor !== -1 && sel.size <= 1) this.host.editRequested(anchor);
      e.preventDefault();
      return;
    }
    // Enter: add a sibling below (mmm.md そのに: enterで兄弟追加、復活)
    if (key === "Enter") {
      if (nodes.length === 0) this.host.addRoot();
      else if (anchor !== -1) this.host.addSibling(anchor);
      e.preventDefault();
      return;
    }
    // create child / wrap in parent: Tab / Shift+Tab (multi: indent/outdent)
    if (key === "Tab" && !e.shiftKey) {
      if (sel.size > 1) this.host.indentSelection();
      else if (anchor !== -1) this.host.addChild(anchor);
      e.preventDefault();
      return;
    }
    if (key === "Tab" && e.shiftKey) {
      if (sel.size > 1) this.host.outdentSelection();
      else if (anchor !== -1) this.host.addParent(anchor);
      e.preventDefault();
      return;
    }
    if (key === "Delete" || key === "Backspace") {
      this.host.deleteSelection();
      e.preventDefault();
      return;
    }
    if (mod && (key === "a" || key === "A")) {
      this.host.setSelection(
        [...this.order],
        anchor !== -1 ? anchor : (this.order[0] ?? -1),
      );
      e.preventDefault();
      return;
    }
    if (mod && (key === "c" || key === "C")) {
      this.host.copySelection(false);
      e.preventDefault();
      return;
    }
    if (mod && (key === "x" || key === "X")) {
      this.host.copySelection(true);
      e.preventDefault();
      return;
    }
    if (mod && (key === "v" || key === "V")) {
      this.host.paste();
      e.preventDefault();
      return;
    }
    if (key === "Escape") {
      this.host.clearSelection();
      return;
    }

    // movement: arrows. 上下は同じ深さの列を縦に辿る
    if (!key.startsWith("Arrow")) return;
    // 並べ替えは Alt+↑↓（Alt+←→ はブラウザの戻る/進むなので取らない）
    if (e.altKey && (key === "ArrowUp" || key === "ArrowDown")) {
      e.preventDefault();
      if (anchor !== -1 && sel.size === 1) {
        this.host.reorder(anchor, key === "ArrowUp" ? -1 : 1);
      }
      return;
    }
    if (mod) return; // Mod+矢印には何も割り当てない
    e.preventDefault();
    if (this.order.length === 0) return;
    if (anchor === -1) {
      const first = this.order[0];
      this.host.setSelection([first], first);
      return;
    }
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const cur = byId.get(anchor);
    if (!cur) return;
    let next = -1;
    if (key === "ArrowUp" || key === "ArrowDown") {
      if (e.shiftKey) {
        // extend by display order; anchor edge stays (spec 3.4)
        const idx = this.order.indexOf(anchor);
        const j = idx + (key === "ArrowUp" ? -1 : 1);
        if (j < 0 || j >= this.order.length) return;
        const nx = this.order[j];
        const set = new Set(sel);
        if (set.has(nx) && sel.size > 1) set.delete(anchor);
        else set.add(nx);
        this.host.setSelection([...set], nx);
        return;
      }
      // 同じ深さの列を文書順（= 画面の上から下）に辿り、端でループする。
      // 兄弟に限らずいとこも含む — 見えている限り、その階層は 1 本の列。
      // 親が畳まれて埋もれたノードは列に入れない（選べないものへは飛べない）。
      const level = this.order.filter(
        (id) => byId.get(id)?.depth === cur.depth && this.boxes.has(id),
      );
      const i = level.indexOf(anchor);
      if (i === -1) return;
      const j = (i + (key === "ArrowUp" ? -1 : 1) + level.length) % level.length;
      next = level[j];
    } else {
      if (key === "ArrowLeft") next = cur.parent;
      else
        next =
          nodes.find((n) => n.parent === anchor && this.boxes.has(n.id))?.id ??
          -1;
    }
    if (next !== -1 && next !== undefined) {
      this.host.setSelection([next], next);
      this.ensureVisible(next);
    }
  }

  // ---------- drag re-parenting ----------

  private startDrag(): void {
    if (!this.dragCand) return;
    const id = this.dragCand.id;
    let ids: number[];
    const sel = this.host.selection();
    if (sel.has(id)) {
      ids = this.order.filter((o) => sel.has(o)); // document order
    } else {
      ids = [id];
      this.host.setSelection([id], id);
    }
    // subtree ids for visuals + drop-target exclusion
    const nodes = this.host.nodes();
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const subtree = new Set<number>();
    for (const nid of ids) {
      const nd = byId.get(nid);
      if (!nd) continue;
      for (const m of nodes) {
        if (m.hs >= nd.hs && m.hs < nd.subEnd) subtree.add(m.id);
      }
    }
    this.dragging = { ids, subtree };
    for (const id of subtree) this.markNode(id, "dragging");
    this.updatePlus();
  }

  /**
   * preferEdge = Shift を押しながら。線への割り込み（A→C→B）を先に判定し、
   * 狙える範囲も広げる。押していないときは「子にする」「前後に挿入」を
   * 優先して、線の判定はどこにも属さない空間だけに絞る。
   */
  private updateDrop(clientX: number, clientY: number, preferEdge = false): void {
    // 呼び出し側は全員 `if (this.dragging)` の中からしか呼ばない。ここで
    // 1 回だけ絞り込めば、以降 `this.dragging!` を都度書かずに済む
    const dragging = this.dragging;
    if (!dragging) return;
    const w = this.toWorld(clientX, clientY);
    let target: {
      id: number;
      pos: 0 | 1 | 2 | 3;
    } | null = null;
    const SLOP = 16;
    const BAND = 40; // wide before/after zones (mmm.md そのに: さらに拡大)
    // pointer position relative to a box's center
    const local = (b: Box) => {
      const c = centerOf(b);
      const dx = w.x - c.x;
      const dy = w.y - c.y;
      return {
        du: dx,
        dv: dy,
        hu: b.w / 2,
        hv: b.h / 2,
      };
    };
    /**
     * A→B の線のまんなかに落とす = B の親として割り込む（A→C→B）。
     * 押していないときはいちばん最後に判定する。ノードの上でも、その外側の
     * 「子にする」帯でもない、どこにも属さない空間だけを拾う。頻度の高い
     * 「子にする」から場所を取ると使いにくい、という実際の使用感を優先。
     * Shift を押していれば先に判定し、狙える範囲も広げる。
     * 複数まとめて持っているときは「誰が親になるのか」が決まらないので出さない。
     */
    const findEdge = (): { id: number; pos: 3 } | null => {
      if (dragging.ids.length !== 1) return null;
      let bestEdge = preferEdge ? 30 : 16; // 線からこの距離まで拾う
      const band = preferEdge ? 0.1 : 0.3; // 端から何割を狙い所から外すか
      let onEdge: number | null = null;
      for (const id of this.parentOf.keys()) {
        if (dragging.subtree.has(id)) continue;
        const pts = this.edgePolyline(id);
        if (!pts) continue;
        // 端のほうは「前後に挿入」や「子にする」と紛らわしいので、
        // 長さで測って真ん中あたりだけを狙い所にする
        let total = 0;
        const segLen: number[] = [];
        for (let i = 1; i < pts.length; i++) {
          const l = Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
          segLen.push(l);
          total += l;
        }
        let acc = 0;
        for (let i = 1; i < pts.length; i++) {
          const mid = acc + segLen[i - 1] / 2;
          acc += segLen[i - 1];
          if (mid < total * band || mid > total * (1 - band)) continue;
          const d = distToSeg(w, pts[i - 1], pts[i]);
          if (d < bestEdge) {
            bestEdge = d;
            onEdge = id;
          }
        }
      }
      return onEdge === null ? null : { id: onEdge, pos: 3 };
    };
    // Shift = 線への割り込みを最優先。見つかったかどうかは後の段でも使う
    // （見つかった線を、外側ゾーンや帯が黙って横取りしない）
    const edgeTarget = preferEdge ? findEdge() : null;
    if (edgeTarget) target = edgeTarget;

    // 帯は隣の兄弟と重なるので、最初に見つかった相手ではなく「いちばん近い」
    // 相手を選ぶ。文書順で決めていたころは、親が違う子スタックの境目で
    // どちらに倒れるかが実質その場の運になっていた。
    let best = Infinity;
    let rival = Infinity; // いちばん近い「別の親になる」候補までの距離
    const parentFor = (id: number, pos: 0 | 1 | 2 | 3): number =>
      pos === 0 ? id : (this.parentOf.get(id) ?? -1);
    const cands: { id: number; pos: 0 | 1 | 2; dist: number; parent: number }[] = [];
    for (const id of this.order) {
      if (dragging.subtree.has(id)) continue;
      const b = this.boxes.get(id);
      if (!b) continue;
      const { du, dv, hu, hv } = local(b);
      if (Math.abs(du) > hu + SLOP || Math.abs(dv) > hv + BAND) continue;
      // 箱の中なら 0。外に出た分だけ距離が増える（兄弟軸のほうを重く見る）
      const dist =
        Math.max(0, Math.abs(du) - hu) + Math.max(0, Math.abs(dv) - hv) * 2;
      // the root has no siblings: any drop on it means "child"
      const pos: 0 | 1 | 2 =
        b.n.depth === 1 ? 0 : dv < -hv * 0.4 ? 1 : dv > hv * 0.4 ? 2 : 0;
      cands.push({ id, pos, dist, parent: parentFor(id, pos) });
      if (dist < best) {
        best = dist;
        if (!edgeTarget) target = { id, pos };
      }
    }
    // outward zone: hovering just beyond a node's outer edge (along its
    // growth axis) also means "as child" (mmm.md 課題)
    //
    // よく使う操作なので広めに取る。重なったときは文書順ではなく近い方を選ぶ。
    // 判定の優先順は 4 段:
    //   1. 箱の中
    //   2. 外側ゾーンの近い側（NEAR まで）… 前後への挿入より強い
    //   3. 前後への挿入（箱の上下の帯）
    //   4. 外側ゾーンの遠い側（REACH まで）… 誰も取らない空間の受け皿
    // 近くを子に振らないと、次の列の子の帯に吸われて「右に置いたのに
    // 兄弟になる」が起きる。逆に遠くまで子を優先させると、今度は前後への
    // 挿入がほぼ出せなくなるので、そこは前後に譲る
    const REACH = GAP.x * 4 + 16; // 成長軸方向にどこまで伸ばすか
    const NEAR = REACH * 0.4; // ここまでは前後への挿入より子を優先する
    const SLACK = 18; // 兄弟軸方向に箱からどれだけはみ出してよいか
    let outTarget: { id: number; pos: 0 } | null = null;
    let bestOut = Infinity;
    let outU = Infinity; // 選んだ相手の、箱の外縁からの距離
    for (const id of this.order) {
      if (dragging.subtree.has(id)) continue;
      const b = this.boxes.get(id);
      if (!b) continue;
      const { du, dv, hu, hv } = local(b);
      if (du <= hu || du > hu + REACH || Math.abs(dv) > hv + SLACK) continue;
      const d = du - hu + Math.max(0, Math.abs(dv) - hv) * 2;
      if (d < bestOut) {
        bestOut = d;
        outU = du - hu;
        outTarget = { id, pos: 0 };
      }
    }
    if (outTarget && !edgeTarget && best > 0 && (outU <= NEAR || !target)) {
      target = outTarget;
    }

    if (!target) target = findEdge();

    // 親が変わりうる相手がすぐ隣にいるときだけ「どの親につくか」を出す。
    // 迷いようがない場面（同じ親の兄弟どうし、ノードのど真ん中）では
    // 挿入線だけにして、目線を余計なところへ引っ張らない。
    // 最終的な行き先が決まってから測る — 外側ゾーンなどで差し替えたあとに
    // 帯の時点の判定を使うと、予告線の出る/出ないが行き先とずれる
    if (target) {
      const chosen = parentFor(target.id, target.pos);
      for (const c of cands) {
        if (c.parent !== chosen && c.dist < rival) rival = c.dist;
      }
    }
    const AMBIGUOUS = 26; // これより競っていれば迷う場面とみなす
    const ambiguous = rival - best <= AMBIGUOUS;

    this.dropTarget = target;
    // indicator is mandatory (spec 3.3.2)
    this.clearDropMarks(false);
    if (!target) {
      this.dropLine.setAttribute("visibility", "hidden");
      this.dropHint.setAttribute("visibility", "hidden");
      return;
    }
    const b = this.boxes.get(target.id)!;

    // 挿入線だけだと「上の親の末尾」と「下の親の先頭」が同じ場所に出て
    // 区別できない。どの親につくのかを、その親からの予告線と枠で示す。
    const parentId = target.pos === 0 ? target.id : (this.parentOf.get(target.id) ?? -1);
    const showHint = (to: { x: number; y: number }): void => {
      const p = ambiguous ? this.boxes.get(parentId) : undefined;
      if (!p) {
        this.dropHint.setAttribute("visibility", "hidden");
        return;
      }
      const from = exitPoint(p, 1, 0);
      this.dropHint.setAttribute("d", edgeHintPath(from, to));
      this.dropHint.setAttribute("visibility", "visible");
      this.markNode(parentId, "drop-parent");
    };

    if (target.pos === 3) {
      // 線への割り込み。線そのものを光らせて、その真ん中に印を出す。
      // 「この線の途中に入る」以外の読み方がないので、親の枠までは出さない。
      this.dropEdgeId = target.id;
      this.edgeEls.get(target.id)?.classList.add("drop-edge");
      const pts = this.edgePolyline(target.id)!;
      const m = midOfPolyline(pts);
      // 印は線に直交させる（線の向きは中央付近の傾きから取る）
      const i = Math.max(1, Math.floor(pts.length / 2));
      const tx = pts[i].x - pts[i - 1].x;
      const ty = pts[i].y - pts[i - 1].y;
      const tl = Math.hypot(tx, ty) || 1;
      const half = 13;
      this.dropLine.setAttribute("x1", String(m.x - (-ty / tl) * half));
      this.dropLine.setAttribute("y1", String(m.y - (tx / tl) * half));
      this.dropLine.setAttribute("x2", String(m.x + (-ty / tl) * half));
      this.dropLine.setAttribute("y2", String(m.y + (tx / tl) * half));
      this.dropLine.setAttribute("visibility", "visible");
      this.dropHint.setAttribute("visibility", "hidden");
    } else if (target.pos === 0) {
      // ring on the target PLUS an insertion line on its outward side,
      // where the new child will appear (mmm.md そのに)
      this.markNode(target.id, "drop-child");
      const e = exitPoint(b, 1, 0);
      const lx = e.x + GAP.x / 2;
      const ly = e.y;
      const half = 16;
      this.dropLine.setAttribute("x1", String(lx));
      this.dropLine.setAttribute("y1", String(ly - half));
      this.dropLine.setAttribute("x2", String(lx));
      this.dropLine.setAttribute("y2", String(ly + half));
      this.dropLine.setAttribute("visibility", "visible");
      showHint({ x: lx, y: ly });
    } else {
      // an insertion line on the sibling axis, before or after the target
      const { hu, hv } = local(b);
      const cx = b.x + b.w / 2;
      const cy = b.y + b.h / 2;
      const off = (hv + GAP.y / 2) * (target.pos === 1 ? -1 : 1);
      const half = Math.max(hu, 40);
      this.dropLine.setAttribute("x1", String(cx - half));
      this.dropLine.setAttribute("y1", String(cy + off));
      this.dropLine.setAttribute("x2", String(cx + half));
      this.dropLine.setAttribute("y2", String(cy + off));
      this.dropLine.setAttribute("visibility", "visible");
      showHint({
        x: cx - hu,
        y: cy + off,
      });
    }
  }

  private stopDragVisuals(): void {
    this.clearDropMarks(true); // dragging の部分木を読むので dragging を消す前に
    this.dragging = null;
    this.dropTarget = null;
    this.lastPointer = null;
    this.dropLine.setAttribute("visibility", "hidden");
    this.dropHint.setAttribute("visibility", "hidden");
  }

  // ---------- context menu ----------

  private showMenu(x: number, y: number): void {
    const sel = this.host.selection();
    const multi = sel.size > 1;
    const anchorHidden =
      this.host.nodes().find((n) => n.id === this.host.anchor())?.hidden ?? false;
    const items: (
      | { label: string; key?: string; run: () => void; disabled?: boolean }
      | "sep"
    )[] = [
      {
        label: "子を追加",
        key: "Tab",
        run: () => this.host.addChild(this.host.anchor()),
        disabled: multi,
      },
      {
        label: "下に追加",
        key: "Enter",
        run: () => this.host.addSibling(this.host.anchor()),
        disabled: multi,
      },
      {
        // キーは持たない（上への追加は下への追加＋並べ替えで届く）
        label: "上に追加",
        run: () => this.host.addSiblingBefore(this.host.anchor()),
        disabled: multi,
      },
      {
        label: "親を作成",
        key: "Shift+Tab",
        run: () => this.host.addParent(this.host.anchor()),
        disabled: multi,
      },
      {
        label: "名前を変更",
        key: "Mod+Enter",
        run: () => this.host.editRequested(this.host.anchor()),
        disabled: multi,
      },
      "sep",
      { label: "1 段下げ", run: () => this.host.indentSelection() },
      { label: "1 段上げ", run: () => this.host.outdentSelection() },
      "sep",
      {
        // mmm.md その３: キーだけでなく UI からも指定・解除できるように
        label: anchorHidden ? "再表示（折り畳みを開く）" : "非表示（折り畳む）",
        key: "H",
        run: () => this.host.toggleHidden(this.host.anchor()),
        disabled: this.host.anchor() === -1,
      },
      "sep",
      { label: "コピー", key: "Mod+C", run: () => this.host.copySelection(false) },
      { label: "カット", key: "Mod+X", run: () => this.host.copySelection(true) },
      {
        label: "子として貼り付け",
        key: "Mod+V",
        run: () => this.host.paste(),
        disabled: multi,
      },
      "sep",
      { label: "削除", key: "Del", run: () => this.host.deleteSelection() },
    ];
    this.menu.replaceChildren();
    for (const it of items) {
      if (it === "sep") {
        this.menu.append(document.createElement("hr"));
        continue;
      }
      const div = document.createElement("div");
      div.className = "item" + (it.disabled ? " disabled" : "");
      const l = document.createElement("span");
      l.textContent = it.label;
      div.append(l);
      if (it.key) {
        const k = document.createElement("span");
        k.className = "key";
        k.textContent = it.key;
        div.append(k);
      }
      div.addEventListener("click", () => {
        this.hideMenu();
        it.run();
      });
      this.menu.append(div);
    }
    this.menu.style.display = "block";
    const mw = this.menu.offsetWidth;
    const mh = this.menu.offsetHeight;
    this.menu.style.left = `${Math.min(x, window.innerWidth - mw - 8)}px`;
    this.menu.style.top = `${Math.min(y, window.innerHeight - mh - 8)}px`;
  }

  hideMenu(): void {
    this.menu.style.display = "none";
  }

  /** Cheap selection repaint without a full re-layout (rubber band path). */
  refreshSelection(): void {
    const sel = this.host.selection();
    for (const [id, g] of this.nodeEls) {
      g.classList.toggle("selected", sel.has(id));
      // class を直接触ったらキャッシュも合わせる。放置すると次の render が
      // 「同じだから書かない」と判断して、DOM とズレたままになる
      this.nodeCls.set(id, g.getAttribute("class") ?? "");
    }
  }
}

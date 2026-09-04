// マップのペイン。core の View を layout で箱にし、render で SVG に写す。
//
// 持っているのは視点（Camera）と、それを動かす入力（ホイール・ドラッグ・
// ピンチ・クリック・矩形・矢印）と、画面外の根を指す針だけ。**選択の値は
// 持たない** — 入力を map/select.ts の値にして host へ渡し、返ってきた
// Selection を塗るだけ。値そのものは main.ts が持つ。あるのは選択、その場
// 編集、Enter / Tab の新規。消す・動かす・カードは次の段。

import type * as core from "./coreApi.ts";
import { type Camera, type Pane, centerOn, fitToPane, panBy, panToShow, pinch, toWorld, zoomAt } from "./map/camera.ts";
import { unionRect } from "./map/geometry.ts";
import { Fingers } from "./map/gesture.ts";
import { indicatorFor, isVisible } from "./map/indicator.ts";
import { type Intent, keyed } from "./map/keys.ts";
import { LabelEditor } from "./map/label.ts";
import { type Layout, layoutMap, rootBox } from "./map/layout.ts";
import { labelOf, nodeSize } from "./map/metrics.ts";
import { MapRenderer } from "./map/render.ts";
import { NONE, type Selection, click, hit, rubber } from "./map/select.ts";
import { svgEl } from "./map/svg.ts";
import { mapToSvg } from "./map/toSvg.ts";
import { icon } from "./icons.ts";
import { paneTool } from "./app/paneTool.ts";
import { paneHint } from "./app/hint.ts";

export interface MapHost {
  /** いまの文書（core が読んだ View） */
  doc(): core.View;
  /** ローカル画像の objectURL。読めていない / 握っていないあいだは null */
  imageUrl(path: string): string | null;
  /** 読めていない場所取りに添える字。握っていないときだけ（他は null） */
  imageHint(): string | null;
  /** その字が押された。画像フォルダを繋ぎ直す */
  connectAssets(): void;
  /** いま選んでいるもの。値は main.ts が持つ */
  selection(): Selection;
  /** 地図で選び直した。reveal は md 側をその頭へスクロールするか */
  setSelection(sel: Selection, reveal: boolean): void;
  /** 操作を md に映す。edit なら、映した後の focus をそのまま編集開始 */
  apply(op: core.Op, edit: boolean): void;
}

/** 全体を収めるときの余白（画面 px） */
const FIT_MARGIN = 60;
/** 矢印で辿るとき、選んだ箱が縁から離れている距離（画面 px） */
const SHOW_MARGIN = 40;

/** その出来事の的が `selector` に当てはまる要素（かその中）なら、それを返す */
function targetIn(e: Event, selector: string): Element | null {
  return e.target instanceof Element ? e.target.closest(selector) : null;
}

export class Mindmap {
  private pane: HTMLElement;
  private host: MapHost;
  /** world 座標の層。Camera の変換はこれに掛ける */
  private world: SVGGElement;
  private renderer = new MapRenderer();
  private hint: HTMLDivElement;
  private indicatorEl: HTMLDivElement;
  private camera: Camera = { k: 1, tx: 60, ty: 60 };
  private layout: Layout = { order: [], boxes: new Map() };
  /** 2 本目の指。1 本のあいだは何も言わない */
  private fingers = new Fingers();
  private panning: { px: number; py: number; ox: number; oy: number } | null = null;
  private fitPending = false;
  /** カーソルの輪の層。world に浮かぶ別の印（ノードの子にすると、動くたびに中身が作り直される） */
  private caretLayer: SVGGElement;
  private caretRings: SVGRectElement[] = [];
  private caretIds: number[] = [];
  /** 矩形選択の面（画面 px）。始点は pane の左上から */
  private rubber: HTMLDivElement;
  private rubberStart: { x: number; y: number } | null = null;
  /** 指で押したノード。動かさずに離せば選ぶ */
  private tapped: { id: number; x: number; y: number } | null = null;
  /** Space を押している間、左ドラッグはパン */
  private spaceHeld = false;
  private label: LabelEditor;

  constructor(pane: HTMLElement, host: MapHost) {
    this.pane = pane;
    this.host = host;

    const svg = svgEl("svg", { id: "map-svg" });
    this.world = svgEl("g");
    this.caretLayer = svgEl("g");
    this.world.append(this.renderer.edgeLayer, this.renderer.nodeLayer, this.caretLayer);
    svg.append(this.world);
    pane.append(svg);

    this.rubber = document.createElement("div");
    this.rubber.id = "rubber";
    pane.append(this.rubber);

    this.label = new LabelEditor(pane, (id, label) => this.host.apply({ kind: "rename", id, label }, false));

    // md からの始め方は md ペイン自身が同じ器で言う（app/hint.ts）
    this.hint = paneHint("Nothing to show yet — write a ", "# heading", "");
    this.hint.style.display = "none";
    pane.append(this.hint);

    this.indicatorEl = document.createElement("div");
    this.indicatorEl.id = "map-indicator";
    this.indicatorEl.style.display = "none";
    pane.append(this.indicatorEl);

    const centerTool = paneTool("map-center");
    const centerBtn = document.createElement("button");
    centerBtn.type = "button";
    centerBtn.title = "Center the view — Home";
    centerBtn.setAttribute("aria-label", "Center the view");
    centerBtn.append(icon("crosshair"));
    centerBtn.addEventListener("click", () => this.centerOnTarget());
    centerTool.append(centerBtn);
    pane.append(centerTool);

    this.bindWheel();
    this.bindPointer();
    this.bindClick();
    this.bindKeys();
    this.applyCamera();
    // a fitView requested while the pane had no size runs once it gets one
    new ResizeObserver(() => {
      if (this.fitPending) this.fitView();
    }).observe(pane);
  }

  // ---------- camera ----------

  /** ペインの左上から測った画面 px（camera.ts が使う座標系） */
  private local(clientX: number, clientY: number): { x: number; y: number } {
    const r = this.pane.getBoundingClientRect();
    return { x: clientX - r.left, y: clientY - r.top };
  }

  private paneSize(): Pane {
    const r = this.pane.getBoundingClientRect();
    return { width: r.width, height: r.height };
  }

  private setCamera(c: Camera): void {
    this.camera = c;
    this.applyCamera();
    const editing = this.label.editing();
    const b = editing === null ? undefined : this.layout.boxes.get(editing);
    if (b) this.label.place(b, this.camera);
    this.updateIndicator();
  }

  private applyCamera(): void {
    const { k, tx, ty } = this.camera;
    this.world.setAttribute("transform", `translate(${tx} ${ty}) scale(${k})`);
    this.pane.style.backgroundPosition = `${tx}px ${ty}px`;
    const cell = 18 * k;
    this.pane.style.backgroundSize = `${cell}px ${cell}px`;
  }

  // ---------- layout & render ----------

  render(): void {
    const doc = this.host.doc();
    this.hint.style.display = doc.trees.length === 0 ? "flex" : "none";
    this.layout = layoutMap(doc.trees, nodeSize);
    this.renderer.draw({
      layout: this.layout,
      imageUrl: (path) => this.host.imageUrl(path),
      imageHint: this.host.imageHint(),
    });
    this.renderer.paintSelection(new Set(this.host.selection().ids));
    // 前サイクルの caretIds で輪を塗り直す。無害なのは、editor.ts の同じ
    // updateListener の中で onChange の直後に必ず onCaret が続き、今の輪へ
    // 即座に上書きされるから
    this.showCaret(this.caretIds);
    const editing = this.label.editing();
    if (editing !== null) {
      const b = this.layout.boxes.get(editing);
      if (b) this.label.place(b, this.camera);
      else this.label.close();
    }
    this.updateIndicator();
  }

  fitView(): void {
    const pane = this.paneSize();
    // まだ大きさが無い（隠れている / 起動直後）なら、付いてから改めて
    if (pane.width < 80 || pane.height < 80) {
      this.fitPending = true;
      return;
    }
    this.fitPending = false;
    const c = fitToPane(this.layout.boxes.values(), pane, FIT_MARGIN);
    if (c) this.setCamera(c);
  }

  /** 選択（無ければ根）を画面の中心へ。拡大率は変えない */
  centerOnTarget(): void {
    const sel = this.host.selection().ids.flatMap((id) => {
      const b = this.layout.boxes.get(id);
      return b ? [b] : [];
    });
    const target = unionRect(sel) ?? rootBox(this.layout);
    if (target) this.setCamera(centerOn(this.camera, target, this.paneSize()));
  }

  /** その箱が画面に入るまでだけ寄せる（矢印で選び直したとき） */
  ensureVisible(id: number): void {
    const b = this.layout.boxes.get(id);
    if (b) this.setCamera(panToShow(this.camera, b, this.paneSize(), SHOW_MARGIN));
  }

  /** 選択の塗り直し。レイアウトは見直さない */
  refreshSelection(): void {
    this.renderer.paintSelection(new Set(this.host.selection().ids));
  }

  /** その場編集に入る。seed は最初の字。箱が無い（畳まれて埋もれた）ノードは開けない */
  beginEdit(id: number, seed: string | null): void {
    const b = this.layout.boxes.get(id);
    if (!b) return;
    this.label.open(id, b, this.camera, labelOf(b.node), seed);
  }

  /**
   * カーソルの輪を、掛かっているノードの**内側**へ重ねる。外から掴むのが選択、
   * 中に居るのがカーソルで、形がそのまま意味になる。箱の無い（畳まれて埋もれた）
   * ノードには出さない。本数が変わったときだけ作り足す/捨てる
   */
  showCaret(ids: number[]): void {
    this.caretIds = ids;
    const boxes = ids.flatMap((id) => {
      const b = this.layout.boxes.get(id);
      return b ? [b] : [];
    });
    while (this.caretRings.length > boxes.length) this.caretRings.pop()?.remove();
    while (this.caretRings.length < boxes.length) {
      const ring = svgEl("rect", { class: "caret-ring" });
      this.caretLayer.append(ring);
      this.caretRings.push(ring);
    }
    const inset = 3;
    boxes.forEach((b, i) => {
      const ring = this.caretRings[i];
      ring.setAttribute("x", String(b.x + inset));
      ring.setAttribute("y", String(b.y + inset));
      ring.setAttribute("width", String(b.w - inset * 2));
      ring.setAttribute("height", String(b.h - inset * 2));
    });
  }

  /** 画面の点がどの箱に居るか。無ければ null */
  private nodeAt(clientX: number, clientY: number): number | null {
    const p = this.local(clientX, clientY);
    const w = toWorld(this.camera, p.x, p.y);
    return hit(this.layout, w.x, w.y);
  }

  /** 画面外にある根を控えめな針で指す。ノードが 1 つでも見えていれば出さない */
  private updateIndicator(): void {
    const root = rootBox(this.layout);
    const pane = this.paneSize();
    if (!root || [...this.layout.boxes.values()].some((b) => isVisible(b, this.camera, pane))) {
      this.indicatorEl.style.display = "none";
      return;
    }
    const ind = indicatorFor(root, this.camera, pane);
    this.indicatorEl.style.display = "block";
    this.indicatorEl.style.left = `${ind.x}px`;
    this.indicatorEl.style.top = `${ind.y}px`;
    this.indicatorEl.style.transform = `translate(-50%, -50%) rotate(${ind.angle}deg)`;
  }

  /** 書き出し用の SVG。全体。空なら null */
  exportSvg(): Promise<SVGSVGElement | null> {
    const nodes: SVGGElement[] = [];
    const edges: SVGPathElement[] = [];
    for (const id of this.layout.order) {
      const el = this.renderer.nodeEl(id);
      if (el) nodes.push(el);
      const edge = this.renderer.edgeEl(id);
      if (edge) edges.push(edge);
    }
    return mapToSvg({ boxes: this.layout.boxes.values(), edges, nodes, pane: this.pane });
  }

  // ---------- input ----------

  /** 見え方を変える入力（ホイールのズームとスクロール）。動かし方そのものは map/camera.ts */
  private bindWheel(): void {
    this.pane.addEventListener(
      "wheel",
      (e) => {
        e.preventDefault();
        if (e.ctrlKey || e.metaKey) {
          const p = this.local(e.clientX, e.clientY);
          this.setCamera(zoomAt(this.camera, p.x, p.y, e.deltaY));
        } else if (e.shiftKey) {
          // Shift+ホイールは横スクロール（縦の目盛りしか出さないマウス用）
          this.setCamera(panBy(this.camera, -(e.deltaY || e.deltaX), 0));
        } else {
          this.setCamera(panBy(this.camera, -e.deltaX, -e.deltaY));
        }
      },
      { passive: false },
    );
  }

  /**
   * 背景の左ドラッグは矩形選択、パンは中クリック / Space+ドラッグ / 指の 1 本。
   * **指は 1 本でも 2 本でも台帳に載せる** — 載らなかった指の pointermove が
   * 「1 本ぶん」の流れへ落ちると、別の指の始点との差で地図が跳ぶ。capture で
   * 取るのは、リンクの ↗ が pointerdown を止めるため。
   */
  private bindPointer(): void {
    const pane = this.pane;
    pane.addEventListener(
      "pointerdown",
      (e) => {
        if (e.pointerType !== "touch") return;
        const p = this.local(e.clientX, e.clientY);
        this.fingers.down(e.pointerId, p.x, p.y);
        // 2 本目が乗った時点で 1 本ぶんのパンは畳む。tapped も畳む —
        // 畳まなければピンチ中ずっと最初の指の場所に居座り、離したときに選んでしまう
        if (this.fingers.pinching) {
          this.panning = null;
          this.tapped = null;
        }
      },
      true,
    );
    pane.addEventListener("pointerdown", (e) => {
      if (targetIn(e, ".link-open, .img-connect, .pane-tool, #node-editor")) return;
      if (e.pointerType === "touch" && this.fingers.pinching) return;
      if (e.button !== 0 && e.button !== 1) return;
      pane.focus();
      const id = this.nodeAt(e.clientX, e.clientY);
      // パンは 3 つ入り口を持つ: 中クリック / Space+ドラッグ / 指で背景をなぞる。
      // 担当する手が違うので、どれか 1 つでは塞がる場面がある
      const pan = e.button === 1 || this.spaceHeld || (e.pointerType === "touch" && id === null);
      if (pan) {
        this.panning = { px: e.clientX, py: e.clientY, ox: this.camera.tx, oy: this.camera.ty };
        pane.style.cursor = "grabbing";
        pane.setPointerCapture(e.pointerId);
        e.preventDefault();
        return;
      }
      if (e.pointerType === "touch") {
        // 指は離したときに選ぶ（なぞったら選ばない）
        this.tapped = id === null ? null : { id, x: e.clientX, y: e.clientY };
        return;
      }
      if (id !== null) {
        const mod = e.shiftKey ? "shift" : e.ctrlKey || e.metaKey ? "mod" : "none";
        this.host.setSelection(click(this.host.selection(), id, mod, this.layout.order), true);
        e.preventDefault();
        return;
      }
      // 背景。ドラッグすれば矩形選択、動かさずに離せば選択を解く
      this.rubberStart = this.local(e.clientX, e.clientY);
      pane.setPointerCapture(e.pointerId);
      e.preventDefault();
    });
    pane.addEventListener("pointermove", (e) => {
      if (e.pointerType === "touch") {
        const p = this.local(e.clientX, e.clientY);
        const g = this.fingers.move(e.pointerId, p.x, p.y);
        if (g) {
          this.setCamera(pinch(this.camera, g.from, g.to));
          return;
        }
        // 2 本乗っているあいだは、1 本ぶんの続きを進めない
        if (this.fingers.pinching) return;
      }
      if (this.tapped && Math.hypot(e.clientX - this.tapped.x, e.clientY - this.tapped.y) > 8) {
        this.tapped = null;
      }
      if (this.rubberStart) {
        const p = this.local(e.clientX, e.clientY);
        const x = Math.min(this.rubberStart.x, p.x);
        const y = Math.min(this.rubberStart.y, p.y);
        const w = Math.abs(p.x - this.rubberStart.x);
        const h = Math.abs(p.y - this.rubberStart.y);
        Object.assign(this.rubber.style, { display: "block", left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` });
        const a = toWorld(this.camera, x, y);
        const b = toWorld(this.camera, x + w, y + h);
        this.host.setSelection(rubber(this.layout, { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y }), false);
        return;
      }
      if (!this.panning) return;
      this.setCamera({
        k: this.camera.k,
        tx: this.panning.ox + (e.clientX - this.panning.px),
        ty: this.panning.oy + (e.clientY - this.panning.py),
      });
    });
    const end = (e: PointerEvent): void => {
      // 選ぶのは離したとき（pointerup）だけ。cancel は取り消しなので選ばずに捨てる
      if (this.tapped && e.type === "pointerup") {
        this.host.setSelection(click(this.host.selection(), this.tapped.id, "none", this.layout.order), true);
      }
      this.tapped = null;
      if (this.rubberStart) {
        const dragged =
          this.rubber.style.display === "block" &&
          (parseFloat(this.rubber.style.width) > 3 || parseFloat(this.rubber.style.height) > 3);
        this.rubber.style.display = "none";
        this.rubberStart = null;
        if (!dragged) this.host.setSelection(NONE, false);
      }
      if (e.pointerType === "touch") {
        this.liftFinger(e.pointerId);
        // 組が壊れて残った指でパンを立て直したなら、その up ではない
        if (this.panning && this.fingers.only()) return;
      }
      this.panning = null;
      pane.style.cursor = this.spaceHeld ? "grab" : "";
    };
    pane.addEventListener("pointerup", end);
    pane.addEventListener("pointercancel", end);
  }

  /** 指が離れた。組が壊れて 1 本に戻ったら、その指から 1 本パンを立て直す */
  private liftFinger(id: number): void {
    const wasPinching = this.fingers.pinching;
    this.fingers.up(id);
    if (!wasPinching) return;
    const solo = this.fingers.only();
    if (solo && !this.fingers.pinching) {
      const r = this.pane.getBoundingClientRect();
      this.panning = {
        px: solo.x + r.left,
        py: solo.y + r.top,
        ox: this.camera.tx,
        oy: this.camera.ty,
      };
    }
  }

  /** リンクの ↗ と、読めていない画像の「繋ぐ」の字 */
  private bindClick(): void {
    this.pane.addEventListener("click", (e) => {
      if (targetIn(e, ".img-connect")) {
        this.host.connectAssets();
        return;
      }
      const url = targetIn(e, ".link-open")?.getAttribute("data-url");
      if (url) window.open(url, "_blank", "noopener,noreferrer");
    });
    this.renderer.nodeLayer.addEventListener("pointerdown", (e) => {
      if (targetIn(e, ".link-open, .img-connect")) e.stopPropagation();
    });
    this.pane.addEventListener("dblclick", (e) => {
      if (targetIn(e, ".link-open, .img-connect, #node-editor")) return;
      const id = this.nodeAt(e.clientX, e.clientY);
      if (id === null) return;
      e.preventDefault();
      this.beginEdit(id, null);
    });
  }

  /** keys.ts が言った「何をするか」を実行する。意味はあちらが持ち、ここは配線だけ */
  private act(intent: Intent): void {
    switch (intent.kind) {
      case "op":
        this.host.apply(intent.op, intent.edit);
        return;
      case "edit":
        this.beginEdit(intent.id, intent.seed);
        return;
      case "select":
        this.host.setSelection(intent.sel, intent.reveal);
        // 矢印で辿るときだけ寄せる（Mod+A / Esc は reveal が偽）
        if (intent.reveal && intent.sel.anchor !== null) this.ensureVisible(intent.sel.anchor);
        return;
      case "center":
        this.centerOnTarget();
        return;
    }
  }

  /** 地図の中だけで効くキー。全体のキーは app/shortcuts.ts */
  private bindKeys(): void {
    this.pane.addEventListener("keydown", (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      if (e.key === " ") {
        this.spaceHeld = true;
        this.pane.style.cursor = "grab";
        e.preventDefault();
        return;
      }
      const intent = keyed(this.layout, this.host.selection(), {
        key: e.key,
        shift: e.shiftKey,
        mod: e.ctrlKey || e.metaKey,
        alt: e.altKey,
      });
      if (intent === null) return;
      e.preventDefault();
      this.act(intent);
    });
    this.pane.addEventListener("keyup", (e) => {
      if (e.key === " ") {
        this.spaceHeld = false;
        if (!this.panning) this.pane.style.cursor = "";
      }
    });
    // Space を押したままペインの外へフォーカスが抜けると keyup が来ない。
    // 持ったままになるとカーソルが grab に貼り付き、背景の左ドラッグが
    // ずっと矩形選択でなくパンになる
    this.pane.addEventListener("focusout", () => {
      this.spaceHeld = false;
      if (!this.panning) this.pane.style.cursor = "";
    });
  }
}

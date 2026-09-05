// マップのペイン。core の View を layout で箱にし、render で SVG に写す。
//
// 持っているのは視点（Camera）と、それを動かす入力（ホイール・ドラッグ・
// ピンチ・クリック・矩形・矢印・右クリック・長押し）と、見失った先を指す針
// だけ。**選択の値は持たない** — 入力を map/select.ts の値にして host へ渡し、
// 返ってきた Selection を塗るだけ。値そのものは main.ts が持つ。あるのは
// 選択、その場編集、消す・並べ替え・畳み・側の操作・カードの選択とその場編集。

import type * as core from "./coreApi.ts";
import { type Camera, type Pane, centerOn, fitToPane, panBy, panToShow, pinch, toWorld, zoomAt } from "./map/camera.ts";
import { CardEditor } from "./map/card.ts";
import { contextItems, menuOf } from "./map/context.ts";
import { type Drop, dropOp, resolveDrop } from "./map/drop.ts";
import { type Rect, unionRect } from "./map/geometry.ts";
import { Fingers } from "./map/gesture.ts";
import { indicatorFor, isLost, nearest } from "./map/indicator.ts";
import { type Intent, type Key, keyed, keyedCard } from "./map/keys.ts";
import { LabelEditor } from "./map/label.ts";
import { type Layout, cardRect, layoutMap, ownerOf, rootBox } from "./map/layout.ts";
import { labelOf, nodeSize } from "./map/metrics.ts";
import { ContextMenu } from "./map/menu.ts";
import { CardPick } from "./map/pick.ts";
import { MapRenderer } from "./map/render.ts";
import { NONE, type Selection, click, hit, rubber } from "./map/select.ts";
import { svgEl } from "./map/svg.ts";
import { mapToSvg } from "./map/toSvg.ts";
import { icon } from "./icons.ts";
import { paneTool } from "./app/paneTool.ts";
import { paneHint } from "./app/hint.ts";
import { failed } from "./app/notice.ts";

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
  /** 選んでいるカードの中身の id。値は main.ts が持つ */
  picked(): number | null;
  /** カードを選び直した（null で外す） */
  setPicked(id: number | null): void;
  /** その中身の原文。地番で md から切り出す（無ければ空） */
  blockText(id: number): string;
  /** 操作を md に映す。edit なら、映した後の focus をそのまま編集開始
   *  （ノードのときだけ — 中身の focus はカードとして選ぶ）。keep は消す前に
   *  選んでおきたい隣の id（keys.ts の Intent の keep）。返り値は映した focus */
  apply(op: core.Op, edit: boolean, keep?: number): number | null;
  /** クリップボードを貼る（Mod+V）。宛先は選択の anchor、無ければ文書 */
  paste(): void;
  /** 選んでいるもの（カードならその原文、でなければ選択の部分木）をクリップボードへ
   *  写す（Mod+C / Mod+X）。写せたか — 写せなければ Cut は消さない */
  copy(): Promise<boolean>;
  /** そのノードへ描いて貼る（Shift+D）。窓を開いて、確定した絵を保存する */
  draw(id: number): void;
}

/** 全体を収めるときの余白（画面 px） */
const FIT_MARGIN = 60;
/** 矢印で辿るとき、選んだ箱が縁から離れている距離（画面 px） */
const SHOW_MARGIN = 40;
/** 長押しが右クリックメニューに化けるまでの間（ms） */
const HOLD_MS = 500;

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
  /** 押したまま離すのを待つノード（指、または選んでいる箱をマウスで）。動かさずに離せば選ぶ */
  private tapped: { id: number; x: number; y: number } | null = null;
  /** Space を押している間、左ドラッグはパン */
  private spaceHeld = false;
  private label: LabelEditor;
  private card: CardEditor;
  /** 選んでいるカードに被せる枠と ×。world に浮かぶ 1 個の印（label.ts と同じ理由） */
  private pick = new CardPick();
  /** 右クリック（と長押し）のメニュー */
  private menu = new ContextMenu();
  /** 長押しの待ち時計。無ければ待っていない */
  private hold: ReturnType<typeof setTimeout> | null = null;
  /** 長押しを起こした指の押した場所。動かせば捨てる */
  private holdAt: { x: number; y: number } | null = null;
  /** 直前に開いたメニューが長押しから来たか。続く contextmenu を握り潰すため */
  private menuOpenedByHold = false;
  /** マウスで掴んだ候補。slop を越えたら startDrag へ化ける */
  private dragCand: { id: number; x: number; y: number } | null = null;
  /** 動かしているノード。ids は選んだ全部（文書順）、subtree はその子孫込み（落とし先から外す） */
  private dragging: { ids: number[]; subtree: Set<number> } | null = null;
  /** 今の落とし先の予告。無ければ離しても何もしない */
  private drop: Drop | null = null;
  /** 予告で drop-parent を付けている箱の id。次の予告や後片付けで外す */
  private dropParentId: number | null = null;
  /** 兄弟へ挿入する予告の線。world に浮かぶ */
  private dropLine: SVGLineElement;

  constructor(pane: HTMLElement, host: MapHost) {
    this.pane = pane;
    this.host = host;
    // この pane はマップの器になった。見た目（style.css の `.map-pane`）はここで付く
    pane.classList.add("map-pane");

    const svg = svgEl("svg", { class: "map-svg" });
    this.world = svgEl("g");
    this.caretLayer = svgEl("g");
    this.dropLine = svgEl("line", { class: "drop-line", visibility: "hidden" });
    this.world.append(this.renderer.edgeLayer, this.renderer.nodeLayer, this.pick.el, this.caretLayer, this.dropLine);
    svg.append(this.world);
    pane.append(svg);

    this.rubber = document.createElement("div");
    this.rubber.className = "rubber";
    pane.append(this.rubber);

    this.label = new LabelEditor(pane, (id, label) => this.host.apply({ kind: "rename", id, label }, false));
    this.card = new CardEditor(pane, (id, text) =>
      this.host.apply({ kind: "setBlock", id, content: { kind: "opaque", text } }, false),
    );

    // md からの始め方は md ペイン自身が同じ器で言う（app/hint.ts）
    this.hint = paneHint("map");
    this.hint.style.display = "none";
    pane.append(this.hint);

    this.indicatorEl = document.createElement("div");
    this.indicatorEl.className = "map-indicator";
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
    this.bindContextMenu();
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
    this.followLabel();
    this.followCard();
    this.updateIndicator();
  }

  /** 編集中の欄を箱に追従させる。書くたび・視点を動かすたびに呼ぶ。
   *  箱が消えていれば（畳まれて埋もれた）閉じる */
  private followLabel(): void {
    const editing = this.label.editing();
    if (editing === null) return;
    const b = this.layout.boxes.get(editing);
    if (b) this.label.place(b, this.camera);
    else this.label.close();
  }

  /** 選んでいるカードの印と、開いている入力欄を今のレイアウト・視点に合わせる。
   *  render 後とカメラが動いたときに呼ぶ（followLabel と同じ理由） */
  private followCard(): void {
    // 持ち主が畳まれて箱を失えば外す — 見えないカードを選んだままにしない
    const picked = this.host.picked();
    const at = picked === null ? null : this.cardRectOf(picked);
    if (picked !== null && at === null) this.host.setPicked(null);
    if (picked === null || at === null) this.pick.hide();
    else this.pick.show(picked, at);
    const editing = this.card.editing();
    if (editing === null) return;
    const rect = this.cardRectOf(editing);
    if (rect) this.card.place(rect, this.camera);
    else this.card.close();
  }

  /** カードの置かれている場所（world 座標）。積み方は数えない —
   *  cardRect が描画と共通の唯一の出所で、ここは箱の位置ぶん動かすだけ */
  private cardRectOf(id: number): Rect | null {
    const o = ownerOf(this.layout, id);
    if (!o) return null;
    const r = cardRect(o.box, o.index);
    return r === null ? null : { ...r, x: o.box.x + r.x, y: o.box.y + r.y };
  }

  /** data-card の「ノードの id, 何枚目」から中身の id */
  private blockAt(spot: string): number | null {
    const [node, index] = spot.split(",").map(Number);
    return this.layout.boxes.get(node)?.node.blocks[index]?.id ?? null;
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
    this.hint.style.display = doc.roots.length === 0 ? "flex" : "none";
    this.layout = layoutMap(doc.roots, nodeSize);
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
    this.followLabel();
    this.followCard();
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

  /** 選ばれている箱。畳まれて箱を失ったものは数えない */
  private selectedBoxes(): Rect[] {
    return this.host.selection().ids.flatMap((id) => {
      const b = this.layout.boxes.get(id);
      return b ? [b] : [];
    });
  }

  /** 選択（無ければ根）を画面の中心へ。拡大率は変えない */
  centerOnTarget(): void {
    const target = unionRect(this.selectedBoxes()) ?? rootBox(this.layout);
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
    this.followCard();
    this.updateIndicator(); // 針は選択を指す — 視点が動かなくても指し直す
  }

  /** その場編集に入る。seed は最初の字。箱が無い（畳まれて埋もれた）ノードは
   *  開けない — 戻り値はそれを呼び出し側（main.ts の apply）に言うためのもの */
  beginEdit(id: number, seed: string | null): boolean {
    const b = this.layout.boxes.get(id);
    if (!b) return false;
    this.label.open(id, b, this.camera, labelOf(b.node), seed);
    return true;
  }

  /** カードをその場で開く。畳まれて埋もれている（箱が無い）ときは断る。
   *  `text` は欄に載せる字（省略すれば md の原文）— 変えずに閉じれば書かない */
  editCard(id: number, from?: number, to?: number, text = this.host.blockText(id).replace(/\n$/, "")): void {
    const rect = this.cardRectOf(id);
    if (rect === null) {
      failed("Couldn't open that card");
      return;
    }
    this.host.setPicked(id);
    this.card.open(id, rect, this.camera, text, from, to);
  }

  /**
   * クリップボードの URL をリンクカードにして足し、題（`[]` の中）を打つ。
   * URL として読めなければ `failed`（core にも聞かない — 貼り付けの判定
   * （app/paste.ts は骨格の有無を core に読ませるが、ここは「URL か否か」だけの単純な形）
   */
  private async addLink(id: number): Promise<void> {
    let url = "";
    try {
      url = (await navigator.clipboard.readText()).trim();
    } catch {
      url = "";
    }
    if (!/^https?:\/\/\S+$/.test(url)) {
      failed("Couldn't read that as a link");
      return;
    }
    const f = this.host.apply(
      { kind: "addBlock", at: { kind: "in", node: id }, content: { kind: "link", text: "", href: url, title: "" } },
      false,
    );
    if (f !== null) this.editCard(f, 1, 1);
  }

  /** 空のコードカードを足して、本文の行を打つ。core は空のコードを開きと閉じの
   *  2 行で書くので、欄には空行を 1 つ挟んだ形で載せ、そこに頭を置く（打たなければ書かない） */
  private addCode(id: number): void {
    const f = this.host.apply(
      { kind: "addBlock", at: { kind: "in", node: id }, content: { kind: "code", info: "", text: "" } },
      false,
    );
    if (f !== null) this.editCard(f, 4, 4, "```\n\n```");
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

  /** 見失った選択（無ければ根）を控えめな針で指す。決めは indicator.ts が持つ */
  private updateIndicator(): void {
    const pane = this.paneSize();
    const sel = this.selectedBoxes();
    // 見失ったかは、選択があれば選択の話。無ければ文書の話
    const watched = sel.length > 0 ? sel : [...this.layout.boxes.values()];
    // 指す先は、選択ならいちばん近いやつ。無ければ根 — 帰る場所は 1 つでいい
    const target = !isLost(watched, this.camera, pane)
      ? null
      : sel.length > 0
        ? nearest(sel, this.camera, pane)
        : rootBox(this.layout);
    if (!target) {
      this.indicatorEl.style.display = "none";
      return;
    }
    const ind = indicatorFor(target, this.camera, pane);
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
      if (targetIn(e, ".link-open, .image-connect, .pane-tool, .label-editor, .card-editor")) return;
      if (e.pointerType === "touch" && this.fingers.pinching) return;
      // 長押しの印は次の押下で用済み（contextmenu を合成しない環境で残らないように）
      this.menuOpenedByHold = false;
      if (e.button !== 0 && e.button !== 1) return;
      pane.focus();
      // カードと × の上の押下は、そのクリック（bindClick）のもの。ここで
      // ノードを選び直すと、pointerup が選択を作り直して picked を落とす
      if (targetIn(e, "[data-card], [data-delete]")) return;
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
        // 長押しは右クリックの代わり。動かさずに HOLD_MS 待てばメニューを開く
        this.holdAt = { x: e.clientX, y: e.clientY };
        this.hold = setTimeout(() => {
          const at = this.holdAt;
          this.dropHold();
          if (!at) return;
          this.tapped = null;
          this.menuOpenedByHold = true;
          this.openMenu(at.x, at.y);
        }, HOLD_MS);
        return;
      }
      if (id !== null) {
        const mod = e.shiftKey ? "shift" : e.ctrlKey || e.metaKey ? "mod" : "none";
        // 選んでいる箱をそのまま押したなら、1 つに畳むのは離したとき（指と同じ）。
        // 押した瞬間に畳むと、複数選択を掴んで動かす手が無くなる
        if (mod === "none" && this.host.selection().ids.includes(id)) {
          this.tapped = { id, x: e.clientX, y: e.clientY };
        } else {
          this.host.setSelection(click(this.host.selection(), id, mod, this.layout.order), true);
          this.dragCand = { id, x: e.clientX, y: e.clientY };
        }
        pane.setPointerCapture(e.pointerId);
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
        // 長押しが先にメニューを開いていれば tapped はもう null（下まで来ない）
        this.startDrag(this.tapped.id, e.clientX, e.clientY);
        this.tapped = null;
      }
      if (this.holdAt && Math.hypot(e.clientX - this.holdAt.x, e.clientY - this.holdAt.y) > 8) {
        this.dropHold();
      }
      if (this.dragCand && Math.hypot(e.clientX - this.dragCand.x, e.clientY - this.dragCand.y) > 8) {
        this.startDrag(this.dragCand.id, e.clientX, e.clientY);
        this.dragCand = null;
      }
      if (this.dragging) {
        this.updateDrop(e.clientX, e.clientY);
        return;
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
      this.dropHold();
      if (this.dragging) {
        // cancel は取り消しなので、印だけ消して Op は投げない
        if (this.drop && e.type === "pointerup") this.host.apply(dropOp(this.drop, this.dragging.ids), false);
        this.endDrag();
      } else {
        this.dragCand = null;
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

  /**
   * 掴んで動かし始める。掴んだのが選択の中ならその全部（文書順）、外なら
   * 単独で選び直してそれ。落とし先から外す部分木は、選んだもの自身とその子孫。
   */
  private startDrag(id: number, clientX: number, clientY: number): void {
    let sel = this.host.selection();
    if (!sel.ids.includes(id)) {
      sel = { ids: [id], anchor: id };
      this.host.setSelection(sel, false);
    }
    // layout.order は親が子より先（layoutMap の文書順）なので、前から 1 回
    // なめれば「親が部分木に居るか」だけで子の判定が決まる
    const subtree = new Set(sel.ids);
    for (const nid of this.layout.order) {
      const p = this.layout.boxes.get(nid)?.parent ?? null;
      if (p && subtree.has(p.id)) subtree.add(nid);
    }
    this.dragging = { ids: sel.ids, subtree };
    for (const nid of sel.ids) this.renderer.nodeEl(nid)?.classList.add("dragging");
    this.updateDrop(clientX, clientY);
  }

  /** ポインタの今の場所から落とし先を計算し直し、予告を塗り直す */
  private updateDrop(clientX: number, clientY: number): void {
    if (!this.dragging) return;
    const p = this.local(clientX, clientY);
    const at = toWorld(this.camera, p.x, p.y);
    this.drop = resolveDrop({ at, layout: this.layout, dragging: this.dragging.subtree });
    this.paintDrop();
  }

  /** 落とし先の印を今の this.drop に合わせる。前の印は消してから塗り直す */
  private paintDrop(): void {
    this.clearDropMark();
    const d = this.drop;
    if (!d) return;
    if (d.kind === "side") {
      this.markDropParent(d.root);
      return;
    }
    if (d.pos === 0) {
      this.markDropParent(d.id);
      return;
    }
    const b = this.layout.boxes.get(d.id);
    if (!b) return;
    const y = d.pos === 1 ? b.y : b.y + b.h;
    this.dropLine.setAttribute("x1", String(b.x));
    this.dropLine.setAttribute("x2", String(b.x + b.w));
    this.dropLine.setAttribute("y1", String(y));
    this.dropLine.setAttribute("y2", String(y));
    this.dropLine.setAttribute("visibility", "visible");
  }

  private markDropParent(id: number): void {
    this.renderer.nodeEl(id)?.classList.add("drop-parent");
    this.dropParentId = id;
  }

  /** 予告の印（drop-parent と drop-line）を消す */
  private clearDropMark(): void {
    if (this.dropParentId !== null) {
      this.renderer.nodeEl(this.dropParentId)?.classList.remove("drop-parent");
      this.dropParentId = null;
    }
    this.dropLine.setAttribute("visibility", "hidden");
  }

  /**
   * ファイルのドラッグ中、その画面の点に落ちる先を予告する（app/dnd.ts）。
   * `null` は予告を消す合図。当たった先のノードの id（無ければ null）を返す —
   * ドラッグ中はノードの部分木を弾く理由が無いので、`resolveDrop` は使わず
   * `nodeAt` だけで決める。
   */
  markFileDrop(at: { x: number; y: number } | null): number | null {
    if (at === null) {
      this.clearDropMark();
      return null;
    }
    const id = this.nodeAt(at.x, at.y);
    this.clearDropMark();
    if (id !== null) this.markDropParent(id);
    return id;
  }

  /** ドラッグを終える。Op を投げるかどうかは呼び出し側が先に決めておく */
  private endDrag(): void {
    if (this.dragging) {
      for (const id of this.dragging.ids) this.renderer.nodeEl(id)?.classList.remove("dragging");
    }
    this.dragging = null;
    this.drop = null;
    this.clearDropMark();
  }

  /** リンクの ↗ と、読めていない画像の「繋ぐ」の字 */
  private bindClick(): void {
    this.pane.addEventListener("click", (e) => {
      const del = targetIn(e, "[data-delete]")?.getAttribute("data-delete");
      if (del !== null && del !== undefined) {
        this.host.apply({ kind: "delete", ids: [Number(del)] }, false);
        return;
      }
      if (targetIn(e, ".image-connect")) {
        this.host.connectAssets();
        return;
      }
      const spot = targetIn(e, "[data-card]")?.getAttribute("data-card");
      if (spot !== null && spot !== undefined) {
        const id = this.blockAt(spot);
        if (id !== null) this.host.setPicked(this.host.picked() === id ? null : id);
        return;
      }
      const url = targetIn(e, ".link-open")?.getAttribute("data-url");
      if (url) window.open(url, "_blank", "noopener,noreferrer");
    });
    this.renderer.nodeLayer.addEventListener("pointerdown", (e) => {
      if (targetIn(e, ".link-open, .image-connect")) e.stopPropagation();
    });
    this.pane.addEventListener("dblclick", (e) => {
      if (targetIn(e, ".link-open, .image-connect, .label-editor, .card-editor")) return;
      const spot = targetIn(e, "[data-card]")?.getAttribute("data-card");
      if (spot !== null && spot !== undefined) {
        const id = this.blockAt(spot);
        if (id !== null) {
          e.preventDefault();
          this.editCard(id);
        }
        return;
      }
      const id = this.nodeAt(e.clientX, e.clientY);
      if (id === null) return;
      e.preventDefault();
      this.beginEdit(id, null);
    });
  }

  /** 長押しの待ち時計を止める。次に押すまで、待っていたことを覚えておかない */
  private dropHold(): void {
    if (this.hold !== null) clearTimeout(this.hold);
    this.hold = null;
    this.holdAt = null;
  }

  /** その画面の点でメニューを開く。箱の外なら閉じるだけ。触った箱がまだ選ばれて
   *  いなければ、それ 1 つに選び直してから並びを組む — 右クリックは選ぶ動作も兼ねる */
  private openMenu(x: number, y: number): void {
    // 開いている欄は閉じてから。メニューは選択を据え直すので、欄の下で id が動かないように
    this.label.close();
    this.card.close();
    const id = this.nodeAt(x, y);
    if (id === null) {
      this.menu.hide();
      return;
    }
    const sel = this.host.selection();
    if (!sel.ids.includes(id)) this.host.setSelection({ ids: [id], anchor: id }, false);
    this.menu.show(x, y, menuOf(contextItems(this.layout, this.host.selection()), (i) => this.act(i)));
  }

  /** 右クリック。触った箱が選ばれていなければそれへ選び直してから開く。長押しが
   *  開いた直後の（触った指が上げるときに走る）contextmenu は握り潰す — 二重に開かせない */
  private bindContextMenu(): void {
    this.pane.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      if (this.menuOpenedByHold) {
        this.menuOpenedByHold = false;
        return;
      }
      this.dropHold();
      this.openMenu(e.clientX, e.clientY);
    });
  }

  /** keys.ts が言った「何をするか」を実行する。意味はあちらが持ち、ここは配線だけ */
  private act(intent: Intent): void {
    switch (intent.kind) {
      case "op":
        this.host.apply(intent.op, intent.edit, intent.keep);
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
      case "pick":
        this.host.setPicked(intent.id);
        return;
      case "editCard":
        this.editCard(intent.id);
        return;
      case "link":
        void this.addLink(intent.id);
        return;
      case "code":
        this.addCode(intent.id);
        return;
      case "draw":
        this.host.draw(intent.id);
        return;
      case "paste":
        this.host.paste();
        return;
      case "copy": {
        // 消すのは写せてから。写せなければ（クリップボードが断った）何も失わない
        const cut = intent.cut;
        void this.host.copy().then((ok) => {
          if (ok && cut !== null) this.act(cut);
        });
        return;
      }
    }
  }

  /** 地図の中だけで効くキー。全体のキーは app/shortcuts.ts */
  private bindKeys(): void {
    this.pane.addEventListener("keydown", (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      if (this.dragging && e.key === "Escape") {
        this.endDrag();
        e.preventDefault();
        return;
      }
      if (e.key === " ") {
        this.spaceHeld = true;
        this.pane.style.cursor = "grab";
        e.preventDefault();
        return;
      }
      const key: Key = { key: e.key, shift: e.shiftKey, mod: e.ctrlKey || e.metaKey, alt: e.altKey };
      const picked = this.host.picked();
      const intent = picked !== null ? keyedCard(this.layout, picked, key) : keyed(this.layout, this.host.selection(), key);
      if (intent === null) {
        // 表が断った Tab（選んでいない・前の兄弟が無い）でも、地図から焦点を逃がさない
        if (e.key === "Tab") e.preventDefault();
        return;
      }
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

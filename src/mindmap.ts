// マップのペイン。SVG の描画と、Figma 風のパン / ズーム / 選択、
// ドラッグでの付け替え（落とし先は必ず線で示す）、そしてラベルとカードを
// その場で直す HTML の入力欄（IME を壊さないため SVG の外に重ねる）。
//
// レイアウトはすべて左から右へ伸びる。

import type { DocView } from "./coreApi.ts";
import { tokenizeBlock, touchesFence } from "./map/highlight.ts";
import {
  type Pt,
  type Rect,
  growthEdgeOf,
  leftOf,
  midOfPolyline,
  rightOf,
  unionRect,
} from "./map/geometry.ts";
import { edgePath, edgeSegs, flattenSegs } from "./map/edge.ts";
import { type CardRef, type CardRow, CODE_LINE, rowH } from "./map/cards.ts";
import {
  ROW_NORMAL,
  labelFont,
  measure,
  monoFont,
  rowOf,
  rowTop,
} from "./map/metrics.ts";
import {
  type Box,
  type Layout,
  GAP,
  branchIds,
  cardRect,
  dirOf,
  edgeEnds,
  layoutMap,
  rootId,
} from "./map/layout.ts";
import { type Drop, resolveDrop } from "./map/drop.ts";
import { arrowTarget, extendSelection, isArrowKey } from "./map/navigate.ts";
import { cardPlacement, labelPlacement } from "./map/overlay.ts";
import {
  type View,
  centerOn,
  fitToPane,
  panBy,
  panToShow,
  toWorld,
  zoomAt,
} from "./map/view.ts";
import { indicatorFor, isVisible } from "./map/indicator.ts";
import { ContextMenu, type MenuEntry } from "./map/menu.ts";
import { MapRenderer } from "./map/render.ts";
import { CardPick } from "./map/pick.ts";
import { mapToSvg } from "./map/toSvg.ts";
import { svgEl } from "./map/svg.ts";
import { icon } from "./icons.ts";
import { paneTool } from "./app/paneTool.ts";
import { paneHint } from "./app/hint.ts";

export interface MapHost {
  /** いまの文書（テキスト・ノード・フェンスの組）。必ず同じ rev のもの */
  doc(): DocView;
  /** objectURL for a local image path (relative to the md); null while
   * loading / until folder permission is granted */
  imageUrl(path: string): string | null;
  /** 読めていない場所取りに添える字。握っていないときだけ（他は null） */
  imageHint(): string | null;
  /** その字が押された。画像フォルダを繋ぎ直す */
  connectAssets(): void;
  /** その場で描いて、画像としてこのノードに貼る */
  addDrawing(id: number): void;
  /**
   * いま画像を足せない理由。足せるなら null。
   * **押す前に分かることは、押す前に言う**ための問い合わせ。
   */
  /** クリップボードの URL を、名前を付けられる形でこのノードに貼る */
  addLink(id: number): void;
  /** 空のコードフェンスをこのノードに足し、その場で打てる状態にする */
  addCode(id: number): void;
  /** その範囲を書き換える（カードをその場で直したとき） */
  replaceText(from: number, to: number, text: string): void;
  selection(): Set<number>;
  anchor(): number;
  setSelection(ids: number[], anchor: number, reveal?: boolean): void;
  clearSelection(): void;
  /** 選ばれているカード（無ければ null）。ノードの選択とは排他。 */
  pickedCard(): CardRef | null;
  /** カードを選ぶ / 外す（null で外す）。ノードの選択は落ちる。 */
  pickCard(ref: CardRef | null): void;
  /** そのカードを行ごと消す */
  deleteCard(ref: CardRef): void;
  /** 同じノードの中で 1 つ上/下へ。端では何もしない。 */
  reorderCard(ref: CardRef, dir: -1 | 1): void;
  /** そのカードを別のノードの index の位置へ動かす。実際に動かせたら
   * true — 呼び出し側はこれで、後追いの click を握りつぶすか決める */
  moveCardTo(ref: CardRef, node: number, index: number): boolean;

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
  reorder(id: number, dir: -1 | 1, cross: boolean): void;
  /** ルート脇へ落とした: その側の末尾へ */
  moveSideEnd(ids: number[], root: number, left: boolean): void;
  /** Mod を押したまま落とした: そこに新しいグループ */
  moveNewGroup(ids: number[], target: number, before: boolean, left: boolean): void;
  /** そのノードの属するグループを、丸ごと反対側へ */
  flipSide(id: number): void;
  toggleHidden(id: number): void; // comment-out hide/show for the subtree
  /**
   * pos 0 = target の子にする
   * pos 1 = target の直前へ挿入 / pos 2 = target の直後へ挿入
   * pos 3 = target の親として割り込む（A→B の線へのドロップ）
   */
  move(ids: number[], target: number, pos: 0 | 1 | 2 | 3): void;
  copySelection(cut: boolean): void;
  /**
   * 選んでいる枝の出し方の並び（右クリックに出す）。**形式も行き先も
   * マップは知らない** — 並べるのがここ、中身を決めるのは app/export.ts。
   */
  exportWays(): MenuEntry[];
  paste(): void;
  editRequested(id: number): void;
  undo(): void;
  redo(): void;
}

/** 描く前の空のレイアウト */
const emptyLayout = (): Layout => ({
  visible: [],
  boxes: new Map(),
  parentOf: new Map(),
  buriedCount: new Map(),
  fanOf: new Map(),
  seams: [],
});

/** 全体を収めるときの余白と、1 つを見せるときの余白（画面 px） */
const FIT_MARGIN = 60;
const SHOW_MARGIN = 40;

/**
 * その出来事の的が `selector` に当てはまる要素（かその中）なら、それを返す。
 *
 * `e.target` は `EventTarget` で、要素とは限らない（document / window も来る）。
 * `as Element` と名乗ってから `?.` で保険をかけるのは、名乗りを自分で
 * 信じていないということ。**確かめれば保険が要らない。**
 */
function targetIn(e: Event, selector: string): Element | null {
  return e.target instanceof Element ? e.target.closest(selector) : null;
}

/**
 * union の分岐が網羅されているかを、コンパイラに見張らせるための到達不能点。
 * `x` の型が `never` にならなければ型エラーになる — variant を足したのに
 * 振り分けを直し忘れたとき、実行時ではなくビルド時に気づける。
 */
function assertNever(x: never): never {
  throw new Error(`unreachable: ${JSON.stringify(x)}`);
}

/** 空集合の使い回し（毎レンダで new しない） */
const NO_IDS: ReadonlySet<number> = new Set<number>();

/** ドラッグと見なす最小の移動量（px の 2 乗）。ダブルクリックの 2 回目が
 *  わずかに動いてもドラッグに化けないよう、ノードにもカードにも同じ値を使う */
const DRAG_SLOP2 = 64;

export class Mindmap {
  private pane: HTMLElement;
  private host: MapHost;
  private svg: SVGSVGElement;
  private viewport: SVGGElement;
  private renderer = new MapRenderer();
  private dropLine: SVGLineElement;
  private dropHint: SVGPathElement; // どの親につくかを示す予告の曲線
  private plusBtn: SVGGElement;
  /** 選んでいるカードに被せる枠と ×（常に高々 1 枚なので 1 個だけ持つ） */
  private pick = new CardPick();
  private rubber: HTMLDivElement;
  private editor: HTMLInputElement;
  private editBox: HTMLDivElement;
  private editInk: HTMLPreElement;
  private cardEditor: HTMLTextAreaElement;
  private hint: HTMLDivElement;
  private indicatorEl: HTMLDivElement;
  private menu = new ContextMenu();

  private tx = 60;
  private ty = 60;
  private k = 1;

  /** 直近のレイアウト。箱の位置も親子も付け根のずらしも、すべてここから引く */
  private layout: Layout = emptyLayout();
  private order: number[] = []; // ids in document order
  private get boxes(): Map<number, Box> {
    return this.layout.boxes;
  }
  private polyOf = new Map<number, Pt[]>(); // 子 → エッジの折れ線（render で捨てる）

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
  /** カードのドラッグ。掴んだだけ（閾値を越えるまで）は drop を出さない */
  private cardDrag: {
    ref: CardRef;
    px: number;
    py: number;
    moved: boolean;
  } | null = null;
  private cardDrop: { node: number; index: number } | null = null;
  // ドラッグでカードを動かした直後、pointerup に続いて発火するネイティブの
  // click が、落とし先の座標にあるカードをふらっと選び直すのを止める印
  private suppressClick = false;
  private drop: Drop | null = null;
  // ドロップ中の一時的なノード印。**どれに付けたかを覚えておくのは、
  // 外すときに全ノードを舐めないため**（マウス移動のたびに外して付け直す）。
  // 描き直しで要素が作り直されても paintState が同じ印を戻す
  private dropMarks = new Map<number, "drop-child" | "drop-parent">();
  private dropEdgeId: number | null = null;
  private hoverId = -1;
  /** その場で直しているカード（位置は毎回引き直す） */
  private editingCard: CardRef | null = null;

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
      this.renderer.edgeLayer,
      this.renderer.seamLayer,
      this.renderer.nodeLayer,
      this.pick.el,
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

    // カードはその場で直す。textarea 自体は色を持てないので、
    // 同じ字形・同じ寸法の色付き層を裏に敷いて重ねる（打つのは透明な
    // textarea、見えているのは裏の層）。字がずれないよう font と padding は
    // CSS で 1 か所に揃えてある
    this.editBox = document.createElement("div");
    this.editBox.id = "card-editor";
    this.editBox.style.display = "none";
    this.editInk = document.createElement("pre");
    this.editInk.className = "card-ink";
    this.cardEditor = document.createElement("textarea");
    this.cardEditor.spellcheck = false;
    this.editBox.append(this.editInk, this.cardEditor);
    pane.append(this.editBox);

    // **マップからの始め方だけを言う。** md からの始め方は md ペイン自身が
    // 同じ器で言う（app/hint.ts）ので、こちらから隣のペインを指さない
    // — 片方を隠しているときは、見えているほうの入口だけが残る
    this.hint = paneHint("Press ", "Enter", " to create the first node");
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
    // 絵しか持たない。名前は title に頼らず言い切る（title はホバーの
    // 保険としてそのまま残す）
    centerBtn.setAttribute("aria-label", "Center the view");
    centerBtn.append(icon("crosshair"));
    centerBtn.addEventListener("click", () => this.centerOnTarget());
    centerTool.append(centerBtn);
    pane.append(centerTool);

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
    return toWorld(this.view(), clientX - r.left, clientY - r.top);
  }

  /** 新しい見え方を受け取って画面へ反映する */
  private setView(v: View): void {
    this.k = v.k;
    this.tx = v.tx;
    this.ty = v.ty;
    this.applyTransform();
    this.updateIndicator();
  }

  /** ペインの大きさ（画面 px） */
  private paneSize(): { width: number; height: number } {
    const r = this.pane.getBoundingClientRect();
    return { width: r.width, height: r.height };
  }

  /** いまの見え方（world → 画面）。入力欄の置き場所を計算する側へ渡す */
  private view(): View {
    return { k: this.k, tx: this.tx, ty: this.ty };
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
    this.positionCardEditor();
  }

  // ---------- layout & render ----------

  render(): void {
    const doc = this.host.doc();
    // **まだ 1 つもノードが無いときだけ。** md 側の同じ言い出しも
    // まったく同じ判断で出入りする（決めるのは applySnap ひとつ）—
    // 対で出るものが別々の理由で動くと、対に見えなくなる
    this.hint.style.display = doc.nodes.length === 0 ? "flex" : "none";

    const L = layoutMap(doc);
    const boxes = L.boxes;
    this.layout = L;
    this.polyOf.clear(); // 箱が動いたら線も動く
    this.order = L.visible.map((n) => n.id);
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
    // 言語は後から読み込まれる。開いている編集欄にも遅れて色を載せる
    if (this.editingCard) this.paintEditInk();


    // 文書とレイアウトから決まるものだけを描き、そのあとで
    // 「いまの操作の状態」（選択・ドラッグ・ドロップ先・選んだカード）を被せる。
    // 作り直された要素にも付け直す必要があるので、順番はこの通り
    this.renderer.draw({
      layout: L,
      imageUrl: (path) => this.host.imageUrl(path),
      imageHint: this.host.imageHint(),
    });
    this.paintState();

    this.updatePlus();
    this.positionEditor();
    this.updateIndicator();
  }

  /**
   * その座標にあるカード。`e.target` は当てにしない — ドラッグのために
   * ペインがポインタキャプチャを取ると、以降のイベントはペインへ
   * 付け替えられ、target が実際に押した要素を指さなくなる。
   *
   * `data-card` はカードそのもの、`data-kill` は選択中に出る × ボタン。
   */
  private cardAt(
    x: number,
    y: number,
    attr: "data-card" | "data-kill",
  ): CardRef | null {
    const mark = document
      .elementFromPoint(x, y)
      ?.closest?.(`[${attr}]`)
      ?.getAttribute(attr);
    if (!mark) return null;
    const [node, index] = mark.split(",").map(Number);
    return Number.isFinite(node) && Number.isFinite(index)
      ? { node, index }
      : null;
  }

  /**
   * カードの置かれている場所（world 座標）。積み方は数えない —
   * `cardRect` が描画と共通の唯一の出所で、ここは箱の位置ぶん動かすだけ。
   */
  private cardWorld(ref: CardRef): Rect | null {
    const b = this.boxes.get(ref.node);
    if (!b || b.n.hidden) return null;
    const r = cardRect(b, ref.index);
    return r === null ? null : { ...r, x: b.x + r.x, y: b.y + r.y };
  }

  /**
   * いまの操作の状態を、描き終えた要素に被せる。**描画はこれを知らない** —
   * 選択もドラッグもドロップ先も文書からは導けず、変えた本人だけが知っている。
   */
  private paintState(): void {
    this.renderer.refreshSelection(this.host.selection());
    for (const id of this.dragging?.subtree ?? NO_IDS) {
      this.renderer.nodeEl(id)?.classList.add("dragging");
    }
    for (const [id, cls] of this.dropMarks) {
      this.renderer.nodeEl(id)?.classList.add(cls);
    }
    if (this.dropEdgeId !== null) {
      this.renderer.edgeEl(this.dropEdgeId)?.classList.add("drop-edge");
    }
    this.showPick();
  }

  /** 選んでいるカードの上に印を置き直す（レイアウトか選択が動いたら呼ぶ） */
  private showPick(): void {
    const ref = this.host.pickedCard();
    if (ref) this.pick.show(ref, this.cardWorld(ref));
    else this.pick.hide();
  }

  /** その座標が、どのノードの何枚目と何枚目の間か */
  private cardSlotAt(
    clientX: number,
    clientY: number,
  ): { node: number; index: number } | null {
    const w = this.toWorld(clientX, clientY);
    for (const [id, b] of this.boxes) {
      if (b.n.hidden) continue;
      if (w.x < b.x || w.x > b.x + b.w || w.y < b.y || w.y > b.y + b.h) continue;
      for (let i = 0; i < b.rows.length; i++) {
        // 行の上半分なら「その手前」、下半分なら「次の隙間」
        const mid = b.y + rowTop(b.rows, i) + rowH(b.rows[i]) / 2;
        if (w.y < mid) return { node: id, index: i };
      }
      return { node: id, index: b.rows.length };
    }
    return null;
  }

  /** 落とし先を線で示す */
  private showCardDrop(): void {
    const d = this.cardDrop;
    if (!d) {
      this.dropLine.setAttribute("visibility", "hidden");
      return;
    }
    const b = this.boxes.get(d.node);
    if (!b) return;
    const y = b.y + rowTop(b.rows, d.index);
    this.dropLine.setAttribute("x1", String(b.x + ROW_NORMAL.padX));
    this.dropLine.setAttribute("y1", String(y));
    this.dropLine.setAttribute("x2", String(b.x + b.w - ROW_NORMAL.padX));
    this.dropLine.setAttribute("y2", String(y));
    this.dropLine.setAttribute("visibility", "visible");
  }

  /** 開いているカードのいまの範囲。boxes は毎レンダで作り直されるので、
   *  外から文書が動いても（undo など）ここは常に現在の位置を返す。 */
  private editingRow(): CardRow | null {
    const ref = this.editingCard;
    return ref ? (this.boxes.get(ref.node)?.rows[ref.index] ?? null) : null;
  }

  /** カードをその場で開く。閉じるのは Esc / Mod+Enter / 他所クリック。 */
  /**
   * そのカードを、その場で直す入力欄で開く。`from`/`to` は入力欄の中で
   * 最初に選んでおく範囲（省略すると末尾にカーソルを置く）。
   */
  editCard(ref: CardRef, from?: number, to?: number): void {
    this.beginCardEdit(ref, from, to);
  }

  private beginCardEdit(ref: CardRef, from?: number, to?: number): void {
    const b = this.boxes.get(ref.node);
    const row = b?.rows[ref.index];
    const rect = this.cardWorld(ref);
    if (!row || !rect) return;
    if (this.isEditingLabel()) this.host.commitEdit();
    this.editingCard = ref;
    this.cardEditor.value = this.host.doc().text.slice(row.from, row.to);
    this.editBox.style.display = "block";
    this.paintEditInk();
    this.positionCardEditor();
    this.cardEditor.focus();
    const end = this.cardEditor.value.length;
    this.cardEditor.setSelectionRange(from ?? end, to ?? from ?? end);
  }

  /** 色付き層を今の中身で塗り直す（打つたびに呼ぶ） */
  private paintEditInk(): void {
    this.editInk.replaceChildren();
    for (const line of tokenizeBlock(this.cardEditor.value)) {
      for (const t of line) {
        const span = document.createElement("span");
        if (t.cls !== "") span.className = t.cls;
        span.textContent = t.text;
        this.editInk.append(span);
      }
      // 空行でも高さを持たせる（改行だけの行がある文書で行がずれる）
      this.editInk.append(document.createTextNode("\n"));
    }
  }

  /**
   * カードの上にぴったり重ねる。中身が増えたら下と右へ伸ばす — 打っている
   * 途中で文字が隠れると、何を書いているか分からなくなる。
   */
  private positionCardEditor(): void {
    if (!this.editingCard) return;
    const rect = this.cardWorld(this.editingCard);
    if (!rect) {
      this.endCardEdit();
      return;
    }
    // 文字を測るのはこちら、置き場所を決めるのは map/overlay.ts
    const lines = this.cardEditor.value.split("\n");
    const p = cardPlacement(rect, this.view(), {
      lines: lines.length,
      widest: Math.max(...lines.map((l) => measure(monoFont(), l))),
    });
    const st = this.editBox.style;
    st.left = `${p.left}px`;
    st.top = `${p.top}px`;
    st.width = `${p.width}px`;
    st.height = `${p.height}px`;
    st.fontSize = `${p.fontSize}px`;
    st.lineHeight = `${CODE_LINE * this.k}px`;
    st.padding = `${p.padding}px`;
  }

  /** 中身を文書へ返して閉じる。空にしたらブロックの中身が空になるだけ。 */
  private commitCardEdit(): void {
    const row = this.editingRow();
    this.endCardEdit();
    if (!row) return;
    const next = this.cardEditor.value;
    if (next !== this.host.doc().text.slice(row.from, row.to)) {
      this.host.replaceText(row.from, row.to, next);
    }
    this.pane.focus();
  }

  private endCardEdit(): void {
    this.editingCard = null;
    this.editBox.style.display = "none";
  }

  /** Center the whole tree in the pane (file open / initial view). If the
   * pane has no size yet (hidden / pre-layout boot), defer until it does. */
  fitView(): void {
    const pane = this.paneSize();
    // まだ大きさが無い（隠れている / 起動直後）なら、付いてから改めて
    if (pane.width < 80 || pane.height < 80) {
      this.fitPending = true;
      return;
    }
    this.fitPending = false;
    const v = fitToPane(this.boxes.values(), pane, FIT_MARGIN);
    if (v) this.setView(v);
  }

  /**
   * 書き出し用の SVG。`whole` なら全体、そうでなければ**選んでいる枝**
   * （何も選んでいなければ全体）。
   *
   * 一時的な UI 状態（選択・ドロップ印）は入らない。computed style を属性へ
   * 焼き込み、画像サムネイルは data URL で埋めるので、この結果だけで単体
   * 表示できる（ダウンロードにもラスタ化にも同じものを使う）。空なら null。
   */
  exportSvg(whole: boolean): Promise<SVGSVGElement | null> {
    const ids = branchIds(this.layout, whole ? NO_IDS : this.host.selection());
    const boxes: Box[] = [];
    const nodes: SVGGElement[] = [];
    const edges: SVGPathElement[] = [];
    for (const id of ids) {
      const b = this.boxes.get(id);
      const el = this.renderer.nodeEl(id);
      if (!b || !el) continue;
      boxes.push(b);
      nodes.push(el);
      // 親への線は、その親も写るときだけ引く。枝の外へ出ていく線を残すと、
      // 何にもつながらない曲線が書き出しの端から生えてしまう
      const up = this.layout.parentOf.get(id);
      const edge = up !== undefined && ids.has(up) ? this.renderer.edgeEl(id) : undefined;
      if (edge) edges.push(edge);
    }
    return mapToSvg({
      boxes,
      edges,
      nodes,
      // 継ぎ目はルート直下の furniture なので、枝だけの書き出しには入れない
      marks: whole ? this.renderer.seamElements() : [],
      pane: this.pane,
    });
  }

  /**
   * エッジを world 座標の折れ線にする（線への当たり判定と印の位置に使う）。
   * ドラッグ中は指を動かすたびに**すべての**エッジを調べるので、レイアウトが
   * 変わるまで使い回す（1 本あたり 9 点を毎フレーム作り直していた）。
   */
  private edgePolyline(id: number): Pt[] | null {
    const hit = this.polyOf.get(id);
    if (hit) return hit;
    const e = edgeEnds(this.layout, id);
    if (!e) return null;
    const pts = flattenSegs(
      edgeSegs(e.to.x - e.from.x, e.to.y - e.from.y),
      8,
    ).map((q) => ({ x: e.from.x + q[0], y: e.from.y + q[1] }));
    this.polyOf.set(id, pts);
    return pts;
  }

  /** id を指定して一時的な class を付ける（DOM を舐めずに済む） */
  private markNode(id: number, cls: "dragging" | "drop-child" | "drop-parent"): void {
    this.renderer.nodeEl(id)?.classList.add(cls);
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
      this.renderer.nodeEl(id)?.classList.remove(cls);
    }
    this.dropMarks.clear();
    if (this.dropEdgeId !== null) {
      this.renderer.edgeEl(this.dropEdgeId)?.classList.remove("drop-edge");
      this.dropEdgeId = null;
    }
    if (alsoDragging && this.dragging) {
      for (const id of this.dragging.subtree) {
        this.renderer.nodeEl(id)?.classList.remove("dragging");
      }
    }
  }

  /** Pan so the given node is visible (used after keyboard nav / creation). */
  ensureVisible(id: number): void {
    const b = this.boxes.get(id);
    if (b) this.setView(panToShow(this.view(), b, this.paneSize(), SHOW_MARGIN));
  }

  /** 選んでいるノードの箱（複数なら外接）。無ければ空配列。 */
  private selectionBoxes(): Rect[] {
    const boxes: Rect[] = [];
    for (const id of this.host.selection()) {
      const b = this.boxes.get(id);
      if (b) boxes.push(b);
    }
    return boxes;
  }

  /** 寄せる/指す先: 選択があればその外接、無ければルート。文書が空なら null。 */
  private targetBox(): Rect | null {
    const sel = this.selectionBoxes();
    if (sel.length > 0) return unionRect(sel);
    const rid = rootId(this.layout);
    return rid === null ? null : (this.boxes.get(rid) ?? null);
  }

  /** 選択（無ければルート）が画面の中心に来るよう寄せる。拡大率は変えない。 */
  centerOnTarget(): void {
    const box = this.targetBox();
    if (box) this.setView(centerOn(this.view(), box, this.paneSize()));
  }

  /**
   * 画面外にある対象を控えめな針で指す。**対象そのものが画面内かは見ない** —
   * 選択があるときは「選んだどれかが見えているか」、無いときは「ノードが
   * 1 つでも見えているか」で判断する(でないと非選択時にルートがずっと
   * 見えっぱなしで邪魔になる)。
   */
  private updateIndicator(): void {
    const target = this.targetBox();
    if (!target) {
      this.indicatorEl.style.display = "none";
      return;
    }
    const pane = this.paneSize();
    const view = this.view();
    const sel = this.selectionBoxes();
    const checked = sel.length > 0 ? sel : [...this.boxes.values()];
    if (checked.some((b) => isVisible(b, view, pane))) {
      this.indicatorEl.style.display = "none";
      return;
    }
    const ind = indicatorFor(target, view, pane);
    this.indicatorEl.style.display = "block";
    this.indicatorEl.style.left = `${ind.x}px`;
    this.indicatorEl.style.top = `${ind.y}px`;
    this.indicatorEl.style.transform = `translate(-50%, -50%) rotate(${ind.angle}deg)`;
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

  /** ラベルの入力欄が開いているか（確定は host.commitEdit が持つ）。 */
  isEditingLabel(): boolean {
    return this.editingId !== -1;
  }

  /**
   * ラベルとカード、**どちらかの入力欄が開いている**か。
   * 「いまキーはネイティブの入力欄のものか」を聞きたい側はこちらを見る —
   * ラベルだけを見ていたころ、カードを直している最中の `Mod+Z` が
   * textarea ではなく文書へ効いて、確定時に別の範囲を上書きしていた。
   */
  isEditing(): boolean {
    return this.editingId !== -1 || this.editingCard !== null;
  }

  private positionEditor(): void {
    if (this.editingId === -1) return;
    const b = this.boxes.get(this.editingId);
    if (!b) return;
    const p = labelPlacement(
      b,
      this.view(),
      measure(labelFont(rowOf(b.n)), this.editor.value),
    );
    const st = this.editor.style;
    st.left = `${p.left}px`;
    st.top = `${p.top}px`;
    st.width = `${p.width}px`;
    st.height = `${p.height}px`;
    st.fontSize = `${p.fontSize}px`;
    st.paddingLeft = `${p.padding}px`;
    st.paddingRight = `${p.padding}px`;
  }

  // ---------- hover plus button ----------

  private updatePlus(): void {
    const b = this.hoverId !== -1 ? this.boxes.get(this.hoverId) : undefined;
    if (!b || this.dragging || this.isEditing()) {
      this.plusBtn.setAttribute("visibility", "hidden");
      return;
    }
    this.plusBtn.setAttribute("visibility", "visible");
    const dir = dirOf(b.n);
    const p = growthEdgeOf(b, dir);
    this.plusBtn.setAttribute("transform", `translate(${p.x + 14 * dir} ${p.y})`);
  }

  // ---------- events ----------

  /** 出来事の配線。ひとかたまりに見えるが、**本当に 1 つの状態機械なのは
   *  bindPointer だけ**で、残りは互いに独立した紐づけ。 */
  private bindEvents(): void {
    this.bindDragKeys();
    this.bindWheel();
    this.bindPointer();
    this.bindClick();
    this.bindMenu();
    this.bindOverlays();
    this.bindKeys();
  }

  /**
   * ドラッグ中の Shift の押し外しと、Space パン。指を動かさずに
   * 判定を出し直したいので、キーの上げ下げも見る。
   */
  private bindDragKeys(): void {
    const pane = this.pane;
    // Shift / Mod を押す/離すだけで、指を動かさずに判定を切り替えたい
    const onDragMod = (e: KeyboardEvent): void => {
      if (!this.dragging || !this.lastPointer) return;
      if (e.key !== "Shift" && e.key !== "Control" && e.key !== "Meta") return;
      this.updateDrop(
        this.lastPointer.x,
        this.lastPointer.y,
        e.shiftKey,
        e.ctrlKey || e.metaKey,
      );
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

  }

  /**
   * 見え方を変える入力（ホイールのズームとスクロール）。
   * 動かし方そのものは map/view.ts。
   */
  private bindWheel(): void {
    const pane = this.pane;
    pane.addEventListener(
      "wheel",
      (e) => {
        e.preventDefault();
        // 動かし方は map/view.ts。ここは入力の振り分けだけ
        if (e.ctrlKey || e.metaKey) {
          const r = pane.getBoundingClientRect();
          this.setView(
            zoomAt(this.view(), e.clientX - r.left, e.clientY - r.top, e.deltaY),
          );
        } else if (e.shiftKey) {
          // Shift+ホイールは横スクロール（縦の目盛りしか出さないマウス用）
          this.setView(panBy(this.view(), -(e.deltaY || e.deltaX), 0));
        } else {
          this.setView(panBy(this.view(), -e.deltaX, -e.deltaY));
        }
      },
      { passive: false },
    );
  }

  /**
   * **ポインタの状態機械。** パン / 矩形選択 / ノードのドラッグ /
   * カードのドラッグは、どれも同じ down → move → up の流れを共有し、
   * 「いまどの最中か」で枝分かれする。分けて書くと状態の持ち主が散る。
   */
  private bindPointer(): void {
    const pane = this.pane;
    // `+` ボタンとリンクの ↗ は pointerdown を止めるので、ここへ来るのは
    // ペイン / ノード / 入力欄の上での押下だけ
    pane.addEventListener("pointerdown", (e) => {
      // 新しい操作の始まり。前の操作が立てた「次の click は捨てる」印が
      // 使われないまま残っていたら、ここで落とす（残すとユーザーの
      // 次の 1 クリックを食う）
      this.suppressClick = false;
      // 入力欄の中のクリックはカーソルを置くためのもので、確定ではない。
      // ここで pane.focus() まで進むと、押した瞬間に blur して閉じてしまう
      if (e.target === this.editor) return;
      if (e.target instanceof Node && this.editBox.contains(e.target)) return;
      // カードの入力欄は blur が自分で確定する。ここはラベルの担当
      if (this.isEditingLabel()) this.host.commitEdit();
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

      // 選んでいるカード（と その ×）の上での押下は、そのカードのもの。
      // ここでノード選択を仕込むと、pointerup が選択を作り直して picked を
      // 落とし、click が届く前に × が DOM から消える。選んでいるカードの
      // 上からのドラッグはカードを動かす — 選んでいないカードの上からは、
      // 従来どおりノードが動く（既存の D&D を奪わない）
      const downCard = this.cardAt(e.clientX, e.clientY, "data-card");
      const held = this.host.pickedCard();
      if (this.cardAt(e.clientX, e.clientY, "data-kill")) return;
      if (
        downCard !== null &&
        held !== null &&
        held.node === downCard.node &&
        held.index === downCard.index
      ) {
        this.cardDrag = { ref: held, px: e.clientX, py: e.clientY, moved: false };
        pane.setPointerCapture(e.pointerId);
        return;
      }

      const id = this.nodeAt(e.clientX, e.clientY);
      if (id !== -1) {
        this.dragCand = { id, px: e.clientX, py: e.clientY };
        pane.setPointerCapture(e.pointerId);
      } else {
        // 何も無いところ: 矩形選択
        const r = pane.getBoundingClientRect();
        this.rubberStart = { x: e.clientX - r.left, y: e.clientY - r.top };
        pane.setPointerCapture(e.pointerId);
      }
    });

    pane.addEventListener("pointermove", (e) => {
      if (this.cardDrag) {
        const dx = e.clientX - this.cardDrag.px;
        const dy = e.clientY - this.cardDrag.py;
        // 一度でも越えたらドラッグ。戻ってきても掴んだままにする
        if (!this.cardDrag.moved && dx * dx + dy * dy <= DRAG_SLOP2) return;
        this.cardDrag.moved = true;
        this.cardDrop = this.cardSlotAt(e.clientX, e.clientY);
        this.showCardDrop();
        return;
      }
      if (this.panning) {
        this.setView({
          k: this.k,
          tx: this.panning.ox + e.clientX - this.panning.px,
          ty: this.panning.oy + e.clientY - this.panning.py,
        });
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
        if (dx * dx + dy * dy > DRAG_SLOP2) this.startDrag();
      }
      if (this.dragging) {
        this.lastPointer = { x: e.clientX, y: e.clientY };
        this.updateDrop(e.clientX, e.clientY, e.shiftKey, e.ctrlKey || e.metaKey);
      }
    });

    pane.addEventListener("pointerup", (e) => {
      if (this.cardDrag) {
        const from = this.cardDrag.ref;
        const to = this.cardDrop;
        this.cardDrag = null;
        this.cardDrop = null;
        this.dropLine.setAttribute("visibility", "hidden");
        if (to && this.host.moveCardTo(from, to.node, to.index)) {
          this.suppressClick = true;
        }
        return;
      }
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
        // 離す直前にも判定し直す（Shift/Mod を押したまま指を動かさず離したとき用）
        if (this.lastPointer) {
          this.updateDrop(e.clientX, e.clientY, e.shiftKey, e.ctrlKey || e.metaKey);
        }
        const drop = this.drop;
        const ids = this.dragging.ids;
        this.stopDragVisuals();
        // 行き先が無い（空所へ離した）ときは何もしない。あるときは 3 つの
        // kind を漏れなく振り分ける — switch + assertNever で、4 つ目の
        // variant が増えたら実行時ではなくビルド時に落ちるようにしてある
        if (drop) {
          switch (drop.kind) {
            case "node":
              this.host.move(ids, drop.id, drop.pos);
              break;
            case "side":
              this.host.moveSideEnd(ids, drop.root, drop.left);
              break;
            case "group":
              this.host.moveNewGroup(ids, drop.target, drop.before, drop.left);
              break;
            default:
              assertNever(drop);
          }
        }
        this.dragCand = null;
        return;
      }
      if (this.dragCand) {
        // ノードの素のクリック: 選択
        const id = this.dragCand.id;
        this.dragCand = null;
        const sel = this.host.selection();
        const mod = e.ctrlKey || e.metaKey;
        if (e.shiftKey && this.host.anchor() !== -1) {
          const a = this.order.indexOf(this.host.anchor());
          const b = this.order.indexOf(id);
          if (a !== -1 && b !== -1) {
            const [lo, hi] = a < b ? [a, b] : [b, a];
            // 画面の並び = 文書順 = md の行順
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
      this.cardDrag = null;
      this.cardDrop = null;
      this.dropLine.setAttribute("visibility", "hidden");
      pane.style.cursor = "";
    });
  }

  /**
   * 押して離す以外のマウス操作 — ダブルクリック、ホバーと `+` ボタン、
   * リンクとカードのクリック。
   */
  private bindClick(): void {
    const pane = this.pane;
    pane.addEventListener("dblclick", (e) => {
      // ↗ のダブルクリックはリンクを開く。編集にまで入らない
      if (targetIn(e, ".link-open")) return;
      // カードはラベルではなく元テキストを直すので、専用の入力欄を開く。
      // 編集の場所を 2 つ持たない — 隣に本物のエディタが出ている
      const card = this.cardAt(e.clientX, e.clientY, "data-card");
      if (card) {
        e.preventDefault();
        this.beginCardEdit(card);
        return;
      }
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
      const hit = targetIn(e, "g.node");
      const next =
        hit instanceof SVGGElement
          ? Number(hit.dataset.id)
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
      // 箱の脇なので、右クリックの `Add ▸` と同じ並びをその場で開く。
      // 子 1 つだけなら `Tab` のほうが速い
      const r = this.plusBtn.getBoundingClientRect();
      this.menu.show(r.right + 4, r.top, this.addItems(this.hoverId));
      this.menu.focusFirst();
    });

    // open link cards
    // ペインに付ける。ノード層だと、ポインタキャプチャで
    // イベントがペインへ付け替わったとき伝播経路から外れて届かない
    pane.addEventListener("click", (e) => {
      if (this.suppressClick) {
        this.suppressClick = false;
        return;
      }
      // × は選ばれているカードにだけ出ている。押されたらその行ごと消す
      const kill = this.cardAt(e.clientX, e.clientY, "data-kill");
      if (kill) {
        this.host.deleteCard(kill);
        return;
      }
      // 読めていない場所取りの「繋ぐ」の字。**場所取りそのものは選択のまま**
      if (targetIn(e, ".img-connect")) {
        this.host.connectAssets();
        return;
      }
      const pick = this.cardAt(e.clientX, e.clientY, "data-card");
      if (pick) {
        // pointerdown が「いま掴んでいるカードの上」を dragCand の対象から
        // 外している（下記 pointerdown 参照）ので、素のノード選択は起きず
        // picked はここに来るまで書き換わっていない
        const now = this.host.pickedCard();
        const same =
          now !== null && now.node === pick.node && now.index === pick.index;
        this.host.pickCard(same ? null : pick);
        return;
      }
      const url = targetIn(e, ".link-open")?.getAttribute("data-url");
      if (url) window.open(url, "_blank", "noopener,noreferrer");
    });
    this.renderer.nodeLayer.addEventListener("pointerdown", (e) => {
      if (targetIn(e, ".link-open")) e.stopPropagation();
    });
  }

  /**
   * 右クリックメニュー。外を押したときと、窓から離れたときに閉じる。
   */
  private bindMenu(): void {
    const pane = this.pane;
    pane.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      const id = this.nodeAt(e.clientX, e.clientY);
      if (id === -1) {
        this.hideMenu();
        return;
      }
      if (!this.host.selection().has(id)) this.host.setSelection([id], id);
      this.menu.show(e.clientX, e.clientY, this.menuItems());
      this.menu.focusFirst();
    });

    // ラベルの入力欄。Enter / Esc / Mod+Enter はどれも**確定**で、
    // キャンセルは存在しない。Tab は何もしない
    // IME の変換中は文書へ書き込まない。
    // 変換中の中間候補まで rename すると、(a) 未確定の文字列が「唯一の真実」
    // であるはずの markdown に流れ込み、(b) 候補が変わるたびに全再描画が走る。
    // 変換中に外から value を書き換えるのは日本語入力を壊す代表的なパターン
    // なので、確定するまで待って compositionend で 1 回だけ反映する。
    // 入力欄の見た目（幅）だけは変換中も追従させる。
  }

  /**
   * その場で直す 2 つの入力欄（ラベルとカード）。IME を壊さないよう、
   * 変換中は文書へ書き込まない。
   */
  private bindOverlays(): void {
    this.editor.addEventListener("compositionstart", () => {
      this.composing = true;
    });
    this.editor.addEventListener("compositionend", () => {
      this.composing = false;
      this.commitEditorValue();
    });
    this.editor.addEventListener("input", (e) => {
      if (this.composing || (e instanceof InputEvent && e.isComposing)) {
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

    // カードの入力欄。Enter は改行なので、確定は Esc / Mod+Enter / 他所へ移る
    this.cardEditor.addEventListener("keydown", (e) => {
      e.stopPropagation(); // マップのショートカットへ流さない
      if (e.isComposing || e.keyCode === 229) return;
      if (e.key === "Escape" || (e.key === "Enter" && (e.ctrlKey || e.metaKey))) {
        e.preventDefault();
        this.commitCardEdit();
      }
    });
    this.cardEditor.addEventListener("blur", () => this.commitCardEdit());
    this.cardEditor.addEventListener("beforeinput", (e) => {
      const v = this.cardEditor.value;
      let from = this.cardEditor.selectionStart;
      let to = this.cardEditor.selectionEnd;
      // 選択が無いときの削除は、隣の 1 文字へ伸びる
      if (from === to) {
        if (e.inputType.startsWith("deleteContentBackward")) from = Math.max(0, from - 1);
        else if (e.inputType.startsWith("deleteContentForward")) to = Math.min(v.length, to + 1);
      }
      if (touchesFence(v, from, to)) e.preventDefault();
    });
    this.cardEditor.addEventListener("input", () => {
      this.paintEditInk();
      this.positionCardEditor();
    });

    // keyboard, select mode
  }

  /**
   * 選択モードのキー。中身は onKeydown。
   */
  private bindKeys(): void {
    const pane = this.pane;
    pane.addEventListener("keydown", (e) => this.onKeydown(e));

  }

  private overPlus(e: Event): boolean {
    return targetIn(e, ".plus-btn") !== null;
  }

  /** Node whose box contains the given client position, or -1. Iterates in
   * reverse document order so the topmost-drawn box wins when boxes touch. */
  /**
   * 落ちてくる絵の着地点を予告する。`null` を渡せば消す。返すのは落ちる先の
   * ノード（無ければ -1）で、呼ぶ側はそれで受け取れるかを決められる。
   *
   * 着地は必ず**そのノードの本文の末尾**（`insertContent` がそこへ足す）。
   * 予告するのは「どこに入るか」だけで、入った後の姿ではない — カードの
   * ドラッグと同じ割り切りで、線は今ある行の隙間に引く。絵の実寸を先読み
   * して箱を膨らませる投機的なレイアウトは持たない。
   *
   * 器は `#drop-line` を使い回す。カードのドラッグと同時には起きない。
   */
  markFileDrop(at: { x: number; y: number } | null): number {
    const id = at === null ? -1 : this.nodeAt(at.x, at.y);
    const b = id === -1 ? undefined : this.boxes.get(id);
    this.cardDrop = b ? { node: id, index: b.rows.length } : null;
    this.showCardDrop();
    return id;
  }

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

  /**
   * 選択モードのキー。**ノードとカードは同時に選ばれない**ので、
   * どちらが選ばれているかで担当を分ける（どちらに効くのかで迷わない）。
   */
  private onKeydown(e: KeyboardEvent): void {
    if (e.isComposing || e.keyCode === 229) return;
    if (this.isEditing()) return;
    // CapsLock は Shift 無しで大文字を送ってくる。素の `h` が `H` として届き、
    // 黙ってサブツリーを畳んでしまうので、Shift 無しの大文字は小文字に戻す
    const key =
      !e.shiftKey && e.key.length === 1 && e.key >= "A" && e.key <= "Z"
        ? e.key.toLowerCase()
        : e.key;
    const card = this.host.pickedCard();
    // カード側で拾わなかったキーは、そのままノード側へ流す。Escape のように
    // どちらでも同じ意味を持つものがあるため
    if (card && this.cardKeys(e, key, card)) return;
    this.nodeKeys(e, key);
  }

  /**
   * カードを選んでいるときのキー。
   *
   * **矢印は行き先が無くても必ず飲む。** ノード側へ抜けさせると、カード選択中は
   * anchor が -1 なので無関係な先頭ノードへ飛んでしまう（ブラウザの戻る/進むへ
   * 渡らないことより、そちらを避けるほうを優先する）。
   *
   * 拾ったら true。false なら呼び出し側がノード側へ流す。
   */
  private cardKeys(e: KeyboardEvent, key: string, card: CardRef): boolean {
    const mod = e.ctrlKey || e.metaKey;
    if (!e.altKey && (key === "Delete" || key === "Backspace")) {
      this.host.deleteCard(card);
      e.preventDefault();
      return true;
    }
    if (key === "Enter" && mod) {
      this.beginCardEdit(card);
      e.preventDefault();
      return true;
    }
    if (!isArrowKey(key)) return false;
    e.preventDefault();
    if (mod) return true; // Mod+矢印には何も割り当てない
    if (e.altKey) {
      // 並べ替えは Alt+↑↓ だけ（Alt+←→ はブラウザの戻る/進む）
      if (key === "ArrowUp" || key === "ArrowDown") {
        this.host.reorderCard(card, key === "ArrowUp" ? -1 : 1);
      }
      return true;
    }
    if (key === "ArrowUp" || key === "ArrowDown") {
      const rows = this.boxes.get(card.node)?.rows ?? [];
      const next = card.index + (key === "ArrowUp" ? -1 : 1);
      if (next >= 0 && next < rows.length) {
        this.host.pickCard({ node: card.node, index: next });
      }
    } else if (key === "ArrowLeft") {
      this.host.setSelection([card.node], card.node);
    }
    return true;
  }

  /** ノードを選んでいるときのキー。 */
  private nodeKeys(e: KeyboardEvent, key: string): void {
    const mod = e.ctrlKey || e.metaKey;
    const anchor = this.host.anchor();
    const sel = this.host.selection();
    // **ちょうど 1 つのノードを指しているか。** 宛先が 1 つに決まらない操作
    // （編集・描く・リンク・コード）はこれを見る。同じ概念はメニュー側も
    // 使う（solo()）— 概念が 1 つなら綴りも 1 つ
    const nodes = this.host.doc().nodes;

    // 選択（無ければルート）を画面の中心へ。マップにしか効かないので、
    // どこにフォーカスがあっても効く app/shortcuts.ts ではなくここに置く
    if (key === "Home" && !mod && !e.altKey) {
      this.centerOnTarget();
      e.preventDefault();
      return;
    }
    // comment-out hide/show for the subtree (= collapse)
    if (key === "H" && !mod && !e.altKey && anchor !== -1) {
      this.host.toggleHidden(anchor);
      e.preventDefault();
      return;
    }
    // その場で描いて貼る。**空ノードの打ち始めより前**に置く — 後ろだと
    // 名前の無いノードで `D` が文字入力に化ける
    if (key === "D" && !mod && !e.altKey && this.solo() !== -1) {
      this.host.addDrawing(anchor);
      e.preventDefault();
      return;
    }
    // クリップボードの URL をリンクとして貼り、そのまま題を打てる状態にする。
    // `D` と同じく**空ノードの打ち始めより前**に置く
    if (key === "L" && !mod && !e.altKey && this.solo() !== -1) {
      this.host.addLink(anchor);
      e.preventDefault();
      return;
    }
    // 空のコードフェンスを足して、そのまま打てる状態にする（`D` / `L` と同じ）
    if (key === "C" && !mod && !e.altKey && this.solo() !== -1) {
      this.host.addCode(anchor);
      e.preventDefault();
      return;
    }
    // 名前がまだ無いノード。ここでは「足す」より「埋める」ほうが要る
    const blank =
      this.solo() !== -1 &&
      (nodes.find((n) => n.id === anchor)?.label ?? "").trim() === "";

    // 名前が無いなら、打ち始めればそのまま書ける（Enter を挟ませない）。
    // 入れる文字は e.key のまま — CapsLock 正規化した key を使うと、
    // CapsLock で打った大文字が小文字になって入る。
    // Space はパンに使うので除く。
    if (blank && !mod && !e.altKey && e.key.length === 1 && e.key !== " ") {
      this.host.editRequested(anchor);
      if (this.isEditingLabel()) {
        this.editor.value = e.key;
        this.editor.setSelectionRange(1, 1);
        // 既存の input 経路に乗せる（ラベルと箱の幅がそのまま追従する）
        this.editor.dispatchEvent(new Event("input", { bubbles: true }));
      }
      e.preventDefault();
      return;
    }

    // edit the label
    if (key === "Enter" && mod) {
      if (nodes.length === 0) this.host.addRoot();
      else if (this.solo() !== -1) this.host.editRequested(anchor);
      e.preventDefault();
      return;
    }
    // Shift+Enter: 上に兄弟を足す
    if (key === "Enter" && e.shiftKey) {
      if (anchor !== -1) this.host.addSiblingBefore(anchor);
      e.preventDefault();
      return;
    }
    // Enter: 下に兄弟を足す。ただし名前が無いノードでは、まずそこを埋める
    // — 空のまま足しても名無しが 2 つ並ぶだけで、次に打つ場所が決まらない
    if (key === "Enter") {
      if (nodes.length === 0) this.host.addRoot();
      else if (blank) this.host.editRequested(anchor);
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
    if (!isArrowKey(key)) return;
    // 並べ替えは Alt+↑↓（Alt+←→ はブラウザの戻る/進む）。Mod を足すとグループの壁を越える
    if (e.altKey && (key === "ArrowUp" || key === "ArrowDown")) {
      e.preventDefault();
      if (anchor !== -1 && sel.size === 1) {
        this.host.reorder(anchor, key === "ArrowUp" ? -1 : 1, mod);
      }
      return;
    }
    if (mod) return; // Mod+矢印には何も割り当てない
    e.preventDefault();
    // 行き先の決め方は map/navigate.ts。ここは選択に反映するだけ
    const next = arrowTarget(nodes, this.layout, anchor, key);
    if (next === -1) return;
    this.host.setSelection(
      e.shiftKey ? extendSelection(sel, anchor, next) : [next],
      next,
    );
    this.ensureVisible(next);
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
    const nodes = this.host.doc().nodes;
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const subtree = new Set<number>();
    for (const nid of ids) {
      const nd = byId.get(nid);
      if (!nd) continue;
      for (const m of nodes) {
        if (m.from >= nd.from && m.from < nd.to) subtree.add(m.id);
      }
    }
    this.dragging = { ids, subtree };
    for (const id of subtree) this.markNode(id, "dragging");
    this.updatePlus();
  }

  /**
   * ドラッグ中の落とし先を決めて、その見た目を出す。
   * **どこへ落とすかの判断は map/drop.ts の純関数**が持つ。ここは世界座標へ
   * 直して渡し、返ってきた行き先を線と枠で示すところだけ。
   */
  private updateDrop(
    clientX: number,
    clientY: number,
    preferEdge = false,
    newGroup = false,
  ): void {
    // 呼び出し側は全員 `if (this.dragging)` の中からしか呼ばない
    const dragging = this.dragging;
    if (!dragging) return;
    const { drop, ambiguous } = resolveDrop({
      at: this.toWorld(clientX, clientY),
      order: this.order,
      boxes: this.boxes,
      parentOf: this.layout.parentOf,
      dragging: dragging.subtree,
      single: dragging.ids.length === 1,
      preferEdge,
      newGroup,
      polyline: (id) => this.edgePolyline(id),
    });

    this.drop = drop;
    // 落とし先は必ず示す。示せないなら受け付けない
    this.clearDropMarks(false);
    this.dropLine.classList.remove("slot");
    if (!drop) {
      this.dropLine.setAttribute("visibility", "hidden");
      this.dropHint.setAttribute("visibility", "hidden");
      return;
    }

    if (drop.kind === "side") {
      // ルートの脇。その側の辺のすぐ外に、末尾への挿入線を出す
      // （行き先は箱から選んでいるので必ず在るが、描き直しと競っていれば
      // 消えていることもある。そのときは印を出さない）
      const rb = this.boxes.get(drop.root);
      if (!rb) return;
      const p = drop.left ? leftOf(rb) : rightOf(rb);
      const lx = p.x + (GAP.x / 2) * (drop.left ? -1 : 1);
      const half = 16;
      this.dropLine.setAttribute("x1", String(lx));
      this.dropLine.setAttribute("y1", String(p.y - half));
      this.dropLine.setAttribute("x2", String(lx));
      this.dropLine.setAttribute("y2", String(p.y + half));
      this.dropLine.setAttribute("visibility", "visible");
      this.dropHint.setAttribute("visibility", "hidden");
      return;
    }

    if (drop.kind === "group") {
      // Mod を押したまま落とした: target の手前/後ろに新しいグループができる。
      // 「隣に入る」との違いは、太さ（.slot）だけで言う
      const b = this.boxes.get(drop.target);
      if (!b) return;
      const cx = b.x + b.w / 2;
      const cy = b.y + b.h / 2;
      const off = (b.h / 2 + GAP.y / 2) * (drop.before ? -1 : 1);
      const half = Math.max(b.w / 2, 40);
      this.dropLine.setAttribute("x1", String(cx - half));
      this.dropLine.setAttribute("y1", String(cy + off));
      this.dropLine.setAttribute("x2", String(cx + half));
      this.dropLine.setAttribute("y2", String(cy + off));
      this.dropLine.classList.add("slot");
      this.dropLine.setAttribute("visibility", "visible");
      this.dropHint.setAttribute("visibility", "hidden");
      return;
    }

    // kind === "node": 従来どおり（0 = 子 / 1,2 = 前後挿入 / 3 = 線への割り込み）
    // 行き先は箱から選んでいるので必ず在るが、描き直しと競っていれば
    // 消えていることもある。そのときは印を出さない
    const b = this.boxes.get(drop.id);
    if (!b) return;

    // 挿入線だけだと「上の親の末尾」と「下の親の先頭」が同じ場所に出て
    // 区別できない。どの親につくのかを、その親からの予告線と枠で示す。
    const parentId =
      drop.pos === 0 ? drop.id : (this.layout.parentOf.get(drop.id) ?? -1);
    const showHint = (to: { x: number; y: number }): void => {
      const p = ambiguous ? this.boxes.get(parentId) : undefined;
      if (!p) {
        this.dropHint.setAttribute("visibility", "hidden");
        return;
      }
      // ルートは両側へ伸びるので、親自身の向き（left フラグ）では出口が
      // 決まらない。**落とし先に近いほうの辺**から出す
      const out = to.x < p.x + p.w / 2 ? leftOf(p) : rightOf(p);
      this.dropHint.setAttribute("d", edgePath(out, to));
      this.dropHint.setAttribute("visibility", "visible");
      this.markNode(parentId, "drop-parent");
    };

    if (drop.pos === 3) {
      // 線への割り込み。線そのものを光らせて、その真ん中に印を出す。
      // 「この線の途中に入る」以外の読み方がないので、親の枠までは出さない。
      this.dropEdgeId = drop.id;
      this.renderer.edgeEl(drop.id)?.classList.add("drop-edge");
      const pts = this.edgePolyline(drop.id);
      if (!pts) return;
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
    } else if (drop.pos === 0) {
      // ring on the target PLUS an insertion line on its outward side,
      // where the new child will appear
      this.markNode(drop.id, "drop-child");
      const dir = dirOf(b.n);
      const e = growthEdgeOf(b, dir);
      const lx = e.x + (GAP.x / 2) * dir;
      const ly = e.y;
      const half = 16;
      this.dropLine.setAttribute("x1", String(lx));
      this.dropLine.setAttribute("y1", String(ly - half));
      this.dropLine.setAttribute("x2", String(lx));
      this.dropLine.setAttribute("y2", String(ly + half));
      this.dropLine.setAttribute("visibility", "visible");
      showHint({ x: lx, y: ly });
    } else {
      // 兄弟軸の上に挿入線を引く（相手の手前 / 後ろ）
      const cx = b.x + b.w / 2;
      const cy = b.y + b.h / 2;
      const off = (b.h / 2 + GAP.y / 2) * (drop.pos === 1 ? -1 : 1);
      const half = Math.max(b.w / 2, 40);
      this.dropLine.setAttribute("x1", String(cx - half));
      this.dropLine.setAttribute("y1", String(cy + off));
      this.dropLine.setAttribute("x2", String(cx + half));
      this.dropLine.setAttribute("y2", String(cy + off));
      this.dropLine.setAttribute("visibility", "visible");
      showHint({ x: cx - (b.w / 2) * dirOf(b.n), y: cy + off });
    }
  }

  private stopDragVisuals(): void {
    this.clearDropMarks(true); // dragging の部分木を読むので dragging を消す前に
    this.dragging = null;
    this.drop = null;
    this.lastPointer = null;
    this.dropLine.setAttribute("visibility", "hidden");
    this.dropLine.classList.remove("slot");
    this.dropHint.setAttribute("visibility", "hidden");
  }

  // ---------- context menu ----------

  /** そのノードに対して、いま何ができるか。並べ方はメニュー側が持つ */
  /** ノードの足し方。右クリックの入れ子も、箱の脇の `+` も、同じ並びを開く */
  private addItems(id: number): MenuEntry[] {
    return [
      { label: "Child", key: "Tab", run: () => this.host.addChild(id) },
      { label: "Below", key: "Enter", run: () => this.host.addSibling(id) },
      { label: "Above", key: "Shift+Enter", run: () => this.host.addSiblingBefore(id) },
      { label: "Parent", key: "Shift+Tab", run: () => this.host.addParent(id) },
    ];
  }

  /**
   * ちょうど 1 つのノードを指しているなら、その id。指していない・複数
   * 選んでいるなら -1。**宛先が 1 つに決まらない操作の、唯一の物差し** —
   * キー（Shift+D/L/C・Mod+Enter）とメニューの行の沈み方が同じこれを見る。
   */
  private solo(): number {
    return this.host.selection().size <= 1 ? this.host.anchor() : -1;
  }

  private menuItems(): MenuEntry[] {
    const anchor = this.host.anchor();
    const multi = this.host.selection().size > 1;
    const solo = this.solo() !== -1;
    const node = this.host.doc().nodes.find((n) => n.id === anchor);
    const folded = node?.hidden ?? false;
    // 根はどのグループにも属さない（コアでは group 0 に丸められる）ので、
    // Flip side を出すと「先頭のグループが動く」という別の意味に化ける
    const isRoot = node?.parent === -1;
    return [
      // 押せば子が増え、開けば下も上も親も選べる。**まとめた名前そのものが、
      // いちばん普通の 1 つでもある** — 子の追加は他の 3 つより桁違いに多い
      {
        label: "Add",
        key: "Tab",
        run: () => this.host.addChild(anchor),
        disabled: multi,
        items: this.addItems(anchor),
      },
      {
        label: "Rename",
        key: "Mod+Enter",
        mark: "pencil",
        run: () => this.host.editRequested(anchor),
        disabled: multi,
      },
      "sep",
      {
        // キーだけでなく、ここからも指定・解除できるように。
        // 絵も字と同じ向きを言う（畳むなら内へ、開くなら外へ）
        label: folded ? "Show (unfold)" : "Hide (fold)",
        key: "Shift+H",
        mark: folded ? "chevrons-up-down" : "chevrons-down-up",
        run: () => this.host.toggleHidden(anchor),
        disabled: anchor === -1,
      },
      {
        label: "Flip side",
        mark: "flip-horizontal",
        run: () => this.host.flipSide(anchor),
        disabled: anchor === -1 || isRoot,
      },
      "sep",
      { label: "Copy", key: "Mod+C", mark: "copy", run: () => this.host.copySelection(false) },
      { label: "Cut", key: "Mod+X", mark: "scissors", run: () => this.host.copySelection(true) },
      {
        label: "Paste",
        key: "Mod+V",
        mark: "clipboard-paste",
        run: () => this.host.paste(),
        disabled: multi,
      },
      "sep",
      // この枝の出し方。ヘッダの書き出しと同じ並びで、対象だけが違う。
      // 平らに 4 行足すと右クリックが伸びるので、入れ子に畳む
      { label: "Export", mark: "download", items: this.host.exportWays(), disabled: anchor === -1 },
      "sep",
      {
        label: "Draw",
        key: "Shift+D",
        mark: "paintbrush",
        run: () => this.host.addDrawing(anchor),
        disabled: !solo,
      },
      {
        label: "Link",
        key: "Shift+L",
        mark: "link",
        run: () => this.host.addLink(anchor),
        disabled: !solo,
      },
      {
        // 置き場所を要らない（画像と違ってフェンスは .md の中で完結する）
        label: "Code",
        key: "Shift+C",
        mark: "code",
        run: () => this.host.addCode(anchor),
        disabled: !solo,
      },
      "sep",
      { label: "Delete", key: "Del", mark: "trash-2", run: () => this.host.deleteSelection() },
    ];
  }

  hideMenu(): void {
    this.menu.hide();
  }

  /** レイアウトを見直さない軽い塗り替え（矩形選択の途中で使う）。
   *  選択そのものは持たない — 何が選ばれているかは main.ts が決める。 */
  refreshSelection(): void {
    this.renderer.refreshSelection(this.host.selection());
    this.showPick();
    this.updateIndicator();
  }
}

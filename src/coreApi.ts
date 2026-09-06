// core の出口と入口。**形を整えるだけ** — 意味は 1 つも足さない。
//
// 使う側は `import * as core` で `core.survey(md)` / `core.hit(layout, x, y)` と書く。
//
// 木も箱も core から出ない。境界は数・文字列・真偽・持ち手（MoonBit の値を**中を見ずに**
// 持ち、core にそのまま返す）と、操作 1 回ぶんの小さな JSON（Intent・落とし先・
// メニューの行・選択）。MoonBit の ToJson は Option の None を鍵ごと落とし、enum を
// `["Image", {…}]` / `"ThematicBreak"` の形で出す。その形を整えるのはここ 1 か所。
// 信頼境界もここだけ — 型は名乗らせず確かめる。

import * as mbt from "../core/_build/js/release/build/tree/js/js.js";

export type Side = "Right" | "Left";

/** 中身そのもの。カードかどうかは core/map の分類 */
export type Content =
  | { kind: "image"; alt: string; src: string; title: string }
  | { kind: "link"; text: string; href: string; title: string }
  | { kind: "code"; info: string; text: string }
  | { kind: "svg"; markup: string }
  | { kind: "thematicBreak" }
  /** `<details>`。open / summary / body は GitHub が描くのと同じ読み取り。text は原文 */
  | { kind: "details"; text: string; open: boolean; summary: string | null; body: string }
  /** 読み解かない原文。その場編集が原文をそのまま書き戻すときに送る */
  | { kind: "opaque"; text: string };

/** 地番。ノードが md のどこに書かれているか。label はラベルの頭（Implicit と文書の散文は null） */
export interface Spot {
  from: number;
  label: number | null;
  to: number;
}

/** 編集 1 つ。CodeMirror の changes と同じ形（前の座標、from 順、重ならない） */
export interface Edit {
  from: number;
  to: number;
  insert: string;
}

/** 編集列を md に当てた後の全文。続けて操作を映すとき、次の操作が読む md はこれ */
export const splice = (md: string, edits: Edit[]): string => {
  let out = "";
  let at = 0;
  for (const e of edits) {
    out += md.slice(at, e.from) + e.insert;
    at = e.to;
  }
  return out + md.slice(at);
};

declare const brand: unique symbol;
/** MoonBit の値の持ち手。中は見ない — core にそのまま返すためだけのもの */
export interface Handle {
  readonly [brand]: never;
}

// ---- 読み ----
//
// 木も地番も core が持つ。ts は持ち手を渡して問い合わせ、返った数・字・真偽を使うだけ。

declare const surveyBrand: unique symbol;
/** 打鍵 1 回ぶんの読み（持ち手）。木と地番と原文は core にしか無い */
export interface Survey {
  readonly [surveyBrand]: never;
}

/** md を core に読ませる。読みのサイクルの唯一の入口 */
export const survey = (md: string): Survey => Object(mbt.mmmSurvey(md));

/** id がノードのものか（中身の id なら false） */
export const isNode = (s: Survey, id: number): boolean => mbt.mmmIsNode(s, id);

/** 木が 1 つも無い（白紙） */
export const empty = (s: Survey): boolean => mbt.mmmEmpty(s);

/** まだ保存していない文書の名前（拡張子なし）。最初の根の字から。無ければ "empty" */
export const name = (s: Survey): string => mbt.mmmName(s);

/** ラベルをファイル名にする。何も残らなければ "" */
export const toFileName = (label: string): string => mbt.mmmToFileName(label);

/** 頭（frontmatter の原文。`---` は含まない）。無ければ null */
export const frontmatter = (s: Survey): string | null => mbt.mmmFrontmatter(s) ?? null;

/** その id の地番。無い id は null */
export const spot = (s: Survey, id: number): Spot | null =>
  opt(mbt.mmmSpot(s, id), (v) => {
    const [from, label, to] = nums(v, 3);
    return { from, label: label < 0 ? null : label, to };
  });

/** その字のノード（文書順で最初）。見本の md から id を引く */
export const find = (s: Survey, label: string): number | null => mbt.mmmFind(s, label) ?? null;

/** そのノードの中身の id、文書順 */
export const blocks = (s: Survey, id: number): number[] => [...mbt.mmmBlocks(s, id)];

/** 選んだ部分木の原文（Mod+C / Mod+X）。何も選んでいなければ "" */
export const copy = (s: Survey, ids: number[]): string => mbt.mmmCopy(s, ids);

/** 頭が言っている画像フォルダ（綴りのまま）。無ければ null */
export const imageFolder = (s: Survey): string | null => mbt.mmmImageFolder(s) ?? null;

/** 画像フォルダの宣言を書き換える編集 1 つ */
export const setImageFolder = (s: Survey, value: string): Edit => editOne(JSON.parse(mbt.mmmSetImageFolder(s, value)));

/** 宣言フォルダの引っ越しに本文の画像を追従させる操作列 */
export const retarget = (s: Survey, from: string, to: string): Op[] =>
  list(JSON.parse(mbt.mmmRetarget(s, from, to)), (json) => ({ kind: "raw", json }));

/** 宣言の綴りを揃える。空・絶対パス・URL は null */
export const normalizePath = (value: string): string | null => mbt.mmmNormalizePath(value) ?? null;

/** path が folder の下にあるなら、フォルダからの残り。外なら null */
export const under = (path: string, folder: string): string | null => mbt.mmmUnder(path, folder) ?? null;

/** 先頭の `./` を落とした形（md が書く `./x` とカードが持つ `x` を揃える） */
export const barePath = (path: string): string => mbt.mmmBarePath(path);

// ---- 選択 ----
//
// 選択の**値**。どう変わるか（クリック・矩形・矢印・当たり）は core が持ち、ts は聞いた値を持つだけ。

/** 選んでいるノード（文書順）と、範囲選択・矢印の基点 */
export interface Selection {
  ids: number[];
  anchor: number | null;
}

export const NONE: Selection = { ids: [], anchor: null };

/** 何を選んでいるか — ノードの並びか、カード 1 枚か。片方だけ（spec.md「C カード」） */
export type Choice = { kind: "nodes"; sel: Selection } | { kind: "card"; id: number };

export const NOTHING: Choice = { kind: "nodes", sel: NONE };

/** ノードの選択として見る。カードを選んでいれば空 */
export const nodesOf = (c: Choice): Selection => (c.kind === "nodes" ? c.sel : NONE);

/** カードの選択として見る。ノードを選んでいれば null */
export const cardOf = (c: Choice): number | null => (c.kind === "card" ? c.id : null);

/** 選択を持っている側。フォーカスが最後に入ったペイン */
export type Holder = "md" | "map";

/** md 側のカーソル 1 つ、または選択 1 つぶん（`from == to` なら点） */
export interface Range {
  from: number;
  to: number;
}

/** md のカーソルぜんぶ。head は主カーソルの頭（anchor になる） */
export interface Caret {
  ranges: Range[];
  head: number;
}

/** 地図の選択の位置。ノードはラベルの頭、カードは中身の原文の頭。CodeMirror が編集で写す。null は無し */
export type Anchors = { kind: "nodes"; at: number[]; anchor: number | null } | { kind: "card"; at: number } | null;

/** 選択。持ち主が決める — md が持つ間はカーソルから、地図が持つ間は位置から */
export const chosen = (s: Survey, holder: Holder, caret: Caret, a: Anchors): Choice =>
  choice(
    JSON.parse(
      mbt.mmmChosen(
        s,
        holder,
        caret.ranges.flatMap((r) => [r.from, r.to]),
        caret.head,
        anchorsJson(a),
      ),
    ),
  );

/** focus の id をその木の地番で位置に。無ければ null */
export const anchorsOf = (s: Survey, id: number | null): Anchors => maybe(mbt.mmmAnchorsOf(s, id ?? undefined), anchors);

/** 選択をその木の地番で位置に。地図で選んだときの setAnchors の値 */
export const anchorsFor = (s: Survey, c: Choice): Anchors => maybe(mbt.mmmAnchorsFor(s, choiceJson(c)), anchors);

/** md 側で薄く塗る範囲。ノードは地番そのもの（子孫込み）、カードは中身の原文 */
export const ranges = (s: Survey, c: Choice): Range[] => {
  const flat = mbt.mmmRanges(s, choiceJson(c));
  const out: Range[] = [];
  for (let i = 0; i + 1 < flat.length; i += 2) out.push({ from: flat[i], to: flat[i + 1] });
  return out;
};

// ---- 地図 ----
//
// 箱は core が持つ。ts は持ち手を渡して問い合わせ、返った数・id・Intent を使うだけ。

declare const layoutBrand: unique symbol;
/** View を置いたもの（持ち手）。箱は core にしか無い */
export interface Layout {
  readonly [layoutBrand]: never;
}

/** 字。大きさは core が決め、綴り（family）は ts が CSS から読む（map/measure.ts） */
export interface Font {
  px: number;
  mono: boolean;
}

/** 幅を測る。core の layout / render / 欄の重ねがこれを閉包で受ける */
export type Measure = (font: Font, text: string) => number;

/** 読みを置く。字の実測は canvas なので ts から渡す */
export const layout = (s: Survey, measure: Measure): Layout => asLayout(mbt.mmmLayout(s, measure));

/** 位置と大きさだけの箱。x, y は左上 */
export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Pt {
  x: number;
  y: number;
}

/** world → 画面: `screen = world * k + t` */
export interface Camera {
  k: number;
  tx: number;
  ty: number;
}

/** ペインの大きさ（画面 px） */
export interface Pane {
  width: number;
  height: number;
}

export type Modifier = "none" | "shift" | "mod";

/** 押されたキー。mod は Ctrl / Cmd のどちらか */
export interface Key {
  key: string;
  shift: boolean;
  mod: boolean;
  alt: boolean;
}

/** 何をするか。core の表（keys.mbt）が言い、ts は実行するだけ */
export type Intent =
  /** 操作を md に映す。edit なら focus をそのまま編集開始。消した後に選ぶ隣は core の focus */
  | { kind: "op"; op: Op; edit: boolean }
  /** その場編集に入る。seed は最初の字（空のノードで打ち始めたとき） */
  | { kind: "edit"; id: number; seed: string | null }
  | { kind: "select"; sel: Selection; reveal: boolean }
  /** 選択（無ければ根）を画面の中心へ */
  | { kind: "center" }
  /** カードを選ぶ（null で外す） */
  | { kind: "pick"; id: number | null }
  /** カードをその場で直す */
  | { kind: "editCard"; id: number }
  /** クリップボードの URL をリンクカードにして題を打つ / 空のコードを足して打つ / 描いて貼る */
  | { kind: "link"; id: number }
  | { kind: "code"; id: number }
  | { kind: "draw"; id: number }
  /** クリップボードを貼る。anchor があればそこへ、無ければ文書へ */
  | { kind: "paste" }
  /** 選んでいるものをクリップボードへ写す。cut は写せてから消すもの。写せなければ消さない */
  | { kind: "copy"; cut: Intent | null };

/** 右クリックの 1 行。`mark` は絵の名（icons.ts の表で確かめる）。intent が null なら沈む（why が理由） */
export interface Item {
  label: string;
  key: string | null;
  mark: string | null;
  intent: Intent | null;
  why: string | null;
  items: Item[] | null;
}
export type Entry = Item | "sep";

/** 落とし先。node は pos 0 = 子の末尾 / 1 = 直前 / 2 = 直後、side は根の脇 */
export type Drop = { kind: "node"; id: number; pos: number } | { kind: "side"; root: number; left: boolean };

/** そのまま style へ入れる値（px） */
export interface Placement {
  left: number;
  top: number;
  width: number;
  height: number;
  fontSize: number;
  padding: number;
  border: number;
  lineHeight: number;
}

/** 画面外の対象を指す針。画面 px と、ペイン中心から対象へ向く向き（度） */
export interface Indicator {
  x: number;
  y: number;
  angle: number;
}

/** world の点がどの箱に居るか。grab は ⋯ の Easy grab（当たりを箱の外へ広げる） */
export const hit = (l: Layout, x: number, y: number, grab: boolean): number | null =>
  mbt.mmmHit(l, x, y, grab) ?? null;

/** 描くノードの id、文書順（= 重なり順） */
export const order = (l: Layout): number[] => [...mbt.mmmOrder(l)];

/** 在る箱の矩形（world）。無い id は飛ぶ */
export const rects = (l: Layout, ids: number[]): Rect[] => mbt.mmmRects(l, ids).map(rect4);

/** そのノードの字（Implicit は ""）。箱が無ければ null */
export const label = (l: Layout, id: number): string | null => mbt.mmmLabel(l, id) ?? null;

/** その中身（ブロック id）の矩形（world）。持ち主が畳まれていれば null */
export const cardRect = (l: Layout, block: number): Rect | null => opt(mbt.mmmCardRect(l, block), rect4);

/** `data-card` の「ノードの id, 何枚目」から中身の id */
export const blockAt = (l: Layout, node: number, index: number): number | null =>
  mbt.mmmBlockAt(l, node, index) ?? null;

/** 選んだものとその子孫（文書順）。落とし先から外す部分木 */
export const subtree = (l: Layout, ids: number[]): number[] => [...mbt.mmmSubtree(l, ids)];

/** 選ぶ。shift は anchor から文書順に範囲、mod は足す・外す */
export const click = (l: Layout, sel: Selection, id: number, mod: Modifier): Selection =>
  selection(JSON.parse(mbt.mmmClick(l, sel.ids, anchorOf(sel), id, mod === "shift" ? 1 : mod === "mod" ? 2 : 0)));

/** 矩形（world）に触れる箱を全部。anchor は文書順の最後 */
export const rubber = (l: Layout, r: Rect): Selection => selection(JSON.parse(mbt.mmmRubber(l, r.x, r.y, r.w, r.h)));

/** キー 1 回ぶん。null は拾わない（ブラウザに渡す） */
export const keyed = (l: Layout, sel: Selection, k: Key): Intent | null =>
  maybe(mbt.mmmKeyed(l, sel.ids, anchorOf(sel), k.key, k.shift, k.mod, k.alt), intent);

/** カードを選んでいるときのキー */
export const keyedCard = (l: Layout, picked: number, k: Key): Intent | null =>
  maybe(mbt.mmmKeyedCard(l, picked, k.key, k.shift, k.mod, k.alt), intent);

/** 右クリックの行 */
export const context = (l: Layout, sel: Selection): Entry[] =>
  list(JSON.parse(mbt.mmmContext(l, sel.ids, anchorOf(sel))), entry);

/** どこへ落とすか。落ちる先が無ければ null */
export const drop = (l: Layout, at: Pt, dragging: number[]): Drop | null =>
  maybe(mbt.mmmDrop(l, at.x, at.y, dragging), dropOf);

/** 落とし先を Op に。側は根のものなので In(root, side) で言う */
export const dropOp = (d: Drop, ids: number[]): Op => ({
  kind: "raw",
  json: JSON.parse(mbt.mmmDropOp(JSON.stringify(encode(d)), ids)),
});

/** 画面の点を world に戻す（座標はペインの左上から測ったもの） */
export const toWorld = (cam: Camera, x: number, y: number): Pt => pt2(mbt.mmmToWorld(cam.k, cam.tx, cam.ty, x, y));

/** ホイールの目盛りを倍率に読み替え、その点の下の world を動かさずに拡大・縮小 */
export const zoomAt = (cam: Camera, x: number, y: number, deltaY: number): Camera =>
  camera(mbt.mmmZoomAt(cam.k, cam.tx, cam.ty, x, y, deltaY));

/** 平行移動だけ（倍率は変えない） */
export const panBy = (cam: Camera, dx: number, dy: number): Camera => camera(mbt.mmmPanBy(cam.k, cam.tx, cam.ty, dx, dy));

/** 2 本指の位置（ペインの左上から測った画面 px） */
export interface Span {
  a: Pt;
  b: Pt;
}

/** 2 本指の前後の位置から、見え方を 1 つ出す */
export const pinch = (cam: Camera, from: Span, to: Span): Camera =>
  camera(mbt.mmmPinch(cam.k, cam.tx, cam.ty, [from.a.x, from.a.y, from.b.x, from.b.y], [to.a.x, to.a.y, to.b.x, to.b.y]));

/** 全部が入る見え方。拡大はしない。箱が無ければ null */
export const fit = (l: Layout, pane: Pane, margin: number): Camera | null =>
  opt(mbt.mmmFit(l, pane.width, pane.height, margin), camera);

/** 選択（無ければ根）を画面の中心へ。拡大率は変えない。どちらも無ければ null */
export const center = (l: Layout, ids: number[], cam: Camera, pane: Pane): Camera | null =>
  opt(mbt.mmmCenter(l, ids, cam.k, cam.tx, cam.ty, pane.width, pane.height), camera);

/** その箱が画面に入るまでだけ寄せる。既に見えていれば同じ視点。箱が無ければ null */
export const show = (l: Layout, id: number, cam: Camera, pane: Pane, margin: number): Camera | null =>
  opt(mbt.mmmShow(l, id, cam.k, cam.tx, cam.ty, pane.width, pane.height, margin), camera);

/** 見失った選択（無ければ根）を指す針。見失っていなければ null */
export const indicator = (l: Layout, ids: number[], cam: Camera, pane: Pane): Indicator | null =>
  opt(mbt.mmmIndicator(l, ids, cam.k, cam.tx, cam.ty, pane.width, pane.height), (v) => {
    const [x, y, angle] = nums(v, 3);
    return { x, y, angle };
  });

/** ラベルの欄をノードの箱に重ねる。text は欄のいまの字。箱が無ければ null */
export const labelPlace = (l: Layout, id: number, cam: Camera, text: string, measure: Measure): Placement | null =>
  opt(mbt.mmmLabelPlace(l, id, cam.k, cam.tx, cam.ty, text, measure), placement);

/** カードの欄をその中身の矩形に重ねる。持ち主が畳まれていれば null */
export const cardPlace = (l: Layout, block: number, cam: Camera, text: string, measure: Measure): Placement | null =>
  opt(mbt.mmmCardPlace(l, block, cam.k, cam.tx, cam.ty, text, measure), placement);

/** 指の台帳（core/map/gesture.mbt）。何本が生きていて、前回どこに居たか */
export class Fingers {
  private readonly handle: Handle = asHandle(mbt.mmmFingers());

  get pinching(): boolean {
    return mbt.mmmPinching(this.handle);
  }

  down(id: number, x: number, y: number): void {
    mbt.mmmFingerDown(this.handle, id, x, y);
  }

  /** 組の片方が実際に動いたときだけ、その前後を返す */
  moved(id: number, x: number, y: number): { from: Span; to: Span } | null {
    const g = mbt.mmmFingerMoved(this.handle, id, x, y);
    if (g === undefined) return null;
    const [ax, ay, bx, by, cx, cy, dx, dy] = nums(g, 8);
    return { from: { a: { x: ax, y: ay }, b: { x: bx, y: by } }, to: { a: { x: cx, y: cy }, b: { x: dx, y: dy } } };
  }

  up(id: number): void {
    mbt.mmmFingerUp(this.handle, id);
  }

  /** ちょうど 1 本だけ生きていれば、その「いま」の位置 */
  only(): Pt | null {
    return opt(mbt.mmmFingerOnly(this.handle), pt2);
  }
}

// ---- 描画 ----

/** コードの色分けの 1 塊。`cls` が空なら色の付かない地の文 */
export interface Token {
  text: string;
  cls: string;
}

/** 1 回の描き直しに要るもの。文書とレイアウトから決まるものと、外から受けるもの */
export interface Scene {
  layout: Layout;
  measure: Measure;
  /** ローカル画像の objectURL（まだ読めていなければ null） */
  imageUrl: (path: string) => string | null;
  /** 読めていない場所取りに添える字。握っていないときだけ（他は null） */
  imageHint: string | null;
  /** コードの色分け。(行, 言語) → 行ごとの塊 */
  tokens: (lines: string[], lang: string) => Token[][];
  /** 言語の読み込みの世代。変われば描き直す */
  epoch: number;
}

/**
 * マップの SVG を差分で更新する描き手（core/render）。edgeLayer / nodeLayer を
 * world の <g> に並べ、draw に場面を渡す。要素の形（class / data-*）は style.css と
 * ハンドラとの契約で、core が守る
 */
export class Renderer {
  readonly edgeLayer: SVGGElement;
  readonly nodeLayer: SVGGElement;
  private readonly handle: Handle;

  constructor() {
    const r = record(mbt.mmmRenderer());
    this.handle = handle(r, "handle");
    this.edgeLayer = field(r, "edgeLayer", svgG);
    this.nodeLayer = field(r, "nodeLayer", svgG);
  }

  /** 場面を DOM に写す。文書順（= 重なり順）も合わせる */
  draw(s: Scene): void {
    mbt.mmmDraw(this.handle, s.layout, s.measure, s.imageUrl, s.imageHint, s.tokens, s.epoch);
  }

  /** 選ばれた箱に印（`.selected`）を付ける。変わった箱だけ触る */
  paint(ids: Iterable<number>): void {
    mbt.mmmPaint(this.handle, [...ids]);
  }

  /** そのノードの <g>。無ければ null */
  nodeEl(id: number): SVGGElement | null {
    const el: unknown = mbt.mmmNodeEl(this.handle, id);
    return el instanceof SVGGElement ? el : null;
  }

  /** そのノードへの線の <path>。無ければ null */
  edgeEl(id: number): SVGPathElement | null {
    const el: unknown = mbt.mmmEdgeEl(this.handle, id);
    return el instanceof SVGPathElement ? el : null;
  }
}

const svgG = (v: unknown): SVGGElement => (v instanceof SVGGElement ? v : bad("<g> でない"));

// ---- 形を確かめながら整える ----

const bad = (what: string): never => {
  throw new Error(`core の JSON: ${what}`);
};

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const record = (v: unknown): Record<string, unknown> => (isRecord(v) ? v : bad("構造体でない"));
const str = (v: unknown): string => (typeof v === "string" ? v : bad("文字列でない"));
const num = (v: unknown): number => (typeof v === "number" ? v : bad("数でない"));
const bool = (v: unknown): boolean => (typeof v === "boolean" ? v : bad("真偽でない"));
const list = <T>(v: unknown, read: (x: unknown) => T): T[] =>
  Array.isArray(v) ? v.map(read) : bad("配列でない");

/** 在るはずの鍵。無ければ壊れている */
const field = <T>(o: Record<string, unknown>, key: string, read: (v: unknown) => T): T =>
  key in o ? read(o[key]) : bad(`${key} が無い`);

/** Option の鍵。None は鍵ごと落ちている */
const option = <T>(o: Record<string, unknown>, key: string, read: (v: unknown) => T): T | null =>
  key in o ? read(o[key]) : null;

/** 持ち手の鍵。中は見ない — 在ることだけ確かめる */
const handle = (o: Record<string, unknown>, key: string): Handle =>
  field(o, key, (v) => (v === null || v === undefined ? bad(`${key} が空`) : asHandle(v)));

/** MoonBit の値を持ち手として持つ。型は名乗らせず、ここだけが言い切る */
const asHandle = (v: unknown): Handle => Object(v);
const asLayout = (v: unknown): Layout => Object(v);

/** 出口の `T?`（`T | undefined`）を読む */
const opt = <A, B>(v: A | undefined, read: (a: A) => B): B | null => (v === undefined ? null : read(v));

/** 出口の「無ければ空文字」の JSON を読む */
const maybe = <T>(json: string, read: (v: unknown) => T): T | null => (json === "" ? null : read(JSON.parse(json)));

/** 出口の数の列。長さが違えば壊れている（タプルは JS では object になるので、数の列で渡す） */
const nums = (v: number[], n: number): number[] => (v.length === n ? v : bad(`数が ${n} 個でない`));
const rect4 = (v: number[]): Rect => {
  const [x, y, w, h] = nums(v, 4);
  return { x, y, w, h };
};
const camera = (v: number[]): Camera => {
  const [k, tx, ty] = nums(v, 3);
  return { k, tx, ty };
};
const pt2 = (v: number[]): Pt => {
  const [x, y] = nums(v, 2);
  return { x, y };
};
const placement = (v: number[]): Placement => {
  const [left, top, width, height, fontSize, padding, border, lineHeight] = nums(v, 8);
  return { left, top, width, height, fontSize, padding, border, lineHeight };
};

/** 出口へ渡す anchor。無ければ undefined（MoonBit の None） */
const anchorOf = (sel: Selection): number | undefined => sel.anchor ?? undefined;

/** enum の形 — `"Tag"`（中身なし）か `["Tag", 中身]`。中身の形は構築子ごとに確かめる */
function tagged(v: unknown): [string, unknown] {
  if (typeof v === "string") return [v, undefined];
  if (!Array.isArray(v) || v.length !== 2) return bad("enum の形でない");
  return [str(v[0]), v[1]];
}

/** Choice の JSON（`["Nodes", {sel}]` / `["Card", {id}]`） */
function choice(v: unknown): Choice {
  const [tag, body] = tagged(v);
  const o = record(body);
  if (tag === "Nodes") return { kind: "nodes", sel: field(o, "sel", selection) };
  if (tag === "Card") return { kind: "card", id: field(o, "id", num) };
  return bad(`知らない Choice ${tag}`);
}

/** Anchors の JSON（`["NodeAt", {at, anchor?}]` / `["CardAt", {at}]`） */
function anchors(v: unknown): Anchors {
  const [tag, body] = tagged(v);
  const o = record(body);
  if (tag === "NodeAt") {
    return { kind: "nodes", at: field(o, "at", (x) => list(x, num)), anchor: option(o, "anchor", num) };
  }
  if (tag === "CardAt") return { kind: "card", at: field(o, "at", num) };
  return bad(`知らない Anchors ${tag}`);
}

/** 入口へ渡す Anchors。無ければ ""（MoonBit の None） */
const anchorsJson = (a: Anchors): string => {
  if (a === null) return "";
  if (a.kind === "card") return JSON.stringify(["CardAt", { at: a.at }]);
  return JSON.stringify(["NodeAt", a.anchor === null ? { at: a.at } : { at: a.at, anchor: a.anchor }]);
};

/** 入口へ渡す Choice */
const choiceJson = (c: Choice): string =>
  JSON.stringify(
    c.kind === "card"
      ? ["Card", { id: c.id }]
      : ["Nodes", { sel: c.sel.anchor === null ? { ids: c.sel.ids } : { ids: c.sel.ids, anchor: c.sel.anchor } }],
  );

/** Selection の JSON（`{ids, anchor?}`） */
export function selection(v: unknown): Selection {
  const o = record(v);
  return { ids: field(o, "ids", (x) => list(x, num)), anchor: option(o, "anchor", num) };
}

/** Intent の JSON。op は core の形のまま持ち、`edit` にそのまま返す（ts は読まない） */
export function intent(v: unknown): Intent {
  const [tag, body] = tagged(v);
  switch (tag) {
    case "Center":
      return { kind: "center" };
    case "Paste":
      return { kind: "paste" };
  }
  const o = record(body);
  switch (tag) {
    case "Op":
      return { kind: "op", op: { kind: "raw", json: field(o, "op", (x) => x) }, edit: field(o, "edit", bool) };
    case "Edit":
      return { kind: "edit", id: field(o, "id", num), seed: option(o, "seed", str) };
    case "Select":
      return { kind: "select", sel: field(o, "sel", selection), reveal: field(o, "reveal", bool) };
    case "Pick":
      return { kind: "pick", id: option(o, "id", num) };
    case "EditCard":
      return { kind: "editCard", id: field(o, "id", num) };
    case "AddLink":
      return { kind: "link", id: field(o, "id", num) };
    case "AddCode":
      return { kind: "code", id: field(o, "id", num) };
    case "Draw":
      return { kind: "draw", id: field(o, "id", num) };
    case "Copy":
      return { kind: "copy", cut: option(o, "cut", intent) };
    default:
      return bad(`知らない Intent ${tag}`);
  }
}

function item(v: unknown): Item {
  const o = record(v);
  return {
    label: field(o, "label", str),
    key: option(o, "key", str),
    mark: option(o, "mark", str),
    intent: option(o, "intent", intent),
    why: option(o, "why", str),
    items: option(o, "items", (x) => list(x, item)),
  };
}

/** 右クリックの行の JSON */
export function entry(v: unknown): Entry {
  const [tag, body] = tagged(v);
  if (tag === "Sep") return "sep";
  if (tag === "Item") return item(body);
  return bad(`知らない Entry ${tag}`);
}

/** 落とし先の JSON */
export function dropOf(v: unknown): Drop {
  const [tag, body] = tagged(v);
  const o = record(body);
  if (tag === "Node") return { kind: "node", id: field(o, "id", num), pos: field(o, "pos", num) };
  if (tag === "Side") return { kind: "side", root: field(o, "root", num), left: field(o, "left", bool) };
  return bad(`知らない Drop ${tag}`);
}

// ---- 操作を core へ送る ----
//
// 席は隣の id で言う（添字は無い）。`in` は列の末尾で、side は node が根のときだけ意味を持つ。

export type NodePlace =
  | { kind: "before"; node: number }
  | { kind: "after"; node: number }
  | { kind: "in"; node: number; side: Side | null };

export type BlockPlace =
  | { kind: "before"; block: number }
  | { kind: "after"; block: number }
  | { kind: "in"; node: number };

/** 操作 1 つ。core の `Op` と同じ形（構築子名が kind）。`raw` は core から来た Op を
 *  core の形のまま持つもの — ts は組まず読まず、`edit` にそのまま返す */
export type Op =
  | { kind: "addNode"; at: NodePlace; labels: string[] }
  | { kind: "addBlock"; at: BlockPlace; content: Content }
  | { kind: "rename"; id: number; label: string }
  | { kind: "setBlock"; id: number; content: Content }
  | { kind: "moveNode"; ids: number[]; at: NodePlace }
  | { kind: "moveBlock"; ids: number[]; at: BlockPlace }
  | { kind: "delete"; ids: number[] }
  | { kind: "wrap"; id: number; label: string }
  | { kind: "flipSide"; id: number }
  | { kind: "fold"; id: number; open: boolean }
  | { kind: "unfold"; id: number }
  | { kind: "graft"; at: NodePlace; md: string }
  | { kind: "raw"; json: unknown };

/** 文書そのものの id。core の `doc_id` と同じ値で、`NodePlace.in` の node に置けば新しい根 */
export const DOC_ID = 1;

/** 操作を md に映した結果。focus は編集を当てて読み直した木での id（消した後は null） */
export interface Edited {
  edits: Edit[];
  focus: number | null;
}

/** 操作を md に映す。できない操作は edits が空で focus も null */
export const edit = (md: string, op: Op): Edited =>
  edited(JSON.parse(mbt.mmmEdit(md, JSON.stringify(encode(op)))));

/**
 * core の enum の形にする（MoonBit の ToJson / FromJson と同じ）:
 * kind は構築子名（頭を大文字）、残りの鍵はラベル付き引数、null の鍵は落とす、
 * 鍵が無ければ裸の名前。`Svg(String)` だけラベルが無いので位置で渡す。
 * `raw` は core から来た形そのもの。
 */
/** core の enum を表す形。kind と、ラベル付き引数 */
type Tagged = { kind: string } & Record<string, unknown>;

export function encode(v: Tagged): unknown {
  const { kind, ...rest } = v;
  if (kind === "raw" && "json" in v) return v.json;
  const tag = kind.charAt(0).toUpperCase() + kind.slice(1);
  if (kind === "svg" && "markup" in v) return [tag, v.markup];
  if (kind === "opaque" && "text" in v) return [tag, v.text];
  const fields: Record<string, unknown> = {};
  for (const [k, x] of Object.entries(rest)) {
    if (x === null) continue;
    fields[k] = isRecord(x) && typeof x["kind"] === "string" ? encode({ ...x, kind: x["kind"] }) : x;
  }
  return Object.keys(fields).length === 0 ? tag : [tag, fields];
}

const editOne = (v: unknown): Edit => {
  const o = record(v);
  return { from: field(o, "from", num), to: field(o, "to", num), insert: field(o, "insert", str) };
};

/** core の JSON（`mmmEdit` の出力）を Edited にする */
export function edited(json: unknown): Edited {
  const o = record(json);
  return { edits: field(o, "edits", (e) => list(e, editOne)), focus: option(o, "focus", num) };
}

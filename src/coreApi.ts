// core の出口と入口。**JSON の形を整えるだけ** — 意味は 1 つも足さない。
//
// 使う側は `import * as core` で `core.View` / `core.survey(md)` と書く。
// フロントでは view は画面を意味し、`Node` は DOM のグローバル型と衝突するので、
// 裸の名前を出さない（MoonBit 側の `@view.Root` と同じ形）。
//
// MoonBit の ToJson は Option の None を鍵ごと落とし、enum を `["Image", {…}]` /
// `"ThematicBreak"` の形で出す。その形を整えるのはここ 1 か所。信頼境界も
// ここだけ — 型は名乗らせず確かめる。
//
// MoonBit の値（View / Layout / 描き手）は `Handle` として**中を見ずに**持ち、
// core にそのまま返す。JSON を 2 度組まない、2 度 parse しない。

import * as mbt from "../core/_build/js/release/build/tree/js/js.js";

export type Side = "Right" | "Left";

/** 畳み。在ること自体が「畳まれている」 */
export interface Fold {
  open: boolean;
  /** `<summary>` の中身。行が無ければ null */
  summary: string | null;
}

/** ノードにぶら下がる中身 1 枚。id はノードと同じ列（文書順の通し番号） */
export interface Block {
  id: number;
  content: Content;
}

/** 中身そのもの。カードかどうかは core/map の分類 */
export type Content =
  | { kind: "image"; alt: string; src: string; title: string }
  | { kind: "link"; text: string; href: string; title: string }
  | { kind: "code"; info: string; text: string }
  | { kind: "svg"; markup: string }
  | { kind: "thematicBreak" }
  /** `<details>`。open / summary / body は GitHub が描くのと同じ読み取り。text は原文 */
  | { kind: "details"; text: string; open: boolean; summary: string | null; body: string }
  /** 読み解かない原文。View には来ない — その場編集が原文をそのまま書き戻すときに送る */
  | { kind: "opaque"; text: string };

export interface Node {
  id: number;
  /** Implicit（綴られなかった見出し）は null。空の見出しは "" */
  label: string | null;
  fold: Fold | null;
  /** 中身のうち、core が読み解いたもの。Opaque は来ない */
  blocks: Block[];
  children: Node[];
}

/** 根 1 つ。側は根の子と並走する（`sides[i]` が `node.children[i]` の側） */
export interface Root {
  node: Node;
  sides: Side[];
}

export interface View {
  frontmatter: string | null;
  roots: Root[];
}

/** id がノードのものか（中身の id なら false）。木を辿って確かめる —
 *  ノードと中身は同じ通し番号を分け合うので、種類は木の形からしか読めない */
export function isNode(view: View, id: number): boolean {
  const under = (n: Node): boolean => n.id === id || n.children.some(under);
  return view.roots.some((t) => under(t.node));
}

/** Implicit は字を持たない。空の見出しと同じく空の字として扱う */
export const labelOf = (n: Node): string => n.label ?? "";

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

/** 打鍵 1 回ぶんの読み。View と地番と、View の持ち手（layout に渡す） */
export interface Survey {
  view: View;
  spots: Map<number, Spot>;
  handle: Handle;
}

/**
 * md を core に読ませ、View と地番を 1 度に受け取る。読みのサイクルの唯一の入口。
 * 選択の持ち越しは core に無い — 位置は ts が CodeMirror に預けて写す（state.ts）
 */
export function survey(md: string): Survey {
  const r = record(mbt.mmmSurvey(md));
  return { ...decodeSurvey(JSON.parse(field(r, "json", str))), handle: handle(r, "view") };
}

// ---- map ----

/** 字。大きさは core が決め、綴り（family）は ts が CSS から読む（map/measure.ts） */
export interface Font {
  px: number;
  mono: boolean;
}

/** 幅を測る。core の layout / render がこれを閉包で受ける */
export type Measure = (font: Font, text: string) => number;

/** 位置と大きさだけの箱。x, y は左上 */
export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 親との繋がり。側は繋がりの性質なのでここに乗る（根は繋がりを持たない） */
export interface Edge {
  id: number;
  side: Side;
}

export interface Box {
  /** View のノードそのまま。label / fold / blocks はここから読む */
  node: Node;
  parent: Edge | null;
  /** 畳んで埋もれた子孫の数 */
  buried: number;
  x: number;
  y: number;
  w: number;
  h: number;
  /** カードごとの中身の矩形（**箱の左上から見た座標**）。積み方は core が数え、ts は読むだけ */
  cards: Rect[];
}

/** View を置いたもの。描くのも当たるのも、これを読む */
export interface Layout {
  /** 描くノードの id、文書順（= 重なり順）。畳まれて埋もれたものは入らない */
  order: number[];
  boxes: Map<number, Box>;
  /** Layout の持ち手（描き手に渡す） */
  handle: Handle;
}

/** View を置く。字の実測は canvas なので ts から渡す */
export function layout(s: Survey, measure: Measure): Layout {
  const r = record(mbt.mmmLayout(s.handle, measure));
  return { ...decodeLayout(JSON.parse(field(r, "json", str)), s.view), handle: handle(r, "layout") };
}

/** その中身（ブロック id）を持つ箱と、その行の番号。畳まれて箱が無ければ null */
export function ownerOf(l: Layout, block: number): { box: Box; index: number } | null {
  for (const box of l.boxes.values()) {
    const index = box.node.blocks.findIndex((x) => x.id === block);
    if (index !== -1) return { box, index };
  }
  return null;
}

/** 最初の木の根。無ければ null（空文書） */
export function rootBox(l: Layout): Box | null {
  for (const id of l.order) {
    const b = l.boxes.get(id);
    if (b && b.parent === null) return b;
  }
  return null;
}

/** ラベル行の規格。pad は文字の開始位置（箱の左からの距離） */
export interface Row {
  px: number;
  pad: number;
  h: number;
}

/** 寸法のうち、入力側（落とし先の帯・入力欄の重ね）が読むもの。数字の源は core/map/metric.mbt */
export interface Metrics {
  /** x は親子の間、y は兄弟の間、root は木と木の間 */
  gap: { x: number; y: number; root: number };
  row: { normal: Row; hidden: Row };
  /** コードのプレビュー 1 行の高さ */
  codeLine: number;
}


/** そのノードのラベル行。畳んでいれば小さいほう */
export const rowOf = (n: Node): Row => (n.fold === null ? metrics.row.normal : metrics.row.hidden);

// ---- render ----

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
    mbt.mmmDraw(this.handle, s.layout.handle, s.measure, s.imageUrl, s.imageHint, s.tokens, s.epoch);
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

// ---- JSON の形を確かめながら整える ----

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

const side = (v: unknown): Side => (v === "Right" || v === "Left" ? v : bad("側でない"));

const fold = (v: unknown): Fold => {
  const o = record(v);
  return { open: field(o, "open", bool), summary: option(o, "summary", str) };
};

/** enum は `"Tag"`（中身なし）か `["Tag", 中身]` */
function content(v: unknown): Content {
  if (v === "ThematicBreak") return { kind: "thematicBreak" };
  if (!Array.isArray(v) || v.length !== 2) return bad("Content の形でない");
  const [tag, body] = v;
  switch (tag) {
    case "Image": {
      const o = record(body);
      return {
        kind: "image",
        alt: field(o, "alt", str),
        src: field(o, "src", str),
        title: field(o, "title", str),
      };
    }
    case "Link": {
      const o = record(body);
      return {
        kind: "link",
        text: field(o, "text", str),
        href: field(o, "href", str),
        title: field(o, "title", str),
      };
    }
    case "Code": {
      const o = record(body);
      return { kind: "code", info: field(o, "info", str), text: field(o, "text", str) };
    }
    case "Svg":
      return { kind: "svg", markup: str(body) };
    case "Details": {
      const o = record(body);
      return {
        kind: "details",
        text: field(o, "text", str),
        open: field(o, "open", bool),
        summary: option(o, "summary", str),
        body: field(o, "body", str),
      };
    }
    default:
      return bad(`知らない Content ${String(tag)}`);
  }
}

const block = (v: unknown): Block => {
  const o = record(v);
  return { id: field(o, "id", num), content: field(o, "content", content) };
};

function node(v: unknown): Node {
  const o = record(v);
  return {
    id: field(o, "id", num),
    label: option(o, "label", str),
    fold: option(o, "fold", fold),
    blocks: field(o, "blocks", (b) => list(b, block)),
    children: field(o, "children", (c) => list(c, node)),
  };
}

const root = (v: unknown): Root => {
  const o = record(v);
  return { node: field(o, "node", node), sides: field(o, "sides", (s) => list(s, side)) };
};

/** core の JSON（`mmmViewJson` の出力）を View にする。試験はここを直接叩く */
export function decode(json: unknown): View {
  const o = record(json);
  return {
    frontmatter: option(o, "frontmatter", str),
    roots: field(o, "roots", (r) => list(r, root)),
  };
}

const spot = (v: unknown): Spot => {
  const o = record(v);
  return { from: field(o, "from", num), label: option(o, "label", num), to: field(o, "to", num) };
};

/** core の JSON（`mmmSurvey` の `json`）を View と地番にする。Map の鍵は文字列で来る */
export function decodeSurvey(json: unknown): { view: View; spots: Map<number, Spot> } {
  const o = record(json);
  const spots = new Map<number, Spot>();
  for (const [k, v] of Object.entries(field(o, "spots", record))) {
    const id = Number(k);
    if (!Number.isInteger(id)) bad(`spots の鍵 ${k}`);
    spots.set(id, spot(v));
  }
  return { view: decode(field(o, "view", (v) => v)), spots };
}

const rect = (v: unknown): Rect => {
  const o = record(v);
  return { x: field(o, "x", num), y: field(o, "y", num), w: field(o, "w", num), h: field(o, "h", num) };
};

const edge = (v: unknown): Edge => {
  const o = record(v);
  return { id: field(o, "id", num), side: field(o, "side", side) };
};

/** View のノードを id で引く表。箱の `node` は参照であって再符号化ではない */
function nodesOf(view: View): Map<number, Node> {
  const out = new Map<number, Node>();
  const walk = (n: Node): void => {
    out.set(n.id, n);
    n.children.forEach(walk);
  };
  for (const t of view.roots) walk(t.node);
  return out;
}

/** core の JSON（`mmmLayout` の `json`）を Layout にする。node は View から引く */
export function decodeLayout(json: unknown, view: View): { order: number[]; boxes: Map<number, Box> } {
  const o = record(json);
  const nodes = nodesOf(view);
  const boxes = new Map<number, Box>();
  for (const b of field(o, "boxes", (v) => list(v, record))) {
    const id = field(b, "id", num);
    const n = nodes.get(id) ?? bad(`箱 ${id} のノードが View に無い`);
    boxes.set(id, {
      node: n,
      parent: option(b, "parent", edge),
      buried: field(b, "buried", num),
      x: field(b, "x", num),
      y: field(b, "y", num),
      w: field(b, "w", num),
      h: field(b, "h", num),
      cards: field(b, "cards", (c) => list(c, rect)),
    });
  }
  return { order: field(o, "order", (v) => list(v, num)), boxes };
}

const row = (v: unknown): Row => {
  const o = record(v);
  return { px: field(o, "px", num), pad: field(o, "pad", num), h: field(o, "h", num) };
};

function decodeMetrics(json: unknown): Metrics {
  const o = record(json);
  const g = field(o, "gap", record);
  const r = field(o, "row", record);
  return {
    gap: { x: field(g, "x", num), y: field(g, "y", num), root: field(g, "root", num) },
    row: { normal: field(r, "normal", row), hidden: field(r, "hidden", row) },
    codeLine: field(o, "codeLine", num),
  };
}

/** 寸法。起動時に 1 度 core から受ける（確かめる道具の後ろに置く — 読み込み順） */
export const metrics: Metrics = decodeMetrics(JSON.parse(mbt.mmmMetrics()));

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

/** 操作 1 つ。core の `Op` と同じ形（構築子名が kind） */
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
  | { kind: "graft"; at: NodePlace; md: string };

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
 */
/** core の enum を表す形。kind と、ラベル付き引数 */
type Tagged = { kind: string } & Record<string, unknown>;

export function encode(v: Tagged): unknown {
  const { kind, ...rest } = v;
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

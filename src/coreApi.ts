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
// ペインを渡せば core が置いて描き、入力を受け、判断して答える。ts が渡すのは host —
// 文書と選択の読み書き（EditorState に居る）と、ブラウザの API（クリップボード・
// メニューの器・しらせ・字の実測・色分け）。

declare const layoutBrand: unique symbol;
/** 読みを置いたもの（持ち手）。見本（lab）が右クリックの行を引くため */
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
export const layout = (s: Survey, measure: Measure): Layout => Object(mbt.mmmLayout(s, measure));

/** 位置と大きさだけの箱。x, y は左上 */
export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 何をするか。core の表（keys.mbt / context.mbt）が言い、ts は読まずに core へ返す */
export interface Intent {
  readonly raw: unknown;
}

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

/** 右クリックの行（見本のため。地図そのものは core が開く） */
export const context = (l: Layout, sel: Selection): Entry[] =>
  entries(mbt.mmmContext(l, sel.ids, sel.anchor ?? undefined));

/** コードの色分けの 1 塊。`cls` が空なら色の付かない地の文 */
export interface Token {
  text: string;
  cls: string;
}

declare const mapBrand: unique symbol;
/** 地図（持ち手）。置く・描く・入力は core にしか無い */
export interface MapHandle {
  readonly [mapBrand]: never;
}

/** core の地図が外に頼るもの。null は core の側で None になる */
export interface MapHost {
  survey(): Survey;
  measure: Measure;
  imageUrl(path: string): string | null;
  imageHint(): string | null;
  connectAssets(): void;
  holder(): Holder;
  selection(): Selection;
  setSelection(sel: Selection, reveal: boolean): void;
  picked(): number | null;
  setPicked(id: number | null): void;
  blockText(id: number): string;
  /** 操作（core の Op の JSON）を md に映す。返り値は映した focus */
  apply(op: string, edit: boolean): number | null;
  paste(): void;
  copy(): Promise<boolean>;
  draw(id: number): void;
  /** クリップボードの字（読めなければ ""） */
  readClipboard(): Promise<string>;
  tokens(lines: string[], lang: string): Token[][];
  tokensBlock(text: string): Token[][];
  epoch(): number;
  /** 右クリックの行（Entry の列の JSON）をその画面の点に開く。空なら閉じる */
  menu(x: number, y: number, entries: string): void;
  failed(msg: string): void;
}

/** ペインを地図の器にする。hint（白紙の言い出し）と tool（寄せるボタン）は HTML の部品 */
export const map = (pane: HTMLElement, host: MapHost, hint: HTMLElement, tool: HTMLElement): MapHandle =>
  Object(mbt.mmmMap(pane, host, hint, tool));

export const mapRender = (m: MapHandle): void => mbt.mmmMapRender(m);
export const mapFit = (m: MapHandle): void => mbt.mmmMapFit(m);
export const mapCenter = (m: MapHandle): void => mbt.mmmMapCenter(m);
export const mapRefresh = (m: MapHandle): void => mbt.mmmMapRefresh(m);
export const mapBeginEdit = (m: MapHandle, id: number, seed: string | null): boolean =>
  mbt.mmmMapBeginEdit(m, id, seed ?? undefined);
export const mapEditCard = (m: MapHandle, id: number): void => mbt.mmmMapEditCard(m, id);
export const mapSetGrab = (m: MapHandle, on: boolean): void => mbt.mmmMapSetGrab(m, on);
/** ファイルの落とし先を予告する。null で消す。落ちる先のノード（無ければ null） */
export const mapFileDrop = (m: MapHandle, at: { x: number; y: number } | null): number | null =>
  mbt.mmmMapFileDrop(m, at?.x ?? 0, at?.y ?? 0, at !== null) ?? null;
/** 「何をするか」（メニューの行が持つもの）を実行する */
export const mapAct = (m: MapHandle, intent: Intent): void => mbt.mmmMapAct(m, JSON.stringify(intent.raw));

/** 書き出しに写すもの。文書順の箱と、その線・ノードの要素 */
export interface SvgParts {
  rects: Rect[];
  edges: SVGPathElement[];
  nodes: SVGGElement[];
}

export const mapSvgParts = (m: MapHandle): SvgParts => {
  const o = record(mbt.mmmMapSvgParts(m));
  return {
    rects: field(o, "rects", (v) => list(v, (r) => rect4(list(r, num)))),
    edges: field(o, "edges", (v) => list(v, svgPath)),
    nodes: field(o, "nodes", (v) => list(v, svgG)),
  };
};

const svgG = (v: unknown): SVGGElement => (v instanceof SVGGElement ? v : bad("<g> でない"));
const svgPath = (v: unknown): SVGPathElement => (v instanceof SVGPathElement ? v : bad("<path> でない"));

// ---- 形を確かめながら整える ----

const bad = (what: string): never => {
  throw new Error(`core の JSON: ${what}`);
};

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const record = (v: unknown): Record<string, unknown> => (isRecord(v) ? v : bad("構造体でない"));
const str = (v: unknown): string => (typeof v === "string" ? v : bad("文字列でない"));
const num = (v: unknown): number => (typeof v === "number" ? v : bad("数でない"));
const list = <T>(v: unknown, read: (x: unknown) => T): T[] =>
  Array.isArray(v) ? v.map(read) : bad("配列でない");

/** 在るはずの鍵。無ければ壊れている */
const field = <T>(o: Record<string, unknown>, key: string, read: (v: unknown) => T): T =>
  key in o ? read(o[key]) : bad(`${key} が無い`);

/** Option の鍵。None は鍵ごと落ちている */
const option = <T>(o: Record<string, unknown>, key: string, read: (v: unknown) => T): T | null =>
  key in o ? read(o[key]) : null;

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

function item(v: unknown): Item {
  const o = record(v);
  return {
    label: field(o, "label", str),
    key: option(o, "key", str),
    mark: option(o, "mark", str),
    intent: option(o, "intent", (raw) => ({ raw })),
    why: option(o, "why", str),
    items: option(o, "items", (x) => list(x, item)),
  };
}

/** 右クリックの行の JSON（Entry の列） */
export const entries = (json: string): Entry[] => list(JSON.parse(json), entry);

function entry(v: unknown): Entry {
  const [tag, body] = tagged(v);
  if (tag === "Sep") return "sep";
  if (tag === "Item") return item(body);
  return bad(`知らない Entry ${tag}`);
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

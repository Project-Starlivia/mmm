// core の出口と入口。**形を整えるだけ** — 意味は 1 つも足さない。
//
// アプリは core が組む（core/main）。ts に残るのは CodeMirror（md ペイン）で、その
// 読み書きを `Editor` の閉包で渡す。それ以外にここへ来るのは、EditorState の field
// （state.ts）が読む問い合わせと、見本（lab）が置く部品だけ。
//
// 木も箱も core から出ない。境界は数・文字列・真偽・持ち手（MoonBit の値を**中を見ずに**
// 持ち、core にそのまま返す）と、選択の位置の小さな JSON。MoonBit の ToJson は Option の
// None を鍵ごと落とし、enum を `["NodeAt", {…}]` の形で出す。その形を整えるのはここ 1 か所。
// 信頼境界もここだけ — 型は名乗らせず確かめる。

import * as mbt from "../_build/js/release/build/mmm/app/js/js.js";

// ---- 読み ----

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

/** その id の地番。無い id は null */
export const spot = (s: Survey, id: number): Spot | null =>
  opt(mbt.mmmSpot(s, id), (v) => {
    const [from, label, to] = nums(v, 3);
    return { from, label: label < 0 ? null : label, to };
  });

/** 地番。from..to が原文の範囲、label はラベルの頭（無いノードは null） */
export interface Spot {
  from: number;
  label: number | null;
  to: number;
}

/** その字のノード（文書順で最初）。見本の md から id を引く */
export const find = (s: Survey, label: string): number | null => mbt.mmmFind(s, label) ?? null;

/** そのノードの中身の id、文書順 */
export const blocks = (s: Survey, id: number): number[] => [...mbt.mmmBlocks(s, id)];

// ---- 選択 ----
//
// 選択（`Choice`）とその位置（`Anchors`）は持ち手。EditorState の field が持ち、
// 1 トランザクションごとに写す（carry）・導く（chosen）。どう変わるかは core が持つ

/** 選んでいるノード（文書順）と、範囲選択・矢印の基点 */
export interface Selection {
  ids: number[];
  anchor: number | null;
}

export const NONE: Selection = { ids: [], anchor: null };

declare const choiceBrand: unique symbol;
/** 何を選んでいるか — ノードの並びか、カード 1 枚か（持ち手） */
export interface Choice {
  readonly [choiceBrand]: never;
}

export const NOTHING: Choice = Object(mbt.mmmNothing());

/** 同じものを選んでいるか */
export const sameChoice = (a: Choice, b: Choice): boolean => mbt.mmmSameChoice(a, b);

/** ノードの選択として見る。カードを選んでいれば空 */
export const selection = (c: Choice): Selection => selectionOf(mbt.mmmSelection(c));

/** カードの選択として見る。ノードを選んでいれば null */
export const card = (c: Choice): number | null => mbt.mmmCard(c) ?? null;

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

declare const anchorsBrand: unique symbol;
/** 地図の選択の位置（持ち手）。ノードはラベルの頭、カードは中身の原文の頭。CodeMirror が編集で写す */
export interface Anchors {
  readonly [anchorsBrand]: never;
}

/** 選択。持ち主が決める — md が持つ間はカーソルから、地図が持つ間は位置から */
export const chosen = (s: Survey, holder: Holder, caret: Caret, a: Anchors | null): Choice =>
  Object(
    mbt.mmmChosen(
      s,
      holder,
      caret.ranges.flatMap((r) => [r.from, r.to]),
      caret.head,
      a,
    ),
  );

/** focus の id をその木の地番で位置に。無ければ null */
export const anchorsOf = (s: Survey, id: number | null): Anchors | null => handle(mbt.mmmAnchorsOf(s, id ?? undefined));

/** 位置を編集で写す。`at` は点の写し（CodeMirror の `changes.mapPos`） */
export const carry = (a: Anchors, at: (p: number) => number): Anchors => Object(mbt.mmmCarry(a, at));

/** ノードの位置（並びと基点）。見本と試験が組む */
export const nodeAt = (at: number[], anchor: number | null): Anchors => Object(mbt.mmmNodeAt(at, anchor ?? undefined));
/** カードの位置 */
export const cardAt = (at: number): Anchors => Object(mbt.mmmCardAt(at));

/** 位置の中身。試験が読む */
export type AnchorsAt = { kind: "nodes"; at: number[]; anchor: number | null } | { kind: "card"; at: number };
export const anchorsAt = (a: Anchors): AnchorsAt => {
  const [tag, body] = tagged(JSON.parse(mbt.mmmAnchorsJson(a)));
  const o = record(body);
  if (tag === "NodeAt") {
    return { kind: "nodes", at: field(o, "at", (x) => list(x, num)), anchor: option(o, "anchor", num) };
  }
  if (tag === "CardAt") return { kind: "card", at: field(o, "at", num) };
  return bad(`知らない Anchors ${tag}`);
};

/** md 側で薄く塗る範囲。ノードは地番そのもの（子孫込み）、カードは中身の原文 */
export const ranges = (s: Survey, c: Choice): Range[] => {
  const flat = mbt.mmmRanges(s, c);
  const out: Range[] = [];
  for (let i = 0; i + 1 < flat.length; i += 2) out.push({ from: flat[i], to: flat[i + 1] });
  return out;
};

// ---- アプリ ----
//
// 束ねる場所は core/main。ts は CodeMirror の読み書きを閉包で渡し、1 トランザクションごとに
// `cycle` を呼ぶ。編集列は `{ from, to, insert }` の並びで来る（CodeMirror の changes と同じ形）

/** 編集 1 つ。from..to を insert に置き換える */
export interface Edit {
  from: number;
  to: number;
  insert: string;
}

/** コードの色分けの 1 塊。`cls` が空なら色の付かない地の文 */
export interface Token {
  text: string;
  cls: string;
}

/** md ペイン（CodeMirror）。core が頼むもの */
export interface Editor {
  text(): string;
  /** いまの読み（EditorState の field） */
  survey(): Survey;
  holder(): Holder;
  selection(): Selection;
  picked(): number | null;
  /** 文書を丸ごと入れ替える（履歴も新しく）。続けてサイクルが回る */
  setText(text: string): void;
  /** 編集列を順に当てる（undo は 1 手）。`held` なら同じトランザクションで focus の effect が乗る */
  apply(sets: Edit[][], held: boolean, focus: number | null): void;
  /** 地図で選び直した。位置は地番で写してある（無ければ null） */
  select(a: Anchors | null): void;
  /** フォーカスがペインに入った。md → map なら引き継ぐ位置も一緒に（md へなら null） */
  hold(h: Holder, a: Anchors | null): void;
  reveal(pos: number): void;
  undo(): void;
  redo(): void;
  focus(): void;
  setTheme(dark: boolean): void;
  /** 白紙の言い出しを出す / 引っ込める */
  showHint(on: boolean): void;
  tokens(lines: string[], lang: string): Token[][];
  tokensBlock(text: string): Token[][];
  epoch(): number;
  /** 言語が後から読み込まれたら呼ぶ（描き直す） */
  onLanguageReady(fn: () => void): void;
}

declare const appBrand: unique symbol;
/** アプリ（持ち手） */
export interface App {
  readonly [appBrand]: never;
}

/** アプリを組む。動かすのは `boot`（サイクルの出口が繋がってから） */
export const main = (editor: Editor): App =>
  Object(
    mbt.mmmMain({
      ...editor,
      // MoonBit の閉包は返り値の無い関数を `undefined` を返すものとして受ける。
      // 編集列は素の object のままで、形だけ確かめる。位置は持ち手（無ければ null）
      apply: (sets: unknown, held: boolean, focus: number | null): undefined => {
        editor.apply(list(sets, (set) => list(set, editOne)), held, focus);
        return undefined;
      },
      select: (a: unknown): undefined => {
        editor.select(handle(a));
        return undefined;
      },
      hold: (h: Holder, a: unknown): undefined => {
        editor.hold(h, handle(a));
        return undefined;
      },
      setText: (t: string): undefined => {
        editor.setText(t);
        return undefined;
      },
      reveal: (pos: number): undefined => {
        editor.reveal(pos);
        return undefined;
      },
      undo: (): undefined => {
        editor.undo();
        return undefined;
      },
      redo: (): undefined => {
        editor.redo();
        return undefined;
      },
      focus: (): undefined => {
        editor.focus();
        return undefined;
      },
      setTheme: (dark: boolean): undefined => {
        editor.setTheme(dark);
        return undefined;
      },
      showHint: (on: boolean): undefined => {
        editor.showHint(on);
        return undefined;
      },
      onLanguageReady: (fn: () => void): undefined => {
        editor.onLanguageReady(fn);
        return undefined;
      },
    }),
  );

export const boot = (a: App): void => mbt.mmmBoot(a);

/** 1 トランザクション = 1 サイクル。`prev` は前の読み（文書を丸ごと入れ替えたなら null） */
export const cycle = (a: App, prev: Survey | null, treeChanged: boolean): void => mbt.mmmCycle(a, prev, treeChanged);

// ---- 見本（lab）が置くもの ----
//
// 地図の器・右クリックの行・帯の並び・書き出しの並び・お絵描き・たずね・絵・しらせ。
// 作ってもらって置くだけ

declare const layoutBrand: unique symbol;
/** 読みを置いたもの（持ち手）。見本が右クリックの行を引くため */
export interface Layout {
  readonly [layoutBrand]: never;
}

/** 読みを置く。字の実測は core（canvas） */
export const layout = (s: Survey): Layout => Object(mbt.mmmLayout(s));

declare const mapBrand: unique symbol;
/** 地図（持ち手）。置く・描く・入力は core にしか無い */
export interface MapHandle {
  readonly [mapBrand]: never;
}

/** 見本の地図が外に頼るもの。文書は固定で、選択だけ動く */
export interface MapHost {
  survey(): Survey;
  imageUrl(path: string): string | null;
  imageHint(): string | null;
  connectAssets(): void;
  holder(): Holder;
  selection(): Selection;
  setSelection(sel: Selection, reveal: boolean): void;
  picked(): number | null;
  setPicked(id: number | null): void;
  blockText(id: number): string;
  tokens(lines: string[], lang: string): Token[][];
  tokensBlock(text: string): Token[][];
  epoch(): number;
}

/** ペインを地図の器にする */
export const map = (pane: HTMLElement, host: MapHost): MapHandle => Object(mbt.mmmMap(pane, host));
export const mapRender = (m: MapHandle): void => mbt.mmmMapRender(m);
export const mapFit = (m: MapHandle): void => mbt.mmmMapFit(m);
export const mapRefresh = (m: MapHandle): void => mbt.mmmMapRefresh(m);
export const mapBeginEdit = (m: MapHandle, id: number, seed: string | null): boolean =>
  mbt.mmmMapBeginEdit(m, id, seed ?? undefined);
export const mapEditCard = (m: MapHandle, id: number): void => mbt.mmmMapEditCard(m, id);

/** 右クリックの行 */
export const contextMenu = (l: Layout, sel: Selection): HTMLDivElement =>
  div(mbt.mmmContextMenu(l, sel.ids, sel.anchor ?? undefined));

/** 絵の名（Lucide の綴り）。表は core/parts/icons.mbt */
export type IconName = string;

/** その名前の絵。線で引き、色は currentColor */
export const icon = (name: IconName): SVGSVGElement => svgSvg(mbt.mmmIcon(name));

/** 絵の名前の全部 */
export const iconNames = (): IconName[] => [...mbt.mmmIconNames()];

/** しらせの言葉。表は core/parts/notice.mbt */
export type Failed = string;
export type Blocked = string;

/** しらせ 1 つぶん。置くのは呼ぶ側 */
export const notice = (mark: IconName, msg: string, sorry: boolean): HTMLDivElement => div(mbt.mmmNotice(mark, msg, sorry));
export const failedWords = (): Failed[] => [...mbt.mmmFailedWords()];
export const blockedWords = (): Blocked[] => [...mbt.mmmBlockedWords()];

/** 空のときの言い出し。2 つのペインが同じ器を使う（md 側は editor.ts が浮かべる） */
export const paneHint = (pane: "md" | "map"): HTMLDivElement => div(mbt.mmmPaneHint(pane));

export interface Files {
  /** ディスク上の名前。まだ無ければ null */
  savedName: string | null;
  /** 覚えている文書の名前。いま開いているものは含まない */
  recent: string[];
  canOpen: boolean;
  canSave: boolean;
  canRename: boolean;
  canChooseFolder: boolean;
  /** 画像フォルダの状態の一言 */
  folder: string;
}

export interface FileActs {
  newFile(): void;
  open(): void;
  openRecent(index: number): void;
  save(): void;
  saveAs(): void;
  rename(): void;
  chooseFolder(): void;
}

/** Files の行 */
export const filesRows = (state: Files, acts: FileActs): HTMLDivElement => div(mbt.mmmFilesRows(state, acts));

export interface More {
  light: boolean;
  /** 掴みやすさ（Easy grab）が入っているか */
  grab: boolean;
  /** リンクにまつわる押す前の但し書き。届いたら行に付く */
  linkNote: Promise<string[]>;
}

export interface MoreActs {
  undo(): void;
  redo(): void;
  pickColor(): void;
  toggleTheme(): void;
  toggleGrab(): void;
  /** 写せたか。写せたことは押した行の絵が言う */
  copyLink(): Promise<boolean>;
}

/** ⋯ の行 */
export const moreRows = (state: More, acts: MoreActs): HTMLDivElement => div(mbt.mmmMoreRows(state, acts));

/** 出し方の並び。`empty` なら全部沈む */
export const exportWays = (empty: boolean): HTMLDivElement => div(mbt.mmmExportWays(empty));

/** お絵描きの form */
export const drawForm = (): HTMLFormElement => form(mbt.mmmDrawForm());

/** 打てる欄。`check` はその値では進めない理由（進めるなら null）。打つそばから効く */
export interface Field {
  value: string;
  check?: (value: string) => string | null;
}
/** 並べるもの。ただの字か、打てる欄か */
export type Part = string | Field;

/** たずねの中身（form）だけ。並べ方は core/app/asks.mbt */
export const askForm = (kind: "discard" | "place" | "connect" | "rename" | "imageName", args: unknown = null): HTMLFormElement =>
  form(mbt.mmmAskForm(kind, args));

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

/** 出口の数の列。長さが違えば壊れている（タプルは JS では object になるので、数の列で渡す） */
const nums = (v: number[], n: number): number[] => (v.length === n ? v : bad(`数が ${n} 個でない`));

/** enum の形 — `"Tag"`（中身なし）か `["Tag", 中身]`。中身の形は構築子ごとに確かめる */
function tagged(v: unknown): [string, unknown] {
  if (typeof v === "string") return [v, undefined];
  if (!Array.isArray(v) || v.length !== 2) return bad("enum の形でない");
  return [str(v[0]), v[1]];
}

/** 出口の持ち手（無ければ null）。MoonBit の値は中を見ずに持つ */
const handle = <T>(v: unknown): T | null => (v === null || v === undefined ? null : (Object(v) as T));

/** Selection の object（`{ ids, anchor | null }`） */
function selectionOf(v: unknown): Selection {
  const o = record(v);
  return { ids: field(o, "ids", (x) => list(x, num)), anchor: field(o, "anchor", (x) => (x === null ? null : num(x))) };
}

const editOne = (v: unknown): Edit => {
  const o = record(v);
  return { from: field(o, "from", num), to: field(o, "to", num), insert: field(o, "insert", str) };
};

const div = (v: unknown): HTMLDivElement => (v instanceof HTMLDivElement ? v : bad("<div> でない"));
const form = (v: unknown): HTMLFormElement => (v instanceof HTMLFormElement ? v : bad("<form> でない"));
const svgSvg = (v: unknown): SVGSVGElement => (v instanceof SVGSVGElement ? v : bad("<svg> でない"));

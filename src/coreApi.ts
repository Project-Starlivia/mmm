// Typed wrapper around the MoonBit core (compiled to ESM).
// Every mutating call returns a Snapshot; `editSets` are the text edits the
// call applied, in order, each set's offsets relative to the text before it.

import * as mbt from "../core/_build/js/release/build/js/js.js";

export interface EditOp {
  from: number;
  to: number;
  insert: string;
}

/**
 * ノードは、テキストの一区間 `[from, to)` に付けた名前でしかない。
 * 削除・コピー・移動・折り畳みはすべてこの区間に対する編集になる。
 */
export interface NodeInfo {
  id: number;
  /** テキストに書かれている `#` の数 */
  depth: number;
  parent: number;
  /** 区間の始まり = 見出し行の行頭 */
  from: number;
  /** 見出し行の行末（改行の手前）。ラベルを書き換える範囲 */
  headEnd: number;
  /** 区間の終わり = 部分木の終わり */
  to: number;
  hasContent: boolean;
  hidden: boolean;
  /** その枝が属するグループ（木ごとに 0 始まり。境界を 1 つ越えるたび +1） */
  group: number;
  /** ルートの反対側（左）へ伸びる枝か。**枝の中では一定**（core が導出済み） */
  left: boolean;
  label: string;
}

/**
 * フェンスで囲まれたコードブロックの一区間。
 * **どこからどこまでがフェンスかを決めるのはコアだけ**（core/parser.mbt）。
 * 同じ規則を UI 側で書き直すと、`” ```js copy ”` のような情報文字列で
 * 静かに食い違う。
 */
export interface FenceSpan {
  /** 開きフェンス行の行頭 */
  from: number;
  /** 閉じフェンス行の行末（閉じていなければ文書末） */
  to: number;
  /** 中身の最初の行頭 */
  bodyFrom: number;
  /** 中身の最後の行末。中身が無ければ bodyFrom より手前 */
  bodyTo: number;
  /** 開きフェンスの後ろ（言語名など） */
  info: string;
}

export interface Snapshot {
  rev: number;
  focus: number;
  canUndo: boolean;
  canRedo: boolean;
  /** 書き方のモード = 深さ n 以上をリストで書く（0 は全部見出し）。
   *  開いたときに検知され、あとは setListFrom でしか動かない */
  listFrom: number;
  editSets: EditOp[][];
  nodes: NodeInfo[];
  fences: FenceSpan[];
}

/**
 * いまの文書。テキスト・ノード・フェンスは**必ず同じ rev のものを組で**
 * 持ち回る — 片方だけ新しいオフセットで読むと、位置が黙ってずれる。
 */
export interface DocView {
  text: string;
  nodes: NodeInfo[];
  fences: FenceSpan[];
}

// The JSON contract (field names/shapes) is defined by core/api.mbt's
// snapshot(); this cast is the single trust boundary.
const snap = (s: string): Snapshot => JSON.parse(s);

export const core = {
  initDoc: (text: string): Snapshot => snap(mbt.initDoc(text)),
  /** 書き方のモードを変える。テキストは触らない（揃えるのは reformat） */
  setListFrom: (b: number): Snapshot => snap(mbt.setListFrom(b)),
  /** 文書ぜんぶをいまのモードの正規形へ（構造行の接頭辞だけ）。undo 1 回 */
  reformat: (tag = ""): Snapshot => snap(mbt.reformat(tag)),
  /**
   * そのノードの本文の末尾へ 1 行を追加する。**貼り付け・ドロップ・
   * お絵描き・その場でのリンクが通る唯一の道**。リストの形で書かれた
   * ノードなら、その項目の中身の列まで字下げする（TS 側で組むと、外の
   * Markdown パーサがそこでリストを閉じ、続く兄弟が迷子になる）。
   */
  insertContent: (id: number, line: string, tag = ""): Snapshot =>
    snap(mbt.insertContent(id, line, tag)),
  /**
   * 深さ `depth` の新しい構造行（見出しかリスト項目か）を、いまの文書の
   * モードで 1 行ぶん書く。ラベルは正規化する。
   */
  formatLine: (depth: number, label: string): string =>
    mbt.formatLine(depth, label),
  getText: (): string => mbt.getText(),
  replaceText: (from: number, to: number, insert: string, tag = ""): Snapshot =>
    snap(mbt.replaceText(from, to, insert, tag)),
  addChild: (id: number, tag = ""): Snapshot => snap(mbt.addChild(id, tag)),
  addSibling: (id: number, tag = ""): Snapshot => snap(mbt.addSibling(id, tag)),
  addSiblingBefore: (id: number, tag = ""): Snapshot =>
    snap(mbt.addSiblingBefore(id, tag)),
  addParent: (id: number, tag = ""): Snapshot => snap(mbt.addParent(id, tag)),
  addRoot: (tag = ""): Snapshot => snap(mbt.addRoot(tag)),
  renameNode: (id: number, label: string, tag = ""): Snapshot =>
    snap(mbt.renameNode(id, label, tag)),
  deleteNodes: (ids: number[]): Snapshot => snap(mbt.deleteNodes(ids)),
  indentNodes: (ids: number[]): Snapshot => snap(mbt.indentNodes(ids)),
  outdentNodes: (ids: number[]): Snapshot => snap(mbt.outdentNodes(ids)),
  /** pos: 0 = target の子にする / 1 = target の直前へ挿入 / 2 = target の直後へ挿入 */
  moveNodes: (ids: number[], target: number, pos: 0 | 1 | 2): Snapshot =>
    snap(mbt.moveNodes(ids, target, pos)),
  /** A→B の線への割り込み: ids を B の直前へ動かしてから B を 1 段下げる */
  moveAsParent: (ids: number[], target: number): Snapshot =>
    snap(mbt.moveAsParent(ids, target)),
  reorderNode: (id: number, dir: -1 | 1): Snapshot =>
    snap(mbt.reorderNode(id, dir)),
  toggleHidden: (id: number): Snapshot => snap(mbt.toggleHidden(id)),
  undo: (): Snapshot => snap(mbt.undo()),
  redo: (): Snapshot => snap(mbt.redo()),
  selectionText: (ids: number[]): string => mbt.selectionText(ids),
  /** 断片に（フェンスの外の）見出しがあるか。いまの文書には触らない */
  hasHeadings: (text: string): boolean => mbt.hasHeadings(text),
  /** 断片のいちばん浅い見出しが targetDepth になるようずらす */
  relevelText: (text: string, targetDepth: number): string =>
    mbt.relevelText(text, targetDepth),
};

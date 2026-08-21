// Typed wrapper around the MoonBit core (compiled to ESM).
// Every mutating call returns a Snapshot; `editSets` are the text edits the
// call applied, in order, each set's offsets relative to the text before it.

import * as mbt from "../core/_build/js/release/build/js/js.js";

export interface EditOp {
  from: number;
  to: number;
  insert: string;
}

export interface NodeInfo {
  id: number;
  /** 構造上の深さ（`---` の後ろでは読み替えられる） */
  depth: number;
  /** テキストに書かれている `#` の数。見出しを組み立てるときはこちら */
  rawDepth: number;
  parent: number;
  hs: number;
  he: number;
  subEnd: number;
  group: number;
  hasContent: boolean;
  hidden: boolean;
  label: string;
}

export interface Snapshot {
  rev: number;
  focus: number;
  canUndo: boolean;
  canRedo: boolean;
  editSets: EditOp[][];
  nodes: NodeInfo[];
}

// The JSON contract (field names/shapes) is defined by core/api.mbt's
// snapshot(); this cast is the single trust boundary.
const snap = (s: string): Snapshot => JSON.parse(s);

export const core = {
  initDoc: (text: string): Snapshot => snap(mbt.initDoc(text)),
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
  /**
   * 側の末尾へ動かす（ルート脇ゾーンへのドロップ）。
   * 左側が空のときだけ `---` を 1 本書く — 区切りが増える唯一の経路。
   */
  moveSideEnd: (ids: number[], left: boolean): Snapshot =>
    snap(mbt.moveSideEnd(ids, left)),
  /** 側の末尾に新しい子を作る（ルートの左右 ＋ ボタン） */
  addSideEnd: (left: boolean, tag = ""): Snapshot =>
    snap(mbt.addSideEnd(left, tag)),
  reorderNode: (id: number, dir: -1 | 1): Snapshot =>
    snap(mbt.reorderNode(id, dir)),
  toggleHidden: (id: number): Snapshot => snap(mbt.toggleHidden(id)),
  undo: (): Snapshot => snap(mbt.undo()),
  redo: (): Snapshot => snap(mbt.redo()),
  selectionText: (ids: number[]): string => mbt.selectionText(ids),
};

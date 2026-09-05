// 地図のキー → 何をするか。DOM も host も知らない表。地図は返った Intent を
// 実行するだけで、段が進めばここに行を足す。
// 決めは docs/superpowers/specs/2026-09-04-label-design.md と shortcuts.md「Mindmap」。

import * as core from "../coreApi.ts";
import { type Layout, ownerOf } from "./layout.ts";
import { NONE, type Selection, all, arrow, extend, isArrowKey, neighbor, nextSibling, parentOf, prevSibling, solo } from "./select.ts";

/** 押されたキー。mod は Ctrl / Cmd のどちらか */
export interface Key {
  key: string;
  shift: boolean;
  mod: boolean;
  alt: boolean;
}

/** 何をするか */
export type Intent =
  /** 操作を md に映す。edit なら focus をそのまま編集開始。keep は消した後に
   *  選び直す隣 — 編集の前に選んでおけば、目印がそれを追いかける */
  | { kind: "op"; op: core.Op; edit: boolean; keep?: number }
  /** その場編集に入る。seed は最初の字（空のノードで打ち始めたとき） */
  | { kind: "edit"; id: number; seed: string | null }
  | { kind: "select"; sel: Selection; reveal: boolean }
  /** 選択（無ければ根）を画面の中心へ */
  | { kind: "center" }
  /** カードを選ぶ（null で外す） */
  | { kind: "pick"; id: number | null }
  /** カードをその場で直す */
  | { kind: "editCard"; id: number }
  /** クリップボードの URL をリンクカードにして題を打つ / 空のコードを足して打つ / 描いて貼る（mindmap.ts の act が実行） */
  | { kind: "link"; id: number }
  | { kind: "code"; id: number }
  | { kind: "draw"; id: number }
  /** クリップボードを貼る。anchor があればそこへ、無ければ文書へ（main.ts の act が実行） */
  | { kind: "paste" }
  /** 選んでいるもの（カードならその原文、でなければ選択の部分木）をクリップボードへ写す。
   *  cut は写せてから消すもの（Delete と同じ Intent）。写せなければ消さない */
  | { kind: "copy"; cut: Intent | null };

const op = (o: core.Op): Intent => ({ kind: "op", op: o, edit: true });

/** 空のラベルで足す。読めば label "" になり、そのまま打ち始める */
const add = (at: core.NodePlace): Intent => op({ kind: "addNode", at, labels: [""] });

/** 選択を消して、隣を keep する（Delete と Mod+X が同じものを使う） */
function remove(L: Layout, sel: Selection): Intent | null {
  if (sel.ids.length === 0) return null;
  const keep = neighbor(L, sel.ids);
  const o: Intent = { kind: "op", op: { kind: "delete", ids: sel.ids }, edit: false };
  return keep === null ? o : { ...o, keep };
}

/** Mod+C / Mod+X。写すものが無ければ null。cut は消すもの（無ければ Mod+X も拾わない） */
function copied(k: Key, cut: () => Intent | null): Intent | null {
  if (!k.mod || k.alt || k.shift) return null;
  const key = k.key.toLowerCase();
  if (key === "c") return { kind: "copy", cut: null };
  if (key !== "x") return null;
  const c = cut();
  return c === null ? null : { kind: "copy", cut: c };
}

/**
 * キー 1 回ぶん。null は拾わない（ブラウザに渡す）。
 *
 * - **宛先は anchor。** いくつ選んでいても同じ（複数選択で Enter を押しても、anchor に
 *   対する Enter と同じことが起きる）
 * - 名前がまだ無いノード（label が ""）では「足す」より「埋める」が先: Enter は
 *   そのノードの編集に入り、字を打てばその字から書ける（Enter を挟まない）
 * - ノードが 1 つも無ければ、Enter は最初の根
 * - Tab / Shift+Tab は 1 つなら足す・包む、複数なら段下げ・上げ（先頭の前の兄弟の子へ / 先頭の親の後ろへ）
 */
export function keyed(L: Layout, sel: Selection, k: Key): Intent | null {
  // Alt が意味を持つのは Alt+↑↓（並べ替え）だけ。それ以外の Alt の組は拾わない。
  // ここで先に他のキーだけ弾く — Alt+↑↓ 自身の判断は後ろの専用の行に任せる
  // （Alt を真っ先に全部捨てると、並べ替えが書けなくなる）
  if (k.alt && k.key !== "ArrowUp" && k.key !== "ArrowDown") return null;
  // anchor が無くても拾う（貼る先が無ければ文書へ）。anchor 頼みの行より先に置く
  if (k.mod && !k.alt && !k.shift && k.key.toLowerCase() === "v") return { kind: "paste" };
  if (sel.ids.length > 0) {
    const c = copied(k, () => remove(L, sel));
    if (c !== null) return c;
  }
  const anchor = sel.anchor;
  const label = anchor === null ? null : (L.boxes.get(anchor)?.node.label ?? null);
  const blank = label === "";
  if (k.shift && !k.mod && !k.alt && (k.key === "L" || k.key === "C" || k.key === "D")) {
    const id = solo(sel);
    if (id === null) return null;
    return k.key === "L" ? { kind: "link", id } : k.key === "C" ? { kind: "code", id } : { kind: "draw", id };
  }
  if (k.key === "Enter") {
    if (L.order.length === 0) return add({ kind: "in", node: core.DOC_ID, side: null });
    if (anchor === null) return null;
    if (k.mod) return { kind: "edit", id: anchor, seed: null };
    if (k.shift) return add({ kind: "before", node: anchor });
    if (blank) return { kind: "edit", id: anchor, seed: null };
    return add({ kind: "after", node: anchor });
  }
  if (k.key === "Tab" && !k.mod) {
    const id = solo(sel);
    if (id !== null) {
      return k.shift ? op({ kind: "wrap", id, label: "" }) : add({ kind: "in", node: id, side: null });
    }
    if (sel.ids.length < 2) return null;
    const first = sel.ids[0];
    if (k.shift) {
      const p = parentOf(L, first);
      return p === null ? null : { kind: "op", op: { kind: "moveNode", ids: sel.ids, at: { kind: "after", node: p } }, edit: false };
    }
    const prev = prevSibling(L, first);
    return prev === null
      ? null
      : { kind: "op", op: { kind: "moveNode", ids: sel.ids, at: { kind: "in", node: prev, side: null } }, edit: false };
  }
  if ((k.key === "Delete" || k.key === "Backspace") && !k.mod) return remove(L, sel);
  if (k.alt && (k.key === "ArrowUp" || k.key === "ArrowDown") && !k.mod) {
    if (sel.ids.length === 0) return null;
    const first = sel.ids[0];
    const last = sel.ids[sel.ids.length - 1];
    const move = (at: core.NodePlace): Intent => ({ kind: "op", op: { kind: "moveNode", ids: sel.ids, at }, edit: false });
    if (k.key === "ArrowUp") {
      const p = prevSibling(L, first);
      return p === null ? null : move({ kind: "before", node: p });
    }
    const n = nextSibling(L, last);
    return n === null ? null : move({ kind: "after", node: n });
  }
  if (k.alt) return null;
  if (k.key === "H" && k.shift && !k.mod) {
    if (anchor === null) return null;
    const node = L.boxes.get(anchor)?.node ?? null;
    if (node === null || node.label === null) return null;
    return node.fold !== null
      ? { kind: "op", op: { kind: "unfold", id: anchor }, edit: false }
      : { kind: "op", op: { kind: "fold", id: anchor, open: false }, edit: false };
  }
  if (k.key === "Escape") return { kind: "select", sel: NONE, reveal: false };
  if (k.key === "Home" && !k.mod) return { kind: "center" };
  if (k.mod && k.key.toLowerCase() === "a") return { kind: "select", sel: all(L), reveal: false };
  if (isArrowKey(k.key) && !k.mod) {
    const next = arrow(L, sel.anchor, k.key);
    if (next === null) return null;
    return { kind: "select", sel: k.shift ? extend(sel, next) : { ids: [next], anchor: next }, reveal: true };
  }
  // 名前が無いなら、打ち始めればそのまま書ける。字は e.key のまま（CapsLock の
  // 正規化を通さない）。Space はパンに使うので除く
  if (blank && anchor !== null && !k.mod && k.key.length === 1 && k.key !== " ") {
    return { kind: "edit", id: anchor, seed: k.key };
  }
  return null;
}

/**
 * カードを選んでいるときの表。持ち主は `node.blocks` に `picked` が居るノード、
 * 隣はその `blocks` を文書順（= 配列順）に見た前後。持ち主が見つからなければ
 * （箱が無い = 畳まれて埋もれた）null。
 */
export function keyedCard(L: Layout, picked: number, k: Key): Intent | null {
  // 外すのに持ち主は要らない（畳まれて箱が無くても、ここから抜けられる）
  if (k.key === "Escape") return { kind: "pick", id: null };
  const o = ownerOf(L, picked);
  if (o === null) return null;
  const owner = o.box.node;
  const blocks = owner.blocks;
  const index = o.index;
  // 消した後に持ち主を選ぶのは core の focus（持ち主ごと書き直されるので目印は追えない）
  const remove: Intent = { kind: "op", op: { kind: "delete", ids: [picked] }, edit: false };
  if ((k.key === "Delete" || k.key === "Backspace") && !k.mod) return remove;
  const c = copied(k, () => remove);
  if (c !== null) return c;
  if ((k.key === "ArrowDown" || k.key === "ArrowUp") && !k.mod && !k.alt) {
    const next = k.key === "ArrowDown" ? blocks[index + 1] : blocks[index - 1];
    return next === undefined ? null : { kind: "pick", id: next.id };
  }
  if (k.key === "ArrowLeft" && !k.mod) {
    return { kind: "select", sel: { ids: [owner.id], anchor: owner.id }, reveal: false };
  }
  if (k.alt && (k.key === "ArrowUp" || k.key === "ArrowDown") && !k.mod) {
    const move = (at: core.BlockPlace): Intent => ({ kind: "op", op: { kind: "moveBlock", ids: [picked], at }, edit: false });
    if (k.key === "ArrowUp") {
      const prev = blocks[index - 1];
      return prev === undefined ? null : move({ kind: "before", block: prev.id });
    }
    const next = blocks[index + 1];
    return next === undefined ? null : move({ kind: "after", block: next.id });
  }
  if (k.mod && k.key === "Enter") return { kind: "editCard", id: picked };
  return null;
}

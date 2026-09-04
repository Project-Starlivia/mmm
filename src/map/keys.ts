// 地図のキー → 何をするか。DOM も host も知らない表。地図は返った Intent を
// 実行するだけで、段が進めばここに行を足す。
// 決めは docs/superpowers/specs/2026-09-04-label-design.md と shortcuts.md「Mindmap」。

import * as core from "../coreApi.ts";
import type { Layout } from "./layout.ts";
import { NONE, type Selection, all, arrow, extend, isArrowKey } from "./select.ts";

/** 押されたキー。mod は Ctrl / Cmd のどちらか */
export interface Key {
  key: string;
  shift: boolean;
  mod: boolean;
  alt: boolean;
}

/** 何をするか */
export type Intent =
  /** 操作を md に映す。edit なら focus をそのまま編集開始 */
  | { kind: "op"; op: core.Op; edit: boolean }
  /** その場編集に入る。seed は最初の字（空のノードで打ち始めたとき） */
  | { kind: "edit"; id: number; seed: string | null }
  | { kind: "select"; sel: Selection; reveal: boolean }
  /** 選択（無ければ根）を画面の中心へ */
  | { kind: "center" };

const op = (o: core.Op): Intent => ({ kind: "op", op: o, edit: true });

/** 空のラベルで足す。読めば label "" になり、そのまま打ち始める */
const add = (at: core.NodePlace): Intent => op({ kind: "addNode", at, labels: [""] });

/** ちょうど 1 つ選んでいる id。宛先が 1 つに決まる操作はこれを見る */
const solo = (sel: Selection): number | null =>
  sel.ids.length === 1 && sel.anchor !== null ? sel.anchor : null;

/**
 * キー 1 回ぶん。null は拾わない（ブラウザに渡す）。
 *
 * - **宛先は anchor。** いくつ選んでいても同じ（複数選択で Enter を押しても、anchor に
 *   対する Enter と同じことが起きる）
 * - 名前がまだ無いノード（label が ""）では「足す」より「埋める」が先: Enter は
 *   そのノードの編集に入り、字を打てばその字から書ける（Enter を挟まない）
 * - ノードが 1 つも無ければ、Enter は最初の根
 * - Tab / Shift+Tab だけは複数選んでいると段下げ・上げ（次の段）に化けるので、いまは拾わない
 */
export function keyed(L: Layout, sel: Selection, k: Key): Intent | null {
  if (k.alt) return null;
  const anchor = sel.anchor;
  const label = anchor === null ? null : (L.boxes.get(anchor)?.node.label ?? null);
  const blank = label === "";
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
    if (id === null) return null;
    return k.shift ? op({ kind: "wrap", id, label: "" }) : add({ kind: "in", node: id, side: null });
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

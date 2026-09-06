// 選択の**値**。何を選んでいるか — ノードの並びかカード 1 枚か。
// 入力でどう変わるか（クリック・矩形・矢印・当たり）は core/map/select.mbt が持ち、
// ts は `core.click` / `core.rubber` / `core.keyed` に聞いて、返った値を持つだけ。
// 決めは docs/superpowers/specs/2026-09-04-select-design.md と spec.md「Mindmap 側」。

import type * as core from "../coreApi.ts";

export const NONE: core.Selection = { ids: [], anchor: null };

/** 何を選んでいるか — ノードの並びか、カード 1 枚か。片方だけ（spec.md「C カード」） */
export type Choice = { kind: "nodes"; sel: core.Selection } | { kind: "card"; id: number };

export const NOTHING: Choice = { kind: "nodes", sel: NONE };

/** ノードの選択として見る。カードを選んでいれば空 */
export const nodesOf = (c: Choice): core.Selection => (c.kind === "nodes" ? c.sel : NONE);

/** カードの選択として見る。ノードを選んでいれば null */
export const cardOf = (c: Choice): number | null => (c.kind === "card" ? c.id : null);

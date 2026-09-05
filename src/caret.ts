// md のカーソル、または地図の選択の位置が、どのノード（かカード）に掛かっているか。
// DOM も文書の意味も知らない、区間の重なりだけの層。選択の規則はここにしか無い。
//
// 自身の文 = 地番の頭から最初の子の頭まで（中身は子より前に書かれる）。地番は
// 入れ子なので、これで「最も深いノード」が出る。子孫まで含む `to` で見ると、
// カーソル 1 つでも根までの祖先が全部光り、選択と見分けが付かない（spec.md
// 「選択の持ち主」）。

import type * as core from "./coreApi.ts";
import { type Choice, NOTHING } from "./map/select.ts";

/** md 側のカーソル 1 つ、または選択 1 つぶん（`from === to` なら点） */
export interface Range {
  from: number;
  to: number;
}

/** md のカーソルぜんぶ。head は主カーソルの頭（anchor になる） */
export interface Caret {
  ranges: Range[];
  head: number;
}

/** 選択を持っている側。フォーカスが最後に入ったペイン */
export type Holder = "md" | "map";

/** 地図の選択の位置。ノードはラベルの頭、カードは中身の原文の頭。CodeMirror が編集で写す */
export type Anchors =
  | { kind: "nodes"; at: number[]; anchor: number | null }
  | { kind: "card"; at: number }
  | null;

/** ノードの自身の文 `[from, to)`。Implicit は空なので入らない */
interface Own {
  id: number;
  from: number;
  to: number;
}

function owns(view: core.View, spots: Map<number, core.Spot>): Own[] {
  const out: Own[] = [];
  const walk = (n: core.Node): void => {
    const s = spots.get(n.id);
    if (s) {
      const first = n.children.length > 0 ? spots.get(n.children[0].id) : undefined;
      const to = first ? first.from : s.to;
      if (to > s.from) out.push({ id: n.id, from: s.from, to });
    }
    for (const k of n.children) walk(k);
  };
  for (const t of view.roots) walk(t.node);
  return out;
}

/**
 * 1 つの範囲に掛かる自身の文。**閉じ際は中と見なす** — 区間は半開だが、カーソルは
 * その位置に立てる。半開で読むと文書の末尾では何にも掛からず、追記しているあいだ
 * 印が出ない。**点が継ぎ目ちょうどなら始まる側 1 つ** — 両側を返すと、地図へ移った
 * 直後の Delete が 2 つ消す。範囲なら掛かる全部
 */
function hits(all: Own[], r: Range): Own[] {
  const on = all.filter((o) => o.from <= r.to && o.to >= r.from);
  if (r.from !== r.to) return on;
  const starting = on.filter((o) => o.from === r.from);
  return starting.length > 0 ? starting : on;
}

/** その範囲たちが掛かるノードの id、文書順。無ければ空 */
export function caretIds(view: core.View, spots: Map<number, core.Spot>, ranges: Range[]): number[] {
  if (ranges.length === 0) return [];
  const all = owns(view, spots);
  const picked = new Set<number>();
  for (const r of ranges) for (const o of hits(all, r)) picked.add(o.id);
  return all.filter((o) => picked.has(o.id)).map((o) => o.id);
}

/** 畳まれて埋もれたノード（fold のあるノードの子孫）。箱を持たないので選択に居られない */
export function buried(view: core.View): Set<number> {
  const out = new Set<number>();
  const walk = (n: core.Node, under: boolean): void => {
    if (under) out.add(n.id);
    for (const k of n.children) walk(k, under || n.fold !== null);
  };
  for (const t of view.roots) walk(t.node, false);
  return out;
}

/** その位置を原文に含む中身の id。持ち主が埋もれていれば無い */
function blockAt(view: core.View, spots: Map<number, core.Spot>, p: number, gone: Set<number>): number | null {
  let found: number | null = null;
  const walk = (n: core.Node): void => {
    if (!gone.has(n.id)) {
      for (const b of n.blocks) {
        const s = spots.get(b.id);
        if (s && s.from <= p && p < s.to) found = b.id;
      }
    }
    for (const k of n.children) walk(k);
  };
  for (const t of view.roots) walk(t.node);
  return found;
}

/**
 * 選択。**持ち主が決める** — md が持つ間はカーソルから、地図が持つ間は位置から。
 * 選択に居るのは箱のあるものだけ（埋もれたノードは落とす）。anchor が落ちれば末尾
 */
export function derive(
  view: core.View,
  spots: Map<number, core.Spot>,
  holder: Holder,
  caret: Caret,
  anchors: Anchors,
): Choice {
  const gone = buried(view);
  const point = (p: number): number | null => caretIds(view, spots, [{ from: p, to: p }])[0] ?? null;
  const nodes = (ids: number[], anchor: number | null): Choice => {
    const kept = [...new Set(ids)].filter((id) => !gone.has(id)).sort((a, b) => a - b);
    const a = anchor !== null && kept.includes(anchor) ? anchor : (kept.at(-1) ?? null);
    return { kind: "nodes", sel: { ids: kept, anchor: a } };
  };
  if (holder === "md") return nodes(caretIds(view, spots, caret.ranges), point(caret.head));
  if (anchors === null) return NOTHING;
  if (anchors.kind === "card") {
    const id = blockAt(view, spots, anchors.at, gone);
    return id === null ? NOTHING : { kind: "card", id };
  }
  const ids = anchors.at.flatMap((p) => {
    const id = point(p);
    return id === null ? [] : [id];
  });
  return nodes(ids, anchors.anchor === null ? null : point(anchors.anchor));
}

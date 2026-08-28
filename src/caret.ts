// md のカーソル（と選択）が、いまどのノードに掛かっているか。DOM も文書の
// 意味も知らない、区間の重なりだけの層。
//
// ノードは [from, to) の区間で、入れ子はそのまま区間の入れ子になる。区間は
// コアが渡してくるものをそのまま読む — どこからどこまでが 1 ノードかを
// ここで数え直さない。

import type { NodeInfo } from "./coreApi.ts";

/** md 側のカーソル 1 つ、または選択 1 つぶん（`from === to` なら点）。 */
export interface Span {
  from: number;
  to: number;
}

/**
 * その範囲たちに**重なる**ノードの id を、文書順で。掛かるものが無ければ空。
 *
 * **重なっていれば全部挙げる。** ノードの区間は子孫をまるごと含むので、
 * 点 1 つでもルートからそのノードまでの道筋が揃って挙がる — マップの上では
 * 「いま木のどのあたりに居るか」が枝ごと見えることになる。
 *
 * **端は両側とも閉じて見る。** 区間そのものは `[from, to)` だが、カーソルは
 * その位置に**立てる**（文字と文字の隙間に居る）。半開で読むと文書の末尾では
 * 全部の区間が閉じきっていて何も挙がらず、追記しているあいだじゅう印が
 * 出ない、といういちばん困る形になる。
 *
 * 範囲が複数あるのは、md 側の複数カーソル（`Alt+クリック`）。
 */
export function caretNodes(nodes: NodeInfo[], spans: readonly Span[]): number[] {
  if (spans.length === 0) return [];
  const out: number[] = [];
  for (const n of nodes) {
    if (spans.some((s) => n.from <= s.to && n.to >= s.from)) out.push(n.id);
  }
  return out;
}

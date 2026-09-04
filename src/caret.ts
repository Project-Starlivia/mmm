// md のカーソル（と選択）が、いまどのノードに掛かっているか。DOM も文書の意味も
// 知らない、区間の重なりだけの層。
//
// 自身の文 = 地番の頭から最初の子の頭まで（中身は子より前に書かれる）。地番は
// 入れ子なので、これで「最も深いノード」が出る。子孫まで含む `to` で見ると、
// カーソル 1 つでも根までの祖先が全部光り、選択と見分けが付かない（spec.md
// 「二つをまたぐ印」）。

import type { Node, Spot, View } from "./coreApi.ts";

/** md 側のカーソル 1 つ、または選択 1 つぶん（`from === to` なら点） */
export interface Range {
  from: number;
  to: number;
}

/**
 * その範囲たちが掛かるノードの id、文書順。無ければ空。
 *
 * **閉じ際は中と見なす。** 区間は半開だが、カーソルはその位置に立てる（文字と文字の
 * 隙間に居る）。半開で読むと文書の末尾では何にも掛からず、追記しているあいだ印が
 * 出ない。裏返しとして、継ぎ目ちょうどでは両側が挙がる。
 * Implicit は行が無く自身の文が空なので、掛からない。
 */
export function caretIds(view: View, spots: Map<number, Spot>, ranges: Range[]): number[] {
  if (ranges.length === 0) return [];
  const out: number[] = [];
  const walk = (n: Node): void => {
    const s = spots.get(n.id);
    if (s) {
      const first = n.children.length > 0 ? spots.get(n.children[0].id) : undefined;
      const own = first ? first.from : s.to;
      if (own > s.from && ranges.some((r) => s.from <= r.to && own >= r.from)) out.push(n.id);
    }
    for (const k of n.children) walk(k);
  };
  for (const t of view.trees) walk(t.node);
  return out;
}

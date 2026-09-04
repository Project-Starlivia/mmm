// 写す（Mod+C / Mod+X）。選んだ部分木の原文を地番で切り出す。paste.ts の対で、
// 貼る側の graft が断片を parse して木として差すので、深さの付け直しはしない。

import type * as core from "../coreApi.ts";

/**
 * 選んだノードの原文を文書順に空行で継ぐ。地番の範囲は部分木を丸ごと覆う
 * （子の中身まで）ので、選んだ祖先の中の子孫には降りない（core の Delete /
 * MoveNode と同じ決め）。末尾は改行 1 つ。何も選んでいなければ空
 */
export function copyText(md: string, view: core.View, spots: Map<number, core.Spot>, ids: number[]): string {
  const chosen = new Set(ids);
  const parts: string[] = [];
  const walk = (n: core.Node): void => {
    const s = chosen.has(n.id) ? spots.get(n.id) : undefined;
    if (s !== undefined) {
      parts.push(md.slice(s.from, s.to).replace(/[\r\n]+$/, ""));
      return;
    }
    for (const c of n.children) walk(c);
  };
  for (const t of view.trees) walk(t.node);
  return parts.length === 0 ? "" : `${parts.join("\n\n")}\n`;
}

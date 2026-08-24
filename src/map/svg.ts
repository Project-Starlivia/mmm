// SVG の要素を作る最小の道具。描画（mindmap.ts）と書き出し（toSvg.ts）が
// 同じものを使う — 同じ 5 行を 2 箇所に置かない。

export const SVG_NS = "http://www.w3.org/2000/svg";

export function svgEl<K extends keyof SVGElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
): SVGElementTagNameMap[K] {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  return el;
}

// SVG の要素を作る最小の道具。描画（mindmap.ts）と書き出し（toSvg.ts）が
// 同じものを使う — 同じ 5 行を 2 箇所に置かない。

export const SVG_NS = "http://www.w3.org/2000/svg";

/**
 * 属性の値は数でも文字でもよい。**SVG の属性はほとんどが数**なので、
 * 呼ぶ側に `String(...)` を書かせると、意味を持たない皮が全体で 44 か所ぶん
 * 積もる。文字にするのは setAttribute に渡す 1 行だけの仕事。
 */
export function svgEl<K extends keyof SVGElementTagNameMap>(
  tag: K,
  attrs: Record<string, string | number> = {},
): SVGElementTagNameMap[K] {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v));
  return el;
}

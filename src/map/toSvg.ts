// マップを 1 枚の <svg> にする。画面の DOM から、一時的な UI 状態
// （選択・ドロップ印）を取り除き、計算済みスタイルを属性に焼き込むので、
// この結果だけで単体表示できる。

import type { Rect } from "./geometry.ts";
import { SVG_NS, svgEl } from "./svg.ts";

export async function mapToSvg(args: {
  boxes: Iterable<Rect>;
  edgeLayer: SVGGElement;
  nodeLayer: SVGGElement;
  pane: HTMLElement;
}): Promise<SVGSVGElement | null> {
  const boxes = [...args.boxes];
  const first = boxes[0];
  if (first === undefined) return null;
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const b of boxes) {
    x0 = Math.min(x0, b.x);
    y0 = Math.min(y0, b.y);
    x1 = Math.max(x1, b.x + b.w);
    y1 = Math.max(y1, b.y + b.h);
  }
  const M = 24;
  const w = Math.ceil(x1 - x0 + M * 2);
  const h = Math.ceil(y1 - y0 + M * 2);
  // export without transient UI state (selection, drop highlights)
  const stripped: Array<{ el: Element; cls: string }> = [];
  // `.drop-edge` はエッジ側に付くので、ノード層だけ見ても外れない
  for (const el of [
    ...args.nodeLayer.querySelectorAll(
      ".selected, .drop-child, .drop-parent, .dragging",
    ),
    ...args.edgeLayer.querySelectorAll(".drop-edge"),
  ]) {
    stripped.push({ el, cls: el.getAttribute("class") ?? "" });
    el.classList.remove(
      "selected",
      "drop-child",
      "drop-parent",
      "drop-edge",
      "dragging",
    );
  }
  // cloneNode は Node しか名乗らないので、複製が同じものであることを確かめる
  const edges = args.edgeLayer.cloneNode(true);
  const nodesG = args.nodeLayer.cloneNode(true);
  if (!(edges instanceof SVGGElement) || !(nodesG instanceof SVGGElement)) {
    return null;
  }
  const PROPS = [
    "fill",
    "stroke",
    "stroke-width",
    "stroke-dasharray",
    "stroke-linecap",
    "font-family",
    "font-size",
    "font-weight",
    "opacity",
    "dominant-baseline",
    "text-anchor",
  ];
  const inline = (orig: Element, copy: Element): void => {
    if (orig.tagName !== "title") {
      const cs = getComputedStyle(orig);
      for (const p of PROPS) {
        const v = cs.getPropertyValue(p);
        if (v !== "") copy.setAttribute(p, v);
      }
      copy.removeAttribute("class");
    }
    for (let i = 0; i < orig.children.length; i++) {
      inline(orig.children[i], copy.children[i]);
    }
  };
  // カードの選択枠と × は、ノードの中ではなく world に浮かぶ別の印なので、
  // ここで写す 2 層（エッジ / ノード）には最初から入っていない
  inline(args.edgeLayer, edges);
  inline(args.nodeLayer, nodesG);
  for (const s of stripped) s.el.setAttribute("class", s.cls);
  // blob: thumbnails don't resolve outside this page — embed them.
  // 各画像の fetch→blob→dataURL は互いに独立なので並列に待つ
  // （直列だと画像 N 枚で N 倍待たされていた）
  await Promise.all(
    [...nodesG.querySelectorAll("image")].map(async (img) => {
      const href = img.getAttribute("href") ?? "";
      if (!href.startsWith("blob:")) return;
      try {
        const b = await (await fetch(href)).blob();
        const dataUrl = await new Promise<string>((resolve, reject) => {
          const fr = new FileReader();
          // readAsDataURL の結果は文字列だが、型は union のまま。確かめる
          fr.onload = () =>
            typeof fr.result === "string"
              ? resolve(fr.result)
              : reject(new Error("data URL にならなかった"));
          fr.onerror = () => reject(fr.error);
          fr.readAsDataURL(b);
        });
        img.setAttribute("href", dataUrl);
      } catch {
        img.remove(); // unreadable thumb: leave the spot empty
      }
    }),
  );
  const out = svgEl("svg", {
    xmlns: SVG_NS,
    viewBox: `${x0 - M} ${y0 - M} ${w} ${h}`,
    width: String(w),
    height: String(h),
  });
  const bgColor = getComputedStyle(args.pane).backgroundColor;
  out.append(
    svgEl("rect", {
      x: String(x0 - M),
      y: String(y0 - M),
      width: String(w),
      height: String(h),
      fill: bgColor,
    }),
    edges,
    nodesG,
  );
  return out;
}

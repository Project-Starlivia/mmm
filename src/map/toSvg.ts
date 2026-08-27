// マップを 1 枚の <svg> にする。画面の DOM から、一時的な UI 状態
// （選択・ドロップ印）を取り除き、計算済みスタイルを属性に焼き込むので、
// この結果だけで単体表示できる。
//
// **写すものは呼ぶ側が選ぶ。** 層をまるごと写していた頃は「全体」しか
// 出せなかったが、枝だけを書き出したいときにここが決められることは無い
// （どれが選ばれているかを知っているのはマップ側）。

import type { Rect } from "./geometry.ts";
import { SVG_NS, svgEl } from "./svg.ts";

export async function mapToSvg(args: {
  /** 収める範囲。写すノードの箱をそのまま渡す */
  boxes: Iterable<Rect>;
  /** 写す親子の線。枝の外へ出ていくものは呼ぶ側が外しておく */
  edges: Iterable<SVGPathElement>;
  /** 枝ではないが写したい線（グループの継ぎ目）。全体の書き出しのときだけ */
  marks?: Iterable<SVGElement>;
  /** 写すノード */
  nodes: Iterable<SVGGElement>;
  /** 地の色をここから読む */
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
  // Iterable は 1 度しか回せないことがあるので、先に確定させる
  const edgeEls = [...args.edges];
  const markEls = [...(args.marks ?? [])];
  const nodeEls = [...args.nodes];
  // いまの操作の状態（選択・ドロップの印）は書き出さない。
  // **計算済みスタイルは元の要素から読む**ので、写す前に画面側から外す
  const stripped: Array<{ el: Element; cls: string }> = [];
  const TRANSIENT = [
    "selected",
    "drop-child",
    "drop-parent",
    "drop-edge",
    "dragging",
  ];
  for (const root of [...edgeEls, ...nodeEls]) {
    for (const el of [root, ...root.querySelectorAll(`.${TRANSIENT.join(",.")}`)]) {
      if (!TRANSIENT.some((c) => el.classList.contains(c))) continue;
      stripped.push({ el, cls: el.getAttribute("class") ?? "" });
      el.classList.remove(...TRANSIENT);
    }
  }
  const edges = svgEl("g");
  const nodesG = svgEl("g");
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
  // 呼ぶ側が渡してくるエッジ / ノードには最初から入っていない
  // 継ぎ目は親子の線と同じ「そのまま写す」経路（PROPS の焼き込み）を通す。
  // 意味は違っても、扱い方は edges 側と同じなので同じ器に入れる
  for (const orig of [...markEls, ...edgeEls]) {
    const copy = orig.cloneNode(true);
    if (!(copy instanceof SVGElement)) return null;
    inline(orig, copy);
    edges.append(copy);
  }
  for (const orig of nodeEls) {
    const copy = orig.cloneNode(true);
    if (!(copy instanceof SVGElement)) return null;
    inline(orig, copy);
    nodesG.append(copy);
  }
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
    width: w,
    height: h,
  });
  const bgColor = getComputedStyle(args.pane).backgroundColor;
  out.append(
    svgEl("rect", {
      x: x0 - M,
      y: y0 - M,
      width: w,
      height: h,
      fill: bgColor,
    }),
    edges,
    nodesG,
  );
  return out;
}

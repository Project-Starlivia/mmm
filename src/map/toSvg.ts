// マップを 1 枚の <svg> にする。画面の DOM から、一時的な UI 状態
// （選択・ドロップ印）を取り除き、計算済みスタイルを属性に焼き込むので、
// この結果だけで単体表示できる。
//
// **写すものは呼ぶ側が選ぶ。** 層をまるごと写していた頃は「全体」しか
// 出せなかったが、枝だけを書き出したいときにここが決められることは無い
// （どれが選ばれているかを知っているのはマップ側）。
//
// **地は持たない。** 貼り先の色にそのまま乗るよう透明のままにする —
// 板を敷かないので、角丸にする／しないの検討も要らない。

import type { Rect } from "./geometry.ts";
import { LOGO_PATH } from "../logo.ts";
import { SVG_NS, svgEl } from "./svg.ts";

/** 透かしの出所。配り先（wrangler.jsonc の `workers_dev` 名）を変えたらここも */
const WATERMARK_URL = "https://mmm.chiwawaz.workers.dev/";

/** 透かしの寸法。ロゴの原寸（144 四方、絵の高さ 143.36）から縮める */
const WM_LOGO_H = 13;
const WM_LOGO_SCALE = WM_LOGO_H / 143.36;
const WM_LOGO_W = 132.352 * WM_LOGO_SCALE;
const WM_GAP = 5;
const WM_FONT = 11;
const WM_PAD_R = 8;
/** 本文の下端から透かしの帯までの高さ。M（余白）に足す */
const WM_BAND = 22;

export async function mapToSvg(args: {
  /** 収める範囲。写すノードの箱をそのまま渡す */
  boxes: Iterable<Rect>;
  /** 写す親子の線。枝の外へ出ていくものは呼ぶ側が外しておく */
  edges: Iterable<SVGPathElement>;
  /** 写すノード */
  nodes: Iterable<SVGGElement>;
  /** 透かしの色（--ink-dim）・書体（--font）をここから読む */
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
  const h = Math.ceil(y1 - y0 + M * 2 + WM_BAND);
  // Iterable は 1 度しか回せないことがあるので、先に確定させる
  const edgeEls = [...args.edges];
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
  for (const orig of edgeEls) {
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
  out.append(edges, nodesG, watermark(x1 + M, y1 + M, args.pane));
  return out;
}

/** 右下の帯に置く「made with mmm」。`right`/`bandTop` は viewBox の右端・本文下端 */
function watermark(right: number, bandTop: number, pane: HTMLElement): SVGAElement {
  const cs = getComputedStyle(pane);
  const ink = cs.getPropertyValue("--ink-dim").trim();
  const font = cs.getPropertyValue("--font").trim();
  const centerY = bandTop + WM_BAND / 2;
  const logoX = right - WM_PAD_R - WM_LOGO_W;
  const logoY = centerY - WM_LOGO_H / 2;

  const path = document.createElementNS(SVG_NS, "path");
  path.setAttribute("d", LOGO_PATH);
  const mark = svgEl("g", {
    transform: `translate(${logoX}, ${logoY}) scale(${WM_LOGO_SCALE})`,
    fill: ink,
  });
  mark.append(path);

  const text = svgEl("text", {
    x: logoX - WM_GAP,
    y: centerY,
    "text-anchor": "end",
    "dominant-baseline": "central",
    "font-family": font,
    "font-size": WM_FONT,
    fill: ink,
  });
  text.textContent = "made with mmm";

  const link = svgEl("a", { href: WATERMARK_URL });
  link.append(text, mark);
  return link;
}

// マップを外へ出す。ファイルにも、クリップボードにも。
//
// 1 枚の <svg> にするのは map/toSvg.ts の仕事で、ここが持つのは
// **その先の出し口**だけ — 直列化・ラスタ化・ダウンロード・クリップボード。
//
// 行き先で入口を分けてある。ファイルはツールバー（形式を ▾ で選ぶ）、
// クリップボードは右クリックメニューのコピーの隣。**貼るためにコピーするのに
// ダイアログが挟まるのは重い**ので、コピーは 1 クリックで終わらせる。

import type { MindMap } from "../mindmap.ts";
import { ContextMenu } from "../map/menu.ts";
import { LS_FORMAT, load, store } from "./persist.ts";

/** ファイルにできる形式。ラベルはそのままボタンの表示になる */
export const FILE_FORMATS = [
  { id: "svg", label: "SVG", mime: "image/svg+xml", ext: "svg" },
  { id: "webp", label: "WebP", mime: "image/webp", ext: "webp" },
] as const;

type FormatId = (typeof FILE_FORMATS)[number]["id"];

/**
 * ラスタの倍率。**選ばせない** — 書き出したものは画面で見えている通りで
 * あるべきで、選ばせるほど何が出るか分からなくなる。貼り先で粗く見えない
 * 下限として 2 倍だけ取る。
 */
const SCALE = 2;

function downloadBlob(blob: Blob, name: string): void {
  const a = document.createElement("a");
  const url = URL.createObjectURL(blob);
  a.href = url;
  a.download = name;
  a.click();
  // click() の直後に revoke するとダウンロードが始まる前に URL が
  // 消えることがある。次のタスクまで待つ
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

const serialize = (svg: SVGSVGElement): string =>
  new XMLSerializer().serializeToString(svg);

/**
 * SVG を絵にする。
 *
 * `toSvg` が `blob:` のサムネイルを data URL に埋め直しているので、
 * canvas は汚染されない（外部を参照したままだと toBlob が例外になる）。
 */
async function rasterize(svg: SVGSVGElement, mime: string): Promise<Blob> {
  const w = Number(svg.getAttribute("width"));
  const h = Number(svg.getAttribute("height"));
  if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0) {
    throw new Error("書き出す大きさが読めない");
  }
  const src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(serialize(svg))}`;
  const img = new Image();
  await new Promise<void>((resolve, reject) => {
    img.onload = () => resolve();
    img.onerror = () => reject(new Error("SVG を絵にできない"));
    img.src = src;
  });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(w * SCALE);
  canvas.height = Math.ceil(h * SCALE);
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2d コンテキストを作れない");
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  return await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("絵にできなかった"))),
      mime,
    );
  });
}

export function initExport(deps: {
  map: MindMap;
  /** 書き出しボタン。表示はいまの形式そのもの（押す前に何が出るか見える） */
  button: HTMLButtonElement;
  /** 形式を選ぶ ▾ */
  formatButton: HTMLButtonElement;
  /** ダウンロード名の元になる、いまのファイル名 */
  name: () => string;
  notify: (msg: string, isError?: boolean) => void;
}): void {
  const menu = new ContextMenu();
  let format: FormatId = pickFormat(load(LS_FORMAT));

  const show = (): void => {
    const f = formatOf(format);
    deps.button.textContent = f.label;
    deps.button.title = `選んでいる枝を ${f.label} でダウンロード（何も選んでいなければ全体）`;
  };
  show();

  /** 書き出す元。空なら null を返して呼ぶ側に知らせる */
  const source = async (): Promise<SVGSVGElement | null> => {
    const svg = await deps.map.exportSvg();
    if (!svg) deps.notify("マップが空です");
    return svg;
  };

  const toFile = async (): Promise<void> => {
    const svg = await source();
    if (!svg) return;
    const f = formatOf(format);
    const blob =
      f.id === "svg"
        ? new Blob([serialize(svg)], { type: f.mime })
        : await rasterize(svg, f.mime);
    const base = deps.name().replace(/\.(md|markdown|txt)$/i, "") || "mmm";
    downloadBlob(blob, `${base}.${f.ext}`);
  };

  deps.button.addEventListener("click", () => {
    void toFile().catch((error: unknown) => {
      console.error("export failed:", error);
      deps.notify("エクスポートに失敗しました", true);
    });
  });

  deps.formatButton.addEventListener("click", () => {
    const r = deps.formatButton.getBoundingClientRect();
    menu.show(
      r.left,
      r.bottom + 4,
      FILE_FORMATS.map((f) => ({
        label: `${f.label} で書き出す`,
        run: () => {
          format = f.id;
          store(LS_FORMAT, f.id);
          show();
        },
      })),
    );
  });
}

/**
 * 絵にしてクリップボードへ置く。
 *
 * **WebP はクリップボードに置けない**（Chromium 148 の `ClipboardItem.supports`
 * が false を返す）。置けるのは PNG と SVG だけなので、ここもその 2 つ。
 * SVG は `text/plain` にも同じものを載せる — Figma や Illustrator は
 * 画像として受け取るより、SVG のソースを貼られたほうが確実に開く。
 */
export async function copyMapImage(
  svg: SVGSVGElement,
  as: "png" | "svg",
): Promise<void> {
  const item =
    as === "svg"
      ? new ClipboardItem({
          "image/svg+xml": new Blob([serialize(svg)], { type: "image/svg+xml" }),
          "text/plain": new Blob([serialize(svg)], { type: "text/plain" }),
        })
      : new ClipboardItem({ "image/png": await rasterize(svg, "image/png") });
  await navigator.clipboard.write([item]);
}

const formatOf = (id: FormatId): (typeof FILE_FORMATS)[number] =>
  FILE_FORMATS.find((f) => f.id === id) ?? FILE_FORMATS[0];

/** 覚えていた形式。知らない値なら既定へ落とす（型は名乗らせず確かめる） */
function pickFormat(saved: string | null): FormatId {
  const hit = FILE_FORMATS.find((f) => f.id === saved);
  return hit ? hit.id : FILE_FORMATS[0].id;
}

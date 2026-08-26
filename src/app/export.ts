// マップを外へ出す。ファイルにも、クリップボードにも。
//
// 1 枚の <svg> にするのは map/toSvg.ts の仕事で、ここが持つのは
// **その先の出し口**だけ — 直列化・ラスタ化・ダウンロード・クリップボード。
//
// **出し方 4 通りの定義はここ 1 か所**。ヘッダも右クリックも同じ並びを開く。
// 違うのは対象だけ — ヘッダは常に全体、右クリックは選んでいる枝。
// 新規 / 開く / 保存 が文書ぜんぶを相手にするのと同じ高さにヘッダを置き、
// 「これ」を相手にする操作は右クリックへ寄せる。

import type { MindMap } from "../mindmap.ts";
import { type MenuEntry, openOnClick } from "../map/menu.ts";
import { type IconName, icon, label } from "../icons.ts";
import { LS_WAY, load, store } from "./persist.ts";

/**
 * ラスタの倍率。**選ばせない** — 書き出したものは画面で見えている通りで
 * あるべきで、選ばせるほど何が出るか分からなくなる。貼り先で粗く見えない
 * 下限として 2 倍だけ取る。
 */
const SCALE = 2;

export interface ExportDeps {
  map: MindMap;
  /** ダウンロード名の元になる、いまのファイル名 */
  name: () => string;
  notify: (msg: string, isError?: boolean) => void;
}

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

/**
 * 出し方 4 通り。**行き先で選べる形式が違う**。
 *
 * `WebP` はクリップボードに置けない — Chromium の `ClipboardItem` が受け取る
 * のは `image/png` と `image/svg+xml` だけ（`ClipboardItem.supports` に聞いた）。
 * なのでコピー側の絵は PNG。
 *
 * SVG のコピーは `text/plain` にも同じものを載せる — Figma や Illustrator は
 * 画像として受け取るより、SVG のソースを貼られたほうが確実に開く。
 *
 * `short` はボタンの表示で、`label`（並びの表示）から動詞を落としたもの。
 * **行き先は `mark` の絵が言う** — 落とすのか、貼れるようにするのか。
 * 形式ではなく行き先に印が付く。
 */
const WAYS: readonly {
  id: string;
  short: string;
  mark: IconName;
  label: string;
  done: string;
  out: (svg: SVGSVGElement, base: string) => Promise<void>;
}[] = [
  {
    id: "svg-file",
    short: "SVG",
    mark: "download",
    label: "Download SVG",
    done: "",
    out: async (svg: SVGSVGElement, base: string): Promise<void> => {
      downloadBlob(
        new Blob([serialize(svg)], { type: "image/svg+xml" }),
        `${base}.svg`,
      );
    },
  },
  {
    id: "webp-file",
    short: "WebP",
    mark: "download",
    label: "Download WebP",
    done: "",
    out: async (svg: SVGSVGElement, base: string): Promise<void> => {
      downloadBlob(await rasterize(svg, "image/webp"), `${base}.webp`);
    },
  },
  {
    id: "png-copy",
    short: "PNG",
    mark: "copy",
    label: "Copy PNG",
    done: "Image copied",
    out: async (svg: SVGSVGElement): Promise<void> => {
      const png = await rasterize(svg, "image/png");
      await navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
    },
  },
  {
    id: "svg-copy",
    short: "SVG",
    mark: "copy",
    label: "Copy SVG",
    done: "SVG copied",
    out: async (svg: SVGSVGElement): Promise<void> => {
      const text = serialize(svg);
      await navigator.clipboard.write([
        new ClipboardItem({
          "image/svg+xml": new Blob([text], { type: "image/svg+xml" }),
          "text/plain": new Blob([text], { type: "text/plain" }),
        }),
      ]);
    },
  },
] as const;

type Way = (typeof WAYS)[number];

/** 覚えていた出し方。知らない値なら既定へ落とす（型は名乗らせず確かめる） */
const wayOf = (saved: string | null): Way =>
  WAYS.find((w) => w.id === saved) ?? WAYS[0];

/** そのやり方で 1 回出す */
function run(deps: ExportDeps, way: Way, whole: boolean): void {
  void (async () => {
    const svg = await deps.map.exportSvg(whole);
    if (!svg) {
      deps.notify("The map is empty");
      return;
    }
    const base = deps.name().replace(/\.(md|markdown|txt)$/i, "") || "mmm";
    await way.out(svg, base);
    if (way.done !== "") deps.notify(way.done, false);
  })().catch((error: unknown) => {
    console.error("export failed:", error);
    deps.notify("Export failed", true);
  });
}

/**
 * 出し方の並び。**ヘッダも右クリックも同じものを開く** — 違うのは対象だけで、
 * `whole` なら全体、そうでなければ選んでいる枝。
 * `chose` はヘッダ用（選んだものを次の既定にする）。
 */
export function exportWays(
  deps: ExportDeps,
  whole: boolean,
  chose?: (way: Way) => void,
): MenuEntry[] {
  const entries: MenuEntry[] = [];
  for (const [i, way] of WAYS.entries()) {
    // ダウンロードとコピーのあいだに線を引く（行き先が変わるところ）
    if (i === 2) entries.push("sep");
    entries.push({
      label: way.label,
      mark: way.mark,
      run: () => {
        chose?.(way);
        run(deps, way, whole);
      },
    });
  }
  return entries;
}

/**
 * ヘッダの書き出し。対象は常に全体。
 *
 * ボタンには**いまの出し方**が出ていて、押せばそれで出る。`▾` で選び直すと
 * その場で出て、次からの既定になる — 押す前に何が起きるかが常に見えている。
 */
export function initExport(
  deps: ExportDeps & { button: HTMLButtonElement; wayButton: HTMLButtonElement },
): void {
  deps.wayButton.replaceChildren(icon("chevron"));
  let way = wayOf(load(LS_WAY));
  const show = (): void => {
    // 形式が文字、行き先が絵。押す前に何が起きるかが見えている
    deps.button.replaceChildren(...label(way.short, way.mark, true));
    deps.button.title = `Export the whole map — ${way.label}`;
  };
  show();

  deps.button.addEventListener("click", () => run(deps, way, true));

  openOnClick(deps.wayButton, () =>
    exportWays(deps, true, (chosen) => {
      way = chosen;
      store(LS_WAY, chosen.id);
      show();
    }),
  );
}

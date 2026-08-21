// マップの書き出し (mmm.md そのに: コピー、ダウンロード svg/webp)。
// SVG は MindMap 側が自己完結の <svg> を作るので、ここでは
// 直列化・ラスタライズ・クリップボード/ダウンロードへの受け渡しだけ。

import type { MindMap } from "../mindmap.ts";

export function downloadBlob(blob: Blob, name: string): void {
  const a = document.createElement("a");
  const url = URL.createObjectURL(blob);
  a.href = url;
  a.download = name;
  a.click();
  // click() の直後に revoke するとダウンロードが始まる前に URL が
  // 消えることがある（大きい WebP で実際に落ちる）。次のタスクまで待つ
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

export function initExport(deps: {
  map: MindMap;
  /** ダウンロード名の元になる、いまのファイル名 */
  name: () => string;
  notify: (msg: string, isError?: boolean) => void;
}): void {
  const exportMap = async (
    kind: "svg" | "webp",
    toClipboard: boolean,
  ): Promise<void> => {
    try {
      const svg = await deps.map.exportSvg();
      if (!svg) {
        deps.notify("マップが空です");
        return;
      }
      const xml = new XMLSerializer().serializeToString(svg);
      const base = deps.name().replace(/\.(md|markdown|txt)$/i, "") || "mmm";
      if (kind === "svg") {
        if (toClipboard) {
          await navigator.clipboard.writeText(xml);
          deps.notify("SVG をコピーしました", false);
        } else {
          downloadBlob(new Blob([xml], { type: "image/svg+xml" }), `${base}.svg`);
        }
        return;
      }
      // rasterize: the snapshot is fully self-contained, so drawing it via
      // an <img> is lossless and doesn't taint the canvas
      const img = new Image();
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve();
        img.onerror = () => reject(new Error("svg rasterize failed"));
        img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(xml)}`;
      });
      const scale = 2; // crisp text at typical zoom levels
      const cv = document.createElement("canvas");
      cv.width = img.naturalWidth * scale;
      cv.height = img.naturalHeight * scale;
      const ctx = cv.getContext("2d")!;
      ctx.scale(scale, scale);
      ctx.drawImage(img, 0, 0);
      if (toClipboard) {
        // clipboard images are PNG — webp writing isn't broadly supported
        const png = await new Promise<Blob | null>((r) =>
          cv.toBlob(r, "image/png"),
        );
        if (!png) throw new Error("png encode failed");
        await navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
        deps.notify("画像をコピーしました", false);
      } else {
        let out = await new Promise<Blob | null>((r) =>
          cv.toBlob(r, "image/webp", 0.95),
        );
        let name = `${base}.webp`;
        if (!out || out.type !== "image/webp") {
          out = await new Promise<Blob | null>((r) => cv.toBlob(r, "image/png"));
          name = `${base}.png`;
        }
        if (!out) throw new Error("image encode failed");
        downloadBlob(out, name);
      }
    } catch (err) {
      console.error("export failed:", err);
      deps.notify("エクスポートに失敗しました");
    }
  };

  const btn = (id: string): HTMLButtonElement => {
    const el = document.getElementById(id);
    if (!el) throw new Error(`#${id} が無い`);
    return el as HTMLButtonElement;
  };
  btn("btn-export-svg").addEventListener("click", () => void exportMap("svg", false));
  btn("btn-export-webp").addEventListener("click", () => void exportMap("webp", false));
  // コピーは隠し操作(Shift+クリック)ではなく専用ボタンにする(mmm.md その３)
  btn("btn-copy-svg").addEventListener("click", () => void exportMap("svg", true));
  btn("btn-copy-webp").addEventListener("click", () => void exportMap("webp", true));
}

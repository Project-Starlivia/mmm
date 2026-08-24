// ディスクへ落とす。マップを 1 枚の <svg> にするのは map/toSvg.ts の
// 仕事なので、ここは直列化とダウンロードへの受け渡しだけ。

import type { MindMap } from "../mindmap.ts";

export function downloadBlob(blob: Blob, name: string): void {
  const a = document.createElement("a");
  const url = URL.createObjectURL(blob);
  a.href = url;
  a.download = name;
  a.click();
  // click() の直後に revoke するとダウンロードが始まる前に URL が
  // 消えることがある。次のタスクまで待つ
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

export function initDownload(deps: {
  map: MindMap;
  /** SVG ボタン。DOM を id で引くのは main.ts だけ */
  button: HTMLButtonElement;
  /** ダウンロード名の元になる、いまのファイル名 */
  name: () => string;
  notify: (msg: string, isError?: boolean) => void;
}): void {
  const exportMap = async (): Promise<void> => {
    try {
      const svg = await deps.map.exportSvg();
      if (!svg) {
        deps.notify("マップが空です");
        return;
      }
      const xml = new XMLSerializer().serializeToString(svg);
      const base = deps.name().replace(/\.(md|markdown|txt)$/i, "") || "mmm";
      downloadBlob(new Blob([xml], { type: "image/svg+xml" }), `${base}.svg`);
    } catch (err) {
      console.error("export failed:", err);
      deps.notify("エクスポートに失敗しました");
    }
  };

  deps.button.addEventListener("click", () => void exportMap());
}

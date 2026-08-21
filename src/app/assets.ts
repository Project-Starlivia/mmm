// 画像 (mmm.md そのに: 画像配置 — local-first)。
//
// 画像は md からの相対パスで書く。解決も保存もネイティブ本体（Rust）が
// 担い、ここは objectURL のキャッシュと WebP への変換だけを持つ。
// フォルダの許可・含有チェック・相対計算はすべて Rust 側へ消えた。

import { io } from "./io.ts";
import { showPromptPopup } from "../popup.ts";

export interface Assets {
  /** objectURL（未解決なら null を返し、裏で読み込みを試みる） */
  imageUrl(path: string): string | null;
  /** 別のファイルを開いたときに、古いサムネイルを手放す */
  clear(): void;
  /** 画像 blob をディスクへ保存し、md に書く相対パスを返す */
  saveToDisk(blob: Blob): Promise<string | null>;
}

// 拡張子と MIME の対応。1 箇所で持ち、両方向の Record をここから作る
// （前は 2 つの手書き表が真の逆写像になっておらず、avif が片方にしか無かった）。
const IMAGE_FORMATS: [ext: string, mime: string][] = [
  ["webp", "image/webp"],
  ["png", "image/png"],
  ["jpg", "image/jpeg"],
  ["jpeg", "image/jpeg"],
  ["gif", "image/gif"],
  ["svg", "image/svg+xml"],
  ["avif", "image/avif"],
];

/** 拡張子 → MIME */
const MIME: Record<string, string> = Object.fromEntries(IMAGE_FORMATS);

/** MIME → 拡張子。jpg/jpeg のように同じ MIME に複数の拡張子があるときは、
 * 先に出てくる方（jpg）を代表にする。 */
const IMG_EXT: Record<string, string> = {};
for (const [ext, mime] of IMAGE_FORMATS) {
  if (!(mime in IMG_EXT)) IMG_EXT[mime] = ext;
}

/** md に書く形。同階層から下は `./`、上へ出るものは `../` のまま。 */
export function mdPath(rel: string): string {
  return rel.startsWith("../") ? rel : `./${rel.replace(/^\.\//, "")}`;
}

export function initAssets(deps: {
  /** 現在ファイルを保存済みか（未保存だと相対パスの基準が無い） */
  hasFile: () => boolean;
  warn: (msg: string) => void;
  /** サムネイルが解決したら描き直す */
  refresh: () => void;
}): Assets {
  /** objectURL cache keyed by md-relative image path; null = 未解決/不在 */
  const assetUrls = new Map<string, string | null>();

  async function loadAsset(path: string): Promise<void> {
    try {
      const buf = await io.resolveImage(path);
      const ext = path.split(".").pop()?.toLowerCase() ?? "";
      const blob = new Blob([buf], { type: MIME[ext] ?? "application/octet-stream" });
      const old = assetUrls.get(path);
      if (old) URL.revokeObjectURL(old);
      assetUrls.set(path, URL.createObjectURL(blob));
      deps.refresh();
    } catch {
      /* 不在・非画像 — プレースホルダのまま */
    }
  }

  return {
    imageUrl(path) {
      const hit = assetUrls.get(path);
      if (hit !== undefined) return hit;
      assetUrls.set(path, null);
      void loadAsset(path);
      return null;
    },
    clear() {
      for (const u of assetUrls.values()) if (u) URL.revokeObjectURL(u);
      assetUrls.clear();
    },
    async saveToDisk(blob) {
      if (!deps.hasFile()) {
        // 相対パスの基準（md の場所）が無い
        deps.warn("画像を置くには先にファイルを保存してください");
        return null;
      }
      // WebP 変換（小さくなる）。できなければ元のまま
      let out = blob;
      if (out.type !== "image/webp") {
        try {
          const bmp = await createImageBitmap(blob);
          const cv = new OffscreenCanvas(bmp.width, bmp.height);
          cv.getContext("2d")!.drawImage(bmp, 0, 0);
          const webp = await cv.convertToBlob({ type: "image/webp", quality: 0.92 });
          if (webp.type === "image/webp") out = webp;
        } catch {
          /* keep original format */
        }
      }
      const ext = IMG_EXT[out.type] ?? "png";
      const d0 = new Date();
      const p2 = (v: number): string => String(v).padStart(2, "0");
      const def =
        `image-${d0.getFullYear()}${p2(d0.getMonth() + 1)}${p2(d0.getDate())}` +
        `-${p2(d0.getHours())}${p2(d0.getMinutes())}${p2(d0.getSeconds())}`;
      // `./` を入れて始め、右に拡張子を添える。`./` は残して名前だけ選択する
      const typed = await showPromptPopup("画像を保存", "画像名", `./${def}`, {
        suffix: `.${ext}`,
        selectFrom: 2,
      });
      if (typed === null) return null;
      const name = typed.trim().replace(/\.(webp|png|jpe?g|gif|svg)$/i, "");
      const segs = name.split("/").filter((s) => s !== "" && s !== ".");
      if (segs.length === 0 || segs.some((s) => /[\\:*?"<>|]/.test(s))) {
        deps.warn("その画像名は使えません");
        return null;
      }
      const rel = segs.join("/") + `.${ext}`;
      try {
        const bytes = new Uint8Array(await out.arrayBuffer());
        await io.saveImage(rel, bytes);
      } catch (err) {
        deps.warn(String(err) === "no-doc" ? "先にファイルを保存してください" : "画像の保存に失敗しました");
        return null;
      }
      assetUrls.set(rel, URL.createObjectURL(out)); // thumbnail: no re-read
      return mdPath(rel);
    },
  };
}

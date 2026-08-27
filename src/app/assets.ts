// Markdown からの相対パスで画像を読み書きする。
// ブラウザはファイルの親へ辿れないため、ユーザーが選んだフォルダと
// 「md から見た保存パス」の組を宣言として扱う。

import { handles, type AssetBinding } from "./handles.ts";
import { io } from "./io.ts";

export interface Assets {
  imageUrl(path: string): string | null;
  clear(): void;
  /** いま結び付いている画像フォルダの名前。未設定なら null */
  folderName(): string | null;
  chooseFolder(): Promise<void>;
  saveToDisk(blob: Blob): Promise<string | null>;
}

export function mdPath(rel: string): string {
  return rel.startsWith("../") ? rel : `./${rel.replace(/^\.\//, "")}`;
}

/** 先頭の `./` を落とした形。`./x` と `x` は同じ場所を指す。 */
const bare = (path: string): string => path.replace(/^\.\//, "");

/**
 * md に書かれたパスが、宣言した保存パスの下に収まるか。
 * 収まればフォルダからの相対を断片で返し、外れていれば null。
 *
 * 同じ場所を指す綴りが `./x` と `x` の 2 通りあるので、**必ず裸に寄せてから**
 * 比べる。md に書くのは `./x`、カード側が持つのは `x` と非対称なため、
 * どちらか片方だけを見ると既定の保存パス `./` で必ず外れる。
 */
export function assetTarget(declared: string, path: string): string[] | null {
  const prefix = bare(declared);
  const rest = bare(path);
  if (!rest.startsWith(prefix)) return null;
  const parts = rest.slice(prefix.length).split("/").filter(Boolean);
  if (parts.length === 0) return null;
  // フォルダの外へ出る綴りは受け取らない（宣言の外は見に行かない）
  if (parts.some((part) => part === "." || part === "..")) return null;
  return parts;
}

const normalizePath = (value: string): string | null => {
  let path = value.trim().replace(/\\/g, "/");
  if (path === "" || path === ".") path = "./";
  if (path.startsWith("/") || /^[a-z]+:\/\//i.test(path)) return null;
  return path.endsWith("/") ? path : `${path}/`;
};

async function nestedFile(
  root: FileSystemDirectoryHandle,
  parts: string[],
  create: boolean,
): Promise<FileSystemFileHandle> {
  let directory = root;
  for (const part of parts.slice(0, -1)) {
    directory = await directory.getDirectoryHandle(part, { create });
  }
  return directory.getFileHandle(parts[parts.length - 1], { create });
}

async function webp(blob: Blob): Promise<Blob> {
  if (blob.type === "image/webp") return blob;
  const bitmap = await createImageBitmap(blob);
  try {
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("2d コンテキストを作れない");
    ctx.drawImage(bitmap, 0, 0);
    const out = await canvas.convertToBlob({ type: "image/webp", quality: 0.92 });
    if (out.type !== "image/webp") throw new Error("webp conversion failed");
    return out;
  } finally {
    bitmap.close();
  }
}

export function initAssets(deps: {
  hasFile: () => boolean;
  warn: (msg: string) => void;
  refresh: () => void;
}): Assets {
  const assetUrls = new Map<string, string | null>();
  let cachedBinding: AssetBinding | null | undefined;

  const releaseUrls = (): void => {
    for (const url of assetUrls.values()) if (url) URL.revokeObjectURL(url);
    assetUrls.clear();
  };

  async function storedBinding(): Promise<AssetBinding | null> {
    if (cachedBinding !== undefined) return cachedBinding;
    const file = io.currentFile();
    const saved = await handles.assets();
    cachedBinding =
      file && saved && (await saved.doc.isSameEntry(file)) ? saved : null;
    return cachedBinding;
  }

  async function selectBinding(): Promise<AssetBinding | null> {
    const file = io.currentFile();
    if (!file) return null;
    let directory: FileSystemDirectoryHandle;
    try {
      directory = await window.showDirectoryPicker({ startIn: file, mode: "readwrite" });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return null;
      throw error;
    }
    const declared = window.prompt("Path to the image folder, relative to the .md", "./");
    if (declared === null) return null;
    const path = normalizePath(declared);
    if (!path) {
      deps.warn("The path must be relative");
      return null;
    }
    const binding = { doc: file, directory, path };
    await handles.saveAssets(binding);
    cachedBinding = binding;
    releaseUrls();
    deps.refresh();
    return binding;
  }

  async function writableBinding(): Promise<AssetBinding | null> {
    const binding = await storedBinding();
    if (binding) {
      const state = await binding.directory.queryPermission({ mode: "readwrite" });
      if (
        state === "granted" ||
        (state === "prompt" &&
          (await binding.directory.requestPermission({ mode: "readwrite" })) === "granted")
      ) {
        return binding;
      }
    }
    return selectBinding();
  }

  async function loadAsset(path: string): Promise<void> {
    try {
      const binding = await storedBinding();
      if (!binding) return;
      const parts = assetTarget(binding.path, path);
      if (!parts) return;
      if ((await binding.directory.queryPermission({ mode: "read" })) !== "granted") return;
      const file = await nestedFile(binding.directory, parts, false);
      const blob = await (await file.getFile()).arrayBuffer();
      const old = assetUrls.get(path);
      if (old) URL.revokeObjectURL(old);
      assetUrls.set(path, URL.createObjectURL(new Blob([blob], { type: "image/webp" })));
      deps.refresh();
    } catch {
      /* 不在・許可待ち — プレースホルダのまま */
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
      releaseUrls();
      cachedBinding = undefined;
      // 捨てたその場で引き直す。`folderName()` は同期で答えるしかなく、
      // 「まだ引いていない」と「無い」を区別できない — 人が
      // メニューを開くより先に決着させて、嘘を言わせない
      void storedBinding().catch(() => {});
    },

    folderName: () => (cachedBinding ? cachedBinding.directory.name : null),

    async chooseFolder() {
      // 保存していない文書には**相対パスの基準になる場所が無い**。
      // 押しても黙って何も起きないのは、入口がヘッダに出た今は通らない
      // （理由は saveToDisk と同じなので、同じ言葉で言う）
      if (!deps.hasFile()) {
        deps.warn("Save the file first to add images");
        return;
      }
      try {
        await selectBinding();
      } catch {
        deps.warn("Could not open the image folder");
      }
    },

    async saveToDisk(blob) {
      if (!deps.hasFile()) {
        deps.warn("Save the file first to add images");
        return null;
      }
      let binding: AssetBinding | null;
      try {
        binding = await writableBinding();
      } catch {
        deps.warn("Could not open the image folder");
        return null;
      }
      if (!binding) return null;

      const now = new Date();
      const two = (value: number): string => String(value).padStart(2, "0");
      const initial =
        `${now.getFullYear()}-${two(now.getMonth() + 1)}-${two(now.getDate())}` +
        `-${two(now.getHours())}${two(now.getMinutes())}${two(now.getSeconds())}`;
      const typed = window.prompt("Image name (.webp)", initial);
      if (typed === null) return null;
      const name = typed.trim().replace(/\.webp$/i, "");
      const parts = name.split("/").filter(Boolean);
      if (
        parts.length === 0 ||
        parts.some((part) => part === "." || part === ".." || /[\\:*?"<>|]/.test(part))
      ) {
        deps.warn("That image name cannot be used");
        return null;
      }
      parts[parts.length - 1] += ".webp";

      try {
        const out = await webp(blob);
        const file = await nestedFile(binding.directory, parts, true);
        const stream = await file.createWritable();
        try {
          await stream.write(out);
        } finally {
          await stream.close();
        }
        const rel = `${binding.path}${parts.join("/")}`;
        // 鍵はカード側が問い合わせてくる形（裸）に合わせる。
        // md へ書くのは mdPath の形（`./x`）。
        assetUrls.set(bare(rel), URL.createObjectURL(out));
        return mdPath(rel);
      } catch {
        deps.warn("Could not save the image");
        return null;
      }
    },
  };
}

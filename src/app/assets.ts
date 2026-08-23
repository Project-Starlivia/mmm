// Markdown からの相対パスで画像を読み書きする。
// ブラウザはファイルの親へ辿れないため、ユーザーが選んだフォルダと
// 「md から見た保存パス」の組を宣言として扱う。

import { handles, type AssetBinding } from "./handles.ts";
import { io } from "./io.ts";

export interface Assets {
  imageUrl(path: string): string | null;
  clear(): void;
  chooseFolder(): Promise<void>;
  saveToDisk(blob: Blob): Promise<string | null>;
}

export function mdPath(rel: string): string {
  return rel.startsWith("../") ? rel : `./${rel.replace(/^\.\//, "")}`;
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
    canvas.getContext("2d")!.drawImage(bitmap, 0, 0);
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
    const declared = window.prompt("md から見た画像フォルダの保存パス", "./");
    if (declared === null) return null;
    const path = normalizePath(declared);
    if (!path) {
      deps.warn("保存パスは相対パスで指定してください");
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
      if (!binding || !path.startsWith(binding.path)) return;
      if ((await binding.directory.queryPermission({ mode: "read" })) !== "granted") return;
      const rel = path.slice(binding.path.length);
      const parts = rel.split("/").filter(Boolean);
      if (parts.length === 0 || parts.some((part) => part === "." || part === "..")) return;
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
    },

    async chooseFolder() {
      try {
        await selectBinding();
      } catch {
        deps.warn("画像フォルダを開けませんでした");
      }
    },

    async saveToDisk(blob) {
      if (!deps.hasFile()) {
        deps.warn("画像を置くには先にファイルを保存してください");
        return null;
      }
      let binding: AssetBinding | null;
      try {
        binding = await writableBinding();
      } catch {
        deps.warn("画像フォルダを開けませんでした");
        return null;
      }
      if (!binding) return null;

      const now = new Date();
      const two = (value: number): string => String(value).padStart(2, "0");
      const initial =
        `${now.getFullYear()}-${two(now.getMonth() + 1)}-${two(now.getDate())}` +
        `-${two(now.getHours())}${two(now.getMinutes())}${two(now.getSeconds())}`;
      const typed = window.prompt("画像名（.webp）", initial);
      if (typed === null) return null;
      const name = typed.trim().replace(/\.webp$/i, "");
      const parts = name.split("/").filter(Boolean);
      if (
        parts.length === 0 ||
        parts.some((part) => part === "." || part === ".." || /[\\:*?"<>|]/.test(part))
      ) {
        deps.warn("その画像名は使えません");
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
        assetUrls.set(rel, URL.createObjectURL(out));
        return rel;
      } catch {
        deps.warn("画像の保存に失敗しました");
        return null;
      }
    },
  };
}

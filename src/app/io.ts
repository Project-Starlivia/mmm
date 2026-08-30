// ブラウザの File System Access API との窓口。
// UTF-8 / LF の Markdown を 1 ファイルずつ読み書きする。

import { handles } from "./handles.ts";

declare global {
  interface FileSystemHandlePermissionDescriptor {
    mode?: "read" | "readwrite";
  }

  interface FileSystemHandle {
    queryPermission(
      descriptor?: FileSystemHandlePermissionDescriptor,
    ): Promise<PermissionState>;
    requestPermission(
      descriptor?: FileSystemHandlePermissionDescriptor,
    ): Promise<PermissionState>;
    /** 同じフォルダの中での改名。Chromium だけが持つので任意 */
    move?: (name: string) => Promise<void>;
  }

  interface Window {
    showOpenFilePicker?: (options?: {
      multiple?: boolean;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }) => Promise<FileSystemFileHandle[]>;
    showSaveFilePicker?: (options?: {
      suggestedName?: string;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }) => Promise<FileSystemFileHandle>;
    showDirectoryPicker?: (options?: {
      startIn?: FileSystemHandle;
      mode?: "read" | "readwrite";
    }) => Promise<FileSystemDirectoryHandle>;
  }

  interface DataTransferItem {
    getAsFileSystemHandle?: () => Promise<FileSystemHandle | null>;
  }
}

export interface Doc {
  name: string;
  text: string;
}

const MARKDOWN = [
  {
    description: "Markdown",
    accept: { "text/markdown": [".md", ".markdown", ".txt"] },
  },
];

let current: FileSystemFileHandle | null = null;

const isCancel = (error: unknown): boolean =>
  error instanceof DOMException && error.name === "AbortError";

async function readDoc(file: FileSystemFileHandle): Promise<Doc> {
  const blob = await file.getFile();
  return { name: file.name, text: (await blob.text()).replace(/\r\n?/g, "\n") };
}

async function use(file: FileSystemFileHandle): Promise<Doc> {
  current = file;
  await handles.opened(file);
  return readDoc(file);
}

async function write(file: FileSystemFileHandle, text: string): Promise<void> {
  const stream = await file.createWritable();
  try {
    await stream.write(text);
  } finally {
    await stream.close();
  }
}

export const io = {
  currentFile: (): FileSystemFileHandle | null => current,

  /**
   * 覚えている文書を開く。**許可はここで取り直す** — 札は残っていても
   * 触ってよいかは別の台帳で、押した瞬間しか聞けない（押されたことが
   * その資格になる）。断られたら null。
   */
  async openKnown(file: FileSystemFileHandle): Promise<Doc | null> {
    if ((await file.requestPermission({ mode: "readwrite" })) !== "granted") {
      return null;
    }
    return use(file);
  },

  /** いまのファイルを手放す（New file）。**覚えている一覧はそのまま** */
  close(): void {
    current = null;
  },

  /** このブラウザがファイルを開けるか。**スマホには無い** —
   *  `docs/web.md` のとおりフォールバックは持たないので、無いなら無いと言う */
  canOpen: (): boolean => typeof window.showOpenFilePicker === "function",
  canSaveAs: (): boolean => typeof window.showSaveFilePicker === "function",

  async openDialog(): Promise<Doc | null> {
    const pick = window.showOpenFilePicker;
    if (!pick) return null;
    try {
      const [file] = await pick({ multiple: false, types: MARKDOWN });
      return file ? use(file) : null;
    } catch (error) {
      if (isCancel(error)) return null;
      throw error;
    }
  },

  openHandle: (file: FileSystemFileHandle): Promise<Doc> => use(file),

  async save(text: string): Promise<void> {
    if (!current) throw new Error("no-file");
    await write(current, text);
  },

  async saveAs(suggested: string, text: string): Promise<Doc | null> {
    const pick = window.showSaveFilePicker;
    if (!pick) return null;
    try {
      const file = await pick({ suggestedName: suggested, types: MARKDOWN });
      await write(file, text);
      current = file;
      await handles.opened(file);
      return { name: file.name, text };
    } catch (error) {
      if (isCancel(error)) return null;
      throw error;
    }
  },

  /**
   * この環境が改名を持つか。**押す前に分かることは、押す前に言う** —
   * `move` の有無はブラウザで決まっていて、試すまでもない。
   *
   * `move` は Chromium だけが持つ（Firefox / Safari は OPFS の中にしか
   * 無い）。mmm は元から Chromium 限定と言い切っているので前提は変わらない。
   */
  canRename: (): boolean =>
    typeof FileSystemFileHandle.prototype.move === "function",

  /**
   * いま開いているファイル**そのもの**の名前を変える（`move` は同じ
   * フォルダの中での改名になる）。保存していなければ何もしない — 名前を
   * 変える相手がディスクに無い。
   */
  async rename(name: string): Promise<string | null> {
    if (!current?.move) return null;
    await current.move(name);
    await handles.opened(current);
    return current.name;
  },
};

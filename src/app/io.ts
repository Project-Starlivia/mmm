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
    showOpenFilePicker(options?: {
      multiple?: boolean;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }): Promise<FileSystemFileHandle[]>;
    showSaveFilePicker(options?: {
      suggestedName?: string;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }): Promise<FileSystemFileHandle>;
    showDirectoryPicker(options?: {
      startIn?: FileSystemHandle;
      mode?: "read" | "readwrite";
    }): Promise<FileSystemDirectoryHandle>;
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
  await handles.saveFile(file);
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

  /** 許可が残っている前回のファイルを起動時に読み直す。 */
  async startupDoc(): Promise<Doc | null> {
    const file = await handles.file();
    if (!file) return null;
    current = file;
    if ((await file.queryPermission({ mode: "readwrite" })) !== "granted") {
      return null;
    }
    return readDoc(file);
  },

  /** ファイル名のクリックから、前回の許可を取り直す。 */
  async restoreDoc(): Promise<Doc | null> {
    const file = current ?? (await handles.file());
    if (!file) return null;
    if ((await file.requestPermission({ mode: "readwrite" })) !== "granted") {
      return null;
    }
    return use(file);
  },

  async close(): Promise<void> {
    current = null;
    await handles.clearFile();
  },

  async openDialog(): Promise<Doc | null> {
    try {
      const [file] = await window.showOpenFilePicker({ multiple: false, types: MARKDOWN });
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
    try {
      const file = await window.showSaveFilePicker({ suggestedName: suggested, types: MARKDOWN });
      await write(file, text);
      current = file;
      await handles.saveFile(file);
      return { name: file.name, text };
    } catch (error) {
      if (isCancel(error)) return null;
      throw error;
    }
  },

  /**
   * いま開いているファイル**そのもの**の名前を変える（`move` は同じ
   * フォルダの中での改名になる）。保存していなければ何もしない — 名前を
   * 変える相手がディスクに無い。
   *
   * `move` は Chromium だけが持つ（Firefox / Safari は OPFS の中にしか
   * 無い）。mmm は元から Chromium 限定と言い切っているので前提は変わらないが、
   * 無い環境で黙って何も起きないのは通らないので、無ければそう言う。
   */
  async rename(name: string): Promise<string | null> {
    if (!current) return null;
    if (typeof current.move !== "function") throw new Error("no-rename");
    await current.move(name);
    await handles.saveFile(current);
    return current.name;
  },
};

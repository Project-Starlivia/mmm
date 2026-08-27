// File System Access API のハンドルを IndexedDB に保存する小さな層。
// 本文は持たない。ディスク上の実体を指すハンドルだけを覚える。

const DB_NAME = "mmm";
const STORE_NAME = "handles";
const FILE_KEY = "file";
const ASSETS_KEY = "assets";

/**
 * 画像フォルダの結び付け。**持つのは許可だけ** — 「md から見てどこか」は
 * .md の頭が宣言する（app/head.ts）。以前はここが `path` も持っていて、
 * 別マシンで開くと宣言ごと消えていた。
 */
export interface AssetBinding {
  doc: FileSystemFileHandle;
  directory: FileSystemDirectoryHandle;
}

function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE_NAME)) {
        req.result.createObjectStore(STORE_NAME);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

/**
 * 1 つの取引を走らせて、結果をそのまま返す。
 *
 * ここは「前回のファイルを覚えておく」ためだけの便利層で、実体は
 * ディスク側のハンドルが指す。private mode でのブロックやスキーマの
 * ずれで壊れても、開く・新規・保存という本体機能を道連れにしない
 * ——読み書き問わず失敗は諦めて null へ倒す。
 *
 * 返すのは `unknown`。**中身が何かはここでは分からない**（前の版が入れた
 * ものや、人が入れ替えたものが出てくる）ので、受け取る側が確かめる。
 */
async function run(
  mode: IDBTransactionMode,
  op: (store: IDBObjectStore) => IDBRequest,
): Promise<unknown> {
  let db: IDBDatabase | null = null;
  try {
    const conn = await database();
    db = conn;
    return await new Promise<unknown>((resolve, reject) => {
      const req = op(conn.transaction(STORE_NAME, mode).objectStore(STORE_NAME));
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  } catch {
    return null;
  } finally {
    db?.close();
  }
}

const read = (key: string): Promise<unknown> =>
  run("readonly", (store) => store.get(key));

const write = async (key: string, value: unknown): Promise<void> => {
  await run("readwrite", (store) => store.put(value, key));
};

const remove = async (key: string): Promise<void> => {
  await run("readwrite", (store) => store.delete(key));
};

/** 覚えていたものが、いまも期待の形をしているか */
const isFile = (v: unknown): v is FileSystemFileHandle =>
  v instanceof FileSystemFileHandle;

const isBinding = (v: unknown): v is AssetBinding =>
  typeof v === "object" &&
  v !== null &&
  "doc" in v &&
  v.doc instanceof FileSystemFileHandle &&
  "directory" in v &&
  v.directory instanceof FileSystemDirectoryHandle;

export const handles = {
  async file(): Promise<FileSystemFileHandle | null> {
    const v = await read(FILE_KEY);
    return isFile(v) ? v : null;
  },
  saveFile: (file: FileSystemFileHandle) => write(FILE_KEY, file),
  clearFile: () => remove(FILE_KEY),
  async assets(): Promise<AssetBinding | null> {
    const v = await read(ASSETS_KEY);
    return isBinding(v) ? v : null;
  },
  saveAssets: (binding: AssetBinding) => write(ASSETS_KEY, binding),
};

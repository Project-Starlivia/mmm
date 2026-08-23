// File System Access API のハンドルを IndexedDB に保存する小さな層。
// 本文は持たない。ディスク上の実体を指すハンドルだけを覚える。

const DB_NAME = "mmm";
const STORE_NAME = "handles";
const FILE_KEY = "file";
const ASSETS_KEY = "assets";

export interface AssetBinding {
  doc: FileSystemFileHandle;
  directory: FileSystemDirectoryHandle;
  path: string;
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
 * ここは「前回のファイルを覚えておく」ためだけの便利層で、実体は
 * ディスク側のハンドルが指す。private mode でのブロックやスキーマの
 * ずれで壊れても、開く・新規・保存という本体機能を道連れにしない
 * ——読み書き問わず失敗は諦めて既定値へ倒す。
 */
async function withStore<T>(
  mode: IDBTransactionMode,
  run: (store: IDBObjectStore) => IDBRequest,
  fallback: T,
): Promise<T> {
  let db: IDBDatabase | null = null;
  try {
    db = await database();
    return await new Promise<T>((resolve, reject) => {
      const req = run(db!.transaction(STORE_NAME, mode).objectStore(STORE_NAME));
      req.onsuccess = () => resolve((req.result as T | undefined) ?? fallback);
      req.onerror = () => reject(req.error);
    });
  } catch {
    return fallback;
  } finally {
    db?.close();
  }
}

const read = <T>(key: string): Promise<T | null> =>
  withStore<T | null>("readonly", (store) => store.get(key), null);

const write = (key: string, value: unknown): Promise<void> =>
  withStore<void>("readwrite", (store) => store.put(value, key), undefined);

const remove = (key: string): Promise<void> =>
  withStore<void>("readwrite", (store) => store.delete(key), undefined);

export const handles = {
  file: () => read<FileSystemFileHandle>(FILE_KEY),
  saveFile: (file: FileSystemFileHandle) => write(FILE_KEY, file),
  clearFile: () => remove(FILE_KEY),
  assets: () => read<AssetBinding>(ASSETS_KEY),
  saveAssets: (binding: AssetBinding) => write(ASSETS_KEY, binding),
};

// File System Access API のハンドルを IndexedDB に保存する小さな層。
// 本文は持たない。ディスク上の実体を指すハンドルだけを覚える。
//
// **ハンドルは参照 ID でしかない。** 中身は覗けず（`JSON.stringify` は `{}`）、
// 実際のパスはブラウザの中にしか無い。触ってよいかはまた別の台帳（許可）で、
// 指し先が消えていることもある。だからここが持っているのは**番号札**で、
// 使えるかどうかは毎回下まで確かめる — **覚えているのは高速化であって、
// 真実ではない**。札が死んでいれば、指し直しの駅（app/assets.ts）へ落ちる。
//
// 覚えるのは**知っている文書の一覧**だけ（`docs`）。1 行が 1 つの .md で、
// その文書の画像フォルダを一緒に持つ。
//
// **「いま開いているのはこれ」は覚えない。** 起動時に勝手に開き直さないので、
// 持っていても使い道が無い — 開くのは常に人が選んだとき（Open か、この一覧）。

const DB_NAME = "mmm";
const STORE_NAME = "handles";
const DOCS_KEY = "docs";
/** 前の版の鍵。読み替えたら消す（下記 readDocs）。
 *  `file` は「いまのファイル」、`assets` は枠 1 つの画像フォルダだった */
const LEGACY_FILE = "file";
const LEGACY_ASSETS = "assets";

/**
 * 知っている文書 1 つ。**持つのは札だけ** — 「md から見てどこか」は .md の頭が
 * 宣言する（app/head.ts）。以前はここが `path` も持っていて、別マシンで開くと
 * 宣言ごと消えていた。
 *
 * `seen` は最後に触れた時刻。**あふれたら古いものから捨てる** — 番号札は
 * 腐るので、際限なく貯めても当たらない札が増えるだけ。
 */
export interface Known {
  doc: FileSystemFileHandle;
  /** その文書の画像フォルダ。まだ指してもらっていなければ null */
  directory: FileSystemDirectoryHandle | null;
  seen: number;
}

/** 覚えておく文書の数。**捨てる基準は「最後に触れた順」** */
const KEEP = 20;

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

/** 覚えていたものが、いまも期待の形をしているか（型は名乗らせず確かめる） */
const isKnown = (v: unknown): v is Known =>
  typeof v === "object" &&
  v !== null &&
  "doc" in v &&
  v.doc instanceof FileSystemFileHandle &&
  "directory" in v &&
  (v.directory === null || v.directory instanceof FileSystemDirectoryHandle) &&
  "seen" in v &&
  typeof v.seen === "number";

/** 読み替えは済んだか。**1 セッションに 1 度でいい** — 済んだ後も毎回
 *  古い鍵を読みに行くと、`list` を呼ぶたびに無駄な往復が 4 回増える */
let inherited = false;

/** 前の版が残したもの（`file` と `assets`）を 1 行に読み替える。
 *  **版が上がっただけで開き直しをさせない。** 読み替えたら古い鍵は捨てる */
async function inherit(): Promise<Known[]> {
  if (inherited) return [];
  inherited = true;
  const file = await read(LEGACY_FILE);
  const old = await read(LEGACY_ASSETS);
  const dir =
    typeof old === "object" &&
    old !== null &&
    "directory" in old &&
    old.directory instanceof FileSystemDirectoryHandle
      ? old.directory
      : null;
  const rows =
    file instanceof FileSystemFileHandle
      ? [{ doc: file, directory: dir, seen: Date.now() }]
      : [];
  if (rows.length > 0) await write(DOCS_KEY, rows);
  await remove(LEGACY_FILE);
  await remove(LEGACY_ASSETS);
  return rows;
}

const readDocs = async (): Promise<Known[]> => {
  const v = await read(DOCS_KEY);
  return Array.isArray(v) ? v.filter(isKnown) : inherit();
};

/**
 * その文書の行を探す。**札どうしは `isSameEntry` でしか比べられない** —
 * 中身が覗けないので、鍵で引くのではなく端から照合する（だから `KEEP` 行）。
 */
async function findRow(rows: Known[], file: FileSystemFileHandle): Promise<number> {
  for (const [i, row] of rows.entries()) {
    if (await row.doc.isSameEntry(file)) return i;
  }
  return -1;
}

const save = (rows: Known[]): Promise<void> => {
  rows.sort((a, b) => b.seen - a.seen);
  return write(DOCS_KEY, rows.slice(0, KEEP));
};

export const handles = {
  /** 知っている文書。**最後に触れた順** — Files の並びがそのままこれ */
  list: (): Promise<Known[]> => readDocs(),

  /**
   * 開いた / 保存した。行が無ければ作り、あれば触れた印を新しくする。
   * **画像フォルダは保つ** — 同じ文書に戻れば結び付きも戻る。
   */
  async opened(file: FileSystemFileHandle): Promise<void> {
    const rows = await readDocs();
    const at = await findRow(rows, file);
    const was = rows[at];
    if (at >= 0) rows.splice(at, 1);
    rows.push({ doc: file, directory: was?.directory ?? null, seen: Date.now() });
    await save(rows);
  },

  /** その文書の画像フォルダ。覚えていなければ null */
  async folderFor(file: FileSystemFileHandle): Promise<FileSystemDirectoryHandle | null> {
    const rows = await readDocs();
    const at = await findRow(rows, file);
    return rows[at]?.directory ?? null;
  },

  /** 画像フォルダを覚える。行が無ければ作る */
  async rememberFolder(
    file: FileSystemFileHandle,
    directory: FileSystemDirectoryHandle,
  ): Promise<void> {
    const rows = await readDocs();
    const at = await findRow(rows, file);
    if (at >= 0) rows.splice(at, 1);
    rows.push({ doc: file, directory, seen: Date.now() });
    await save(rows);
  },

  /** 画像フォルダだけ忘れる（触って失敗した・指し先が消えた）。行は残す */
  async forgetFolder(file: FileSystemFileHandle): Promise<void> {
    const rows = await readDocs();
    const at = await findRow(rows, file);
    const row = rows[at];
    if (row === undefined) return;
    row.directory = null;
    await save(rows);
  },
};

// Markdown からの相対パスで画像を読む。
//
// **宣言（md から見てどこか）は .md の頭が持ち、許可（そのフォルダを読み書き
// してよい）だけをここが持つ。** ブラウザはパス文字列からフォルダハンドルを
// 作れないので、2 つに分かれること自体は避けられない — どちらが何の真実かを
// 言い切ることで、食い違いを事故にしない。
//
// **宣言を書くのは操作の段。** 今は読むだけで、宣言が無い文書は `./`（md と
// 同じ場所）として読む。指したフォルダが宣言と食い違っても直さない。
// 画像を置く（`saveToDisk`）のも同じく操作なので、いまは無い。

import { handles } from "./handles.ts";
import { io } from "./io.ts";
import { under } from "./head.ts";

export interface Assets {
  imageUrl(path: string): string | null;
  clear(): void;
  /** いま結び付いている画像フォルダの名前。未設定なら null */
  folderName(): string | null;
  /**
   * いま画像を読める状態か。**繋ぎ直しの箱を出すかの判定**（main.ts）。
   * 札を引き直し、許可まで見るので約束を返す。
   */
  connected(): Promise<boolean>;
  /**
   * 繋ぎ直す。**札を持っているなら許可を聞くだけ**で済ませ、指し直しの
   * ピッカーは出さない — 場所はもう分かっているのに選ばせるのは、
   * 分かっていることを聞くのと同じ。札が無い / 断られたときだけ指してもらう。
   */
  connect(): Promise<void>;
  /**
   * いま画像が読めているか。**同期で答える** — 場所取りの字は描くたびに
   * 引かれるので、待てない。`connected()` が確かめた結果をここが覚えている。
   */
  readable(): boolean;
  /** このブラウザがフォルダを選べるか（触る道具では持たないことがある） */
  canChooseFolder(): boolean;
  chooseFolder(): Promise<void>;
}

/**
 * いま握っているもの。**セッションの持ち物**で、覚えているのは札だけ
 * （app/handles.ts）。`doc` を組で持つのは、握りが「**この md** から見た
 * **あのフォルダ**」という対でしか意味を持たないから。
 */
interface AssetBinding {
  doc: FileSystemFileHandle;
  directory: FileSystemDirectoryHandle;
}

/**
 * 読みに行ってよい絵の種類。**綴りはここ 1 つ**で、種類の判定も
 * `<image>` に載せる MIME も同じ表から引く。
 */
const IMAGE_TYPES: Readonly<Record<string, string>> = {
  webp: "image/webp",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  avif: "image/avif",
  svg: "image/svg+xml",
  bmp: "image/bmp",
  ico: "image/x-icon",
};

/** その名前が指す絵の種類。絵でなければ null */
export function imageType(name: string): string | null {
  const dot = name.lastIndexOf(".");
  if (dot <= 0) return null;
  return IMAGE_TYPES[name.slice(dot + 1).toLowerCase()] ?? null;
}

/**
 * md に書かれたパスが、宣言した保存パスの下に収まるか。
 * 収まればフォルダからの相対を断片で返し、外れていれば null。
 *
 * 「その綴りは宣言の下か」の判定は app/head.ts の `under` が唯一の持ち主。
 * ここが足すのは、**フォルダの中として受け取ってよいか**の柵だけ。
 */
export function assetTarget(declared: string, path: string): string[] | null {
  const rest = under(path, declared);
  if (rest === null) return null;
  const parts = rest.split("/").filter(Boolean);
  if (parts.length === 0) return null;
  // フォルダの外へ出る綴りは受け取らない（宣言の外は見に行かない）
  if (parts.some((part) => part === "." || part === "..")) return null;
  // **絵でないものは読みに行かない。** `![](notes.txt)` と書けば、マップに
  // 何も出ないまま中身が読まれ、書き出した SVG に base64 で載ってしまう
  // （`<image>` は描けなくてもデータは埋まる）。宣言したフォルダの中に
  // 限られるとはいえ、絵を置く場所として渡したフォルダなので、絵だけ見る
  if (!imageType(parts[parts.length - 1] ?? "")) return null;
  return parts;
}

async function nestedFile(
  root: FileSystemDirectoryHandle,
  parts: string[],
): Promise<FileSystemFileHandle> {
  let directory = root;
  for (const part of parts.slice(0, -1)) {
    directory = await directory.getDirectoryHandle(part);
  }
  return directory.getFileHandle(parts[parts.length - 1]);
}

export function initAssets(deps: {
  /** 果たせなかった */
  failed: (msg: string) => void;
  refresh: () => void;
  /** いま頭が言っている宣言（正規化済み）。無ければ null */
  declared: () => string | null;
}): Assets {
  const assetUrls = new Map<string, string | null>();
  let cachedBinding: AssetBinding | null | undefined;
  /** 直近に確かめた「読めているか」。描くたびに同期で聞かれるので覚えておく */
  let live = false;

  // 宣言が無いのは「md と同じ場所」。頭を持たない古い文書がそのまま読めるように、ここで倒す
  const declaredPath = (): string => deps.declared() ?? "./";

  const releaseUrls = (): void => {
    for (const url of assetUrls.values()) if (url) URL.revokeObjectURL(url);
    assetUrls.clear();
  };

  async function storedBinding(): Promise<AssetBinding | null> {
    if (cachedBinding !== undefined) return cachedBinding;
    const file = io.currentFile();
    // **札は文書ごと**（handles）。別の .md を開いても前の結び付きは残る
    const directory = file ? await handles.folderFor(file) : null;
    cachedBinding = file && directory ? { doc: file, directory } : null;
    return cachedBinding;
  }

  /** フォルダを指してもらい、握る。取りやめは false */
  async function pick(): Promise<boolean> {
    const file = io.currentFile();
    if (!file) return false;
    const picker = window.showDirectoryPicker;
    if (!picker) return false;
    let directory: FileSystemDirectoryHandle;
    try {
      directory = await picker({ startIn: file, mode: "readwrite" });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return false;
      throw error;
    }
    await handles.rememberFolder(file, directory);
    cachedBinding = { doc: file, directory };
    live = true;
    releaseUrls();
    deps.refresh();
    return true;
  }

  async function loadAsset(path: string): Promise<void> {
    try {
      const binding = await storedBinding();
      if (!binding) return;
      const parts = assetTarget(declaredPath(), path);
      if (!parts) return;
      if ((await binding.directory.queryPermission({ mode: "read" })) !== "granted") return;
      const file = await nestedFile(binding.directory, parts);
      // 種類は名前から引く（`assetTarget` を通った時点で必ず絵）
      const type = imageType(parts[parts.length - 1] ?? "") ?? "image/webp";
      const blob = await (await file.getFile()).arrayBuffer();
      const old = assetUrls.get(path);
      if (old) URL.revokeObjectURL(old);
      assetUrls.set(path, URL.createObjectURL(new Blob([blob], { type })));
      live = true;
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
      live = false;
      // 捨てたその場で引き直す。`folderName()` は同期で答えるしかなく、
      // 「まだ引いていない」と「無い」を区別できない — 人が
      // メニューを開くより先に決着させて、嘘を言わせない
      void storedBinding().catch(() => {});
    },

    folderName: () => (cachedBinding ? cachedBinding.directory.name : null),

    canChooseFolder: (): boolean => typeof window.showDirectoryPicker === "function",

    readable: () => live,

    async connected() {
      const binding = await storedBinding();
      live =
        binding !== null &&
        (await binding.directory.queryPermission({ mode: "read" })) === "granted";
      return live;
    },

    async connect() {
      try {
        const binding = await storedBinding();
        if (
          binding &&
          (await binding.directory.requestPermission({ mode: "readwrite" })) === "granted"
        ) {
          live = true;
          releaseUrls();
          deps.refresh();
          return;
        }
        await pick();
      } catch {
        deps.failed("Couldn't open the image folder");
      }
    },

    /** フォルダを指してもらう。保存されているかの確認は呼ぶ側（main.ts の駅）が済ませている */
    async chooseFolder() {
      try {
        await pick();
      } catch {
        deps.failed("Couldn't open the image folder");
      }
    },
  };
}

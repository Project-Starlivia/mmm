// Markdown からの相対パスで画像を読み書きする。
//
// **宣言（md から見てどこか）は .md の頭が持ち、許可（そのフォルダを読み書き
// してよい）だけをここが持つ。** ブラウザはパス文字列からフォルダハンドルを
// 作れないので、2 つに分かれること自体は避けられない — どちらが何の真実かを
// 言い切ることで、食い違いを事故にしない。

import { type Field, type Part, ask } from "./ask.ts";
import { handles } from "./handles.ts";
import { io } from "./io.ts";
import { bare } from "../map/cards.ts";
import { normalizePath, under } from "./head.ts";

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
  saveToDisk(blob: Blob): Promise<string | null>;
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

export function mdPath(rel: string): string {
  return rel.startsWith("../") ? rel : `./${rel.replace(/^\.\//, "")}`;
}

/**
 * **宣言の綴りとして通らない理由。** 通るなら null。
 *
 * ここが呼ばれるのは `resolve` が効かなかったとき — つまり**選んだフォルダは
 * md を含んでいない**。だから末尾のフォルダ名は必ず選んだものと一致するはずで、
 * 一致しなければ打ち間違い。`./`（md と同じ場所）もこの場では矛盾になる。
 *
 * 深さ（`../` が何段か）だけは確かめようが無い — ハンドルから親は辿れない。
 * **確かめられる嘘は全部止めて、確かめられないところだけ人を信じる。**
 */
export function folderProblem(typed: string, dirName: string): string | null {
  const norm = normalizePath(typed);
  if (norm === null) return "Use a path relative to the .md";
  const parts = norm.split("/").filter((part) => part !== "");
  const last = parts[parts.length - 1];
  if (last === undefined || last === "." || last === "..") {
    return `The folder you picked is named ${dirName}`;
  }
  return last === dirName ? null : `The folder you picked is named ${dirName}`;
}

/**
 * 選んだフォルダから md までの断片を、md から見たフォルダの相対に読み替える。
 * `FileSystemDirectoryHandle.resolve` が返すのは「フォルダ → md」なので、
 * **末尾のファイル名を除いた数**だけ上へ戻る（`["notes","a.md"]` なら md は
 * 1 段深いところに居るので `../`）。
 */
export function folderFromDoc(segments: string[]): string {
  const up = Math.max(0, segments.length - 1);
  return up === 0 ? "./" : "../".repeat(up);
}

// ---- 画像の名前 ----
//
// **決めるのも咎めるのも 1 か所**。`nameProblem` はたずね箱が打鍵のたびに
// 呼び、`nameParts` は通った値だけを受け取る — だめな値がここから先へ
// 進むことは無いので、書き込む側で二度確かめない。

/** 名前をフォルダの断片に割る（末尾が置くファイル） */
const nameParts = (typed: string): string[] =>
  typed
    .trim()
    .replace(/\.webp$/i, "")
    .split("/")
    .filter(Boolean);

/** その名前では置けない理由。置けるなら null */
export function nameProblem(typed: string): string | null {
  const parts = nameParts(typed);
  if (parts.length === 0) return "Give it a name";
  if (parts.some((part) => part === "." || part === ".."))
    return "Folder names cannot be . or ..";
  const bad = parts.join("").match(/[\\:*?"<>|]/)?.[0];
  return bad === undefined ? null : `A file name cannot contain ${bad}`;
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
  /** 果たせなかった。保存が先だと言うのもここ — 置き場所を持たない文書に
   *  画像を収めると約束したのはこちらで、相手の不注意ではない */
  failed: (msg: string) => void;
  refresh: () => void;
  /** いま頭が言っている宣言（正規化済み）。無ければ null */
  declared: () => string | null;
  /** 頭に宣言を書き込む */
  declare: (value: string) => void;
}): Assets {
  const assetUrls = new Map<string, string | null>();
  let cachedBinding: AssetBinding | null | undefined;
  /** 直近に確かめた「読めているか」。描くたびに同期で聞かれるので覚えておく */
  let live = false;

  // 宣言が無いのは「md と同じ場所」— prompt の既定値がずっと `./` だった
  // のと同じ意味。頭を持たない古い文書がそのまま読めるように、ここで倒す
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

  /** 握りが腐った。**捨てて、繋ぎ直しの駅へ落とす** — 腐ったまま持っていると
   *  次も同じところで失敗する。宣言は md に残るので、指し直せば戻る */
  function forget(): void {
    cachedBinding = null;
    live = false;
    const file = io.currentFile();
    if (file) void handles.forgetFolder(file);
    releaseUrls();
    deps.refresh();
  }

  /** 指してもらった結果。**宣言をどう決めるかは、ここでは決めない** */
  interface Picked {
    binding: AssetBinding;
    /** md から見た位置。`resolve` が効いたときだけ確か（効かなければ null） */
    computed: string | null;
    /** 効かなかったときの当て推量。人に確かめてもらう既定値になる */
    guess: string;
  }

  /** フォルダを指してもらい、握る。取りやめは null */
  async function pick(): Promise<Picked | null> {
    const file = io.currentFile();
    if (!file) return null;
    const pick = window.showDirectoryPicker;
    if (!pick) return null;
    let directory: FileSystemDirectoryHandle;
    try {
      directory = await pick({ startIn: file, mode: "readwrite" });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return null;
      throw error;
    }
    const binding = { doc: file, directory };
    await handles.rememberFolder(file, directory);
    cachedBinding = binding;
    live = true;
    // 選んだフォルダが md を含んでいれば、md から見た位置は**計算できる**
    // （`resolve` は「このフォルダから見た子孫」を返すので、末尾のファイル名を
    // 除いた数だけ上へ戻る）。含まなければ手がかりはフォルダ名だけ
    const segments = await directory.resolve(file);
    releaseUrls();
    deps.refresh();
    return {
      binding,
      computed: segments ? folderFromDoc(segments) : null,
      guess: `./${directory.name}/`,
    };
  }

  /** 宣言を聞く箱。初めて決めるときと、選び直して食い違ったときの両方 */
  async function askDeclaration(dirName: string, was: string | null, initial: string): Promise<string | null> {
    const field: Field = {
      value: initial,
      check: (typed) => folderProblem(typed, dirName),
    };
    const out = await ask(
      was === null
        ? {
            title: `Where is ${dirName}, seen from the .md?`,
            ok: "Save",
            parts: ["image-folder:", field],
          }
        : {
            title: "The folder changed — update the declaration?",
            note: "Image paths in the document will follow.",
            ok: "Update",
            cancel: "Keep as is",
            parts: ["image-folder:", field],
          },
    );
    return out === null ? null : (out[0] ?? null);
  }

  /**
   * 指してもらった結果に対して、宣言を決める。
   *
   * **道具は宣言を黙って書き換えない。** 書くのは 2 通りだけ —
   * `resolve` で**計算できた**とき（推量ではない）と、**人が箱で確定した**とき。
   *
   * `inline` は「呼ぶ側のフォームが位置の欄を持っている」の合図。
   * 画像を置く流れでは、フォルダも名前も 1 枚の中で聞きたいので、
   * ここでは聞かずに欄だけ返す。
   */
  async function settle(p: Picked, inline: boolean): Promise<Field | null> {
    const was = deps.declared();
    const dirName = p.binding.directory.name;
    if (was === null) {
      if (p.computed !== null) {
        deps.declare(p.computed);
        return null;
      }
      if (inline) return { value: p.guess, check: (t) => folderProblem(t, dirName) };
      const typed = await askDeclaration(dirName, null, p.guess);
      if (typed !== null) deps.declare(typed);
      return null;
    }
    // 記録があるのに別の場所を指された。**黙って書き換えない** — 直すのも、
    // 記録を古いままにするのも、人が決める（握りはもう移っている）
    const now = p.computed ?? p.guess;
    if (normalizePath(now) !== normalizePath(was)) {
      const typed = await askDeclaration(dirName, was, now);
      if (typed !== null) deps.declare(typed);
    }
    return null;
  }

  /**
   * 書けるフォルダを用意する。握っていればそれ、無ければ指してもらう。
   * 返すのは「呼ぶ側のフォームに載せる位置の欄」（要らなければ null）。
   */
  async function ensureBinding(inline: boolean): Promise<{ binding: AssetBinding; folder: Field | null } | null> {
    const binding = await storedBinding();
    if (binding) {
      const state = await binding.directory.queryPermission({ mode: "readwrite" });
      if (
        state === "granted" ||
        (state === "prompt" &&
          (await binding.directory.requestPermission({ mode: "readwrite" })) === "granted")
      ) {
        return { binding, folder: null };
      }
      // 許可が下りない札は腐っている。捨ててから指し直してもらう
      forget();
    }
    const picked = await pick();
    if (!picked) return null;
    return { binding: picked.binding, folder: await settle(picked, inline) };
  }

  /**
   * フォルダの中に**既に在る**綴り（小文字・フォルダからの相対）。
   *
   * 名前がぶつかると `createWritable` は黙って上書きする。押す前に言えるよう、
   * 箱を開く時点で 1 度だけ数える。数えられなくても、上書きの警告が出ない
   * だけで先へは進める。
   */
  async function taken(dir: FileSystemDirectoryHandle): Promise<Set<string>> {
    const out = new Set<string>();
    const walk = async (d: FileSystemDirectoryHandle, prefix: string): Promise<void> => {
      for await (const [name, handle] of d.entries()) {
        const path = `${prefix}${name}`;
        // 型は名乗らせず確かめる（`kind` を見るだけでは絞り込めない）
        if (handle instanceof FileSystemDirectoryHandle) await walk(handle, `${path}/`);
        else out.add(path.toLowerCase());
      }
    };
    try {
      await walk(dir, "");
    } catch {
      /* 数えられない — 警告が出ないだけ */
    }
    return out;
  }

  async function loadAsset(path: string): Promise<void> {
    try {
      const binding = await storedBinding();
      if (!binding) return;
      const parts = assetTarget(declaredPath(), path);
      if (!parts) return;
      if ((await binding.directory.queryPermission({ mode: "read" })) !== "granted") return;
      const file = await nestedFile(binding.directory, parts, false);
      // 種類は名前から引く（`assetTarget` を通った時点で必ず絵）。
      // 以前はすべて `image/webp` と名乗らせていて、png も jpg も嘘だった
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
        const picked = await pick();
        if (picked) await settle(picked, false);
      } catch {
        deps.failed("Couldn't open the image folder");
      }
    },

    /**
     * フォルダを指してもらう。**繋ぎ直しも選び直しも同じ一手** —
     * 記録が無ければ宣言を決め、あって食い違えば直すか聞く（`settle`）。
     *
     * 保存されているかの確認は呼ぶ側（main.ts の駅）が済ませている。
     */
    async chooseFolder() {
      try {
        const picked = await pick();
        if (picked) await settle(picked, false);
      } catch {
        deps.failed("Couldn't open the image folder");
      }
    },

    async saveToDisk(blob) {
      let ready: { binding: AssetBinding; folder: Field | null } | null;
      try {
        // 位置の欄は**このフォームの中で**聞く（inline）。フォルダと名前は
        // 1 つの行き先の 2 つの部分でしかないので、箱を分けない
        ready = await ensureBinding(true);
      } catch {
        deps.failed("Couldn't open the image folder");
        return null;
      }
      if (!ready) return null;
      const { binding, folder } = ready;

      const now = new Date();
      const two = (value: number): string => String(value).padStart(2, "0");
      const initial =
        `${now.getFullYear()}-${two(now.getMonth() + 1)}-${two(now.getDate())}` +
        `-${two(now.getHours())}${two(now.getMinutes())}${two(now.getSeconds())}`;

      // **どれの名前を聞かれているのかを、絵が言う。** 何枚も続けて落とした
      // ときは、字だけでは区別が付かない
      const shot = URL.createObjectURL(blob);
      const here = await taken(binding.directory);
      const name: Field = {
        value: initial,
        check: (typed) => {
          const why = nameProblem(typed);
          if (why !== null) return why;
          const parts = nameParts(typed);
          const last = parts[parts.length - 1];
          if (last === undefined) return null;
          const at = [...parts.slice(0, -1), `${last}.webp`].join("/");
          return here.has(at.toLowerCase()) ? "That name is taken" : null;
        },
      };
      // **分かっているところは字、分からないところだけ欄。** 位置が計算
      // できていれば `./pics/` はただの字で、打てるのは名前だけになる
      const shape: Part[] = ["![](", folder ?? declaredPath(), name, ".webp)"];
      let out: string[] | null;
      try {
        out = await ask({ title: "Name this image", ok: "Save", parts: shape, preview: shot });
      } finally {
        URL.revokeObjectURL(shot);
      }
      if (out === null) return null;
      // 欄の並び順は `shape` の並び順。位置の欄があるなら先に居る
      const typed = folder ? (out[1] ?? "") : (out[0] ?? "");
      if (folder) deps.declare(out[0] ?? folder.value);

      const parts = nameParts(typed);
      const last = parts[parts.length - 1];
      if (last === undefined) return null;
      parts[parts.length - 1] = `${last}.webp`;

      try {
        const webpBlob = await webp(blob);
        const file = await nestedFile(binding.directory, parts, true);
        const stream = await file.createWritable();
        try {
          await stream.write(webpBlob);
        } finally {
          await stream.close();
        }
        const rel = `${declaredPath()}${parts.join("/")}`;
        // 鍵はカード側が問い合わせてくる形（裸）に合わせる。
        // md へ書くのは mdPath の形（`./x`）。
        assetUrls.set(bare(rel), URL.createObjectURL(webpBlob));
        return mdPath(rel);
      } catch {
        // **触って失敗した握りは腐っている。** 抜かれた USB・消されたフォルダ
        // を掴んだまま持っていると、次も同じところで転ぶ
        deps.failed("Couldn't save the image");
        forget();
        return null;
      }
    },
  };
}

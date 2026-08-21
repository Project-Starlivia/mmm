// ネイティブ本体（Rust）との窓口。パスは Rust が持ち、ここはテキストと
// 表示名だけを受け取る。ブラウザの File System Access API は使わない。

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { ask } from "@tauri-apps/plugin-dialog";

/** UI に渡る文書。text は常に LF。改行/文字コード/BOM は Rust 側だけが持つ。 */
export interface Doc {
  name: string;
  text: string;
}

export interface DocChange {
  text: string;
}

/** ドロップ 1 件。ネイティブ D&D はファイルの実パスを渡す。 */
export interface DropPayload {
  paths: string[];
  position: { x: number; y: number };
}

export const io = {
  /** 起動時の 1 枚（引数の .md か、前回のファイル）。無ければ null。 */
  startupDoc: () => invoke<Doc | null>("startup_doc"),
  /** 新規作成。現在のパスと監視を手放す。 */
  close: () => invoke<void>("close"),
  /** ネイティブの「開く」。キャンセルは null。 */
  openDialog: () => invoke<Doc | null>("open_dialog"),
  /** パス指定で開く（ドロップ）。 */
  openPath: (path: string) => invoke<Doc>("open_path", { path }),
  /** 上書き保存。パスが無ければ reject（"no-path"）。 */
  save: (text: string) => invoke<void>("save", { text }),
  /** 別名で保存。キャンセルは null。 */
  saveAs: (suggested: string, text: string) =>
    invoke<Doc | null>("save_as", { suggested, text }),
  /** 画像を解決してバイト列で返す。無ければ reject。 */
  resolveImage: (rel: string) => invoke<ArrayBuffer>("resolve_image", { rel }),
  /** フロントが作ったバイト列（WebP など）を rel へ書く。 */
  saveImage: (rel: string, bytes: Uint8Array) =>
    invoke<string>("save_image", { rel, bytes: Array.from(bytes) }),
  /** ディスク上の画像を rel へ複製する（ドロップされた実ファイル）。 */
  importImage: (src: string, rel: string) =>
    invoke<string>("import_image", { src, rel }),
  /** 絶対パスを現在のファイルからの相対へ。同ドライブでなければ null。 */
  relativize: (abs: string) => invoke<string | null>("relativize", { abs }),

  onDocChanged: (cb: (d: DocChange) => void): Promise<UnlistenFn> =>
    listen<DocChange>("doc:changed", (e) => cb(e.payload)),
  onDocRemoved: (cb: () => void): Promise<UnlistenFn> =>
    listen("doc:removed", () => cb()),
  onDrop: (cb: (d: DropPayload) => void): Promise<UnlistenFn> =>
    listen<DropPayload>("tauri://drag-drop", (e) => cb(e.payload)),

  /** ネイティブの確認ダイアログ（Yes/No）。true = Yes。
   * WebView の `window.confirm()` は Tauri で当てにならないので必ずこちらを使う。 */
  confirm: (message: string): Promise<boolean> =>
    ask(message, { title: "mmm", kind: "warning" }),

  /**
   * ウィンドウを閉じる要求を受ける。`isDirty` が偽ならそのまま閉じ、真なら
   * 一旦止めて破棄してよいか尋ね、Yes なら本当に閉じる。
   * ブラウザの `beforeunload` はネイティブの閉じるを止められないので、これが要る。
   */
  onCloseRequest: (
    isDirty: () => boolean,
    message: string,
  ): Promise<UnlistenFn> =>
    // getCurrentWindow() は非 Tauri 文脈で同期例外を投げる。マイクロタスクに
    // 逃がして「拒否」に変え、呼び出し側の .catch で拾えるようにする
    // （閉じる確認の登録失敗で boot 全体を巻き添えにしない）。
    Promise.resolve().then(() =>
      getCurrentWindow().onCloseRequested(async (e) => {
        if (!isDirty()) return;
        e.preventDefault(); // 同期で止める（await より前）
        if (await ask(message, { title: "mmm", kind: "warning" })) {
          await getCurrentWindow().destroy();
        }
      }),
    ),
};

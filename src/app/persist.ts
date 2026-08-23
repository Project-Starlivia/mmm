// 永続化の器。
//
// **持つのは見た目の好みだけ**（ブランドカラーとテーマ）。文書の控えや
// ファイルハンドルは持たない。ハンドルは IndexedDB の app/handles.ts が扱う。

export const LS_COLOR = "mmm.color";
export const LS_THEME = "mmm.theme";

/**
 * localStorage への読み書き。容量オーバーや無効化で例外が飛ぶので、
 * 呼ぶたびに try/catch を書かずに済むようにまとめる（読み取りも書き込み
 * と同じくらい無防備になりうる — private mode やポリシーで無効化された
 * 環境では getItem も投げるため、起動時の復元がここを通らないと丸ごと
 * 落ちかねない）。
 */
export function store(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* storage full / blocked */
  }
}

export function load(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

// 永続化の器。
//
// **持つのは見た目の好みだけ**（テーマとブランドカラー）。文書の控えも
// ファイルハンドルも持たない（ハンドルは IndexedDB の app/handles.ts が扱う）。

export const LS_THEME = "mmm.theme";
export const LS_COLOR = "mmm.color";

/** いま意味のあるキー。ここに無い `mmm.*` は過去の遺物として捨てる。 */
const OWNED: readonly string[] = [LS_THEME, LS_COLOR];

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

/**
 * 役目を終えた `mmm.*` を捨てる。消えたキーの名前を並べる移行リストは
 * 増え続けて誰も消せなくなるので、持ち物のほうを宣言して残りを掃く。
 * これまでに捨てたもの: text / savedText（.md と二重の真実になる）、
 * fileName / eol（読めば分かる）、panes / folderQuiet / edgeTune / migrated。
 */
export function sweep(): void {
  try {
    const dead = Object.keys(localStorage).filter(
      (k) => k.startsWith("mmm.") && !OWNED.includes(k),
    );
    for (const k of dead) localStorage.removeItem(k);
  } catch {
    /* storage blocked — 捨てられなくても実害は無い */
  }
}

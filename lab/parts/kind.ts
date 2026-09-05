// 表の語。parts.ts（DOM の部品）と map.ts（Mindmap 経由）の両方がここを見る。

export interface Part {
  name: string;
  /**
   * 状態の名前 → その状態の要素。1 状態 1 行で、呼び方がそのまま見える。
   * Storybook の CSF（story = 要素を返す名前付き関数）と同じ形 — その日が
   * 来たら story ファイルへ機械的に写せる
   */
  states: Record<string, () => Element>;
  /** 枠の高さ（px）。無ければ index.ts の既定 */
  height?: number;
}

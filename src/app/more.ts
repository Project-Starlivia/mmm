// 帯の `⋯`。低頻度だが消したくないものの受け皿。3 つの塊 — 戻す / 見た目 / 外に開く。
//
// 並びは純粋な表（files.ts と同じ作り）。いまの状態を受けて行を返し、
// 押されたら `Acts` を呼ぶだけ。

import type { MenuEntry } from "../map/menu.ts";

/** リポジトリの行き先。ここ 1 か所 */
export const REPO = "https://github.com/Project-Starlivia/mmm";

export interface More {
  light: boolean;
  /** リンクにまつわる押す前の但し書き。届いたら行に付く */
  linkNote: Promise<string[]>;
}

export interface Acts {
  undo(): void;
  redo(): void;
  pickColor(): void;
  toggleTheme(): void;
  /** 写せたか。写せたことは押した行の絵が言う */
  copyLink(): Promise<boolean>;
  open(url: string): void;
}

export function moreMenu(s: More, a: Acts): MenuEntry[] {
  return [
    { label: "Undo", key: "Mod+Z", mark: "undo-2", run: () => a.undo() },
    { label: "Redo", key: "Mod+Shift+Z", mark: "redo-2", run: () => a.redo() },
    "sep",
    { label: "Accent color", mark: "palette", run: () => a.pickColor() },
    // 絵は「押すと何になるか」（切り替えた先）を言う。字と同じ向き
    { label: s.light ? "Dark theme" : "Light theme", mark: s.light ? "moon" : "sun", run: () => a.toggleTheme() },
    "sep",
    // 但し書きは待たずに開いて、届いたら埋まる（測るのに gzip が要る）
    { label: "Copy link", mark: "link", note: s.linkNote, done: () => a.copyLink() },
    "sep",
    { label: "Shortcuts", mark: "keyboard", run: () => a.open(`${REPO}/blob/main/docs/shortcuts.md`) },
    { label: "GitHub", mark: "mark-github", run: () => a.open(REPO) },
  ];
}

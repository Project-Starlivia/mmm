// 帯の Files。文書に何かする道はここにまとめる。**画像フォルダもここ** —
// 「この .md の画像がどこに居るか」は文書ぜんぶの設定で、新規 / 開く / 保存と
// 同じ高さのもの。塊は 2 つ（.md と、その画像フォルダ）で、見出しが状態を
// 言い、続く行がそれに対してできること。**絵が付くのは、押せるものだけ。**
//
// 並びは純粋な表。いまの状態（`Files`）を受けて行を返し、押されたら `Acts` を
// 呼ぶだけ — 文書もファイルも知らない。並べて見る道具は好きな状態を渡す。

import type { MenuEntry } from "../map/menu.ts";
import type { Failed } from "./notice.ts";

/** 改名する相手そのものがディスクに無い（保存したらもう改名する必要が無いので、駅にならない） */
export const NOTHING_TO_RENAME = "Save the .md first — nothing on disk to rename yet";

/** その環境が改名を持たない。どのブラウザが、とは言わない（名指しは移り変わる） */
export const NO_RENAME_HERE = "This browser can't rename files";

/** File System Access API が無いブラウザで、Files のできない行と
 *  ショートカットの両方がこの理由を言う。しらせにもなる（notice.ts の FAILED の 1 つ） */
export const NO_FILE_ACCESS = "This browser cannot open or save files" satisfies Failed;

export interface Files {
  /** ディスク上の名前。まだ無ければ null */
  savedName: string | null;
  /** 覚えている文書の名前。いま開いているものは含まない */
  recent: string[];
  canOpen: boolean;
  canSave: boolean;
  canRename: boolean;
  canChooseFolder: boolean;
  /** 画像フォルダの状態の一言（`folderCaption`） */
  folder: string;
}

export interface Acts {
  newFile(): void;
  open(): void;
  openRecent(index: number): void;
  save(): void;
  saveAs(): void;
  rename(): void;
  chooseFolder(): void;
}

export function filesMenu(s: Files, a: Acts): MenuEntry[] {
  return [
    { caption: s.savedName ?? "not saved yet" },
    { label: "New", key: "Mod+Alt+N", mark: "file-plus", run: () => a.newFile() },
    { label: "Open", key: "Mod+O", mark: "folder-open", run: () => a.open(), disabled: !s.canOpen && NO_FILE_ACCESS },
    {
      // 覚えている文書。**選ぶのは人**（起動時に勝手に開き直すのはやめた）
      label: "Recent",
      mark: "clock",
      items: s.recent.map((name, i) => ({ label: name, run: () => a.openRecent(i) })),
      disabled: s.recent.length === 0 && "Nothing opened yet",
    },
    { label: "Save", key: "Mod+S", mark: "save", run: () => a.save(), disabled: !s.canSave && NO_FILE_ACCESS },
    // 「as」は Save と同じ操作の別名なので、絵は主の行にだけ付ける
    { label: "Save as", key: "Mod+Shift+S", run: () => a.saveAs(), disabled: !s.canSave && NO_FILE_ACCESS },
    {
      label: "Rename",
      mark: "pencil",
      run: () => a.rename(),
      disabled: !s.canRename ? NO_RENAME_HERE : s.savedName === null && NOTHING_TO_RENAME,
    },
    { caption: s.folder },
    {
      // **保存していないことでは沈めない。** 押した先で保存まで案内する（駅）。
      // 沈むのは、この環境がフォルダを選べないときだけ
      label: "Choose folder",
      mark: "folder",
      run: () => a.chooseFolder(),
      disabled: !s.canChooseFolder && NO_FILE_ACCESS,
    },
  ];
}

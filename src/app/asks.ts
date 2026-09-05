// アプリが聞くことの全部。**並べ方はここ 1 つ** — 器（ask.ts）は聞き方を
// 知らず、聞く場所（main.ts / assets.ts）は綴りを持たない。並べて見る道具も
// ここを読む。値が要るものは関数（聞く時点で決まるものを受ける）。

import type { Ask, Part } from "./ask.ts";

export const ASKS = {
  /** 未保存の文書を捨てて先へ進むか */
  discard: { title: "Discard unsaved changes?", ok: "Discard" },
  /** 画像を置く前に .md を保存してもらう。**壁ではなく駅** — 行程を先に見せる */
  place: { title: "Images need a place on disk. Save the .md, then pick a folder.", ok: "Save the .md…" },
  /** 開いた文書に画像があり、まだフォルダを握っていない */
  connect: (where: string): Ask => ({
    title: "Connect the image folder?",
    note: `Images here point to ${where}.`,
    ok: "Connect…",
    cancel: "Not now",
  }),
  /** ディスク上のファイルの名前を変える */
  rename: (name: string): Ask => ({ title: "New file name", ok: "Rename", parts: [{ value: name }] }),
  /** 貼る画像の名前。`shape` は「分かっているところは字、分からないところだけ欄」の並び */
  imageName: (shape: Part[], shot: string): Ask => ({ title: "Name this image", ok: "Save", parts: shape, preview: shot }),
} satisfies Record<string, Ask | ((...args: never[]) => Ask)>;

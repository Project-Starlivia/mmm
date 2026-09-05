// 部品 × 状態の表。**見本の値はここだけが持つ。** 見た目は 1 つも持たない —
// 状態 1 つは「src の部品をどう呼ぶか」の 1 行で、それがそのまま読める形。
//
// テーマは部品の話ではないので、ここには無い（index.ts が枠に振る）。

import { ICONS, icon } from "../../src/icons.ts";
import { notice } from "../../src/app/notice.ts";
import { paneHint } from "../../src/app/hint.ts";
import { type Ask, askForm } from "../../src/app/ask.ts";
import { type MenuEntry, menu } from "../../src/map/menu.ts";
import { drawBoard } from "../../src/app/draw.ts";
import type { Part } from "./kind.ts";
import { MAP } from "./map.ts";

const nothing = (): void => {};

/** 出ている状態のしらせ（`.on` は 4 秒の出入りの印。ここでは出しっぱなし） */
function shown(mark: Parameters<typeof notice>[0], msg: string, sorry: boolean): HTMLDivElement {
  const el = notice(mark, msg, sorry);
  el.classList.add("on");
  return el;
}

/** 開いたままのたずね。modal は top layer に出て枠に収まらないので `open` で置く */
function asked(a: Ask): HTMLDialogElement {
  const dlg = document.createElement("dialog");
  dlg.className = "ask";
  dlg.open = true;
  dlg.append(askForm(a, nothing).form);
  return dlg;
}

/** 灰色の四角。画像の名前を聞くときの「その画像」の代わり */
const SHOT =
  "data:image/svg+xml," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="100"><rect width="160" height="100" fill="#888"/></svg>',
  );

const MENU_PLAIN: MenuEntry[] = [
  { label: "Add child", key: "Tab", run: nothing },
  { label: "Add sibling", key: "Enter", run: nothing },
  "sep",
  { label: "Delete", key: "Del", run: nothing },
];

export const PARTS: Part[] = [
  {
    name: "icons",
    height: 100,
    states: {
      all: () => {
        const row = document.createElement("div");
        row.style.cssText = "display:flex;gap:12px;padding:16px;flex-wrap:wrap";
        for (const n of ICONS) row.append(icon(n));
        return row;
      },
    },
  },
  {
    name: "notice",
    height: 110,
    states: {
      failed: () => shown("circle-alert", "Couldn't save — the folder is gone", true),
      // アプリで blocked が出るのは 1 箇所（書き出すものが無いときの Mod+E）
      blocked: () => shown("triangle-alert", "Nothing to export yet", false),
    },
  },
  {
    name: "pane-hint",
    height: 160,
    states: {
      md: () => paneHint("Write a ", "# heading", " to start"),
      map: () => paneHint("Nothing to show yet — write a ", "# heading", ""),
    },
  },
  {
    name: "ask",
    height: 300,
    states: {
      "yes-no": () => asked({ title: "Discard unsaved changes?", ok: "Discard", cancel: "Keep" }),
      field: () => asked({ title: "Rename", ok: "Rename", parts: [{ value: "notes.md" }] }),
      "text-field-text": () =>
        asked({ title: "Image name", ok: "Insert", parts: ["![](", { value: "shot-1" }, ".webp)"] }),
      preview: () =>
        asked({
          title: "Image name",
          note: "Saved next to the .md",
          ok: "Insert",
          parts: ["![](", { value: "shot-1" }, ".webp)"],
          preview: SHOT,
        }),
      invalid: () =>
        asked({
          title: "Rename",
          ok: "Rename",
          parts: [{ value: "a/b", check: (v) => (v.includes("/") ? "No slashes" : null) }],
        }),
    },
  },
  {
    name: "menu",
    height: 220,
    states: {
      plain: () => menu(MENU_PLAIN),
      mark: () =>
        menu([
          { label: "Recent", mark: "clock", run: nothing },
          { label: "Shortcuts", mark: "keyboard", run: nothing },
        ]),
      note: () =>
        menu([
          { label: "Copy link", note: ["12 KB"], run: nothing },
          {
            label: "Copy link (slow)",
            note: new Promise((r) => setTimeout(() => r(["12 KB", "gzip"]), 800)),
            run: nothing,
          },
        ]),
      disabled: () =>
        menu([
          { label: "Rename", disabled: true, run: nothing },
          { label: "Save", disabled: "Save the .md first", run: nothing },
          { label: "Close", run: nothing },
        ]),
      caption: () =>
        menu([
          { caption: "notes.md", mark: "file" },
          { label: "Rename", run: nothing },
          { label: "Save", run: nothing },
          "sep",
          { caption: "not saved yet" },
        ]),
      nested: () =>
        menu([
          { label: "Add", items: MENU_PLAIN, run: nothing },
          { label: "Delete", run: nothing },
        ]),
      done: () => menu([{ label: "Copy", mark: "copy", done: () => Promise.resolve(true) }]),
    },
  },
  {
    name: "draw",
    height: 560,
    states: {
      board: () => {
        // 窓ごと出す（`.draw` は窓の中に載るもの）。題と足元は showDrawing のものと同じ
        const dlg = document.createElement("dialog");
        dlg.className = "ask";
        dlg.open = true;
        const form = document.createElement("form");
        form.method = "dialog";
        const title = document.createElement("p");
        title.className = "title";
        title.textContent = "Draw";
        form.append(title, drawBoard().el);
        dlg.append(form);
        return dlg;
      },
    },
  },
  MAP,
];

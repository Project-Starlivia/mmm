// 部品 × 状態の表。**見本の値は src の表から引く** — 絵の名前（icons.ts）、
// しらせの言葉（notice.ts）、言い出し（hint.ts）、たずね（asks.ts）、メニューの
// 並び（context.ts / files.ts / more.ts / export.ts）。ここが持つのは「どの状態で
// 呼ぶか」だけで、綴りも並びも持たない。
//
// テーマは部品の話ではないので、ここには無い（index.ts が枠に振る）。

import { ICONS, icon } from "../../src/icons.ts";
import { BLOCKED, FAILED, notice } from "../../src/app/notice.ts";
import { paneHint } from "../../src/app/hint.ts";
import { type Ask, askForm } from "../../src/app/ask.ts";
import { ASKS } from "../../src/app/asks.ts";
import { menu } from "../../src/map/menu.ts";
import { contextItems, menuOf } from "../../src/map/context.ts";
import { type Files, filesMenu } from "../../src/app/files.ts";
import { moreMenu } from "../../src/app/more.ts";
import { exportWays } from "../../src/app/export.ts";
import { drawForm } from "../../src/app/draw.ts";
import { NONE } from "../../src/map/select.ts";
import type { Part } from "./kind.ts";
import { MAP, named, sample } from "./map.ts";

const nothing = (): void => {};

/**
 * 出ている状態のしらせ（`.on` は 4 秒の出入りの印。ここでは出しっぱなし）。
 * 本物は帯の下に fixed で浮くが、並べて見るには流れの中へ置く — 置き場所は
 * 道具の話で、見た目（器・字・印）は本体のまま
 */
function shown(mark: Parameters<typeof notice>[0], msg: string, sorry: boolean): HTMLDivElement {
  const el = notice(mark, msg, sorry);
  el.classList.add("on");
  el.style.position = "static";
  el.style.transform = "none";
  return el;
}

/** 開いたままの窓。modal は top layer に出て枠に収まらないので `open` で置く */
function opened(form: HTMLFormElement): HTMLDialogElement {
  const dlg = document.createElement("dialog");
  dlg.className = "ask";
  dlg.open = true;
  dlg.append(form);
  return dlg;
}
const asked = (a: Ask): HTMLDialogElement => opened(askForm(a, nothing).form);

/** 灰色の四角。画像の名前を聞くときの「その画像」の代わり */
const SHOT =
  "data:image/svg+xml," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="100"><rect width="160" height="100" fill="#888"/></svg>',
  );

/** 右クリック。見本の木の、その名前のノードを選んでいるとき */
function context(label: string | null): HTMLDivElement {
  const { view, L } = sample();
  const id = label === null ? null : named(view, label).id;
  const sel = id === null ? NONE : { ids: [id], anchor: id };
  return menu(menuOf(contextItems(L, sel), nothing));
}

const SAVED: Files = {
  savedName: "notes.md",
  recent: ["ideas.md", "todo.md"],
  canOpen: true,
  canSave: true,
  canRename: true,
  canChooseFolder: true,
  folder: "pics",
};
const FILES_ACTS = {
  newFile: nothing,
  open: nothing,
  openRecent: nothing,
  save: nothing,
  saveAs: nothing,
  rename: nothing,
  chooseFolder: nothing,
};
const MORE_ACTS = {
  undo: nothing,
  redo: nothing,
  pickColor: nothing,
  toggleTheme: nothing,
  copyLink: () => Promise.resolve(true),
  open: nothing,
};
/** 書き出しの並びが要るもの。出すもの以外は使われない */
const exportDeps = (empty: boolean) => ({
  map: { exportSvg: () => Promise.resolve(null) },
  name: () => "notes.md",
  failed: nothing,
  blocked: nothing,
  empty: () => empty,
});

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
    states: {
      all: () => {
        const col = document.createElement("div");
        col.style.cssText = "display:flex;flex-direction:column;align-items:flex-start;gap:6px;padding:12px";
        for (const m of FAILED) col.append(shown("circle-alert", m, true));
        for (const m of BLOCKED) col.append(shown("triangle-alert", m, false));
        return col;
      },
    },
  },
  {
    name: "pane-hint",
    height: 160,
    states: {
      md: () => paneHint("md"),
      map: () => paneHint("map"),
    },
  },
  {
    name: "ask",
    height: 300,
    states: {
      discard: () => asked(ASKS.discard),
      place: () => asked(ASKS.place),
      connect: () => asked(ASKS.connect("./pics/")),
      rename: () => asked(ASKS.rename("notes.md")),
      "image-name": () => asked(ASKS.imageName(["![](", "./pics/", { value: "2026-09-05-101500" }, ".webp)"], SHOT)),
      "image-name-taken": () =>
        asked(
          ASKS.imageName(["![](", "./pics/", { value: "shot", check: () => "That name is taken" }, ".webp)"], SHOT),
        ),
    },
  },
  {
    name: "menu",
    height: 380,
    states: {
      "context-node": () => context("Left"),
      "context-root": () => context("mmm"),
      "context-folded": () => context("hidden"),
      "context-none": () => context(null),
      "files-saved": () => menu(filesMenu(SAVED, FILES_ACTS)),
      "files-unsaved": () =>
        menu(filesMenu({ ...SAVED, savedName: null, recent: [], folder: "no folder" }, FILES_ACTS)),
      "files-no-access": () =>
        menu(
          filesMenu(
            { ...SAVED, savedName: null, canOpen: false, canSave: false, canRename: false, canChooseFolder: false },
            FILES_ACTS,
          ),
        ),
      "more-dark": () => menu(moreMenu({ light: false, linkNote: Promise.resolve([]) }, MORE_ACTS)),
      "more-light-noted": () =>
        menu(
          moreMenu(
            { light: true, linkNote: Promise.resolve(["Images won't travel", "Long link — may be cut"]) },
            MORE_ACTS,
          ),
        ),
      "export-ways": () => menu(exportWays(exportDeps(false))),
      "export-empty": () => menu(exportWays(exportDeps(true))),
    },
  },
  {
    name: "draw",
    height: 560,
    states: { open: () => opened(drawForm({ cancel: nothing, insert: nothing }).form) },
  },
  MAP,
];

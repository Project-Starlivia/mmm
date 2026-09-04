// 右クリックメニューの行。何をするかは Intent で言い、沈む行は理由を持つ。
// キーの表（keys.ts）と同じ作り方を引き、意味を 2 か所に書かない。

import type * as core from "../coreApi.ts";
import type { IconName } from "../icons.ts";
import { type Intent, keyed } from "./keys.ts";
import type { Layout } from "./layout.ts";
import type { Selection } from "./select.ts";

export interface Item {
  label: string;
  key?: string;
  mark?: IconName;
  /** null なら沈む（why が理由） */
  intent: Intent | null;
  why?: string;
  items?: Item[];
}
export type Entry = Item | "sep";

const ONE = "Select one node";

const press = (L: Layout, sel: Selection, key: string, shift = false, mod = false): Intent | null =>
  keyed(L, sel, { key, shift, mod, alt: false });

export function contextItems(L: Layout, sel: Selection): Entry[] {
  const solo = sel.ids.length === 1 && sel.anchor !== null ? sel.anchor : null;
  const node = sel.anchor === null ? null : (L.boxes.get(sel.anchor)?.node ?? null);
  /** 宛先が 1 つに決まらないと沈む行の intent / why */
  const one = (intent: Intent | null): Pick<Item, "intent" | "why"> =>
    solo === null ? { intent: null, why: ONE } : { intent };
  const folded = node?.fold !== null && node?.fold !== undefined;
  // Below / Above は「押せば足す」が常に正しい（Enter は名前の無いノードでは
  // 「埋める」に化けるが、メニューの Below/Above はそれでは困る）。ここだけ
  // press を通さず、addNode を直に組む
  const belowAbove = (at: core.NodePlace): Intent | null =>
    solo === null ? null : { kind: "op", op: { kind: "addNode", at, labels: [""] }, edit: true };
  return [
    {
      label: "Add",
      key: "Tab",
      ...one(press(L, sel, "Tab")),
      items: [
        { label: "Child", key: "Tab", ...one(press(L, sel, "Tab")) },
        { label: "Below", key: "Enter", ...one(solo === null ? null : belowAbove({ kind: "after", node: solo })) },
        {
          label: "Above",
          key: "Shift+Enter",
          ...one(solo === null ? null : belowAbove({ kind: "before", node: solo })),
        },
        { label: "Parent", key: "Shift+Tab", ...one(press(L, sel, "Tab", true)) },
      ],
    },
    { label: "Rename", key: "Mod+Enter", mark: "pencil", ...one(press(L, sel, "Enter", false, true)) },
    "sep",
    {
      label: folded ? "Show (unfold)" : "Hide (fold)",
      key: "Shift+H",
      mark: folded ? "chevrons-up-down" : "chevrons-down-up",
      // Implicit（label === null）は理由を持つ。anchor が無い（node === null）だけなら、
      // 沈む理由は「選んでいない」こと自体が語るので why は付けない
      intent: node === null || node.label === null ? null : press(L, sel, "H", true),
      ...(node !== null && node.label === null ? { why: "Nothing to fold here" } : {}),
    },
    {
      label: "Flip side",
      mark: "flip-horizontal",
      ...(sel.anchor === null || L.boxes.get(sel.anchor)?.parent === null
        ? { intent: null, why: "The root has no side" }
        : { intent: { kind: "op", op: { kind: "flipSide", id: sel.anchor }, edit: false } }),
    },
    "sep",
    { label: "Link", key: "Shift+L", mark: "link", ...one(solo === null ? null : { kind: "link", id: solo }) },
    { label: "Code", key: "Shift+C", mark: "code", ...one(solo === null ? null : { kind: "code", id: solo }) },
    { label: "Draw", key: "Shift+D", mark: "paintbrush", ...one(solo === null ? null : { kind: "draw", id: solo }) },
    "sep",
    { label: "Delete", key: "Del", mark: "trash-2", intent: press(L, sel, "Delete") },
  ];
}

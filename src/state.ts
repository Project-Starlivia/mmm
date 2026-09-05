// 文書から導けるものは全部 EditorState に居る。
//
// CodeMirror が構文木を `syntaxTree(state)` の StateField で持つのと同じ位置に、
// core の答え（View + 地番）を置く。地図の選択の位置・持ち主・選択もここ。
// 1 トランザクション = 1 サイクルで、位置は CodeMirror が編集で写す（`mapPos`）。
// DOM を知らない — node の試験でトランザクションを流して固定する（test/state.test.ts）。
//
// field の依存はアクセス時に解ける（`tr.state.field(other)` で other の新しい値が
// 先に計算される。並べ順は関係ない。循環は投げる）— ai-docs/codemirror.md。
// 決めは docs/superpowers/specs/2026-09-05-holder-design.md。

import { type EditorState, type Extension, StateEffect, StateField, type Transaction } from "@codemirror/state";
import * as core from "./coreApi.ts";
import { type Anchors, type Caret, type Holder, derive } from "./caret.ts";
import type { Choice } from "./map/select.ts";

/** core が読んだ木と地番。doc が変わったときだけ読み直す */
export const tree = StateField.define<core.Survey>({
  create: (s) => core.survey(s.doc.toString()),
  update: (v, tr) => (tr.docChanged ? core.survey(tr.newDoc.toString()) : v),
});

/** 地図で選ぶ・引き継ぐ・捨てる */
export const setAnchors = StateEffect.define<Anchors>();
/** 操作の focus（後の木の id）。anchors が同じトランザクションの後の木で位置に写す。null は空に */
export const focused = StateEffect.define<number | null>();
/** フォーカスがペインに入った */
export const setHolder = StateEffect.define<Holder>();

/** 選択を持っている側。窓やメニューへ抜けても変わらない（粘る）。起動は md */
export const holder = StateField.define<Holder>({
  create: () => "md",
  update(v, tr) {
    for (const e of tr.effects) if (e.is(setHolder)) v = e.value;
    return v;
  },
});

/** 位置を編集で写す。挿入がちょうどその位置なら前に留まる（assoc = -1）— ラベルの頭に字を打てば、その字がラベルの先頭 */
const carry = (tr: Transaction, a: Anchors): Anchors => {
  if (a === null) return null;
  const at = (p: number): number => tr.changes.mapPos(p, -1);
  if (a.kind === "card") return { kind: "card", at: at(a.at) };
  return { kind: "nodes", at: a.at.map(at), anchor: a.anchor === null ? null : at(a.anchor) };
};

/** 地図の選択の位置。doc が変われば写り、effect で置き換わる */
export const anchors = StateField.define<Anchors>({
  create: () => null,
  update(v, tr) {
    if (tr.docChanged) v = carry(tr, v);
    for (const e of tr.effects) {
      if (e.is(setAnchors)) v = e.value;
      if (e.is(focused)) v = anchorsOf(tr.state.field(tree), e.value);
    }
    return v;
  },
});

/** md のカーソル。head は主カーソルの頭 */
export const caretOf = (s: EditorState): Caret => ({
  ranges: s.selection.ranges.map((r) => ({ from: r.from, to: r.to })),
  head: s.selection.main.head,
});

const derived = (s: EditorState): Choice => {
  const t = s.field(tree);
  return derive(t.view, t.spots, s.field(holder), caretOf(s), s.field(anchors));
};

/** 選択。持ち主が決める（caret.ts の derive） */
export const choice = StateField.define<Choice>({
  create: derived,
  update: (_, tr) => derived(tr.state),
});

export const fields: Extension = [tree, holder, anchors, choice];

/** focus の id をその木の地番で位置に。ノードならラベルの頭、中身なら原文の頭。無ければ null */
export function anchorsOf(t: core.Survey, id: number | null): Anchors {
  if (id === null) return null;
  const s = t.spots.get(id);
  if (!s) return null;
  if (!core.isNode(t.view, id)) return { kind: "card", at: s.from };
  return s.label === null ? null : { kind: "nodes", at: [s.label], anchor: s.label };
}

/** 選択（id）をその木の地番で位置に。地図で選んだときの setAnchors の値。Implicit は行が無いので入らない */
export function anchorsFor(t: core.Survey, c: Choice): Anchors {
  if (c.kind === "card") {
    const s = t.spots.get(c.id);
    return s ? { kind: "card", at: s.from } : null;
  }
  const label = (id: number): number | null => t.spots.get(id)?.label ?? null;
  const at = c.sel.ids.flatMap((id) => {
    const l = label(id);
    return l === null ? [] : [l];
  });
  return { kind: "nodes", at, anchor: c.sel.anchor === null ? null : label(c.sel.anchor) };
}

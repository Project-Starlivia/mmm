// 文書から導けるものは全部 EditorState に居る。
//
// CodeMirror が構文木を `syntaxTree(state)` の StateField で持つのと同じ位置に、
// core の読み（木 + 地番の持ち手）を置く。地図の選択の位置・持ち主・選択もここ。
// 1 トランザクション = 1 サイクルで、位置は CodeMirror が編集で写す（`mapPos`）。
// 選択がどのノードかは core が決める（`core.chosen`）。
// DOM を知らない — node の試験でトランザクションを流して固定する（test/state.test.ts）。
//
// field の依存はアクセス時に解ける（`tr.state.field(other)` で other の新しい値が
// 先に計算される。並べ順は関係ない。循環は投げる）— ai-docs/codemirror.md。
// 決めは docs/superpowers/specs/2026-09-05-holder-design.md。

import { type EditorState, type Extension, StateEffect, StateField, type Transaction } from "@codemirror/state";
import * as core from "./coreApi.ts";

/** core が読んだ木と地番（持ち手）。doc が変わったときだけ読み直す */
export const tree = StateField.define<core.Survey>({
  create: (s) => core.survey(s.doc.toString()),
  update: (v, tr) => (tr.docChanged ? core.survey(tr.newDoc.toString()) : v),
});

/** 地図で選ぶ・引き継ぐ・捨てる */
export const setAnchors = StateEffect.define<core.Anchors>();
/** 操作の focus（後の木の id）。anchors が同じトランザクションの後の木で位置に写す。null は空に */
export const focused = StateEffect.define<number | null>();
/** フォーカスがペインに入った */
export const setHolder = StateEffect.define<core.Holder>();

/** 選択を持っている側。窓やメニューへ抜けても変わらない（粘る）。起動は md */
export const holder = StateField.define<core.Holder>({
  create: () => "md",
  update(v, tr) {
    for (const e of tr.effects) if (e.is(setHolder)) v = e.value;
    return v;
  },
});

/** 位置を編集で写す。挿入がちょうどその位置なら前に留まる（assoc = -1）— ラベルの頭に字を打てば、その字がラベルの先頭 */
const carry = (tr: Transaction, a: core.Anchors): core.Anchors => {
  if (a === null) return null;
  const at = (p: number): number => tr.changes.mapPos(p, -1);
  if (a.kind === "card") return { kind: "card", at: at(a.at) };
  return { kind: "nodes", at: a.at.map(at), anchor: a.anchor === null ? null : at(a.anchor) };
};

/** 地図の選択の位置。doc が変われば写り、effect で置き換わる */
export const anchors = StateField.define<core.Anchors>({
  create: () => null,
  update(v, tr) {
    if (tr.docChanged) v = carry(tr, v);
    for (const e of tr.effects) {
      if (e.is(setAnchors)) v = e.value;
      if (e.is(focused)) v = core.anchorsOf(tr.state.field(tree), e.value);
    }
    return v;
  },
});

/** md のカーソル。head は主カーソルの頭 */
export const caretOf = (s: EditorState): core.Caret => ({
  ranges: s.selection.ranges.map((r) => ({ from: r.from, to: r.to })),
  head: s.selection.main.head,
});

const derived = (s: EditorState): core.Choice =>
  core.chosen(s.field(tree), s.field(holder), caretOf(s), s.field(anchors));

/** 同じものを選んでいるか */
const sameChoice = (a: core.Choice, b: core.Choice): boolean => {
  if (a.kind === "nodes" && b.kind === "nodes") {
    return (
      a.sel.anchor === b.sel.anchor &&
      a.sel.ids.length === b.sel.ids.length &&
      a.sel.ids.every((id, i) => id === b.sel.ids[i])
    );
  }
  return a.kind === "card" && b.kind === "card" && a.id === b.id;
};

/** 選択。持ち主が決める（core の chosen）。同じものを選んだままなら**前の値のまま** —
 *  下の段は値が変わったかを identity 1 つで見分けられる */
export const choice = StateField.define<core.Choice>({
  create: derived,
  update(v, tr) {
    const next = derived(tr.state);
    return sameChoice(v, next) ? v : next;
  },
});

export const fields: Extension = [tree, holder, anchors, choice];

/**
 * md 側で薄く塗る範囲。**地図が持つ間だけ**（md が持つ間はカーソルそのものが在る）。
 * ノードは地番そのもの（子孫込み）、カードは中身の原文。無い地番は落とす
 */
export function highlightRanges(s: EditorState): core.Range[] {
  if (s.field(holder) !== "map") return [];
  return core.ranges(s.field(tree), s.field(choice));
}

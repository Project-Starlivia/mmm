// 文書から導けるものは全部 EditorState に居る。**導くだけの field と、
// トランザクションに編集を足す 1 つの filter**（`followImageFolder`）。
//
// CodeMirror が構文木を `syntaxTree(state)` の StateField で持つのと同じ位置に、
// core の読み（木 + 地番の持ち手）を置く。地図の選択の位置・持ち主・選択もここ。
// 1 トランザクション = 1 サイクルで、位置は CodeMirror が編集で写す（`mapPos`）。
// 選択がどのノードかは core が決める（`core.chosen`）。選択も位置も持ち手のまま持つ。
// DOM を知らない — node の試験でトランザクションを流して固定する（test/state.test.ts）。
//
// field の依存はアクセス時に解ける（`tr.state.field(other)` で other の新しい値が
// 先に計算される。並べ順は関係ない。循環は投げる）— ai-docs/codemirror.md。
// 決めは docs/superpowers/specs/2026-09-05-holder-design.md。

import { EditorState, type Extension, StateEffect, StateField, type Transaction } from "@codemirror/state";
import * as core from "./app.ts";

/** core が読んだ木と地番（持ち手）。doc が変わったときだけ読み直す */
export const tree = StateField.define<core.Survey>({
  create: (s) => core.survey(s.doc.toString()),
  update: (v, tr) => (tr.docChanged ? core.survey(tr.newDoc.toString()) : v),
});

/**
 * 画像の追従が判定に使う「打ち始めの md」（#57）。宣言を打ち替えている間ずっと
 * 打ち始めの姿を指し、打ち終われば今の姿に移る。
 *
 * **頭を触らなかった打鍵が基準を更新する。** 引っ越しは 1 打鍵で終わらず、
 * `./p/` → `./img/` は途中で `./` を通る。1 打鍵前を基準にすると、その `./` を見て
 * 「md の下の相対パス全部」を掴み、無関係な画像まで連れて行く。**基準を凍らせれば、
 * 打ち始めに宣言の下だったかどうかを何回目の打鍵でも同じように問える。**
 *
 * 追従が書き戻す本文は頭を触らないので、追従中の打鍵は必ず基準を保つ。undo も
 * 頭を触るので保つが、宣言が基準と同じ値に戻れば追従が空振りして止まる
 */
export const base = StateField.define<string>({
  create: (s) => s.doc.toString(),
  update(v, tr) {
    if (!tr.docChanged) return v;
    const now = tr.newDoc.toString();
    // 問うのは「この打鍵が頭を触ったか」。基準の頭と比べると、打ち終わった後の
    // 打鍵がどれも「頭が違う」と言い続け、基準が二度と進まない
    return core.sameHead(tr.startState.doc.toString(), now) ? now : v;
  },
});

/** 地図で選ぶ・引き継ぐ・捨てる（null は無し） */
export const setAnchors = StateEffect.define<core.Anchors | null>();
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
const carry = (tr: Transaction, a: core.Anchors | null): core.Anchors | null =>
  a === null ? null : core.carry(a, (p) => tr.changes.mapPos(p, -1));

/** 地図の選択の位置。doc が変われば写り、effect で置き換わる */
export const anchors = StateField.define<core.Anchors | null>({
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
const caretOf = (s: EditorState): core.Caret => ({
  ranges: s.selection.ranges.map((r) => ({ from: r.from, to: r.to })),
  head: s.selection.main.head,
});

const derived = (s: EditorState): core.Choice =>
  core.chosen(s.field(tree), s.field(holder), caretOf(s), s.field(anchors));

/** 選択。持ち主が決める（core の chosen）。同じものを選んだままなら**前の値のまま** —
 *  下の段は値が変わったかを identity 1 つで見分けられる */
export const choice = StateField.define<core.Choice>({
  create: derived,
  update(v, tr) {
    const next = derived(tr.state);
    return core.sameChoice(v, next) ? v : next;
  },
});

export const fields: Extension = [tree, base, holder, anchors, choice];

/**
 * 頭の `image-folder:` を打ち替えたら、本文の画像パスを**同じトランザクションで**
 * 追従させる（#57）。**ここだけが書く** — 上の field は導くだけ。読みのサイクルから
 * 書くと「書くのは操作だけ」の線を跨ぐし、後から別の操作として流すと Undo が
 * 2 手に割れる。トランザクションが組まれる所で足せば、打鍵と追従が 1 手のまま残る。
 *
 * **判定の基準は打ち始めの md**（`base`）。1 打鍵前を基準にすると、打ち替えの
 * 途中で通る `./` が md の下の相対パスを全部掴む。
 *
 * **聞くのは文書が変わったときだけ。** core は宣言が動いていなければ頭の 1 行しか
 * 読まないので、打鍵ごとに通っても読みは走らない。`sequential` は「前の編集を当てた
 * 座標で次を読む」— core が返す列がその形
 */
export const followImageFolder = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged) return tr;
  const sets = core.followDeclaration(tr.startState.field(base), tr.newDoc.toString());
  if (sets.length === 0) return tr;
  return [tr, ...sets.map((changes) => ({ changes, sequential: true }))];
});

/**
 * md 側で薄く塗る範囲。**地図が持つ間だけ**（md が持つ間はカーソルそのものが在る）。
 * ノードは地番そのもの（子孫込み）、カードは中身の原文。無い地番は落とす
 */
export function highlightRanges(s: EditorState): core.Range[] {
  if (s.field(holder) !== "map") return [];
  return core.ranges(s.field(tree), s.field(choice));
}

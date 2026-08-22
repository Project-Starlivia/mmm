// core 内部の改行不変条件 (F-010): コアはどんなコマンドを通しても常に LF
// だけを持ち、CRLF を一切混ぜない。実際の改行の往復（開くとき CRLF→LF、
// 保存するとき LF→元の種別へ書き戻す）は Tauri 移行後は Rust 側
// （src-tauri/src/lib.rs の decode / encode_for_write、cargo test で
// 別途検証済み）が担う。ここではその実装は呼ばず、コア単体の LF 純度だけを
// 確かめる自前の adopt/toFile（CRLF↔LF の単純な相互変換）で代用する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, initDoc, getText, idOf, type Snapshot } from "./_helpers.ts";

/** 開くとき: CRLF/CR を LF へ正規化（Rust の decode() が実際にやること） */
const adopt = (raw: string): string => raw.replace(/\r\n?/g, "\n");
/** 保存するとき: LF を元の改行種別へ書き戻す（Rust の encode_for_write() が実際にやること） */
const toFile = (text: string, crlf: boolean): string =>
  crlf ? text.replace(/\n/g, "\r\n") : text;

const CRLF = "# r\r\n\r\n## a\r\n\r\n本文\r\n\r\n---\r\n\r\n## b\r\n";

/** いま保存したらどうなるか */
const saved = (): string => toFile(getText(), true);

test("E1: CRLF を開いてそのまま保存すると 1 バイトも変わらない", () => {
  initDoc(adopt(CRLF));
  assert.equal(saved(), CRLF);
});

test("E2: どのコマンドを通しても LF が混ざらない", () => {
  let s: Snapshot = initDoc(adopt(CRLF));
  const noLone = (step: string): void => {
    assert.ok(!/[^\r]\n/.test(saved()), `${step} で LF が混ざった`);
  };

  s = core.addChild(idOf(s.nodes, "a"), "");
  noLone("子を追加");
  s = core.renameNode(s.focus, "新しい子", "");
  noLone("名前を変更");
  s = core.moveNodes([idOf(s.nodes, "新しい子")], idOf(s.nodes, "b"), 2);
  noLone("ノードを移動");
  s = core.toggleHidden(idOf(s.nodes, "a"));
  noLone("折り畳み");
  s = core.toggleHidden(idOf(s.nodes, "a"));
  noLone("展開");
  s = core.deleteNodes([idOf(s.nodes, "b")]);
  noLone("削除");

  // 全部 undo すれば原文へバイト単位で戻る
  // （initDoc を挟むと undo スタックが消えるので、途中で呼ばないこと）
  let n = 0;
  while (s.canUndo && n < 30) {
    s = core.undo();
    n++;
  }
  assert.equal(saved(), CRLF, `undo ${n} 回で原文に戻らない`);
});

test("E3: LF の文書はそのまま LF（CR を足さない）", () => {
  const LF = "# r\n\n## a\n\n---\n\n## b\n";
  initDoc(adopt(LF));
  assert.equal(toFile(getText(), false), LF);
  assert.ok(!getText().includes("\r"), "CR が混ざった");
});

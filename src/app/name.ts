// 文書の名前。
//
// 名前は状態ではなく**導出**する。保存したファイルには名前があるのでそれを
// 名乗り、まだ無いなら本文の見出しから作る。「無題」という状態変数を持たない
// ので、`# 設計メモ` と打った瞬間からその文書は設計メモと呼ばれる。
//
// 表示にも、保存ダイアログの初期値にも同じものを使う。道具が出す提案は
// **常にファイル名として有効**であること（失敗してから拾いにいかない）。

import type { NodeInfo } from "../coreApi.ts";

/** 見出しが無い / 整形して何も残らない文書の名前 */
export const EMPTY_NAME = "empty";

// ファイル名に使えない文字（いちばん厳しい Windows に合わせる）と制御文字。
// パス区切りもここに含むので、名前が勝手に階層を作ることはない
const BAD = /[\\/:*?"<>|\x00-\x1f]+/g;

// MS-DOS 由来の予約名。拡張子を付けても予約のままなので `CON.md` も作れない
const RESERVED = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i;

// 実際の上限は 255（ext4/APFS はバイト、NTFS は UTF-16 単位）。バイトで
// 測っておけばどれも満たす。`.md` の 3 バイトを残して 250 で打ち切る。
// 日本語で 83 文字ぶんあり、**普段は誰も触らない安全柵**であって、
// 見た目を整えるためのものではない
const MAX_BYTES = 250;

const utf8Len = (s: string): number => new TextEncoder().encode(s).length;

/** 上限を超えないところまで、文字の境界で切る（サロゲートペアを割らない） */
function clampBytes(s: string, max: number): string {
  if (utf8Len(s) <= max) return s;
  let out = "";
  let n = 0;
  for (const ch of s) {
    const w = utf8Len(ch);
    if (n + w > max) break;
    out += ch;
    n += w;
  }
  return out;
}

/**
 * ラベルをファイル名にする。使えない文字で分けて `-` で繋ぐので、
 * `設計/検討` は `設計-検討`、`A: B` は `A-B` になる（空白はそのまま。
 * ファイル名として正しいものを削る理由が無い）。
 * 何も残らなければ空文字を返す — 呼び出し側が次の候補へ落ちる。
 */
export function toFileName(label: string): string {
  const joined = label
    .split(BAD)
    .map((s) => s.trim())
    .filter((s) => s !== "")
    .join("-");
  // Windows は末尾のドットと空白を黙って落とすので、こちらで先に落とす
  const cut = clampBytes(joined, MAX_BYTES).replace(/[. ]+$/, "");
  return RESERVED.test(cut) ? `${cut}_` : cut;
}

/**
 * まだ保存していない文書の名前（拡張子なし）。
 *
 * いちばん大きい見出し（`#` がいちばん少ないもの）のうち先頭を使う。同じ
 * 大きさが並べば先に書いたほうが勝つ。`##` しか無い文書ならそれがいちばん
 * 大きい。整形して何も残らなければ、文書順で最初の見出しへ落ちる。
 */
export function deriveName(nodes: NodeInfo[]): string {
  if (nodes.length === 0) return EMPTY_NAME;
  let top = nodes[0];
  for (const n of nodes) {
    if (n.depth < top.depth) top = n;
  }
  return toFileName(top.label) || toFileName(nodes[0].label) || EMPTY_NAME;
}

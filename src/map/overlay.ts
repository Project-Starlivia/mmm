// その場で直す入力欄を、SVG の上のどこに置くか。DOM を触らない算術だけの層。
//
// 入力欄は HTML（IME を SVG の中で走らせられないため）なので、**枠(border)と
// 余白(padding)は CSS ピクセルでズームに追従しない**。world の単位で組んでから
// 1 度だけ倍率を掛け、追従しないぶんを別に足す — これを間違えると、倍率 1 では
// 合っているのに 2 倍で箱と文字がずれる（実際にずれていた）。
//
// **文字の実測値は受け取る**。どう測るかはブラウザの仕事（map/metrics.ts）で、
// ここは置き場所しか決めない。おかげで「重なる条件」を関係として試験できる:
// 入力欄の中で文字が始まる位置は、SVG のラベルが始まる位置と画面座標で
// 一致しなければならない（test/overlay.test.ts）。

import type { Rect } from "./geometry.ts";
import type { Box } from "./layout.ts";
import { CODE_LINE } from "./cards.ts";
import { rowOf } from "./metrics.ts";
import type { View } from "./view.ts";

/** そのまま style へ入れる値（px） */
export interface Placement {
  left: number;
  top: number;
  width: number;
  height: number;
  fontSize: number;
  padding: number;
}

/** ラベルの入力欄の枠。拡大しない */
export const LABEL_BORDER = 2;
/** 余白をいくら縮めても、これだけは残す（文字が縁に貼り付かないように） */
export const LABEL_MIN_PAD = 2;

/** カードの入力欄の枠（拡大しない）と、内側の余白（world の単位） */
export const CARD_BORDER = 2;
export const CARD_PAD = 5;
/** カードの入力欄の字の大きさ（world の単位。カードのコードと同じ） */
export const CARD_FONT_PX = 11;

/**
 * ラベルの入力欄。ノードのラベル行に**ぴったり**重なる。
 * `textWidth` は world 単位で実測したラベルの文字幅（余白は含まない）。
 *
 * `box-sizing: border-box` なので文字は left + border + padding から始まる。
 * left を border ぶん**外へずらす**ことでその分が打ち消し、padding は SVG の
 * ラベルの x（= `rowOf().padX`）をそのまま倍率に掛けた値でよくなる。
 * 文字が箱より長くなったら右へ伸び、短いときは箱に重なったまま。
 */
export function labelPlacement(b: Box, view: View, textWidth: number): Placement {
  const row = rowOf(b.n);
  const wWorld = Math.max(b.w, textWidth + row.padX * 2);
  return {
    left: b.x * view.k + view.tx - LABEL_BORDER,
    top: b.y * view.k + view.ty - LABEL_BORDER,
    width: wWorld * view.k + LABEL_BORDER * 2,
    height: row.rowH * view.k + LABEL_BORDER * 2,
    fontSize: row.fontPx * view.k,
    padding: Math.max(row.padX * view.k, LABEL_MIN_PAD),
  };
}

/**
 * カードの入力欄。カードに重ね、**中身が増えたら下と右へ伸ばす** —
 * 打っている途中で文字が隠れると、何を書いているか分からなくなる。
 * 枠の分を足しておかないと最終行が 1〜2px 削れる。
 *
 * `text` は world 単位の実測（行数と、いちばん長い行の幅）。
 */
export function cardPlacement(
  rect: Rect,
  view: View,
  text: { lines: number; widest: number },
): Placement {
  const wWorld = Math.max(rect.w, text.widest + CARD_PAD * 2);
  const hWorld = Math.max(rect.h, text.lines * CODE_LINE + CARD_PAD * 2);
  return {
    left: rect.x * view.k + view.tx,
    top: rect.y * view.k + view.ty,
    width: wWorld * view.k + CARD_BORDER,
    height: hWorld * view.k + CARD_BORDER,
    fontSize: CARD_FONT_PX * view.k,
    padding: CARD_PAD * view.k,
  };
}

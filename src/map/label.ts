// ラベルのその場編集。SVG の中では IME を走らせられないので、箱の上に HTML の
// <input> を 1 つ重ねる。**打つたびに md へ書く**（キャンセルは存在しない。
// 打った字はもう md に在る — spec.md「Mindmap 側」）。IME の変換中は待ち、確定で書く。
//
// 枠(border)と余白(padding)は CSS ピクセルでズームに追従しないので、world の
// 単位で組んでから 1 度だけ倍率を掛け、追従しないぶんを別に足す — これを間違えると
// 倍率 1 では合っているのに 2 倍で箱と文字がずれる。

import type { Camera } from "./camera.ts";
import type { Box } from "./layout.ts";
import { labelFont, measure, rowOf } from "./metrics.ts";

/** そのまま style へ入れる値（px） */
export interface Placement {
  left: number;
  top: number;
  width: number;
  height: number;
  fontSize: number;
  padding: number;
}

/** 入力欄の枠。拡大しない */
export const LABEL_BORDER = 2;
/** 余白をいくら縮めても、これだけは残す（字が縁に貼り付かないように） */
export const LABEL_MIN_PAD = 2;

/**
 * 入力欄をノードのラベル行に**ぴったり**重ねる。`textWidth` は world 単位で実測した
 * 字の幅（余白は含まない）。`box-sizing: border-box` なので字は left + border + padding
 * から始まる。left を border ぶん外へずらせばその分が打ち消え、padding は SVG の
 * ラベルの x（= `rowOf().padX`）をそのまま倍率に掛けた値でよい。
 * 字が箱より長くなったら右へ伸び、短いときは箱に重なったまま。
 */
export function labelPlacement(b: Box, cam: Camera, textWidth: number): Placement {
  const row = rowOf(b.node);
  const wWorld = Math.max(b.w, textWidth + row.padX * 2);
  return {
    left: b.x * cam.k + cam.tx - LABEL_BORDER,
    top: b.y * cam.k + cam.ty - LABEL_BORDER,
    width: wWorld * cam.k + LABEL_BORDER * 2,
    height: row.rowH * cam.k + LABEL_BORDER * 2,
    fontSize: row.fontPx * cam.k,
    padding: Math.max(row.padX * cam.k, LABEL_MIN_PAD),
  };
}

/** 入力欄の器。開く / 打つたびに rename / 閉じる。値の意味は持たない */
export class LabelEditor {
  private input: HTMLInputElement;
  /** 読みのサイクルを越えて id を持つ唯一の場所。Rename は木の形を変えず
   *  番号を振り直さないので安全。形を変える操作が編集中に走ることは無い
   *  （欄が開いている間は keydown が地図へ届かない） */
  private id: number | null = null;
  private composing = false;
  private readonly pane: HTMLElement;
  private readonly rename: (id: number, label: string) => void;

  constructor(pane: HTMLElement, rename: (id: number, label: string) => void) {
    this.pane = pane;
    this.rename = rename;
    this.input = document.createElement("input");
    this.input.className = "label-editor";
    this.input.spellcheck = false;
    pane.append(this.input);
    this.input.addEventListener("compositionstart", () => {
      this.composing = true;
    });
    this.input.addEventListener("compositionend", () => {
      this.composing = false;
      this.write();
    });
    this.input.addEventListener("input", (e) => {
      if (this.composing || (e instanceof InputEvent && e.isComposing)) return;
      this.write();
    });
    this.input.addEventListener("keydown", (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      // 地図のキーへ流さない（Enter が「兄弟を足す」に化ける）
      e.stopPropagation();
      if (e.key === "Escape" || e.key === "Enter") {
        e.preventDefault();
        // キー由来の close だけ、地図へフォーカスを戻す。blur は既に
        // フォーカスが行き先を持っている最中なので奪わない（#3）
        this.close();
        this.pane.focus();
      } else if (e.key === "Tab") {
        // 編集中の Tab は無効（spec.md）
        e.preventDefault();
      }
    });
    // 欄の外を押す・md 側に触る・Mod+/ で移る — フォーカスが抜けたら閉じる
    this.input.addEventListener("blur", () => this.close());
  }

  editing(): number | null {
    return this.id;
  }

  /** 開く。カーソルは末尾（全選択しない）。seed があればそれが最初の字 */
  open(id: number, b: Box, cam: Camera, label: string, seed: string | null): void {
    this.id = id;
    this.input.value = seed ?? label;
    this.input.style.display = "block";
    this.place(b, cam);
    this.input.focus();
    const end = this.input.value.length;
    this.input.setSelectionRange(end, end);
    // 最初の字はもう欄に在るので、いまの値を md へ
    if (seed !== null) this.write();
  }

  /** 箱に追従する。書くたびに箱が変わるので、描き直しの後に呼ぶ */
  place(b: Box, cam: Camera): void {
    if (this.id === null) return;
    const p = labelPlacement(b, cam, measure(labelFont(rowOf(b.node)), this.input.value));
    const st = this.input.style;
    st.left = `${p.left}px`;
    st.top = `${p.top}px`;
    st.width = `${p.width}px`;
    st.height = `${p.height}px`;
    st.fontSize = `${p.fontSize}px`;
    st.paddingLeft = `${p.padding}px`;
    st.paddingRight = `${p.padding}px`;
    st.borderWidth = `${LABEL_BORDER}px`;
  }

  /** 閉じる。書くものは無い（もう書いてある）。二重に閉じても何も起きない */
  close(): void {
    if (this.id === null) return;
    // 変換中にフォーカスが抜けたなら、未確定ぶんを取りこぼさない
    // （keydown は isComposing で早期リターンするので、ここに来るのは blur だけ）
    if (this.composing) {
      this.composing = false;
      this.write();
    }
    this.id = null;
    this.input.style.display = "none";
  }

  private write(): void {
    if (this.id !== null) this.rename(this.id, this.input.value);
  }
}

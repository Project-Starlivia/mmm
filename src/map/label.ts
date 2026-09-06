// ラベルのその場編集。SVG の中では IME を走らせられないので、箱の上に HTML の
// <input> を 1 つ重ねる。**打つたびに md へ書く**（キャンセルは存在しない。
// 打った字はもう md に在る — spec.md「Mindmap 側」）。IME の変換中は待ち、確定で書く。
//
// 欄をどこに置くかは core（`core.labelPlace`）が数え、ここは style に入れるだけ。

import * as core from "../coreApi.ts";
import { measure } from "./measure.ts";

/** 入力欄の器。開く / 打つたびに rename / 閉じる。値の意味は持たない */
export class LabelEditor {
  private input: HTMLInputElement;
  /** 読みのサイクルを越えて id を持つ唯一の場所。Rename は木の形を変えず
   *  番号を振り直さないので安全。形を変える操作が編集中に走ることは無い
   *  （欄が開いている間は keydown が地図へ届かない） */
  private id: number | null = null;
  private composing = false;
  /** 最後に place() へ渡された配置と視点。打鍵のたびに欄を今の値へ合わせ直すのに使う
   *  （変換中は md へ書かず render も走らないので、ここから自分で place() する） */
  private last: { layout: core.Layout; cam: core.Camera } | null = null;
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
      // 欄は打った字の分だけ先に育つ（card.ts と同じ）。md へ書くかは別の話
      if (this.last) this.place(this.last.layout, this.last.cam);
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
  open(id: number, layout: core.Layout, cam: core.Camera, label: string, seed: string | null): void {
    this.id = id;
    this.input.value = seed ?? label;
    this.input.style.display = "block";
    this.place(layout, cam);
    this.input.focus();
    const end = this.input.value.length;
    this.input.setSelectionRange(end, end);
    // 最初の字はもう欄に在るので、いまの値を md へ
    if (seed !== null) this.write();
  }

  /** 箱に追従する。書くたびに箱が変わるので、描き直しの後に呼ぶ。
   *  箱が消えていれば（畳まれて埋もれた）閉じる */
  place(layout: core.Layout, cam: core.Camera): void {
    if (this.id === null) return;
    const p = core.labelPlace(layout, this.id, cam, this.input.value, measure);
    if (p === null) {
      this.close();
      return;
    }
    this.last = { layout, cam };
    const st = this.input.style;
    st.left = `${p.left}px`;
    st.top = `${p.top}px`;
    st.width = `${p.width}px`;
    st.height = `${p.height}px`;
    st.fontSize = `${p.fontSize}px`;
    st.paddingLeft = `${p.padding}px`;
    st.paddingRight = `${p.padding}px`;
    st.borderWidth = `${p.border}px`;
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
    this.last = null;
    this.input.style.display = "none";
  }

  private write(): void {
    if (this.id !== null) this.rename(this.id, this.input.value);
  }
}

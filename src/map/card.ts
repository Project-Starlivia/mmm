// カードのその場編集。ラベルと同じ理由で HTML を重ねるが、値の書き戻し方が違う
// — カードは打鍵のたびに書かず、**閉じるときに 1 回**書く（コードは打っている
// 途中の中間状態が md に流れると、フェンスが割れて木が壊れる。spec.md「C カード」）。
//
// 枠(border)と余白(padding)はズームに追従しない CSS ピクセルなので、labelPlacement
// と同じく world の単位で組んでから 1 度だけ倍率を掛ける。カードは `rect` が
// すでに描画と同じ内容の矩形（layout.cardRect）なので、入力欄の文字の始まりは
// その原点にそのまま重なる — 枠と余白は外側へ育つ。

import type { Camera } from "./camera.ts";
import type { Rect } from "./geometry.ts";
import { tokenizeBlock } from "./highlight.ts";
import type { Placement } from "./label.ts";
import { CODE_LINE, measure, monoFont } from "./metrics.ts";

/** 入力欄の枠。拡大しない */
export const CARD_BORDER = 2;
/** 入力欄の内側の余白（world の単位） */
export const CARD_PAD = 5;
/** 入力欄の字の大きさ（world の単位。カードのコードと同じ） */
export const CARD_FONT_PX = 11;

/**
 * カードの入力欄を、カードの矩形に重ねる。枠は `rect` の上に置き、余白は内側
 * （labelPlacement と同じ）— 外へ育てると隣の行に被る。中身が rect より
 * 大きければ、その分だけ下と右へ伸びる（打っている途中で文字が隠れると
 * 何を書いているか分からなくなる）。枠の分を足しておかないと最終行が削れる。
 */
export function cardPlacement(rect: Rect, cam: Camera, text: { lines: number; widest: number }): Placement {
  const wWorld = Math.max(rect.w, text.widest + CARD_PAD * 2);
  const hWorld = Math.max(rect.h, text.lines * CODE_LINE + CARD_PAD * 2);
  return {
    left: rect.x * cam.k + cam.tx,
    top: rect.y * cam.k + cam.ty,
    width: wWorld * cam.k + CARD_BORDER * 2,
    height: hWorld * cam.k + CARD_BORDER * 2,
    fontSize: CARD_FONT_PX * cam.k,
    padding: CARD_PAD * cam.k,
  };
}

/**
 * カードの入力欄の器。開く / place / 閉じるだけを知り、値の意味は持たない。
 * ラベル（`LabelEditor`）と違って**閉じるときに 1 回だけ**書く。
 */
export class CardEditor {
  private box: HTMLDivElement;
  private ink: HTMLPreElement;
  private textarea: HTMLTextAreaElement;
  /** 開いたときの値。閉じるとき、これと違えば書く（同じなら書かない） */
  private opened = "";
  private id: number | null = null;
  /** 最後に place() へ渡された rect / cam。中身だけが変わった打鍵の再配置に使う
   *  （書くのは閉じるときだけなので、打つたびに sync が地図を描き直すことはない） */
  private lastRect: Rect | null = null;
  private lastCam: Camera | null = null;
  private readonly pane: HTMLElement;
  private readonly commit: (id: number, text: string) => void;

  constructor(pane: HTMLElement, commit: (id: number, text: string) => void) {
    this.pane = pane;
    this.commit = commit;
    this.box = document.createElement("div");
    this.box.id = "card-editor";
    this.box.style.display = "none";
    this.ink = document.createElement("pre");
    this.ink.className = "card-ink";
    this.textarea = document.createElement("textarea");
    this.textarea.spellcheck = false;
    this.box.append(this.ink, this.textarea);
    pane.append(this.box);

    this.textarea.addEventListener("input", () => {
      this.paintInk();
      if (this.lastRect && this.lastCam) this.place(this.lastRect, this.lastCam);
    });
    this.textarea.addEventListener("keydown", (e) => {
      // 地図のキーへ流さない（Delete がカードを消すに化ける）
      e.stopPropagation();
      if (e.key === "Escape" || (e.key === "Enter" && (e.ctrlKey || e.metaKey))) {
        e.preventDefault();
        this.close();
        this.pane.focus();
      } else if (e.key === "Tab") {
        e.preventDefault();
      }
    });
    this.textarea.addEventListener("blur", () => this.close());
  }

  editing(): number | null {
    return this.id;
  }

  /** 開く。`from`/`to` は最初に選んでおく範囲（省略すれば末尾にカーソル） */
  open(id: number, rect: Rect, cam: Camera, text: string, from?: number, to?: number): void {
    this.id = id;
    this.opened = text;
    this.textarea.value = text;
    this.box.style.display = "block";
    this.paintInk();
    this.place(rect, cam);
    this.textarea.focus();
    const end = text.length;
    this.textarea.setSelectionRange(from ?? end, to ?? from ?? end);
  }

  /** カードに追従する。書くたび・視点を動かすたびに呼ぶ */
  place(rect: Rect, cam: Camera): void {
    if (this.id === null) return;
    this.lastRect = rect;
    this.lastCam = cam;
    const lines = this.textarea.value.split("\n");
    const p = cardPlacement(rect, cam, {
      lines: lines.length,
      widest: Math.max(...lines.map((l) => measure(monoFont(), l))),
    });
    const st = this.box.style;
    st.left = `${p.left}px`;
    st.top = `${p.top}px`;
    st.width = `${p.width}px`;
    st.height = `${p.height}px`;
    st.fontSize = `${p.fontSize}px`;
    st.lineHeight = `${CODE_LINE * cam.k}px`;
    st.padding = `${p.padding}px`;
    st.borderWidth = `${CARD_BORDER}px`;
  }

  /** 色付き層を今の中身で塗り直す */
  private paintInk(): void {
    this.ink.replaceChildren();
    for (const line of tokenizeBlock(this.textarea.value)) {
      for (const t of line) {
        const span = document.createElement("span");
        if (t.cls !== "") span.className = t.cls;
        span.textContent = t.text;
        this.ink.append(span);
      }
      // 空行でも高さを持たせる（改行だけの行がある文書で行がずれる）
      this.ink.append(document.createTextNode("\n"));
    }
  }

  /** 閉じる。値が開いたときと違えば `commit` を 1 回。二重に閉じても何も起きない */
  close(): void {
    if (this.id === null) return;
    const id = this.id;
    const value = this.textarea.value;
    this.id = null;
    this.lastRect = null;
    this.lastCam = null;
    this.box.style.display = "none";
    if (value !== this.opened) this.commit(id, value);
  }
}

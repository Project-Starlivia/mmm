// カードのその場編集。ラベルと同じ理由で HTML を重ねるが、値の書き戻し方が違う
// — カードは打鍵のたびに書かず、**閉じるときに 1 回**書く（コードは打っている
// 途中の中間状態が md に流れると、フェンスが割れて木が壊れる。spec.md「C カード」）。
//
// 欄をどこに置くかは core（`core.cardPlace`）が数え、ここは style に入れるだけ。
// 欄の字は描かれたカードの字と数 px ずれるが、欄が不透明な背景で下のカードを
// 覆うので見えない。

import * as core from "../coreApi.ts";
import { tokenizeBlock } from "./highlight.ts";
import { measure } from "./measure.ts";

/**
 * カードの入力欄の器。開く / place / 閉じるだけを知り、値の意味は持たない。
 * ラベル（`LabelEditor`）と違って**閉じるときに 1 回だけ**書く。
 */
export class CardEditor {
  private box: HTMLDivElement;
  private highlight: HTMLPreElement;
  private textarea: HTMLTextAreaElement;
  /** 開いたときの値。閉じるとき、これと違えば書く（同じなら書かない） */
  private opened = "";
  private id: number | null = null;
  /** 最後に place() へ渡された配置と視点。中身だけが変わった打鍵の再配置に使う
   *  （書くのは閉じるときだけなので、打つたびに CodeMirror の更新が地図を描き直すことはない） */
  private last: { layout: core.Layout; cam: core.Camera } | null = null;
  private readonly pane: HTMLElement;
  private readonly commit: (id: number, text: string) => void;

  constructor(pane: HTMLElement, commit: (id: number, text: string) => void) {
    this.pane = pane;
    this.commit = commit;
    this.box = document.createElement("div");
    this.box.className = "card-editor";
    this.box.style.display = "none";
    this.highlight = document.createElement("pre");
    this.highlight.className = "highlight";
    this.textarea = document.createElement("textarea");
    this.textarea.spellcheck = false;
    this.box.append(this.highlight, this.textarea);
    pane.append(this.box);

    this.textarea.addEventListener("input", () => {
      this.paintHighlight();
      if (this.last) this.place(this.last.layout, this.last.cam);
    });
    this.textarea.addEventListener("keydown", (e) => {
      // 地図のキーへ流さない（Delete がカードを消すに化ける）
      e.stopPropagation();
      // 変換中の Esc / Enter は IME のもの（label.ts と同じ）
      if (e.isComposing || e.keyCode === 229) return;
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
  open(id: number, layout: core.Layout, cam: core.Camera, text: string, from?: number, to?: number): void {
    this.id = id;
    this.opened = text;
    this.textarea.value = text;
    this.box.style.display = "block";
    this.paintHighlight();
    this.place(layout, cam);
    this.textarea.focus();
    const end = text.length;
    this.textarea.setSelectionRange(from ?? end, to ?? from ?? end);
  }

  /** カードに追従する。書くたび・視点を動かすたびに呼ぶ。持ち主が畳まれて
   *  カードが無ければ閉じる */
  place(layout: core.Layout, cam: core.Camera): void {
    if (this.id === null) return;
    const p = core.cardPlace(layout, this.id, cam, this.textarea.value, measure);
    if (p === null) {
      this.close();
      return;
    }
    this.last = { layout, cam };
    const st = this.box.style;
    st.left = `${p.left}px`;
    st.top = `${p.top}px`;
    st.width = `${p.width}px`;
    st.height = `${p.height}px`;
    st.fontSize = `${p.fontSize}px`;
    st.lineHeight = `${p.lineHeight}px`;
    st.padding = `${p.padding}px`;
    st.borderWidth = `${p.border}px`;
  }

  /** 色付き層を今の中身で塗り直す */
  private paintHighlight(): void {
    this.highlight.replaceChildren();
    for (const line of tokenizeBlock(this.textarea.value)) {
      for (const t of line) {
        const span = document.createElement("span");
        if (t.cls !== "") span.className = t.cls;
        span.textContent = t.text;
        this.highlight.append(span);
      }
      // 空行でも高さを持たせる（改行だけの行がある文書で行がずれる）
      this.highlight.append(document.createTextNode("\n"));
    }
  }

  /** 閉じる。値が開いたときと違えば `commit` を 1 回。二重に閉じても何も起きない */
  close(): void {
    if (this.id === null) return;
    const id = this.id;
    const value = this.textarea.value;
    this.id = null;
    this.last = null;
    this.box.style.display = "none";
    if (value !== this.opened) this.commit(id, value);
  }
}

// メニューの器。**何を並べるかは持たない** — 並びは呼ぶ側が決めて渡す。
// ここが引き受けるのは、作る・置く・画面からはみ出させない・**外を押されたら
// 閉じる**、だけ。閉じる条件はメニューであることの一部であって、
// マップであることの一部ではない。
//
// **1 個しか作れない器にはしない**（id ではなく class）。マップの右クリックと、
// 書き出しの形式選びが、同じ器を別々に持つ。

/** 1 行。`sep` は区切り線 */
export type MenuEntry =
  | { label: string; key?: string; run: () => void; disabled?: boolean }
  | "sep";

const MARGIN = 8; // 画面の縁からこれだけは離す

export class ContextMenu {
  private el = document.createElement("div");

  constructor() {
    this.el.className = "ctx-menu";
    this.el.style.display = "none";
    document.body.append(this.el);
    // 開いているあいだだけ付け外しする手もあるが、`hide()` は何度呼んでも
    // 同じなので、付けっぱなしのほうが短い
    document.addEventListener("pointerdown", (e) => {
      if (!this.contains(e.target)) this.hide();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.hide();
    });
    window.addEventListener("blur", () => this.hide());
  }

  /** その座標に開く。画面外へはみ出すときは内側へ寄せる */
  show(x: number, y: number, items: MenuEntry[]): void {
    this.el.replaceChildren();
    for (const it of items) {
      if (it === "sep") {
        this.el.append(document.createElement("hr"));
        continue;
      }
      const row = document.createElement("div");
      row.className = "item" + (it.disabled ? " disabled" : "");
      const label = document.createElement("span");
      label.textContent = it.label;
      row.append(label);
      if (it.key) {
        const key = document.createElement("span");
        key.className = "key";
        key.textContent = it.key;
        row.append(key);
      }
      row.addEventListener("click", () => {
        this.hide();
        it.run();
      });
      this.el.append(row);
    }
    // 大きさは出してからでないと測れない
    this.el.style.display = "block";
    const w = this.el.offsetWidth;
    const h = this.el.offsetHeight;
    this.el.style.left = `${Math.min(x, window.innerWidth - w - MARGIN)}px`;
    this.el.style.top = `${Math.min(y, window.innerHeight - h - MARGIN)}px`;
  }

  hide(): void {
    this.el.style.display = "none";
  }

  /** いま開いているか。同じボタンを押し直して閉じたい呼び出し側のため */
  get open(): boolean {
    return this.el.style.display === "block";
  }

  /** メニューの中で起きた出来事か（外を押したときだけ閉じるため）。
   *  `EventTarget` をそのまま受けて、ここで確かめる — 呼び出し側に
   *  `as Node` と名乗らせない */
  contains(target: EventTarget | null): boolean {
    return target instanceof Node && this.el.contains(target);
  }
}

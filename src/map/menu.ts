// メニューの器。**何を並べるかは持たない** — 並びは呼ぶ側が決めて渡す。
// ここが引き受けるのは、作る・置く・画面からはみ出させない・**外を押されたら
// 閉じる**、だけ。閉じる条件はメニューであることの一部であって、
// マップであることの一部ではない。
//
// **1 個しか作れない器にはしない**（id ではなく class）。マップの右クリックと、
// 書き出しの出し方選びが、同じ器を別々に持つ。
//
// 入れ子も同じ器で作る — 子メニューは `ContextMenu` そのもので、置く場所が
// 親の行の隣になるだけ。**別の器を書き足さない。**

import { type IconName, icon } from "../icons.ts";

/**
 * 1 行。`sep` は区切り線、`items` を持つ行は入れ子、`caption` は見出し。
 *
 * **入れ子の行も `run` を持てる** — 触れば開き、押せばその場で走る。
 * 「まとめた名前そのものが、いちばん普通の 1 つでもある」形のため
 * （`Add ▸` を押すと子ノードが増え、開けば下や上や親も選べる）。
 * `run` の無い入れ子は開くだけ。
 *
 * `caption` は**続く行たちが何に効くか**を言う、押せない見出し
 * （`current file.md` の下に Rename / Save が並ぶ、など）。区切り線と違って
 * 名前を持てるので、「どれに効くのか」が要る並びで区切りの代わりに置く。
 */
export type MenuEntry =
  | {
      label: string;
      key?: string;
      /** 行の頭の絵。無ければ字だけ */
      mark?: IconName;
      run: () => void;
      disabled?: boolean;
    }
  | {
      label: string;
      key?: string;
      mark?: IconName;
      items: MenuEntry[];
      run?: () => void;
      disabled?: boolean;
    }
  | { caption: string }
  | "sep";

const MARGIN = 8; // 画面の縁からこれだけは離す
/** 子メニューは親の行にこれだけ重ねて出す（縁の線をまたぐ量） */
const OVERLAP = 4;

/**
 * そのボタンでメニューを開く。**押し直したら閉じる** — 閉じるのは document 側の
 * `pointerdown` が済ませるので、押した時点で開いていたかだけを覚えて開き直さない
 * （ボタン自身の `pointerdown` は document より先に届く）。
 *
 * 並びは開くたびに作る。押した瞬間の文書に合わせるため。
 */
export function openOnClick(
  button: HTMLButtonElement,
  items: () => MenuEntry[],
): void {
  const menu = new ContextMenu();
  let wasOpen = false;
  button.addEventListener("pointerdown", () => {
    wasOpen = menu.open;
  });
  button.addEventListener("click", () => {
    if (wasOpen) return;
    const r = button.getBoundingClientRect();
    menu.show(r.left, r.bottom + 4, items());
  });
}

export class ContextMenu {
  private el = document.createElement("div");
  /** 開いている子メニュー。要るまで作らない（大半のメニューに入れ子は無い） */
  private sub: ContextMenu | null = null;
  /** 自分が誰の子か。子から選んだとき、親ごと閉じるために辿る */
  private parent: ContextMenu | null = null;

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
    this.closeSub();
    this.el.replaceChildren();
    for (const it of items) {
      if (it === "sep") {
        this.el.append(document.createElement("hr"));
        continue;
      }
      if ("caption" in it) {
        const cap = document.createElement("div");
        cap.className = "caption";
        cap.textContent = it.caption;
        this.el.append(cap);
        continue;
      }
      const row = document.createElement("div");
      row.className = "item" + (it.disabled ? " disabled" : "");
      if (it.mark) row.append(icon(it.mark));
      const label = document.createElement("span");
      label.textContent = it.label;
      row.append(label);
      const nested = "items" in it;
      // 押して走る行のキーと、開ける印は同居しうる（`Tab ▸`）
      const hint = [it.key, nested ? "▸" : ""].filter(Boolean).join(" ");
      if (hint) {
        const key = document.createElement("span");
        key.className = "key";
        key.textContent = hint;
        row.append(key);
      }
      // どの行へ移っても、開いていた子は閉じる。入れ子の行なら開き直す
      row.addEventListener("pointerenter", () => {
        this.closeSub();
        if (nested && !it.disabled) this.openSub(row, it.items);
      });
      row.addEventListener("click", () => {
        // 走るものが無い入れ子は「開く」だけ。触るとすぐ閉じては選べない
        if (nested && !it.run) {
          if (!it.disabled) this.openSub(row, it.items);
          return;
        }
        this.hideAll();
        it.run?.();
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
    this.closeSub();
    this.el.style.display = "none";
  }

  /** いま開いているか。同じボタンを押し直して閉じたい呼び出し側のため */
  get open(): boolean {
    return this.el.style.display === "block";
  }

  /**
   * メニューの中で起きた出来事か（外を押したときだけ閉じるため）。
   * **子メニューの中も自分の中**として数える — そうしないと、子を押した
   * 瞬間に親が閉じ、閉じるついでに子まで畳まれて選べない。
   *
   * `EventTarget` をそのまま受けて、ここで確かめる — 呼び出し側に
   * `as Node` と名乗らせない
   */
  contains(target: EventTarget | null): boolean {
    if (target instanceof Node && this.el.contains(target)) return true;
    return this.sub?.contains(target) ?? false;
  }

  /** 親の行の右隣へ子を開く。器は使い回す（開くたびに作らない） */
  private openSub(row: HTMLElement, items: MenuEntry[]): void {
    if (!this.sub) {
      this.sub = new ContextMenu();
      this.sub.parent = this;
    }
    const r = row.getBoundingClientRect();
    this.sub.show(r.right - OVERLAP, r.top - OVERLAP, items);
    // 右に入らないときは**親の左へ回す**。`show` の寄せは画面の中へ入れる
    // だけなので、そのままだと親に重なって文字を隠す
    const w = this.sub.el.offsetWidth;
    if (r.right - OVERLAP + w > window.innerWidth - MARGIN) {
      const left = this.el.getBoundingClientRect().left - w + OVERLAP;
      this.sub.el.style.left = `${Math.max(MARGIN, left)}px`;
    }
  }

  /** いちばん上まで辿って閉じる。子から選んだら親も畳む */
  private hideAll(): void {
    let top: ContextMenu = this;
    while (top.parent) top = top.parent;
    top.hide();
  }

  private closeSub(): void {
    this.sub?.hide();
  }
}

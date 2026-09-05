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

import { type IconName, icon, nod } from "../icons.ts";

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
 *
 * `mark` は**主語を絵で言う**。見出しは値を言う場所（`notes.md`）だが、
 * 値の無い状態（`not saved yet`）では状態しか残らず、何の話か消える。
 * `File —` のような語を足すと、11px の見出しで**装飾語が値より長くなる** —
 * 絵なら同じ役を場所を食わずに果たし、見出しは値を言う場所のままでいられる。
 */
/**
 * 押せない理由。**文字列を渡せば、それが押せない理由として hover に出る。**
 * 真偽値と 1 つのフィールドに畳んであるので、「無効なのに理由が無い」と
 * 「理由があるのに押せる」が食い違いようがない。
 *
 * 理由を書くのは、見ただけでは分からないときだけ — 「選んでいない」
 * 「複数選んでいる」は行の並びと選択そのものが既に言っている。
 */
type Disabled = boolean | string;

/**
 * その行について、**押す前に知っておくとよいこと**。押せなくはしない
 * （押せないなら `disabled` の側）。
 *
 * **1 つにつき印 1 つ**を右端に並べる — まとめて 1 つにすると、いくつ
 * あるのかが読めない。字のまま並べないのは、行ごとに幅が変わって短い
 * label の行が長い但し書きに引きずられるから。印なら幅は一定。
 *
 * 中身は触れば**すぐ**読める（`title` はブラウザ任せで一拍待たされるので、
 * 吹き出しは自前で出す）。
 *
 * 約束を返してもよい — メニューは**待たずに開き**、届いた時点でその行
 * だけに印が付く。押す前に分かることでも、確かめるのに一手かかるもの
 * （リンクの長さは gzip してからでないと分からない）を、開くのを
 * 遅らせずに言うため。空なら何も出さない。
 */
type Note = string[] | Promise<string[]>;

/** 行に共通の見た目。押したときの振る舞いは `Act` が持つ */
interface Row {
  label: string;
  key?: string;
  /** 行の頭の絵。無ければ字だけ */
  mark?: IconName;
  note?: Note;
  disabled?: Disabled;
}

/**
 * 押したら何が起きるか。**どちらか一方**。
 *
 * `run` は閉じて走る — 結果が画面のどこかに出るもの。
 * `done` は**閉じずに走り、済んだらその行の絵がチェックになる** —
 * 手元から何も見えないもの（コピー）を、押した場所で答えるため。
 * しらせを出して閉じるより近いし、続けてもう 1 つ選べる。
 * **できたかを返す** — しくじりに頷いてしまわないように（しらせは
 * 走らせた側が出す。ここは印を付けるかどうかだけを見る）。
 */
type Act =
  | { run: () => void; done?: never }
  | { done: () => Promise<boolean>; run?: never };

export type MenuEntry =
  | (Row & Act)
  | (Row & { items: MenuEntry[]; run?: () => void })
  | { caption: string; mark?: IconName }
  | "sep";

const MARGIN = 8; // 画面の縁からこれだけは離す
/** 子メニューは親の行にこれだけ重ねて出す（縁の線をまたぐ量） */
const OVERLAP = 4;

/** 絵の無い行に置く、同じ大きさの空欄。中身が無いだけの `.icon` */
function emptyMark(): HTMLSpanElement {
  const span = document.createElement("span");
  span.className = "icon";
  return span;
}

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
  button.addEventListener("click", (e) => {
    if (wasOpen) return;
    const r = button.getBoundingClientRect();
    menu.show(r.left, r.bottom + 4, items());
    // **開けたのがキーなら先頭の行へ、マウスならメニューそのものへ。**
    // マウスで開いた瞬間に行が光ると、指してもいないところを「ここ」だと
    // 言うことになる（右クリックで開くメニューが誰も光らせないのと同じ）。
    // 焦点はメニューが持ったままなので、矢印を押せばそこから先頭に着く。
    // キーで押した click は `detail` が 0（マウスは押した回数が入る）
    menu.focusFirst(e.detail === 0);
  });
}

/**
 * 行が器へ返すもの。位置・開閉・焦点は器（`ContextMenu`）の持ち物で、行は
 * 「入れ子を開いて」「選んだから閉じて」と言うだけ。
 */
export interface MenuHost {
  /** 入れ子をその行の隣に開く */
  openSub(row: HTMLElement, items: MenuEntry[]): void;
  /** 開いている入れ子を閉じる（別の行へ移った） */
  closeSub(): void;
  /** 選んだので器ごと閉じる */
  close(): void;
}

/**
 * `.menu` の器に行を並べる。**中身だけ** — どこに出すか・いつ閉じるかは
 * 持たない。返るのは、入れ子を持つ行の「開く」動作（ArrowRight とホバーの
 * 両方がこれを引く。2 つの入口が同じ判断をばらばらに持たない）。
 */
export function fillMenu(el: HTMLElement, items: MenuEntry[], host: MenuHost): Map<HTMLElement, () => void> {
  el.replaceChildren();
  const openers = new Map<HTMLElement, () => void>();
  // 空欄で頭出しを揃えるのは、**このメニューの中に絵を持つ行が 1 つでも
  // あるとき**だけ。1 つも無いなら（Add の子など）揃える相手が無いので、
  // 全部の行を左端まで詰める — 空欄ぶんの余白だけが浮いて見えていた
  const anyMark = items.some((it) => it !== "sep" && !("caption" in it) && !!it.mark);
  for (const it of items) {
    if (it === "sep") {
      el.append(document.createElement("hr"));
      continue;
    }
    if ("caption" in it) {
      const cap = document.createElement("div");
      cap.className = "caption";
      // 字は span に入れる — 長い名前を省略するのは字だけで、絵は縮めない
      const text = document.createElement("span");
      text.textContent = it.caption;
      if (it.mark) cap.append(icon(it.mark));
      cap.append(text);
      el.append(cap);
      continue;
    }
    const row = document.createElement("div");
    row.className = "item";
    row.setAttribute("role", "menuitem");
    // 矢印キーで辿れる。触っても効かない行だけが機能しないので、
    // トップレベルには常に参加させる（見えるが効かない、が Tab と同じ形）
    row.tabIndex = -1;
    // 理由を持つなら、触れば読める。押せない行は pointer-events を落として
    // あるが、`title` は要素そのものに付くので hover では出る。
    // アクセシブルネームも同じ理由を言う — hover できない読み上げでも
    // 「なぜ」がその場で分かる
    if (it.disabled) row.setAttribute("aria-disabled", "true");
    if (typeof it.disabled === "string") {
      row.title = it.disabled;
      row.setAttribute("aria-label", `${it.label}, ${it.disabled}`);
    }
    // 絵の有る行と無い行で字の頭出しがずれないよう、無い行にも同じ幅の
    // 空欄を置く（絵は行ごとの都合、字の頭は並びの都合 — 別の話）。
    // ただし揃える相手（絵を持つ行）がこのメニューに 1 つも無ければ、
    // 空欄そのものを置かない
    if (it.mark) row.append(icon(it.mark));
    else if (anyMark) row.append(emptyMark());
    const label = document.createElement("span");
    label.textContent = it.label;
    row.append(label);
    const nested = "items" in it;
    if (nested) {
      row.setAttribute("aria-haspopup", "menu");
      row.setAttribute("aria-expanded", "false");
    }
    // 但し書きは**印だけ**を右端に出し、中身は触れば読める。
    // **待たずに開いて、届いたら付ける** — 閉じた後に届いても、器ごと
    // 捨てられているだけなので何も起きない
    if (it.note !== undefined) {
      const show = (texts: string[]): void => {
        if (texts.length === 0) return;
        // **印は 1 つ。** その行についての但し書きが何本あっても、
        // 「この一手には気に留めることがある」という同じ 1 つの話なので、
        // 印を数だけ並べると別々の物に見える。数は吹き出しの中で言う
        const mark = icon("triangle-alert");
        mark.classList.add("note");
        // 印そのものが読み上げの対象になる。行の名前に但し書きを足すので
        // はなく、印に名前を持たせる（label は label のまま）
        mark.removeAttribute("aria-hidden");
        mark.setAttribute("role", "img");
        mark.setAttribute("aria-label", texts.join(". "));
        // 吹き出しは自前。`title` はブラウザ任せで一拍待たされる
        const tip = document.createElement("div");
        tip.className = "tip";
        for (const text of texts) {
          const line = document.createElement("div");
          line.textContent = text;
          tip.append(line);
        }
        // `<span>` にしない — 行は「`.key` でも絵でもない `<span>` は
        // 字だ」と見て `flex: 1` を当てるので、印の器が横幅を全部
        // 持っていってしまう
        const box = document.createElement("div");
        box.className = "note-box";
        box.append(mark, tip);
        row.append(box);
      };
      if (Array.isArray(it.note)) show(it.note);
      else void it.note.then(show);
    }
    // 押して走る行のキーと、開ける印は同居しうる（`Tab ▸`）
    const hint = [it.key, nested ? "▸" : ""].filter(Boolean).join(" ");
    if (hint) {
      const key = document.createElement("span");
      key.className = "key";
      key.textContent = hint;
      row.append(key);
    }
    // 「開く」判断は 1 か所。ホバーと ArrowRight の両方がこれを呼ぶ
    if (nested && !it.disabled) openers.set(row, () => host.openSub(row, it.items));
    // どの行へ移っても、開いていた子は閉じる。入れ子の行なら開き直す
    row.addEventListener("pointerenter", () => {
      host.closeSub();
      openers.get(row)?.();
    });
    row.addEventListener("click", () => {
      // **押せなさは、ここが持つ。** CSS の `pointer-events: none` で
      // 止めていた頃は、同じ指定が hover まで殺していて理由が読めなかった
      if (it.disabled) return;
      // 走るものが無い入れ子は「開く」だけ。触るとすぐ閉じては選べない
      if (nested && !it.run) {
        host.openSub(row, it.items);
        return;
      }
      // **`done` を持つ行は閉じない。** 済んだことはその場で絵が言うので、
      // 閉じて別の場所に出すより近いし、続けてもう 1 つ選べる
      const done = "done" in it ? it.done : undefined;
      if (done) {
        // 行の頭の絵だけを差し替える（`:scope >` が無いと、但し書きの
        // 印まで拾いうる）。差し替えるたび引き直すので、そのつど探す
        void nod(done(), (mark) => {
          row.querySelector(":scope > .icon")?.replaceWith(icon(mark));
        });
        return;
      }
      host.close();
      if ("run" in it) it.run?.();
    });
    el.append(row);
  }
  return openers;
}

/** 行だけのメニュー。位置も開閉も持たない — 並べて見るためのもの */
export function menu(items: MenuEntry[]): HTMLDivElement {
  const el = document.createElement("div");
  el.className = "menu";
  el.setAttribute("role", "menu");
  fillMenu(el, items, { openSub() {}, closeSub() {}, close() {} });
  return el;
}

export class ContextMenu implements MenuHost {
  private el = document.createElement("div");
  /** 開いている子メニュー。要るまで作らない（大半のメニューに入れ子は無い） */
  private sub: ContextMenu | null = null;
  /** 自分が誰の子か。子から選んだとき、親ごと閉じるために辿る */
  private parent: ContextMenu | null = null;
  /** 子を開いた行。閉じたとき、そこへ焦点を戻す（← キー） */
  private openerRow: HTMLElement | null = null;
  /** 開いたときに焦点があった要素。トップレベルだけが持つ — 閉じたら戻る先 */
  private opener: HTMLElement | null = null;
  /** 入れ子を持つ行の「開く」動作（`fillMenu` が返す）。ArrowRight が引く */
  private openers = new Map<HTMLElement, () => void>();

  constructor() {
    this.el.className = "menu";
    this.el.style.display = "none";
    this.el.setAttribute("role", "menu");
    this.el.tabIndex = -1;
    document.body.append(this.el);
    // 開いているあいだだけ付け外しする手もあるが、`hide()` は何度呼んでも
    // 同じなので、付けっぱなしのほうが短い
    document.addEventListener("pointerdown", (e) => {
      if (!this.contains(e.target)) this.hide();
    });
    // トップレベルだけ、閉じたときに呼んだ場所へ焦点を戻す。子から選んで
    // 閉じるときも同じ道を通る（close → 一番上の hide(true)）
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.hide(!this.parent);
    });
    window.addEventListener("blur", () => this.hide());
    this.el.addEventListener("keydown", (e) => this.onKeydown(e));
  }

  /**
   * 開いた直後に呼ぶ。**先頭の行へ焦点を移す。** トップレベルなら、閉じた
   * ときに戻る先（そのとき焦点があった要素）もここで覚える — 呼ぶ側に
   * 「開ける前の焦点を覚えておいて」と言わせない。
   */
  focusFirst(onRow = true): void {
    if (!this.parent) {
      this.opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    }
    // 行に乗せないときも**焦点はメニューが持つ** — 手放すと Escape も
    // Tab も届かず、閉じた後に戻る先も分からなくなる
    if (onRow) this.el.querySelector<HTMLElement>(".item")?.focus();
    else this.el.focus();
  }

  /** 今どの行に焦点があるか。行でなければ null（絞り込んで確かめる） */
  private activeRow(): HTMLElement | null {
    const el = document.activeElement;
    return el instanceof HTMLElement && el.classList.contains("item") ? el : null;
  }

  private onKeydown(e: KeyboardEvent): void {
    const rows = [...this.el.querySelectorAll<HTMLElement>(".item")];
    if (rows.length === 0) return;
    const active = this.activeRow();
    const at = active ? rows.indexOf(active) : -1;
    const move = (next: number): void => rows[(next + rows.length) % rows.length]?.focus();
    switch (e.key) {
      case "ArrowDown":
        e.preventDefault();
        move(at + 1);
        break;
      case "ArrowUp":
        e.preventDefault();
        move(at - 1);
        break;
      case "Home":
        e.preventDefault();
        rows[0]?.focus();
        break;
      case "End":
        e.preventDefault();
        rows[rows.length - 1]?.focus();
        break;
      case "ArrowRight": {
        // 入れ子でない行では何もしない（横に伸びる先が無い）
        const open = active && this.openers.get(active);
        if (!open) break;
        e.preventDefault();
        open();
        this.sub?.focusFirst();
        break;
      }
      case "ArrowLeft":
        // 自分が子のときだけ意味を持つ。**親の `closeSub()` を経由する** —
        // 直に `hide()` すると、開いた行の `aria-expanded` を戻す係が
        // 素通りされる（そこは親しか持っていない）
        if (this.parent) {
          e.preventDefault();
          const row = this.openerRow;
          this.parent.closeSub();
          row?.focus();
        }
        break;
      case "Enter":
      case " ":
        e.preventDefault();
        // 押せなさもキーの並びも、click 側が既に持っている判断をそのまま使う
        active?.click();
        break;
      case "Tab": {
        // 抜けるところまで持っていかない — Tab の既定の移動に任せ、
        // 浮いたままにならないよう畳むだけ
        let top: ContextMenu = this;
        while (top.parent) top = top.parent;
        top.hide(false);
        break;
      }
    }
  }

  /** その座標に開く。画面外へはみ出すときは内側へ寄せる */
  show(x: number, y: number, items: MenuEntry[]): void {
    this.closeSub();
    this.openers = fillMenu(this.el, items, this);
    // 大きさは出してからでないと測れない
    this.el.style.display = "block";
    const w = this.el.offsetWidth;
    const h = this.el.offsetHeight;
    this.el.style.left = `${Math.min(x, window.innerWidth - w - MARGIN)}px`;
    this.el.style.top = `${Math.min(y, window.innerHeight - h - MARGIN)}px`;
  }

  /**
   * `restoreFocus` はトップレベルが閉じるときだけ意味を持つ — 選んで閉じた
   * とき（`close`）と Escape で閉じたときは呼んだ場所へ戻り、外を押した・
   * 窓が背後へ回った・Tab で抜けたときは戻さない（戻すと、その操作を
   * わざわざやり直させることになる）。
   */
  hide(restoreFocus = false): void {
    this.closeSub();
    this.el.style.display = "none";
    if (restoreFocus) {
      this.opener?.focus();
      this.opener = null;
    }
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
  openSub(row: HTMLElement, items: MenuEntry[]): void {
    if (!this.sub) {
      this.sub = new ContextMenu();
      this.sub.parent = this;
    }
    row.setAttribute("aria-expanded", "true");
    this.sub.openerRow = row;
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

  /**
   * いちばん上まで辿って閉じる。子から選んだら親も畳む。
   * `restoreFocus` は `hide()` と同じ意味 — 選んで閉じるときは既定で戻す
   * （キー操作でも選んだ後は呼んだ場所へ）。
   */
  close(restoreFocus = true): void {
    let top: ContextMenu = this;
    while (top.parent) top = top.parent;
    top.hide(restoreFocus);
  }

  closeSub(): void {
    this.sub?.openerRow?.setAttribute("aria-expanded", "false");
    this.sub?.hide();
  }
}

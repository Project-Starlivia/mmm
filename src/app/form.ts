// 木の書き方（見出し / リスト）の切り替え。md ペインの右上に住む。
//
// モード = 「深さ b 以上をリストで書く」の b ひとつ（core が持つ）。
// ここが持つのは 3 つのボタンと、Hybrid の b の覚えだけ。
// **読みはモードを知らない**ので、押して変わるのは書かれ方だけ —
// マップは 1 ピクセルも動かない。

import { paneTool } from "./paneTool.ts";

export interface FormDeps {
  /** ボタンを住まわせるペイン（md ペイン） */
  pane: HTMLElement;
  /** モードを b にして、文書ぜんぶをその正規形へ書き直す */
  apply: (b: number) => void;
}

/** Hybrid の b の巡回範囲。1 は List と同じになるが、重なりは無害 */
const HYBRID_MIN = 1;
const HYBRID_MAX = 6;

export function initForm(deps: FormDeps): {
  /** いまのモードをボタンに映す（applySnap から毎回呼ばれる） */
  show: (listFrom: number) => void;
} {
  // ペインの隅の道具（pane-tool）で、3 つが 1 つの塊に見える（group）。
  // 住む場所だけが `#form-picker` の持ちもの
  const box = paneTool("form-picker");
  box.classList.add("group");
  // 顔は **.md に実際に書かれる字**（`#` と `-`）。`H` / `L` は Heading /
  // List という英語の頭文字で、書かれるものを指していなかった。
  //
  // 真ん中だけ数字なのは、そこだけが**値を持つ**から — 境目の深さは
  // 押すたびに巡回し、次にどこへ行くかはこのボタンにしか出ていない
  // （`#/-` のような記号にすると、その値が消える）。
  // 3 つは種類ではなく**同じ物差しの上の 3 点**: 全部 `#` → 途中から → 全部 `-`。
  const bHead = button("#", "Write the tree as headings");
  // 境目が**いまどこか**はボタンの顔（`2+`）が言っているので、hover は
  // 2 つの領域と、押せば動くことだけを言う
  const bHybrid = button("2+", "Headings above, a list below — press to move");
  const bList = button("-", "Write the tree as a list");
  box.append(bHead, bHybrid, bList);
  deps.pane.append(box);

  /** Hybrid が指している b。表示（`n+`）と押したときの行き先 */
  let hybridN = 2;
  let current = 0;

  const show = (listFrom: number): void => {
    current = listFrom;
    if (listFrom >= HYBRID_MIN && listFrom <= HYBRID_MAX && listFrom !== 1) {
      hybridN = listFrom;
    }
    bHybrid.textContent = `${hybridN}+`;
    bHead.classList.toggle("on", listFrom === 0);
    bList.classList.toggle("on", listFrom === 1);
    bHybrid.classList.toggle("on", listFrom > 1);
  };

  bHead.addEventListener("click", () => deps.apply(0));
  bList.addEventListener("click", () => deps.apply(1));
  bHybrid.addEventListener("click", () => {
    // 点いていなければ、いま指している b をそのまま。点いていれば巡回
    if (current > 1) {
      hybridN = current >= HYBRID_MAX ? HYBRID_MIN : current + 1;
    }
    deps.apply(hybridN);
  });

  return { show };
}

function button(text: string, title: string): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = text;
  b.title = title;
  return b;
}

// しらせ。**答えを待たない** — 出て、勝手に消える。
//
// 以前はファイル名の欄を 4 秒書き換えていたが、名乗りが嘘をつく形だった
// （`empty.md — Could not save`）。名乗りは名乗りに戻し、しらせは自分の器を持つ。
//
// **器は 1 つ。** 続けて呼べば中身が差し替わる — 積み上げると、何秒でどう
// 畳むか・古いものが新しいものを押し出す向きは、といった規則が要る。
// 出るのは操作の直後だけなので、いちばん新しい 1 つで足りる。
//
// **出るのは「起きなかったこと」だけ。** 済んだことは押した場所の絵が言う
// （`icons.ts` の `nod`）。そのうえで、起きなかった理由には**向きが 2 つ**ある。
//
//   failed  … こちらが果たせなかった。ほとんどはこちら
//   blocked … 先へ進めない。**次の一手はそちらにある**
//
// **その向きを言うのは印の形で、色は増やさない。** 危険色を 1 つ足せば
// 「その色＝まずいこと」を覚えてもらう話になるし、形なら、テーマにも色覚にも
// 寄りかからない。読み上げにはどちらも `alert`（すぐ割り込む）で出す —
// 頼んだことが起きなかったのは同じで、待たせる理由が無い。

import { type IconName, icon } from "../icons.ts";

/** 出したままにする時間（ms） */
const LINGER = 4000;

/**
 * 詫び。**綴りはここ 1 つで、`failed` の側が持つ** — 言葉ごとに書くと、
 * 足すたびに付け忘れるし、詫びるかどうかは文言ではなく**向き**の話。
 *
 * 印のすぐ隣に立つ（`.lead`）。どちらも「こちらが言っている」ことで、
 * 何が起きなかったかを言う文言（`.msg`）とは別のもの。
 *
 * 末尾が `.` ではなく `...` なのは、言い切って区切るのではなく、
 * そのまま続けて言うため。文言のほうが `—` を持っていることがあるので
 * （`Save the .md first — nothing on disk to rename yet`）、`—` は使わない。
 */
const SORRY = "Sorry...";

let box: HTMLDivElement | null = null;
let timer = -1;

/**
 * 字のひと続き。**`span` は「意味を持たない字の一区切り」そのもの**なので、
 * ここに `div` を置くと「段落だ」と嘘をつくことになる（flex の中では
 * どちらも同じに敷かれるので、選ぶ理由は見た目ではなく意味のほう）。
 */
function words(name: string, text: string): HTMLSpanElement {
  const el = document.createElement("span");
  el.className = name;
  el.textContent = text;
  return el;
}

function show(mark: IconName, msg: string, sorry: boolean): void {
  if (!box) {
    box = document.createElement("div");
    box.id = "notice";
    // HTML に「しらせ」のタグは無い。`<output>` は `role="status"` に落ちる
    // ので、すぐ割り込む `alert` が要るこちらは div に role を載せる
    box.setAttribute("role", "alert");
    document.body.append(box);
  }
  // **入れ物は、意味を持つか CSS で言えない境目があるときだけ置く。**
  //
  //   .icon  印（飾り。意味は role と字が持つので `aria-hidden`）
  //   .lead  詫び（`blocked` では出さない）
  //   .msg   何が起きなかったか
  //
  // 印と詫びを束ねる器は要らない — 伸びるのは `.msg` だけなので、文言が
  // 折り返しても 2 つが離れることはない。束ねる器はそのために置いていた
  const kids: Node[] = [icon(mark)];
  if (sorry) kids.push(words("lead", SORRY));
  kids.push(words("msg", msg));
  box.replaceChildren(...kids);
  box.classList.add("on");
  if (timer !== -1) window.clearTimeout(timer);
  timer = window.setTimeout(() => {
    timer = -1;
    box?.classList.remove("on");
  }, LINGER);
}

/**
 * こちらが果たせなかった。**鳴らすのではなく、認める。**
 *
 * 印が三角でなく丸なのは、三角が道路標識と同じで「この先危ない・気をつけろ」と
 * **読む人へ向けて**言う形だから。ここで気をつけるべきだったのは相手ではない。
 * 字も人の言い方で言う（`Couldn't …`。`Could not` はログの口調）。頭には
 * **詫びが 1 文**付く — 起きなかったのはこちらの都合なので、そう言う。
 *
 * **ほぼ全部がこちら。** 「保存が先」も「リンクとして読めない」もここに入る —
 * 置き場所を持たない文書に画像を収めると言ったのも、貼られた字をリンクとして
 * 読むと言ったのもこちらで、相手の不注意ではない。
 */
export const failed = (msg: string): void => show("circle-alert", msg, true);

/**
 * 先へ進めない。**次の一手はそちらにある。**
 *
 * こちらは三角でいい — 読む人へ向けて言う形が、ここでは実際に正しい
 * （動くのは相手）。**いまは書き出すものが無いときだけ**で、ボタンは沈めて
 * あるのでキー（`Mod+E`）から来た人にしか出ない。触って読める言葉と
 * 同じものを出す。
 */
export const blocked = (msg: string): void => show("triangle-alert", msg, false);

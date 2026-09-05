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

/**
 * 言葉の全部。**綴りはここ 1 つ** — 呼ぶ側はこの中の 1 つを渡す（外れていれば
 * 型が止める）ので、足すときはまずここに書く。並べて見る道具もこれを読む。
 * 名前を付けて引かないのは、呼び出し元で文言そのものが読める方が早いから。
 */
export const FAILED = [
  "Couldn't save",
  "Couldn't save the image",
  "Couldn't open the file",
  "Couldn't open the dropped file",
  "Couldn't open the image folder",
  "Couldn't create a new file",
  "Couldn't rename the file",
  "Couldn't export",
  "Couldn't copy",
  "Couldn't copy the link",
  "Couldn't paste",
  "Couldn't read that as a link",
  "Couldn't add the drawing",
  "Couldn't open that card",
  "Couldn't start editing — the node is folded",
  "Couldn't do that here",
  "Select a node to paste an image into",
  "Select a node to paste a link into",
  "This browser cannot open or save files",
] as const;
export type Failed = (typeof FAILED)[number];

/** 次の一手が相手にあるもの。いまは書き出すものが無いときの Mod+E だけ */
export const BLOCKED = ["Nothing to export yet"] as const;
export type Blocked = (typeof BLOCKED)[number];

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

/**
 * しらせ 1 つぶん。器（`.notice`）ごと組んで返す — **置くのは呼ぶ側**。
 * アプリは下の `show` が body に 1 個だけ置き、並べて見る道具はどこにでも置く。
 *
 * 中身は 3 つ。**入れ物は、意味を持つか CSS で言えない境目があるときだけ置く。**
 *
 *   .icon  印（飾り。意味は role と字が持つので `aria-hidden`）
 *   .lead  詫び（`blocked` では出さない）
 *   .msg   何が起きなかったか
 *
 * 印と詫びを束ねる器は要らない — 伸びるのは `.msg` だけなので、文言が
 * 折り返しても 2 つが離れることはない。束ねる器はそのために置いていた
 */
export function notice(mark: IconName, msg: string, sorry: boolean): HTMLDivElement {
  const box = document.createElement("div");
  box.className = "notice";
  // HTML に「しらせ」のタグは無い。`<output>` は `role="status"` に落ちる
  // ので、すぐ割り込む `alert` が要るこちらは div に role を載せる
  box.setAttribute("role", "alert");
  box.append(icon(mark));
  if (sorry) box.append(words("lead", SORRY));
  box.append(words("msg", msg));
  return box;
}

/** body に 1 個。続けて呼べば中身が差し替わり、時計は打ち直す */
function show(mark: IconName, msg: string, sorry: boolean): void {
  const next = notice(mark, msg, sorry);
  if (box) box.replaceChildren(...next.childNodes);
  else {
    box = next;
    document.body.append(box);
  }
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
export const failed = (msg: Failed): void => show("circle-alert", msg, true);

/**
 * 先へ進めない。**次の一手はそちらにある。**
 *
 * こちらは三角でいい — 読む人へ向けて言う形が、ここでは実際に正しい
 * （動くのは相手）。**いまは書き出すものが無いときだけ**で、ボタンは沈めて
 * あるのでキー（`Mod+E`）から来た人にしか出ない。触って読める言葉と
 * 同じものを出す。
 */
export const blocked = (msg: Blocked): void => show("triangle-alert", msg, false);

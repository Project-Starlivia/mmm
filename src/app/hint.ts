// 空のときの言い出し。**2 つのペインが同じ器を使う。**
//
// md とマップは、それぞれ**自分のペインでできること**だけを言う
// （md は `# 見出しを書く`、マップは `Enter を押す`）。片方に両方を書いて
// 隣のペインを指さす形だと、そのペインを隠したときに文言が嘘になる。
//
// 器を 1 つにしてあるのは、**対に見えることそのものが役**だから — 別々に
// 組むと、片方だけ字の大きさや寄せ方が変わって対の関係が崩れる。
//
// **出る理由は 1 つ**（まだノードが 1 つも無いか）。決めるのは applySnap
// （main.ts）ひとつで、そこから両方へ渡る — 片方だけ別の理由で出入りすると、
// 対ではなく別々の 2 つに見える。
//
// 本文が空かではなくノードの数で見るのは、**このアプリで意味のある「空」が
// マップの空だから** — 見出しの無い本文を打っている間も、まだ地図は無い。

/**
 * ペインの真ん中に浮かべる言い出し。`act` はその一手そのもの
 * （`Enter` / `# heading`）で、**そこだけが明るくなる**。
 *
 * 太字にはしない — このアプリに太字は実質無く、沈む（`--ink-dim`）と
 * 立つ（`--ink`）の明るさの差が、hover でもフォーカスでも使っている
 * ただ 1 つの強調の軸。ヒント 2 つのために軸を増やさない。
 */
export function paneHint(before: string, act: string, after: string): HTMLDivElement {
  const box = document.createElement("div");
  box.className = "pane-hint";
  // 見えているものは飾りで、読み上げには別の道がある
  // （md は `aria-placeholder`、マップはペイン自身の名前）
  box.setAttribute("aria-hidden", "true");
  const lit = document.createElement("span");
  lit.className = "act";
  lit.textContent = act;
  // **文は 1 つの塊にまとめてから入れる。** 外側は真ん中へ寄せるための
  // flex なので、字を直に入れると 3 つが別々の flex アイテムになり、
  // 文の途中の空白（`Press ` の末尾、` to …` の先頭）が行組みで潰れる
  const line = document.createElement("span");
  line.append(before, lit, after);
  box.append(line);
  return box;
}

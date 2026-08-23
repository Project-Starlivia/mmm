// カードの削除・移動を「1 回の置き換え」に落とす計算。DOM も文書の意味も
// 知らない、ただのオフセット算術。
//
// 1 回に落とすのは Undo を 1 回にするため。2 回に分けると、戻すのに
// 2 回押すことになる。

/** core.replaceText にそのまま渡せる形 */
export interface TextEdit {
  from: number;
  to: number;
  insert: string;
}

/**
 * その範囲を行ごと消す。行末の改行も持っていく — 残すと空行が居座る。
 * 末尾の行なら、代わりに手前の改行を巻き取る。
 */
export function removeCard(text: string, from: number, to: number): TextEdit {
  let head = from;
  let tail = to;
  if (text[tail] === "\n") tail += 1;
  else if (head > 0 && text[head - 1] === "\n") head -= 1;
  return { from: head, to: tail, insert: "" };
}

/**
 * その範囲を `at`（行頭のオフセット）へ動かす。
 * 元と先を含む一続きの範囲を組み直して返すので、置き換えは 1 回で済む。
 * 動かす意味が無い（結果が元と 1 文字も変わらない）ときは null。
 */
export function moveCard(
  text: string,
  from: number,
  to: number,
  at: number,
): TextEdit | null {
  if (at >= from && at <= to) return null;
  const body = text.slice(from, to);
  const cut = removeCard(text, from, to);
  let edit: TextEdit;
  if (at < from) {
    // 上へ。[at, cut.to) を「本文 + 改行 + 元々そこにあったもの」に組み直す
    const between = text.slice(at, cut.from);
    edit = { from: at, to: cut.to, insert: `${body}\n${between}` };
  } else {
    // 下へ。[cut.from, at) を「間にあったもの + 本文 + 改行」に組み直す
    const between = text.slice(cut.to, at);
    // between が改行で終わらないのは「改行で終わらない文書の末尾」だけ。
    // そこへ足すときは改行を前に置き、後ろには置かない — 文書の末尾に
    // 改行があるかどうかは、こちらから変えない
    const nlBefore = between === "" || between.endsWith("\n") ? "" : "\n";
    const nlAfter = nlBefore === "" ? "\n" : "";
    edit = { from: cut.from, to: at, insert: `${between}${nlBefore}${body}${nlAfter}` };
  }
  // 置き換えても 1 文字も変わらないなら、動いていない。自分のすぐ下へ
  // 落とした場合がこれで、返すと呼び出し側が「動かせた」と信じてしまう
  return text.slice(edit.from, edit.to) === edit.insert ? null : edit;
}

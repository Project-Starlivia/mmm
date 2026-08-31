// 出力に色を付ける。**読むためだけ**の飾りで、意味は何も足さない。
//
// 打った md がそのまま出るので、組み立ては DOM で行う（文字列を innerHTML へ
// 流すと、md に書いた `<script>` がそのまま動く）。

/** 種類ごとに `<span class=…>` を作って並べる。 */
function paint(parts: [string, string][]): DocumentFragment {
  const f = document.createDocumentFragment();
  for (const [kind, text] of parts) {
    if (text === "") continue;
    if (kind === "") {
      f.append(text);
    } else {
      const s = document.createElement("span");
      s.className = kind;
      s.textContent = text;
      f.append(s);
    }
  }
  return f;
}

/**
 * mmmTree の指紋。引用符の中はラベル（原文そのまま）なので、そこだけ地の色にして、
 * 構造の記号（`[ ] > < · # -`）を立てる。
 */
export function paintSig(s: string): DocumentFragment {
  const parts: [string, string][] = [];
  let i = 0;
  while (i < s.length) {
    if (s[i] === '"') {
      // ラベル。`\"` は中身なので閉じ引用符として数えない
      let j = i + 1;
      while (j < s.length && s[j] !== '"') j += s[j] === "\\" ? 2 : 1;
      parts.push(["label", s.slice(i, Math.min(j + 1, s.length))]);
      i = j + 1;
    } else if ("[]".includes(s[i])) {
      parts.push(["brace", s[i]]);
      i += 1;
    } else if ("><".includes(s[i])) {
      parts.push(["side", s[i]]);
      i += 1;
    } else if ("#-·^".includes(s[i])) {
      parts.push(["mark", s[i]]);
      i += 1;
    } else {
      parts.push(["", s[i]]);
      i += 1;
    }
  }
  return paint(parts);
}

/** mdAst の指紋。`種類[from,to]` の範囲だけ落とす。 */
export function paintAst(s: string): DocumentFragment {
  const parts: [string, string][] = [];
  for (const m of s.matchAll(/(\[[\d,]*\])|([^[]+)/g)) {
    parts.push(m[1] ? ["dim", m[1]] : ["mark", m[2]]);
  }
  return paint(parts);
}

/** JSON。鍵・文字列・数・真偽を分ける。 */
export function paintJson(s: string): DocumentFragment {
  const parts: [string, string][] = [];
  const re = /("(?:\\.|[^"\\])*")(\s*:)?|(\btrue\b|\bfalse\b|\bnull\b)|(-?\d+)/g;
  let last = 0;
  for (const m of s.matchAll(re)) {
    const at = m.index ?? 0;
    if (at > last) parts.push(["", s.slice(last, at)]);
    if (m[1] !== undefined) {
      parts.push([m[2] ? "key" : "label", m[1]]);
      if (m[2]) parts.push(["", m[2]]);
    } else if (m[3] !== undefined) {
      parts.push(["lit", m[3]]);
    } else {
      parts.push(["num", m[4]]);
    }
    last = at + m[0].length;
  }
  parts.push(["", s.slice(last)]);
  return paint(parts);
}

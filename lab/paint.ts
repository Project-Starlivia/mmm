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

/** mdAst の指紋。`種類[from,to]` の範囲だけ落とす。 */
export function paintAst(s: string): DocumentFragment {
  const parts: [string, string][] = [];
  for (const m of s.matchAll(/(\[[\d,]*\])|([^[]+)/g)) {
    parts.push(m[1] ? ["dim", m[1]] : ["mark", m[2]]);
  }
  return paint(parts);
}

/** 行末。テキストノードなのでコピーにそのまま入る。 */
const NL = "\n";

/** 値 1 つを描く。配列と構造体は `<details>` で畳める。
 *
 * インデントは**実際の空白文字**で持つ。CSS の余白で寄せるとコピーしたときに
 * 平らになって階層が読めなくなる（三角は擬似要素なのでコピーに入らない）。 */
function paintValue(v: unknown, depth: number, key?: string): DocumentFragment {
  const f = document.createDocumentFragment();
  const lead = document.createDocumentFragment();
  lead.append("  ".repeat(depth));
  if (key !== undefined) lead.append(span("key", JSON.stringify(key)), ": ");

  if (v === null || typeof v !== "object") {
    lead.append(span(kindOf(v), JSON.stringify(v)));
    f.append(lead, NL);
    return f;
  }

  const list = Array.isArray(v);
  const entries: [string | undefined, unknown][] = list
    ? (v as unknown[]).map((x) => [undefined, x])
    : Object.entries(v as Record<string, unknown>);

  // 空はそのまま出す。畳む中身が無いので `<details>` にすると邪魔なだけ
  if (entries.length === 0) {
    lead.append(span("dim", list ? "[]" : "{}"));
    f.append(lead, NL);
    return f;
  }

  const d = document.createElement("details");
  d.open = true;
  const sum = document.createElement("summary");
  sum.append(span("tri", ""), lead, span("dim", list ? `[${entries.length}]` : `{${entries.length}}`));
  d.append(sum);
  for (const [k, x] of entries) d.append(paintValue(x, depth + 1, k));
  f.append(d);
  return f;
}

function kindOf(v: unknown): string {
  return typeof v === "string" ? "label" : typeof v === "number" ? "num" : "lit";
}

function span(kind: string, text: string): HTMLSpanElement {
  const s = document.createElement("span");
  s.className = kind;
  s.textContent = text;
  return s;
}

/** JSON。配列と構造体ごとに畳める形で描く。 */
export function paintTree(s: string): DocumentFragment {
  try {
    return paintValue(JSON.parse(s), 0);
  } catch {
    return paint([["", s]]);
  }
}

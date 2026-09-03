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

/** 値 1 つを描く。配列と構造体は `<details>` で畳めるようにする。 */
function paintValue(v: unknown, key?: string): DocumentFragment {
  const f = document.createDocumentFragment();
  const head = document.createDocumentFragment();
  if (key !== undefined) {
    head.append(span("key", JSON.stringify(key)), ": ");
  }

  if (v === null || typeof v !== "object") {
    head.append(span(typeof v === "string" ? "label" : typeof v === "number" ? "num" : "lit", JSON.stringify(v)));
    f.append(head);
    return f;
  }

  const list = Array.isArray(v);
  const entries: [string | undefined, unknown][] = list
    ? (v as unknown[]).map((x) => [undefined, x])
    : Object.entries(v as Record<string, unknown>);

  // 空はそのまま出す。畳む中身が無いので `<details>` にすると邪魔なだけ
  if (entries.length === 0) {
    head.append(span("dim", list ? "[]" : "{}"));
    f.append(head);
    return f;
  }

  const d = document.createElement("details");
  d.open = true;
  const sum = document.createElement("summary");
  sum.append(head, span("dim", list ? `[${entries.length}]` : `{${entries.length}}`));
  d.append(sum);

  const body = document.createElement("div");
  body.className = "kids";
  for (const [k, x] of entries) {
    const row = document.createElement("div");
    row.append(paintValue(x, k));
    body.append(row);
  }
  d.append(body);
  f.append(d);
  return f;
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
    return paintValue(JSON.parse(s));
  } catch {
    return paint([["", s]]);
  }
}

// クリップボードから何を貼るかの判定。
// URL 単体 → そのノードの内容(リンクカード) / 見出し無しテキスト →
// 行ごとに子ノード(アンカー無しなら先頭行をルート) / 見出しあり →
// 従来どおり子ツリー。
//
// クリップボード I/O と、結果を文書へ適用するのは呼び出し側(main.ts)。
// ここが問い合わせるのは「その断片に見出しがあるか」「深さをずらすと
// どうなるか」だけで、その答えはコアが持つ（同じ規則を 2 つ書かない）。

import { core } from "../coreApi.ts";

export type PasteAction =
  | { kind: "noop" }
  | { kind: "link"; url: string }
  | { kind: "rootTree"; body: string }
  | { kind: "children"; body: string }
  | { kind: "block"; body: string };

export function decidePaste(
  clip: string,
  anchor: { depth: number } | null,
  hasNodes: boolean,
): PasteAction {
  // アプリの中の改行は常に LF。外から来る文字列はここで揃える
  // （読み込み側 app/io.ts と同じ規則。単独の CR も落とす）
  const normalized = clip.replace(/\r\n?/g, "\n");
  if (!normalized.trim()) return { kind: "noop" };

  const asLink = normalized.trim();
  if (anchor && /^https?:\/\/\S+$/.test(asLink)) {
    return { kind: "link", url: asLink };
  }

  if (!core.hasHeadings(normalized)) {
    const labels = normalized
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l !== "");
    if (labels.length === 0) return { kind: "noop" };
    // 新しい行の形（見出しかリスト項目か・字下げ）は**いまの文書のモード**
    // が決める。以前ここで `#` を直に書いていたころ、リストの形の文書に
    // 貼ると見出しがリストの入れ子をリセットして、以降の兄弟が丸ごと
    // 迷子になっていた（木そのものが壊れる不具合だった）
    if (!anchor) {
      const body = [
        core.formatLine(1, labels[0]),
        ...labels.slice(1).map((l) => core.formatLine(2, l)),
      ].join("\n\n");
      return { kind: "rootTree", body };
    }
    const depth = anchor.depth + 1;
    const body = labels.map((l) => core.formatLine(depth, l)).join("\n\n");
    return { kind: "children", body };
  }

  if (!anchor) {
    if (hasNodes) return { kind: "noop" };
    return { kind: "block", body: normalized.trimEnd() };
  }
  return {
    kind: "block",
    body: core.relevelText(normalized, anchor.depth + 1).trimEnd(),
  };
}

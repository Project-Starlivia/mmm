// クリップボードから何を貼るかの純粋な判定(mmm.md その３)。
// URL 単体 → そのノードの内容(リンクカード) / 見出し無しテキスト →
// 行ごとに子ノード(アンカー無しなら先頭行をルート) / 見出しあり →
// 従来どおり子ツリー。
// クリップボード I/O・core への実際の適用は呼び出し側(main.ts)が担う —
// ここは navigator.clipboard も core も知らない純粋関数のみ。

import { hasHeadings, relevel } from "../relevel";

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
  const normalized = clip.replace(/\r\n/g, "\n");
  if (!normalized.trim()) return { kind: "noop" };

  const asLink = normalized.trim();
  if (anchor && /^https?:\/\/\S+$/.test(asLink)) {
    return { kind: "link", url: asLink };
  }

  if (!hasHeadings(normalized)) {
    const labels = normalized
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l !== "");
    if (labels.length === 0) return { kind: "noop" };
    if (!anchor) {
      const body = [
        `# ${labels[0]}`,
        ...labels.slice(1).map((l) => `## ${l}`),
      ].join("\n\n");
      return { kind: "rootTree", body };
    }
    const hashes = "#".repeat(Math.min(anchor.depth + 1, 100));
    const body = labels.map((l) => `${hashes} ${l}`).join("\n\n");
    return { kind: "children", body };
  }

  if (!anchor) {
    if (hasNodes) return { kind: "noop" };
    return { kind: "block", body: normalized.trimEnd() };
  }
  return {
    kind: "block",
    body: relevel(normalized, anchor.depth + 1).trimEnd(),
  };
}

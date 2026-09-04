// クリップボードから何を貼るか。純粋な判定だけをここに置く。
//
// 「見出しや項目があるか（骨格）」は core に読ませて決める — TS で `#` や
// `- ` を見ると、md の読みの規則を 2 か所に書くことになる。呼ぶ側
// （main.ts）が `core.survey` を通した答えを `hasSkeleton` として渡す。

export type Paste =
  | { kind: "noop" }
  | { kind: "link"; url: string }
  | { kind: "labels"; labels: string[] }
  | { kind: "md"; md: string };

/**
 * クリップボードの字から、何を貼るかを決める。
 *
 * 規則: 空 → noop。1 行だけで URL の形 → link。骨格が無い（`hasSkeleton` が
 * 偽）→ 空でない行ごとに labels。骨格がある → そのまま md。
 */
export function decidePaste(clip: string, hasSkeleton: (md: string) => boolean): Paste {
  // アプリの中の改行は常に LF（app/io.ts と同じ規則）
  const normalized = clip.replace(/\r\n?/g, "\n");
  const trimmed = normalized.trim();
  if (trimmed === "") return { kind: "noop" };

  if (/^https?:\/\/\S+$/.test(trimmed)) return { kind: "link", url: trimmed };

  if (!hasSkeleton(normalized)) {
    const labels = normalized
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l !== "");
    return labels.length === 0 ? { kind: "noop" } : { kind: "labels", labels };
  }

  return { kind: "md", md: normalized.trimEnd() };
}

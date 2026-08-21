// Re-level a pasted Markdown fragment so its shallowest heading lands at
// `targetDepth`. Fence-aware, mirroring the core's scan rule.

/** Per-line heading depth (0 = not a heading), fence-aware. */
function scanDepths(lines: string[]): number[] {
  const depths: number[] = [];
  let inFence = false;
  let fenceChar = "";
  let fenceLen = 0;
  for (const line of lines) {
    let depth = 0;
    const fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
    if (inFence) {
      if (
        fence &&
        fence[1][0] === fenceChar &&
        fence[1].length >= fenceLen &&
        // core (parser.mbt の is_space) が空白と見なすのは半角スペース/タブだけ。
        // trim() は全角空白等も剥がしてしまい、それらが残る行を core とは
        // 逆に「閉じた」と誤判定しうる
        /^[ \t]*$/.test(fence[2])
      ) {
        inFence = false;
      }
    } else if (fence && !(fence[1][0] === "`" && fence[2].includes("`"))) {
      inFence = true;
      fenceChar = fence[1][0];
      fenceLen = fence[1].length;
    } else {
      const m = /^(#+)[ \t]/.exec(line);
      if (m) depth = m[1].length;
    }
    depths.push(depth);
  }
  return depths;
}

/** True if the fragment contains at least one real (non-fenced) heading. */
export function hasHeadings(md: string): boolean {
  return scanDepths(md.split(/\r?\n/)).some((d) => d > 0);
}

export function relevel(md: string, targetDepth: number): string {
  const lines = md.split(/\r?\n/);
  const depths = scanDepths(lines);
  let minDepth = Infinity;
  for (const d of depths) if (d > 0 && d < minDepth) minDepth = d;
  if (!isFinite(minDepth)) return md; // no headings: return as-is
  const delta = targetDepth - minDepth;
  if (delta === 0) return md;
  return lines
    .map((line, i) => {
      const d = depths[i];
      if (d === 0) return line;
      return "#".repeat(Math.max(1, d + delta)) + line.slice(d);
    })
    .join("\n");
}

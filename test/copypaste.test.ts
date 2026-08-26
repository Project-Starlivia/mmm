// フェーズ3: コピー → 貼り付け の往復。
// これは「ツリー → テキスト → ツリー」を通る唯一の実経路であり、
// 往復で情報が落ちるならここに出る。
//
// 経路(src/main.ts の host.copySelection / host.paste に対応):
//   copy  : core.selectionText(ids)
//   paste : decidePaste で何を貼るか決め、insertBlock で対象の to に挿す
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, initDoc, getText, randomDoc, brief, fuzzCases, nodeOf, type NodeInfo } from "./_helpers.ts";
import { decidePaste } from "../src/app/paste.ts";
import { insertBlock } from "../src/edits.ts";

const CASES = fuzzCases(250);

/**
 * src/main.ts の paste() が通る道を、**アプリと同じ部品で**再現する。
 * 何を貼るかは app/paste.ts、どう挿すかは src/edits.ts が決める —
 * ここに写経を置くと、アプリだけ直したときに誰も気づけない。
 */
function pasteAsChildOf(anchorId: number, clip: string) {
  const text = getText();
  const s = core.initDoc(text); // 現在のノードを取り直す
  const n = s.nodes.find((x) => x.id === anchorId);
  if (!n) throw new Error("anchor が無い");
  const action = decidePaste(clip, { depth: n.depth }, s.nodes.length > 0);
  if (action.kind !== "block") return { skipped: `${action.kind} として扱われた` };
  const e = insertBlock(text, n.to, action.body);
  return { snap: core.replaceText(e.from, e.to, e.insert, "") };
}

/** ノード部分木の「形」だけを取り出す(深さの相対値とラベル) */
function subtreeShape(nodes: NodeInfo[], rootId: number) {
  const root = nodes.find((n) => n.id === rootId);
  if (!root) return null;
  const out: { rel: number; label: string }[] = [];
  for (const n of nodes) {
    if (n.from >= root.from && n.to <= root.to) {
      out.push({ rel: n.depth - root.depth, label: n.label });
    }
  }
  return out;
}

// ---------------------------------------------------------------
// X1: コピーした部分木を別の場所に貼ると、同じ形になる
// ---------------------------------------------------------------

test("X1: コピー→貼り付けで部分木の形が保たれる", () => {
  const docs = [
    ["単純", "# r\n\n## src\n\n### s1\n\n### s2\n\n#### s21\n\n## dst\n"],
    ["本文つき", "# r\n\n## src\n\n本文\n\n### s1\n\n本文2\n\n## dst\n"],
    ["深さ飛び", "# r\n\n## src\n\n##### deep\n\n## dst\n"],
    ["区切りを含む", "# r\n\n## src\n\n### s1\n\n---\n\n### s2\n\n## dst\n"],
    ["フェンスを含む", "# r\n\n## src\n\n```\n## にせ見出し\n```\n\n### s1\n\n## dst\n"],
  ];
  const failures: string[] = [];
  for (const [name, md] of docs) {
    const s0 = initDoc(md);
    const src = nodeOf(s0.nodes, "src");
    const dst = nodeOf(s0.nodes, "dst");
    const want = subtreeShape(s0.nodes, src.id);

    const clip = core.selectionText([src.id]);
    const res = pasteAsChildOf(dst.id, clip);
    if (res.skipped) { failures.push(`${name}: ${res.skipped}`); continue; }

    // 貼り付け後、dst の子として src と同じ形が現れているはず
    const after = core.initDoc(getText());
    const dst2 = nodeOf(after.nodes, "dst");
    const pasted = after.nodes.filter(
      (n) => n.from > dst2.from && n.to <= dst2.to && n.label === "src",
    )[0];
    if (!pasted) {
      failures.push(`${name}: 貼り付けた src が dst の下に見つからない。text=${brief(getText(), 200)}`);
      continue;
    }
    const got = subtreeShape(after.nodes, pasted.id);
    try {
      assert.deepEqual(got, want);
    } catch {
      failures.push(`${name}: 形が違う\n    元  =${JSON.stringify(want)}\n    貼付=${JSON.stringify(got)}`);
    }
  }
  assert.deepEqual(failures, [], `コピー→貼り付けで形が崩れる:\n  ${failures.join("\n  ")}`);
});

// ---------------------------------------------------------------
// X2: relevelText は深さの相対関係を保つ
// ---------------------------------------------------------------

test("X2: relevelText は見出しの相対的な深さ関係を保つ", () => {
  const failures: string[] = [];
  const cases = [
    ["連続", "## a\n### b\n#### c\n"],
    ["飛び", "## a\n##### c\n"],
    ["戻り", "## a\n### b\n## d\n"],
    ["1始まり", "# a\n## b\n"],
    ["深い開始", "##### a\n###### b\n"],
  ];
  for (const [name, md] of cases) {
    for (const target of [1, 2, 3, 6]) {
      const out = core.relevelText(md, target);
      const depthsIn = md.split("\n").filter((l) => /^#+\s/.test(l)).map((l) => l.match(/^#+/)![0].length);
      const depthsOut = out.split("\n").filter((l) => /^#+\s/.test(l)).map((l) => l.match(/^#+/)![0].length);
      if (depthsIn.length !== depthsOut.length) {
        failures.push(`${name} -> ${target}: 見出しの数が ${depthsIn.length} -> ${depthsOut.length}`);
        continue;
      }
      if (depthsOut[0] !== target) {
        failures.push(`${name} -> ${target}: 先頭の深さが ${depthsOut[0]}(期待 ${target})`);
      }
      // 相対関係（増減の符号）が保たれているか
      for (let i = 1; i < depthsIn.length; i++) {
        const a = Math.sign(depthsIn[i] - depthsIn[i - 1]);
        const b = Math.sign(depthsOut[i] - depthsOut[i - 1]);
        if (a !== b) {
          failures.push(`${name} -> ${target}: ${i}番目で相対関係が反転 (${depthsIn.join(",")}) -> (${depthsOut.join(",")})`);
          break;
        }
      }
    }
  }
  assert.deepEqual(failures, [], `relevelText が深さ関係を壊す:\n  ${failures.join("\n  ")}`);
});

// ---------------------------------------------------------------
// X3: relevelText はフェンス内の # を見出しとして扱わない
// ---------------------------------------------------------------

test("X3: relevelText と hasHeadings がフェンス内の # を無視する", () => {
  const md = "## real\n\n```\n# fake\n## fake2\n```\n\n### real2\n";
  const out = core.relevelText(md, 4);
  assert.ok(out.includes("# fake\n"), `フェンス内の # が書き換えられた:\n${out}`);
  assert.ok(out.includes("## fake2\n"), `フェンス内の ## が書き換えられた:\n${out}`);
  assert.ok(/^#### real\b/m.test(out), `本物の見出しが 4 に揃っていない:\n${out}`);
  assert.equal(
    core.hasHeadings("```\n# fake\n```\n"),
    false,
    "フェンス内だけの # を見出しと誤判定",
  );
  assert.equal(core.hasHeadings("# real\n"), true);
  assert.equal(core.hasHeadings("ただの本文\n"), false);
});

test("X3b: 情報文字列が 2 語のフェンスでも中は見出しにならない", () => {
  // `” ```js copy ”` のような書き方（GitHub のコピー指定など）。
  // 以前はカード側だけがこれをフェンスと認めず、中の URL がカードに
  // なっていた。フェンスの答えはコアの 1 箇所しか無いので、ずれようがない
  const md = "## real\n\n```js copy\n# fake\n```\n";
  assert.ok(core.relevelText(md, 4).includes("# fake\n"));
  assert.equal(core.hasHeadings("```js copy\n# fake\n```\n"), false);
});

// ---------------------------------------------------------------
// X4: コピーした内容に未選択の重複ルートが混ざらない（F-005 の回帰）
// ---------------------------------------------------------------

test("X4: コピーに未選択の # ブロックが混入しない（F-005 の回帰）", () => {
  const md = "# root\n\n## a\n\n本文A\n\n# 二つ目のルート\n\n## b\n";
  const s = initDoc(md);
  const a = nodeOf(s.nodes, "a");
  const clip = core.selectionText([a.id]);
  assert.ok(
    !clip.includes("二つ目のルート"),
    `ノード a のコピーに、選択していない見出しが混入している:\n  clip=${brief(clip)}`,
  );
});

// ---------------------------------------------------------------
// X5: ランダム文書でも コピー→貼り付け が例外を出さず木を壊さない
// ---------------------------------------------------------------

test("X5: ランダム文書のコピー→貼り付けで木が壊れない", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES && failures.length < 6; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    if (s.nodes.length < 2) continue;
    const src = s.nodes[1];
    const dst = s.nodes[s.nodes.length - 1];
    if (src.id === dst.id) continue;
    let clip;
    try { clip = core.selectionText([src.id]); }
    catch (e) { failures.push(`seed=${seed}: copy で例外 ${String(e).slice(0, 80)}`); continue; }
    let res;
    try { res = pasteAsChildOf(dst.id, clip); }
    catch (e) { failures.push(`seed=${seed}: paste で例外 ${String(e).slice(0, 80)}`); continue; }
    if (res.skipped) continue;
    const text = getText();
    const after = core.initDoc(text);
    // 内部整合性
    for (const n of after.nodes) {
      const line = text.slice(n.from, n.headEnd);
      if (!/^(#+|\s*[-*+])(\s|$)/.test(line)) {
        failures.push(`seed=${seed}: 貼り付け後に構造でない行がノード化 ${JSON.stringify(line)}`);
        break;
      }
    }
    // ノードが減っていないこと（貼り付けは増えるだけのはず）
    if (after.nodes.length < s.nodes.length) {
      failures.push(`seed=${seed}: 貼り付けでノードが ${s.nodes.length} -> ${after.nodes.length} に減った`);
    }
  }
  assert.deepEqual(failures, [], `コピー→貼り付けが木を壊す:\n  ${failures.join("\n  ")}`);
});

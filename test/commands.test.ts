// フェーズ3: 構造コマンド・undo/redo・hide/show の往復性質。
// 実行: pnpm test
//
// 監査で見つけた不具合は F-0xx として名前を付け、直った後もその形の
// テストを回帰ガードとしてここに残している。

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, initDoc, getText, shape, randomDoc, brief, fuzzCases, nodeOf, reason, type NodeInfo, type Snapshot } from "./_helpers.ts";

const CASES = fuzzCases(250);

/** ノードのオフセット整合性（roundtrip.test.mjs の P2c と同じ検査） */
function assertTreeSane(nodes: NodeInfo[], text: string, tag: string): void {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  let prevFrom = -1;
  for (const n of nodes) {
    assert.ok(n.from > prevFrom, `${tag}: from が単調増加でない (id=${n.id})`);
    prevFrom = n.from;
    assert.ok(n.to <= text.length, `${tag}: to が本文長超過 (id=${n.id})`);
    const line = text.slice(n.from, n.headEnd);
    // 構造行は見出しかリスト項目（list-form 以降、リストも構造）
    assert.match(
      line,
      /^(#+|\s*[-*+])(\s|$)/,
      `${tag}: 構造行でない (id=${n.id}, ${JSON.stringify(line)})`,
    );
    if (n.parent !== -1) {
      const p = byId.get(n.parent);
      assert.ok(p, `${tag}: 親 ${n.parent} が存在しない (id=${n.id})`);
      assert.ok(p.from < n.from && n.to <= p.to, `${tag}: 親の範囲外 (id=${n.id})`);
    }
  }
}

// ---------------------------------------------------------------
// C1: すべての構造コマンドで undo がバイト単位に元へ戻す
// ---------------------------------------------------------------

const SEED_DOC = "# root\n\n## a\n\n本文A\n\n### a1\n\n## b\n\n---\n\n## c\n\n### c1\n\n本文C\n";

/** コマンド1個ぶんの定義。fn は snapshot を返す。 */
function commandsFor(nodes: NodeInfo[]): [string, () => Snapshot][] {
  const ids = nodes.map((n) => n.id);
  const mid = ids[Math.floor(ids.length / 2)];
  const last = ids[ids.length - 1];
  const cmds: [string, () => Snapshot][] = [];
  for (const id of ids) {
    cmds.push([`addChild(${id})`, () => (core.addChild(id))]);
    
    cmds.push([`addSibling(${id})`, () => (core.addSibling(id))]);
    cmds.push([`addSiblingBefore(${id})`, () => (core.addSiblingBefore(id))]);
    cmds.push([`addParent(${id})`, () => (core.addParent(id))]);
    cmds.push([`rename(${id})`, () => (core.renameNode(id, "変更後ラベル", ""))]);
    cmds.push([`rename(${id},empty)`, () => (core.renameNode(id, "", ""))]);
    cmds.push([`delete(${id})`, () => (core.deleteNodes([id]))]);
    cmds.push([`indent(${id})`, () => (core.indentNodes([id]))]);
    cmds.push([`outdent(${id})`, () => (core.outdentNodes([id]))]);
    cmds.push([`reorder(${id},-1)`, () => (core.reorderNode(id, -1))]);
    cmds.push([`reorder(${id},1)`, () => (core.reorderNode(id, 1))]);
    cmds.push([`toggleHidden(${id})`, () => (core.toggleHidden(id))]);
    for (const pos of [0, 1, 2] as const) {
      if (id !== mid) cmds.push([`move(${id}->${mid},${pos})`, () => (core.moveNodes([id], mid, pos))]);
      if (id !== last) cmds.push([`move(${id}->${last},${pos})`, () => (core.moveNodes([id], last, pos))]);
    }
    // A->B の線への割り込み(線の相手が動かす本人自身でないものだけ)
    if (id !== mid) cmds.push([`moveAsParent(${id}->${mid})`, () => (core.moveAsParent([id], mid))]);
    if (id !== last) cmds.push([`moveAsParent(${id}->${last})`, () => (core.moveAsParent([id], last))]);
  }
  cmds.push([`delete(multi)`, () => (core.deleteNodes(ids.slice(1, 3)))]);
  cmds.push([`indent(multi)`, () => (core.indentNodes(ids.slice(1, 3)))]);
  cmds.push([`outdent(multi)`, () => (core.outdentNodes(ids.slice(1, 3)))]);
  cmds.push([`addRoot`, () => (core.addRoot())]);
  return cmds;
}

test("C1: 全構造コマンドで undo がバイト単位に元へ戻す", () => {
  const base = initDoc(SEED_DOC);
  const failures: string[] = [];
  for (const [name, fn] of commandsFor(base.nodes)) {
    initDoc(SEED_DOC);
    const before = getText();
    fn();
    const afterCmd = getText();
    (core.undo());
    const afterUndo = getText();
    if (afterUndo !== before) {
      failures.push(`${name}: undo 後が元と違う\n    元  =${brief(before, 120)}\n    実行後=${brief(afterCmd, 120)}\n    undo後=${brief(afterUndo, 120)}`);
    }
  }
  assert.deepEqual(failures, [], `undo がバイト復元しないコマンド:\n  ${failures.join("\n  ")}`);
});

test("C2: 全構造コマンドで undo→redo が実行直後と一致", () => {
  const base = initDoc(SEED_DOC);
  const failures: string[] = [];
  for (const [name, fn] of commandsFor(base.nodes)) {
    initDoc(SEED_DOC);
    fn();
    const afterCmd = getText();
    (core.undo());
    (core.redo());
    const afterRedo = getText();
    if (afterRedo !== afterCmd) {
      failures.push(`${name}: redo 後が実行直後と違う\n    実行後=${brief(afterCmd, 120)}\n    redo後=${brief(afterRedo, 120)}`);
    }
  }
  assert.deepEqual(failures, [], `redo が復元しないコマンド:\n  ${failures.join("\n  ")}`);
});

test("C3: コマンド実行後のツリーが常に内部整合を保つ", () => {
  const base = initDoc(SEED_DOC);
  const failures: string[] = [];
  for (const [name, fn] of commandsFor(base.nodes)) {
    initDoc(SEED_DOC);
    let s;
    try { s = fn(); } catch (e) { failures.push(`${name}: 例外 ${String(e).slice(0, 120)}`); continue; }
    try { assertTreeSane(s.nodes, getText(), name); } catch (e) { failures.push(`${name}: ${reason(e)}`); }
  }
  assert.deepEqual(failures, [], `整合性が壊れるコマンド:\n  ${failures.join("\n  ")}`);
});

test("C4: コマンド実行後の木が、同じテキストを新規パースした木と構造一致", () => {
  // 増分state と 新規パース が食い違えば、UI が見ている木は嘘になる。
  const base = initDoc(SEED_DOC);
  const failures: string[] = [];
  for (const [name, fn] of commandsFor(base.nodes)) {
    initDoc(SEED_DOC);
    const s = fn();
    const incremental = shape(s.nodes);
    const fresh = shape(initDoc(getText()).nodes);
    try {
      assert.deepEqual(incremental, fresh);
    } catch {
      failures.push(`${name}: 増分の木 と 再パースの木 が違う`);
    }
  }
  assert.deepEqual(failures, [], `増分と再パースが食い違うコマンド:\n  ${failures.join("\n  ")}`);
});

// ---------------------------------------------------------------
// C5: ランダムなコマンド列でも undo を全部巻き戻せば原文に戻る
// ---------------------------------------------------------------

test("C5: ランダムコマンド列を全 undo すると原文に戻る", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= 120 && failures.length < 6; seed++) {
    const md = randomDoc(seed);
    let s = initDoc(md);
    if (s.nodes.length === 0) continue;
    const original = getText();
    const applied: string[] = [];
    for (let step = 0; step < 6; step++) {
      const nodes = s.nodes;
      if (nodes.length === 0) break;
      const cmds = commandsFor(nodes);
      const [name, fn] = cmds[(seed * 7919 + step * 104729) % cmds.length];
      applied.push(name);
      s = fn();
    }
    for (let i = 0; i < applied.length + 2; i++) (core.undo());
    if (getText() !== original) {
      failures.push(`seed=${seed} 手順=[${applied.join(", ")}]\n    原文=${brief(original, 140)}\n    復元=${brief(getText(), 140)}`);
    }
  }
  assert.deepEqual(failures, [], `全 undo で原文に戻らない:\n  ${failures.join("\n  ")}`);
});

// ---------------------------------------------------------------
// C6: hide → show の往復（コメントアウト無効化）
// ---------------------------------------------------------------

test("C6: hide→show がテキストを元に戻す", () => {
  const docs = [
    ["末尾改行あり", "# r\n\n## a\n\n### a1\n\n## b\n"],
    ["末尾改行なし", "# r\n\n## a"],
    ["末尾改行なし・子あり", "# r\n\n## a\n\n### a1"],
    ["本文つき", "# r\n\n## a\n\n本文\n\n## b\n"],
    ["CRLF", "# r\r\n\r\n## a\r\n\r\n## b\r\n"],
    ["区切りの直前", "# r\n\n## a\n\n---\n\n## b\n"],
  ];
  const failures: string[] = [];
  for (const [name, md] of docs) {
    const s = initDoc(md);
    const target = s.nodes.find((n) => n.depth === 2);
    if (!target) continue;
    const before = getText();
    (core.toggleHidden(target.id));
    const hidden = getText();
    // hide が実際に効いたか
    if (hidden === before) { failures.push(`${name}: hide が何もしなかった`); continue; }
    (core.toggleHidden(target.id));
    const shown = getText();
    if (shown !== before) {
      failures.push(`${name}: hide→show が元に戻らない\n    元    =${brief(before, 120)}\n    hide後=${brief(hidden, 120)}\n    show後=${brief(shown, 120)}`);
    }
  }
  assert.deepEqual(failures, [], `hide→show が非可逆:\n  ${failures.join("\n  ")}`);
});

test("C7: hide 状態のノードは構造に残り、hidden=true になる", () => {
  const s = initDoc("# r\n\n## a\n\n### a1\n\n## b\n");
  const a = nodeOf(s.nodes, "a");
  const idsBefore = s.nodes.map((n) => n.id);
  const h = (core.toggleHidden(a.id));
  assert.deepEqual(h.nodes.map((n) => n.id), idsBefore, "hide でノード id が変わった");
  const hiddenLabels = h.nodes.filter((n) => n.hidden).map((n) => n.label);
  assert.deepEqual(hiddenLabels, ["a", "a1"], "hidden フラグが部分木全体に付いていない");
});

// ---------------------------------------------------------------
// C8: ノード ID の保存
// ---------------------------------------------------------------

test("C8: rename は全ノードの id を保存する", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    if (!s.nodes.length) continue;
    const target = s.nodes[Math.floor(s.nodes.length / 2)];
    const before = s.nodes.map((n) => n.id);
    const after = (core.renameNode(target.id, "新ラベル", "")).nodes.map((n) => n.id);
    if (JSON.stringify(before) !== JSON.stringify(after)) {
      failures.push(`seed=${seed}: rename で id 集合が変化 ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
    }
    if (failures.length > 5) break;
  }
  assert.deepEqual(failures, [], `rename が id を壊す:\n  ${failures.join("\n  ")}`);
});

test("C9a: indent は全ノードの id を保存する", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    if (s.nodes.length < 2) continue;
    const target = s.nodes[s.nodes.length - 1];
    const before = s.nodes.map((n) => n.id).sort((a, b) => a - b);
    const after = (core.indentNodes([target.id])).nodes.map((n) => n.id).sort((a, b) => a - b);
    if (JSON.stringify(before) !== JSON.stringify(after)) {
      failures.push(`seed=${seed}: indent で id 集合が変化 ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
    }
    if (failures.length > 5) break;
  }
  assert.deepEqual(failures, [], `indent が id を壊す:\n  ${failures.join("\n  ")}`);
});

// F-004（outdent で id が捨てられ選択が外れる）の回帰テスト。
// 原因は doc.mbt の map_offset が「見出し開始位置ちょうどでの純削除」を
// 無条件に「その見出しは消えた」と解釈していたこと。改行をまたぐ削除だけを
// 破壊扱いにするよう修正済み。
test("C9b: outdent は対象ノードの id を保存する（F-004 の回帰）", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    if (s.nodes.length < 2) continue;
    const target = s.nodes[s.nodes.length - 1];
    const beforeId = target.id;
    const before = s.nodes.map((n) => n.id).sort((a, b) => a - b);
    const res = (core.outdentNodes([target.id]));
    const after = res.nodes.map((n) => n.id).sort((a, b) => a - b);
    if (JSON.stringify(before) === JSON.stringify(after)) continue; // no-op だった
    if (!after.includes(beforeId)) {
      failures.push(`seed=${seed}: outdent 対象 id=${beforeId} が消滅（id 集合 ${JSON.stringify(before)} -> ${JSON.stringify(after)}）`);
    }
    if (failures.length > 5) break;
  }
  assert.deepEqual(failures, [], `outdent が対象ノードの id を捨てている:\n  ${failures.join("\n  ")}`);
});

test("C10a: ルート以外への移動は id を保存する", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    if (s.nodes.length < 3) continue;
    const src = s.nodes[s.nodes.length - 1];
    // 深さ1（ルート）を移動先にしない = UI のドロップガードと同じ条件
    const dst = s.nodes.find((n) => n.depth !== 1 && n.id !== src.id);
    if (!dst) continue;
    const before = s.nodes.map((n) => n.id).sort((a, b) => a - b);
    let after;
    try { after = (core.moveNodes([src.id], dst.id, 1)).nodes.map((n) => n.id).sort((a, b) => a - b); }
    catch (e) { failures.push(`seed=${seed}: move で例外 ${String(e).slice(0, 100)}`); continue; }
    if (JSON.stringify(before) !== JSON.stringify(after)) {
      failures.push(`seed=${seed}: move で id 集合が変化 ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
    }
    if (failures.length > 5) break;
  }
  assert.deepEqual(failures, [], `ルート以外への move が id を壊す:\n  ${failures.join("\n  ")}`);
});

// F-006（ルートの「兄弟」位置へ移動すると `#` が2つになり、単一ルート規約で
// 一方が構造から消える）の回帰テスト。UI は updateDrop (src/mindmap.ts の
// 深さ1へのドロップ判定)が強制的に pos=0（子）に倒すので到達しないが、
// コア API 自体がノードを失わないことも別途保証しておく。
test("C10b: ルートの兄弟位置への移動でノードが消えない（F-006 の回帰）", () => {
  const md = "# root\n\n## a\n\n### a1\n\n## b\n";
  const failures: string[] = [];
  for (const pos of [1, 2] as const) {
    const s0 = initDoc(md);
    const root = nodeOf(s0.nodes, "root");
    const b = nodeOf(s0.nodes, "b");
    const s1 = (core.moveNodes([b.id], root.id, pos));
    const lostIds = s0.nodes.map((n) => n.id).filter((id) => !s1.nodes.some((n) => n.id === id));
    if (lostIds.length) {
      failures.push(
        `pos=${pos}: ノード id ${JSON.stringify(lostIds)} が構造から消滅 ` +
          `(${s0.nodes.length} -> ${s1.nodes.length})。text=${brief(getText(), 120)}`,
      );
    }
  }
  assert.deepEqual(failures, [], `ルート兄弟への移動でノードが消える:\n  ${failures.join("\n  ")}`);
});

test("C11: undo / redo をまたいでも id が保存される", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= 120; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    if (s.nodes.length < 2) continue;
    const target = s.nodes[s.nodes.length - 1];
    const before = s.nodes.map((n) => n.id).sort((a, b) => a - b);
    (core.indentNodes([target.id]));
    const undone = (core.undo()).nodes.map((n) => n.id).sort((a, b) => a - b);
    if (JSON.stringify(before) !== JSON.stringify(undone)) {
      failures.push(`seed=${seed}: undo 後に id 集合が変化 ${JSON.stringify(before)} -> ${JSON.stringify(undone)}`);
    }
    if (failures.length > 5) break;
  }
  assert.deepEqual(failures, [], `undo が id を壊す:\n  ${failures.join("\n  ")}`);
});

// ---------------------------------------------------------------
// C12: 自分自身・自分の子孫への移動は木を壊してはいけない
// ---------------------------------------------------------------

test("C12: 自分の子孫への移動が木を壊さない", () => {
  const failures: string[] = [];
  const md = "# r\n\n## a\n\n### a1\n\n#### a11\n\n## b\n";
  const s0 = initDoc(md);
  const a = nodeOf(s0.nodes, "a");
  const a1 = nodeOf(s0.nodes, "a1");
  const a11 = nodeOf(s0.nodes, "a11");
  for (const [name, src, dst] of ([
    ["a を自分自身へ", a.id, a.id],
    ["a を子 a1 へ", a.id, a1.id],
    ["a を孫 a11 へ", a.id, a11.id],
    ["a1 を子 a11 へ", a1.id, a11.id],
  ] satisfies [string, number, number][])) {
    for (const pos of ([0, 1, 2] as const)) {
      initDoc(md);
      let s;
      try { s = (core.moveNodes([src], dst, pos)); }
      catch (e) { failures.push(`${name} pos=${pos}: 例外 ${String(e).slice(0, 100)}`); continue; }
      const text = getText();
      try { assertTreeSane(s.nodes, text, `${name} pos=${pos}`); }
      catch (e) { failures.push(reason(e)); continue; }
      // ノードが消えたり増殖したりしていないこと
      if (s.nodes.length !== s0.nodes.length) {
        failures.push(`${name} pos=${pos}: ノード数が ${s0.nodes.length} -> ${s.nodes.length} に変化。text=${brief(text, 150)}`);
      }
    }
  }
  assert.deepEqual(failures, [], `子孫への移動で木が壊れる:\n  ${failures.join("\n  ")}`);
});

test("スナップショットが枝ごとのグループと側を載せる", () => {
  const snap = initDoc("# r\n\n## a\n\n---\n---\n\n## b\n\n### b1\n\n#### b2\n");
  const by = (label: string) => nodeOf(snap.nodes, label);
  assert.equal(by("a").group, 0);
  assert.equal(by("a").left, false);
  assert.equal(by("b").group, 1);
  assert.equal(by("b").left, true);
  // 枝の中も同じ値（UI は導き直さない）。孫（b1）だけでなく曾孫（b2）まで
  // 通しておかないと、1 段だけ伝えて止まる退行に気づけない
  assert.equal(by("b1").group, 1);
  assert.equal(by("b1").left, true);
  assert.equal(by("b2").group, 1);
  assert.equal(by("b2").left, true);
});

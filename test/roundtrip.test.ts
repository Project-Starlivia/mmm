// フェーズ3: parse → serialize の往復性質。
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { initDoc, getText, normTree, randomDoc, corpus, brief, fuzzCases } from "./_helpers.ts";

// commands/copypaste の CASES(既定 250)より多いのは、ここは構造コマンドを
// 経由しない純粋な parse→serialize なので 1 ケースが軽く、数を稼ぎやすいため。
const RANDOM_CASES = fuzzCases(400);

// ---------------------------------------------------------------
// P1: parse → serialize が冪等（バイト単位で同一）
// このアプリの「テキストが唯一の真実」という主張そのもの。
// ---------------------------------------------------------------

test("P1: リポジトリ内の実 .md すべてで parse→serialize がバイト同一", () => {
  const docs = corpus();
  assert.ok(docs.length > 0, "対象の .md が1つも見つからない");
  for (const { path, md } of docs) {
    initDoc(md);
    assert.equal(getText(), md, `${path} で往復に差が出た`);
  }
});

test("P1: ランダム生成入力で parse→serialize がバイト同一", () => {
  for (let seed = 1; seed <= RANDOM_CASES; seed++) {
    const md = randomDoc(seed);
    initDoc(md);
    assert.equal(getText(), md, `seed=${seed} で差分。入力=${brief(md)}`);
  }
});

test("P1: 病的な入力でも parse→serialize がバイト同一", () => {
  const cases: [string, string][] = [
    ["空文書", ""],
    ["改行のみ", "\n"],
    ["改行2つ", "\n\n"],
    ["CR のみ", "\r"],
    ["末尾 CR", "# a\r"],
    ["CRLF 混在", "# a\r\n## b\n### c\r\n"],
    ["末尾改行なし", "# a\n\n## b"],
    ["見出しなし本文のみ", "ただの本文\nもう一行\n"],
    ["先頭が区切り", "---\n\n# a\n"],
    ["ルート前ノード", "## before\n\n# root\n\n## after\n"],
    ["複数ルート", "# one\n\n# two\n\n# three\n"],
    ["深さ7以上", "# a\n\n######## eight\n"],
    ["空ラベル", "#\n\n##\n"],
    ["#のみ連続", "#\n#\n#\n"],
    ["見出し記号だが空白なし", "#nospace\n"],
    ["先頭空白付き見出し", "   # indented\n"],
    ["未閉フェンス", "# a\n\n```\n## inside\n"],
    ["未閉コメント", "# a\n\n<!--\n## hidden\n"],
    ["コメント閉じのみ", "# a\n\n-->\n\n## b\n"],
    ["フェンス内コメント", "# a\n\n```\n<!--\n```\n\n## b\n"],
    ["タブ区切り見出し", "#\ta\n"],
    ["全角スペース見出し", "#　a\n"],
    ["絵文字とサロゲートペア", "# 😀𝔘𝔫𝔦\n\n## 🇯🇵\n"],
    ["結合文字", "# が\n"],
    ["NUL を含む本文", "# a\n\n\u0000\n"],
    ["巨大単一行", "# " + "x".repeat(50000) + "\n"],
    ["区切りの変種", "# a\n\n***\n\n## b\n\n___\n\n## c\n"],
    ["3スペース字下げ区切り", "# a\n\n   ---\n\n## b\n"],
    ["4スペース字下げ区切り", "# a\n\n    ---\n\n## b\n"],
  ];
  for (const [name, md] of cases) {
    initDoc(md);
    assert.equal(getText(), md, `「${name}」で差分。入力=${brief(md)}`);
  }
});

// ---------------------------------------------------------------
// P2: parse → serialize → parse でツリーが一致
// ---------------------------------------------------------------

test("P2: 実 .md で parse→serialize→parse のツリーが完全一致", () => {
  for (const { path, md } of corpus()) {
    const a = initDoc(md);
    const t1 = getText();
    const b = initDoc(t1);
    assert.deepEqual(normTree(b.nodes), normTree(a.nodes), `${path} で再パース結果が違う`);
  }
});

test("P2: ランダム入力で parse→serialize→parse のツリーが完全一致", () => {
  for (let seed = 1; seed <= RANDOM_CASES; seed++) {
    const md = randomDoc(seed);
    const a = initDoc(md);
    const b = initDoc(getText());
    assert.deepEqual(
      normTree(b.nodes),
      normTree(a.nodes),
      `seed=${seed} で再パース結果が違う。入力=${brief(md)}`,
    );
  }
});

// ---------------------------------------------------------------
// P2b: パースの決定性 — 同じ入力を2回 parse したら必ず同じ木
// （グローバル状態 st の持ち越しが無いことの確認）
// ---------------------------------------------------------------

test("P2b: 同一入力の再パースが決定的（前のセッションを引きずらない）", () => {
  for (let seed = 1; seed <= 120; seed++) {
    const md = randomDoc(seed);
    const a = initDoc(md);
    // 別の文書を挟んでから同じものをもう一度
    initDoc("# 別の文書\n\n## x\n");
    const b = initDoc(md);
    assert.deepEqual(
      normTree(b.nodes),
      normTree(a.nodes),
      `seed=${seed}: 直前の文書の状態が漏れている。入力=${brief(md)}`,
    );
  }
});

// ---------------------------------------------------------------
// P2c: ツリーの内部整合性 — オフセットと親子関係が矛盾しないこと
// ---------------------------------------------------------------

test("P2c: ノードのオフセットと親子関係が常に整合する", () => {
  const check = (md: string, tag: string): void => {
    const s = initDoc(md);
    const text = getText();
    const byId = new Map(s.nodes.map((n) => [n.id, n]));
    let prevHs = -1;
    for (const n of s.nodes) {
      assert.ok(n.hs > prevHs, `${tag}: hs が文書順に単調増加でない (id=${n.id})`);
      prevHs = n.hs;
      assert.ok(n.he >= n.hs, `${tag}: he < hs (id=${n.id})`);
      assert.ok(n.subEnd >= n.he, `${tag}: subEnd < he (id=${n.id})`);
      assert.ok(n.subEnd <= text.length, `${tag}: subEnd が本文長を超える (id=${n.id})`);
      // 見出し行が本当に見出しであること
      const line = text.slice(n.hs, n.he);
      assert.match(line, /^#+(\s|$)/, `${tag}: hs..he が見出し行でない (id=${n.id}, ${JSON.stringify(line)})`);
      // depth は「# の数」そのものではない。`---` で始まる束の中では、
      // 束の先頭を深さ 2 として相対的に読み替える（2026-08-12 の記法変更）。
      // 読み替えは持ち上げる方向にしか働かないので、depth が # の数を
      // 超えることはない。深さ 1 は必ず `#` 1 個。
      const hashes = line.match(/^#+/)![0].length;
      assert.ok(
        n.depth <= hashes,
        `${tag}: depth が # の数を超えている (id=${n.id}, depth=${n.depth}, #=${hashes})`,
      );
      assert.ok(n.depth >= 1, `${tag}: depth が 1 未満 (id=${n.id})`);
      if (hashes === 1) {
        assert.equal(n.depth, 1, `${tag}: # 1 個なのに depth が 1 でない (id=${n.id})`);
      }
      if (n.parent !== -1) {
        const p = byId.get(n.parent);
        assert.ok(p, `${tag}: parent id ${n.parent} が存在しない (id=${n.id})`);
        assert.ok(p.depth < n.depth, `${tag}: 親の depth が子以上 (id=${n.id})`);
        assert.ok(
          p.hs < n.hs && n.subEnd <= p.subEnd,
          `${tag}: 子の範囲が親の範囲に含まれていない (id=${n.id})`,
        );
      }
    }
  };
  for (const { path, md } of corpus()) check(md, path);
  for (let seed = 1; seed <= RANDOM_CASES; seed++) check(randomDoc(seed), `seed=${seed}`);
});

// ---------------------------------------------------------------
// P2d: 複数ルート規約 — depth1 は何個あってもよく、それぞれ独立した木になる
//
// 2026-08-12 に規約を変更した。以前は 2 つ目以降の `#` を構造から外して
// いたが、テキストに在るのにマップから消え（選択も移動も削除もできない）、
// その子は親を失って浮いていた。いまは最初の `#` より前に書いたノードと
// 同じ扱い＝親なしの別ツリーとして出す。
// ---------------------------------------------------------------

test("P2d: depth1 のノードはどれも親を持たず、範囲が重ならない", () => {
  for (let seed = 1; seed <= RANDOM_CASES; seed++) {
    const md = randomDoc(seed);
    const s = initDoc(md);
    const roots = s.nodes.filter((n) => n.depth === 1);
    for (const r of roots) {
      assert.equal(
        r.parent,
        -1,
        `seed=${seed}: depth1 の id=${r.id} に親 ${r.parent} が付いている。入力=${brief(md)}`,
      );
    }
    // 隣り合うルートの範囲が食い合わない（食うと片方を消したとき巻き添えになる）
    for (let i = 1; i < roots.length; i++) {
      assert.ok(
        roots[i - 1].subEnd <= roots[i].hs,
        `seed=${seed}: ルート id=${roots[i - 1].id} の範囲が次のルートに食い込んでいる。入力=${brief(md)}`,
      );
    }
  }
});

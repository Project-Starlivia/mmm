# カードをノード並みに扱う 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** マップ上のカード（リンク / 画像 / SVG / コード）を、ノードと同じように選び・その場で直し・消し・並べ替え・別ノードへ動かせるようにする。

**Architecture:** カードは `{node: ノード id, index: 何枚目}` で指す。`CardRow` の 4 種すべてに元の行の範囲（`from`/`to`）を持たせ、編集・削除・移動をすべて `core.replaceText` 1 回に落とす。選択は `main.ts` が一括で持ち、「ノード群」か「カード 1 枚」のどちらか一方だけが空でない。`core/`（MoonBit）は一行も変えない。

**Tech Stack:** TypeScript / SVG（自前描画）/ MoonBit コア（変更なし）/ node:test

**Spec:** `docs/superpowers/specs/2026-08-23-cards-as-nodes-design.md`

## Global Constraints

- `core/`（MoonBit）は変更しない。カードの操作はすべて `core.replaceText(from, to, insert, tag)` 経由。
- 移動・削除・編集は **1 回の `replaceText`** に落とす（Undo を 1 回にするため）。
- 選択の不変条件: `selection`（ノード）と `picked`（カード）は、**どちらか一方だけが空でない**。
- 並べ替えは `Alt+↑↓`。`Mod+矢印` には何も割り当てない。
- カードの複数選択はしない。
- コメント・コミットメッセージは日本語。コミットは Semantic Commit Message（`<type>: <emoji> <title>`）。
- 各タスクの最後に `pnpm run check` と `pnpm test` を通してからコミットする。
- 検証でブラウザを使うときは、**ペインへ dispatch する経路**で試す（要素へ直接 dispatch するとポインタキャプチャによる付け替えを迂回してしまい、通らない経路を「通った」と誤認する）。

---

### Task 1: 4 種すべてのカードに元の行の範囲を持たせる

いま `from`/`to` を持つのはコード（フェンス全体）と画像（1 行）だけ。リンクと SVG にも持たせ、「どのカードも自分がどの行から来たか知っている」状態にする。以降の全タスクの土台。

**Files:**
- Modify: `src/map/cards.ts`（`CardRow` 型、`rowsOfContent` の link / svg の push 箇所）
- Test: `test/cards.test.ts`（新規）

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: `CardRow` の 4 種すべてが `from: number` と `to: number` を持つ。`from` はそのカードの元テキストの開始オフセット、`to` は終了オフセット（`to` は含まない）。`text.slice(from, to)` がそのカードの元テキストそのものになる。

- [ ] **Step 1: 失敗するテストを書く**

`test/cards.test.ts` を新規作成:

```typescript
// カードは「自分がどの行から来たか」を知っている。ここが選択・編集・移動の
// 土台なので、4 種すべてで slice が元テキストに一致することを固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { core, initDoc } from "./_helpers.ts";
import { cardRows } from "../src/map/cards.ts";

/** 1 ノードぶんのカードを取り出す小道具 */
function rowsOf(md: string) {
  const snap = initDoc(md);
  const text = core.getText();
  const map = cardRows(text, snap.nodes, new Set<number>());
  const node = snap.nodes[snap.nodes.length - 1];
  return { rows: map.get(node.id) ?? [], text };
}

test("cardRows: 4 種すべてが from/to を持ち、slice が元テキストに一致する", () => {
  const md =
    "# r\n\n## n\n\n" +
    "[題](https://example.com)\n" +
    "![](./a.webp)\n" +
    "<svg><rect/></svg>\n" +
    "```ts\nconst a = 1;\n```\n";
  const { rows, text } = rowsOf(md);
  assert.deepEqual(
    rows.map((r) => r.kind),
    ["link", "img", "svg", "code"],
  );
  assert.equal(text.slice(rows[0].from, rows[0].to), "[題](https://example.com)");
  assert.equal(text.slice(rows[1].from, rows[1].to), "![](./a.webp)");
  assert.equal(text.slice(rows[2].from, rows[2].to), "<svg><rect/></svg>");
  assert.equal(text.slice(rows[3].from, rows[3].to), "```ts\nconst a = 1;\n```");
});

test("cardRows: 複数行の svg も丸ごと指す", () => {
  const md = "# r\n\n## n\n\n<svg>\n  <rect/>\n</svg>\n";
  const { rows, text } = rowsOf(md);
  assert.equal(rows.length, 1);
  assert.equal(text.slice(rows[0].from, rows[0].to), "<svg>\n  <rect/>\n</svg>");
});
```

- [ ] **Step 2: 失敗を確認する**

Run: `pnpm test 2>&1 | grep -A5 "cardRows"`
Expected: 型エラー、または `rows[0].from` が `undefined` で FAIL

- [ ] **Step 3: 型に from/to を足す**

`src/map/cards.ts` の `CardRow` を差し替え:

```typescript
/** One card row under the label, from the attached content.
 *  from/to はそのカードの元テキストの範囲。`text.slice(from, to)` が
 *  そのカードそのものになる（選択・編集・移動はすべてこれに乗る）。 */
export type CardRow =
  | { kind: "link"; link: LinkInfo; from: number; to: number }
  | { kind: "img"; path: string; name: string; from: number; to: number }
  | { kind: "svg"; markup: string; from: number; to: number }
  | { kind: "code"; lang: string; lines: string[]; from: number; to: number };
```

- [ ] **Step 4: link と svg の push に範囲を足す**

`src/map/cards.ts` の `rowsOfContent` 内、svg の push を差し替え:

```typescript
      if (buf[buf.length - 1].includes("</svg>")) {
        list.push({
          kind: "svg",
          markup: buf.join("\n"),
          from: lineAt[li],
          to: lineAt[j] + lines[j].length,
        });
        li = j;
        continue;
      }
```

同じく link の push を差し替え:

```typescript
      const l = parseLink(lines[li]);
      if (l)
        list.push({
          kind: "link",
          link: l,
          from: lineAt[li],
          to: lineAt[li] + lines[li].length,
        });
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "cardRows|^ℹ (tests|pass|fail)"`
Expected: cardRows の 2 本が PASS、全体の fail 0

- [ ] **Step 6: コミット**

```bash
git add src/map/cards.ts test/cards.test.ts
git commit -m "refactor: ♻️ 全カードに元の行の範囲を持たせる"
```

---

### Task 2: 削除・移動のオフセット計算（純粋層）

「どの範囲を何で置き換えるか」を純粋関数に切り出す。ここが合っていれば残りは配線なので、単体テストで固める。

**Files:**
- Create: `src/map/cardEdit.ts`
- Test: `test/cardEdit.test.ts`（新規）

**Interfaces:**
- Consumes: Task 1 の `CardRow`（`from`/`to`）
- Produces:
  - `type TextEdit = { from: number; to: number; insert: string }`
  - `removeCard(text: string, from: number, to: number): TextEdit`
  - `moveCard(text: string, from: number, to: number, at: number): TextEdit | null`
    - `at` は挿入したい位置（行頭のオフセット）。`from <= at && at <= to` のときは動かす意味が無いので `null`。

- [ ] **Step 1: 失敗するテストを書く**

`test/cardEdit.test.ts` を新規作成:

```typescript
// カードの削除・移動は「どの範囲を何で置き換えるか」に尽きる。
// 1 回の replaceText に落とすので Undo も 1 回になる。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { moveCard, removeCard } from "../src/map/cardEdit.ts";

/** 編集を当てた結果の本文 */
const apply = (text: string, e: { from: number; to: number; insert: string }) =>
  text.slice(0, e.from) + e.insert + text.slice(e.to);

const DOC = "a\nB\nc\n";
//           0 1 2 3 4 5
// "B" は [2,3)

test("removeCard: 行末の改行ごと持っていく（空行を残さない）", () => {
  const e = removeCard(DOC, 2, 3);
  assert.equal(apply(DOC, e), "a\nc\n");
});

test("removeCard: 末尾の行なら手前の改行を巻き取る", () => {
  const doc = "a\nB";
  const e = removeCard(doc, 2, 3);
  assert.equal(apply(doc, e), "a");
});

test("moveCard: 下へ動かす", () => {
  // "B" を "c" の後ろ（オフセット 6 = 末尾）へ
  const e = moveCard(DOC, 2, 3, 6);
  assert.ok(e);
  assert.equal(apply(DOC, e), "a\nc\nB\n");
});

test("moveCard: 上へ動かす", () => {
  // "c" を先頭（オフセット 0）へ
  const e = moveCard(DOC, 4, 5, 0);
  assert.ok(e);
  assert.equal(apply(DOC, e), "c\na\nB\n");
});

test("moveCard: 書き換えるのは動かす範囲だけ（外側は触らない）", () => {
  const doc = "x\na\nB\nc\ny\n";
  const from = doc.indexOf("B");
  const e = moveCard(doc, from, from + 1, doc.indexOf("y"));
  assert.ok(e);
  assert.equal(apply(doc, e), "x\na\nc\nB\ny\n");
  // 先頭の "x\n" と末尾の "y\n" は書き換え範囲の外にある
  assert.ok(e.from >= 2, `書き換えが先頭まで伸びている: ${e.from}`);
});

test("moveCard: 自分の中へ落としたら何もしない", () => {
  assert.equal(moveCard(DOC, 2, 3, 2), null);
  assert.equal(moveCard(DOC, 2, 3, 3), null);
});
```

- [ ] **Step 2: 失敗を確認する**

Run: `pnpm test 2>&1 | grep -E "Cannot find module|cardEdit"`
Expected: `Cannot find module '../src/map/cardEdit.ts'`

- [ ] **Step 3: 実装する**

`src/map/cardEdit.ts` を新規作成:

```typescript
// カードの削除・移動を「1 回の置き換え」に落とす計算。DOM も文書の意味も
// 知らない、ただのオフセット算術。
//
// 1 回に落とすのは Undo を 1 回にするため。2 回に分けると、戻すのに
// 2 回押すことになる。

/** core.replaceText にそのまま渡せる形 */
export interface TextEdit {
  from: number;
  to: number;
  insert: string;
}

/**
 * その範囲を行ごと消す。行末の改行も持っていく — 残すと空行が居座る。
 * 末尾の行なら、代わりに手前の改行を巻き取る。
 */
export function removeCard(text: string, from: number, to: number): TextEdit {
  let head = from;
  let tail = to;
  if (text[tail] === "\n") tail += 1;
  else if (head > 0 && text[head - 1] === "\n") head -= 1;
  return { from: head, to: tail, insert: "" };
}

/**
 * その範囲を `at`（行頭のオフセット）へ動かす。
 * 元と先を含む一続きの範囲を組み直して返すので、置き換えは 1 回で済む。
 * 動かす意味が無い（自分の中へ落とした）ときは null。
 */
export function moveCard(
  text: string,
  from: number,
  to: number,
  at: number,
): TextEdit | null {
  if (at >= from && at <= to) return null;
  const body = text.slice(from, to);
  const cut = removeCard(text, from, to);
  if (at < from) {
    // 上へ。[at, cut.to) を「本文 + 改行 + 元々そこにあったもの」に組み直す
    const between = text.slice(at, cut.from);
    return { from: at, to: cut.to, insert: `${body}\n${between}` };
  }
  // 下へ。[cut.from, at) を「間にあったもの + 本文 + 改行」に組み直す
  const between = text.slice(cut.to, at);
  return { from: cut.from, to: at, insert: `${between}${body}\n` };
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "removeCard|moveCard|^ℹ (tests|pass|fail)"`
Expected: 6 本すべて PASS、全体の fail 0

- [ ] **Step 5: コミット**

```bash
git add src/map/cardEdit.ts test/cardEdit.test.ts
git commit -m "feat: ✨ カードの削除・移動を 1 回の置き換えに落とす"
```

---

### Task 3: 選択の持ち主を main.ts へ寄せる

いま「ノードの選択」は `main.ts`、「画像の選択」は `mindmap.ts` の `pickedImage` と割れている。片方へ寄せ、不変条件（どちらか一方だけ）を作る。**このタスクでは見た目と操作を変えない** — 画像の選択・×・Undo が今までどおり動くことがゴール。

**Files:**
- Modify: `src/mindmap.ts`（`MapHost` に 2 つ足す、`pickedImage` を撤去して `host` 経由に、`isPicked` の判定を `CardRef` に）
- Modify: `src/main.ts`（`picked` を持つ、`setSelection` で相互排他、MD ペインのハイライト）

**Interfaces:**
- Consumes: Task 1 の `CardRow.from/to`
- Produces:
  - `src/map/cards.ts` から `export interface CardRef { node: number; index: number }`
  - `MapHost.pickedCard(): CardRef | null`
  - `MapHost.pickCard(ref: CardRef | null): void`
  - `main.ts` の `picked: CardRef | null`（`selection` と相互排他）

- [ ] **Step 1: CardRef 型を足す**

`src/map/cards.ts` の `CardRow` 型定義の直後に追記:

```typescript
/**
 * カードの指し方。文書上の位置ではなく「ノード id + そのノードの中で
 * 何枚目か」で指す — 位置だと別のノードを 1 行編集しただけでずれるが、
 * ノード id はコアが編集をまたいで維持するので外れない。
 */
export interface CardRef {
  node: number;
  index: number;
}
```

- [ ] **Step 2: MapHost に選択の出入り口を足す**

`src/mindmap.ts` の `MapHost` の `clearSelection(): void;` の直後に追記:

```typescript
  /** 選ばれているカード（無ければ null）。ノードの選択とは排他。 */
  pickedCard(): CardRef | null;
  /** カードを選ぶ / 外す（null で外す）。ノードの選択は落ちる。 */
  pickCard(ref: CardRef | null): void;
```

`src/mindmap.ts` の cards からの import に `type CardRef` を足す:

```typescript
import {
  type CardRef,
  type CardRow,
  CODE_LINE,
  CODE_PAD,
  IMG_H,
  IMG_ROW,
  LINK_ROW,
  rowH,
} from "./map/cards";
```

- [ ] **Step 3: mindmap.ts の pickedImage を撤去する**

`src/mindmap.ts` から次の 2 行（フィールド定義）を削除:

```typescript
  /** 選んだ画像カード（文書上の位置で覚える。id は編集で変わらない） */
  private pickedImage: { from: number; to: number } | null = null;
```

`isPicked` を `CardRef` で判定する形に差し替え。**引数が変わる**ので、呼び出し側（`contentSig` と描画）も合わせる:

```typescript
  /** そのカードが選ばれているか（ノード id と何枚目かで見る） */
  private isPicked(nodeId: number, index: number): boolean {
    const p = this.host.pickedCard();
    return p !== null && p.node === nodeId && p.index === index;
  }
```

`contentSig` の image 分岐を差し替え（`b.rows` の走査を index 付きにする）:

```typescript
    for (let i = 0; i < b.rows.length; i++) {
      const r = b.rows[i];
      if (r.kind === "link") s += `|L${r.link.title}${SEP}${r.link.url}`;
      else if (r.kind === "svg") s += `|S${r.markup}`;
      else if (r.kind === "code") s += `|C${r.lang}${SEP}${r.lines.join(SEP)}`;
      else s += `|I${r.path}${SEP}${this.host.imageUrl(r.path) ?? ""}`;
      if (this.isPicked(n.id, i)) s += `${SEP}picked`;
    }
```

描画側の `if (this.isPicked(r))` を `if (this.isPicked(n.id, rowIndex))` に変える。そのために `for (const r of b.rows)` を index 付きに変える:

```typescript
      let rowY = ROW_NORMAL.rowH;
      for (let rowIndex = 0; rowIndex < b.rows.length; rowIndex++) {
        const r = b.rows[rowIndex];
```

（ループ末尾の `}` はそのまま。`rowY += …` も変えない）

- [ ] **Step 4: data-image / data-kill を CardRef にする**

`spot` の組み立てを差し替え（画像の描画箇所）:

```typescript
          const spot = `${n.id},${rowIndex}`;
```

`refreshSelection` の中の画像選択落としを差し替え:

```typescript
    const selSig = [...sel].sort((a, b) => a - b).join(",");
    if (selSig !== this.lastSelSig) {
      this.lastSelSig = selSig;
      if (sel.size > 0 && this.host.pickedCard()) this.host.pickCard(null);
    }
```

クリック処理の 2 か所を差し替え:

```typescript
      const kill = MindMap.span(this.markAt(e.clientX, e.clientY, "data-kill"));
      if (kill) {
        this.host.deleteCard({ node: kill[0], index: kill[1] });
        return;
      }
      const pick = MindMap.span(this.markAt(e.clientX, e.clientY, "data-image"));
      if (pick) {
        const ref = { node: pick[0], index: pick[1] };
        const now = this.host.pickedCard();
        const same = now !== null && now.node === ref.node && now.index === ref.index;
        this.host.pickCard(same ? null : ref);
        return;
      }
```

`MapHost` に削除の出入り口を足す（`pickCard` の直後）:

```typescript
  /** そのカードを行ごと消す */
  deleteCard(ref: CardRef): void;
```

- [ ] **Step 5: main.ts に選択を持たせる**

`src/main.ts` の `let savedName` の近く（`selection` の宣言のそば）に追記:

```typescript
/**
 * 選ばれているカード。ノードの選択とは**どちらか一方だけ**が空でない。
 * 片方を選ぶともう片方は外れる — 選ばれているものが 2 種類あると、
 * Delete や Alt+↑↓ が何に効くのか決まらない。
 */
let picked: CardRef | null = null;
```

import に足す:

```typescript
import { type CardRef, cardRows } from "./map/cards";
import { removeCard } from "./map/cardEdit";
```

`setSelection` の先頭でカードの選択を落とす:

```typescript
function setSelection(ids: number[], anchor: number, reveal = true): void {
  if (ids.length > 0) picked = null; // 相互排他
  selection = new Set(ids);
  anchorId = anchor;
  syncSelectionViews(reveal);
}
```

`host` に 3 つ実装を足す（`replaceText` の直後）:

```typescript
  pickedCard: () => picked,
  pickCard(ref) {
    picked = ref;
    if (ref) {
      selection = new Set();
      anchorId = -1;
    }
    syncSelectionViews(false);
    map.render();
  },
  deleteCard(ref) {
    const row = cardOf(ref);
    if (!row) return;
    picked = null;
    const e = removeCard(core.getText(), row.from, row.to);
    applySnap(core.replaceText(e.from, e.to, e.insert, `x${++sessionN}`), "map");
  },
```

`cardOf` を `host` の前に足す:

```typescript
/** CardRef からいまのカードを引く。範囲外なら null（選択は落とす）。 */
function cardOf(ref: CardRef | null) {
  if (!ref) return null;
  const rows = cardRows(core.getText(), nodes, new Set<number>()).get(ref.node);
  return rows?.[ref.index] ?? null;
}
```

`syncSelectionViews` でカードの行も光らせる:

```typescript
function syncSelectionViews(reveal: boolean): void {
  map.refreshSelection();
  const card = cardOf(picked);
  editor.highlight(
    card
      ? [{ from: card.from, to: card.to }]
      : [...selection]
          .map((id) => byId.get(id))
          .filter((n): n is NodeInfo => !!n)
          .map((n) => ({ from: n.hs, to: n.subEnd })),
  );
  if (reveal && anchorId !== -1) {
    const n = byId.get(anchorId);
    if (n) editor.reveal(n.hs);
  }
}
```

`loadText` でカードの選択も落とす（`assets.clear()` の直後）:

```typescript
  picked = null;
```

- [ ] **Step 6: 型チェックとテストを通す**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: 型エラー無し、fail 0

- [ ] **Step 7: ブラウザで今までどおり動くことを確かめる**

`pnpm run dev` を起動し、ハードリロードしてから、ペインへ dispatch する経路で:

```javascript
// 画像を選ぶ → × が出る → 押すと消える → Undo で戻る
```

確認項目: 画像クリックで枠と × が出る / もう一度クリックで外れる / × で消える / `Mod+Z` で戻る / 別ノードを選ぶと選択が外れる / **MD ペインでその行が光る**（新規）

- [ ] **Step 8: コミット**

```bash
git add src/main.ts src/mindmap.ts src/map/cards.ts
git commit -m "refactor: ♻️ カードの選択を main.ts へ寄せる"
```

---

### Task 4: 4 種すべてを選べるようにする

画像だけだった選択の枠と × を、リンク / SVG / コードにも出す。

**Files:**
- Modify: `src/mindmap.ts`（描画: 各カードに `data-image` 相当の印を付け、選択中は枠と × を描く）
- Modify: `src/style.css`（枠を画像以外にも合う形に）

**Interfaces:**
- Consumes: Task 3 の `pickedCard()` / `pickCard()` / `deleteCard()`
- Produces: 4 種すべてのカードが `data-card="ノードid,何枚目"` を持ち、選択中は `.card-picked` の枠と `.img-kill` の × が出る

- [ ] **Step 1: 印の名前を data-card に統一する**

`src/mindmap.ts` の描画ループで、カードの種類ごとの分岐に入る前に印を用意する（`const r = b.rows[rowIndex];` の直後）:

```typescript
        const spot = `${n.id},${rowIndex}`;
```

画像の分岐にあった `const spot = …` の行を削除（上へ移したため）。`data-image` は `data-card` に改名する（`<image>` / `rect.img-ph` / `text.img-name` の 3 か所）。

リンクの `rect`（`class: "link-row"`）と、SVG の `<image>`、コードの `rect.code-bg` / `text.code-line` にも `"data-card": spot` を足す。

- [ ] **Step 2: 選択の枠と × を種類によらず描く**

画像の分岐の中にある `if (this.isPicked(...))` のブロックを、**分岐の外**（`rowY += …` の直前、すべての種類が通る位置）へ移す。矩形の寸法はその行の高さから取る:

```typescript
        if (this.isPicked(n.id, rowIndex)) {
          const top = rowY + (r.kind === "code" ? 5 : 6);
          const h = rowH(r) - (r.kind === "code" ? 10 : 12);
          const w = b.w - ROW_NORMAL.padX * 2;
          g.append(
            svgEl("rect", {
              class: "card-picked",
              x: String(ROW_NORMAL.padX),
              y: String(top),
              width: String(w),
              height: String(h),
              rx: "6",
            }),
          );
          const cx = ROW_NORMAL.padX + w;
          const cy = top;
          const arm = 2.5;
          const kill = svgEl("g", { class: "img-kill", "data-kill": spot });
          kill.append(svgEl("circle", { cx: String(cx), cy: String(cy), r: "7" }));
          for (const [dx, dy] of [
            [1, 1],
            [1, -1],
          ]) {
            kill.append(
              svgEl("line", {
                x1: String(cx - arm * dx),
                y1: String(cy - arm * dy),
                x2: String(cx + arm * dx),
                y2: String(cy + arm * dy),
              }),
            );
          }
          g.append(kill);
        }
```

- [ ] **Step 3: クリック判定を data-card にする**

`src/mindmap.ts` のクリック処理で `"data-image"` を `"data-card"` に変える。

- [ ] **Step 4: CSS の名前を合わせる**

`src/style.css` の `.node rect.img-picked` を差し替え:

```css
/* 選んだカードの枠と、その右上の × */
.node rect.card-picked {
  fill: none;
  stroke: var(--accent);
  stroke-width: 2;
  pointer-events: none;
}
```

リンク行とコードもクリックで拾えるようにする（`pointer-events: none` が付いていれば外す）。`.node rect.link-row` と `.node rect.code-bg` に `cursor: pointer;` を足す。

- [ ] **Step 5: 型チェックとテストを通す**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: fail 0

- [ ] **Step 6: ブラウザで 4 種すべて選べることを確かめる**

4 種を 1 ノードに並べた文書を貼り、**ペインへ dispatch する経路**で各カードをクリック → 枠と × が出ること、× で消えること、`Mod+Z` で戻ることを確認する。

- [ ] **Step 7: コミット**

```bash
git add src/mindmap.ts src/style.css
git commit -m "feat: ✨ カードを 4 種とも選べるようにする"
```

---

### Task 5: その場編集を 4 種へ広げる

コード用に作った入力欄を、選ばれているカードの元テキストに対して使い回す。

**Files:**
- Modify: `src/mindmap.ts`（`beginCodeEdit` を `beginCardEdit(ref)` に一般化、ダブルクリックと `Mod+Enter` の配線）

**Interfaces:**
- Consumes: Task 3 の `pickedCard()`、Task 1 の `CardRow.from/to`
- Produces: `MindMap` の `private beginCardEdit(ref: CardRef): void`。ダブルクリックと `Mod+Enter` の両方から呼ぶ。

- [ ] **Step 1: codeRect を種類によらない cardRect にする**

`src/mindmap.ts` の `codeRect(from, to)` を差し替え:

```typescript
  /**
   * カードの置かれている場所（world 座標）。描画の積み方をそのまま
   * なぞって数える — 描画時に控えておく手もあるが、中身が変わっていない
   * ノードは作り直しを飛ばすので、控えは歯抜けになる。
   */
  private cardRect(
    ref: CardRef,
  ): { x: number; y: number; w: number; h: number } | null {
    const b = this.boxes.get(ref.node);
    if (!b || b.n.hidden) return null;
    let rowY = ROW_NORMAL.rowH;
    for (let i = 0; i < b.rows.length; i++) {
      if (i === ref.index) {
        const r = b.rows[i];
        const pad = r.kind === "code" ? 5 : 6;
        return {
          x: b.x + ROW_NORMAL.padX,
          y: b.y + rowY + pad,
          w: b.w - ROW_NORMAL.padX * 2,
          h: rowH(r) - pad * 2,
        };
      }
      rowY += rowH(b.rows[i]);
    }
    return null;
  }
```

- [ ] **Step 2: beginCodeEdit を beginCardEdit にする**

```typescript
  /** カードをその場で開く。閉じるのは Esc / Mod+Enter / 他所クリック。 */
  private beginCardEdit(ref: CardRef): void {
    const b = this.boxes.get(ref.node);
    const row = b?.rows[ref.index];
    const rect = this.cardRect(ref);
    if (!row || !rect) return;
    if (this.isEditing()) this.host.commitEdit();
    this.codeEdit = { from: row.from, to: row.to };
    this.codeEditor.value = this.host.docText().slice(row.from, row.to);
    this.codeBox.style.display = "block";
    this.paintCodeInk();
    this.positionCodeEditor();
    this.codeEditor.focus();
    this.codeEditor.setSelectionRange(
      this.codeEditor.value.length,
      this.codeEditor.value.length,
    );
  }
```

`positionCodeEditor` の中の `this.codeRect(this.codeEdit.from, this.codeEdit.to)` は、開いているカードの `CardRef` を覚えて `cardRect(ref)` を引く形にする。`codeEdit` の型を差し替え:

```typescript
  /** その場で直しているカード（位置は毎回引き直す） */
  private codeEdit: { ref: CardRef; from: number; to: number } | null = null;
```

`beginCardEdit` の代入を `this.codeEdit = { ref, from: row.from, to: row.to };` に、`positionCodeEditor` の引き直しを `this.cardRect(this.codeEdit.ref)` に変える。

- [ ] **Step 3: ダブルクリックと Mod+Enter を配線する**

ダブルクリックの `data-code` 判定を `data-card` に変え、`beginCardEdit` を呼ぶ:

```typescript
      const card = MindMap.span(this.markAt(e.clientX, e.clientY, "data-card"));
      if (card) {
        e.preventDefault();
        this.beginCardEdit({ node: card[0], index: card[1] });
        return;
      }
```

`onKeydown` の `Mod+Enter` 分岐の先頭に、カードが選ばれているときの枝を足す:

```typescript
    if (key === "Enter" && mod) {
      const p = this.host.pickedCard();
      if (p) {
        this.beginCardEdit(p);
        e.preventDefault();
        return;
      }
      if (nodes.length === 0) this.host.addRoot();
      else if (anchor !== -1 && sel.size <= 1) this.host.editRequested(anchor);
      e.preventDefault();
      return;
    }
```

- [ ] **Step 4: 型チェックとテストを通す**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: fail 0

- [ ] **Step 5: ブラウザで 4 種とも編集できることを確かめる**

ペイン経由のダブルクリックで、リンク `[題](URL)` / 画像 `![](パス)` / SVG / コードそれぞれの**元テキスト**が入力欄に出ること、直して `Mod+Enter` で文書に返ること、コードだけ囲いが守られることを確認する。

- [ ] **Step 6: コミット**

```bash
git add src/mindmap.ts
git commit -m "feat: ✨ カードを 4 種ともその場で編集できるようにする"
```

---

### Task 6: キー操作（Delete / ↑↓ / ← / Alt+↑↓）

**Files:**
- Modify: `src/mindmap.ts`（`onKeydown` にカード選択中の枝）
- Modify: `src/main.ts`（`moveCardTo` の実装）

**Interfaces:**
- Consumes: Task 2 の `moveCard`、Task 3 の `pickedCard()` / `pickCard()` / `deleteCard()`
- Produces: `MapHost.reorderCard(ref: CardRef, dir: -1 | 1): void`

- [ ] **Step 1: MapHost に並べ替えを足す**

`src/mindmap.ts` の `deleteCard` の直後:

```typescript
  /** 同じノードの中で 1 つ上/下へ。端では何もしない。 */
  reorderCard(ref: CardRef, dir: -1 | 1): void;
```

- [ ] **Step 2: main.ts に実装する**

`host` の `deleteCard` の直後:

```typescript
  reorderCard(ref, dir) {
    const rows = cardRows(core.getText(), nodes, new Set<number>()).get(ref.node);
    const row = rows?.[ref.index];
    const next = rows?.[ref.index + dir];
    if (!rows || !row || !next) return; // 端では何もしない
    // 下へ動かすときは相手の後ろ、上へ動かすときは相手の頭へ入れる
    const at = dir === 1 ? next.to + 1 : next.from;
    const e = moveCard(core.getText(), row.from, row.to, at);
    if (!e) return;
    picked = { node: ref.node, index: ref.index + dir };
    applySnap(core.replaceText(e.from, e.to, e.insert, `m${++sessionN}`), "map");
  },
```

import に `moveCard` を足す:

```typescript
import { moveCard, removeCard } from "./map/cardEdit";
```

- [ ] **Step 3: onKeydown にカードの枝を足す**

`onKeydown` の `Shift+H` 分岐の直前（CapsLock 正規化の直後）に挿入:

```typescript
    // カードを選んでいる間は、キーはカードに効く。ノードの選択とは排他なので
    // 「どちらに効くのか」で迷わない
    const card = this.host.pickedCard();
    if (card && !e.altKey) {
      if (key === "Delete" || key === "Backspace") {
        this.host.deleteCard(card);
        e.preventDefault();
        return;
      }
      if (key === "Escape") {
        this.host.pickCard(null);
        e.preventDefault();
        return;
      }
      if (key === "ArrowUp" || key === "ArrowDown") {
        const rows = this.boxes.get(card.node)?.rows ?? [];
        const next = card.index + (key === "ArrowUp" ? -1 : 1);
        if (next >= 0 && next < rows.length) {
          this.host.pickCard({ node: card.node, index: next });
        }
        e.preventDefault();
        return;
      }
      if (key === "ArrowLeft") {
        this.host.setSelection([card.node], card.node);
        e.preventDefault();
        return;
      }
    }
    if (card && e.altKey && (key === "ArrowUp" || key === "ArrowDown")) {
      this.host.reorderCard(card, key === "ArrowUp" ? -1 : 1);
      e.preventDefault();
      return;
    }
```

- [ ] **Step 4: 型チェックとテストを通す**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: fail 0

- [ ] **Step 5: ブラウザで確かめる**

4 種を並べたノードで: `↓`/`↑` でカード間を移動 / `←` でノードへ戻る / `Alt+↓` で順番が入れ替わり**選択が付いてくる** / 端では動かない / `Delete` で消える / `Mod+Z` で戻る。

- [ ] **Step 6: コミット**

```bash
git add src/mindmap.ts src/main.ts
git commit -m "feat: ✨ カードをキーで動かせるようにする"
```

---

### Task 7: ドラッグで移動する

選んでいるカードだけがドラッグで動く。落とし先は「どのノードの、何枚目の位置か」。

**Files:**
- Modify: `src/mindmap.ts`（pointerdown / pointermove / pointerup にカードの枝、落とし先の線）
- Modify: `src/main.ts`（`moveCardTo` の実装）

**Interfaces:**
- Consumes: Task 2 の `moveCard`、Task 6 の配線
- Produces: `MapHost.moveCardTo(ref: CardRef, node: number, index: number): void`

- [ ] **Step 1: MapHost に移動を足す**

```typescript
  /** そのカードを別のノードの index の位置へ動かす */
  moveCardTo(ref: CardRef, node: number, index: number): void;
```

- [ ] **Step 2: main.ts に実装する**

```typescript
  moveCardTo(ref, node, index) {
    const text = core.getText();
    const all = cardRows(text, nodes, new Set<number>());
    const row = all.get(ref.node)?.[ref.index];
    if (!row) return;
    const target = all.get(node) ?? [];
    // 落とし先の行頭。末尾なら、そのノードの本文の終わりへ
    const dst = target[index];
    const at = dst ? dst.from : contentEnd(node);
    const e = moveCard(text, row.from, row.to, at);
    if (!e) return;
    picked = null;
    applySnap(core.replaceText(e.from, e.to, e.insert, `d${++sessionN}`), "map");
  },
```

`contentEnd` を `cardOf` の隣に足す:

```typescript
/** そのノードの本文の終わり（末尾へ落としたときの挿入位置） */
function contentEnd(id: number): number {
  const n = byId.get(id);
  if (!n) return core.getText().length;
  const i = nodes.indexOf(n);
  return i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd
    ? nodes[i + 1].hs
    : n.subEnd;
}
```

- [ ] **Step 3: ドラッグの開始をカードに向ける**

`src/mindmap.ts` の pointerdown、`const id = this.nodeAt(...)` の直前に挿入:

```typescript
      // 選んでいるカードの上からのドラッグはカードを動かす。選んでいない
      // カードの上からは、従来どおりノードが動く（既存の D&D を奪わない）
      const onCard = MindMap.span(this.markAt(e.clientX, e.clientY, "data-card"));
      const held = this.host.pickedCard();
      if (
        onCard &&
        held &&
        held.node === onCard[0] &&
        held.index === onCard[1]
      ) {
        this.cardDrag = { ref: held, px: e.clientX, py: e.clientY };
        pane.setPointerCapture(e.pointerId);
        return;
      }
```

フィールドを足す:

```typescript
  /** カードのドラッグ。掴んだだけの間は drop を出さない */
  private cardDrag: { ref: CardRef; px: number; py: number } | null = null;
  private cardDrop: { node: number; index: number } | null = null;
```

- [ ] **Step 4: 落とし先を出す**

pointermove の先頭に挿入:

```typescript
      if (this.cardDrag) {
        this.cardDrop = this.cardSlotAt(e.clientX, e.clientY);
        this.showCardDrop();
        return;
      }
```

`cardSlotAt` と `showCardDrop` を `cardRect` の隣に足す:

```typescript
  /** その座標が、どのノードの何枚目と何枚目の間か */
  private cardSlotAt(
    clientX: number,
    clientY: number,
  ): { node: number; index: number } | null {
    const w = this.toWorld(clientX, clientY);
    for (const [id, b] of this.boxes) {
      if (b.n.hidden) continue;
      if (w.x < b.x || w.x > b.x + b.w || w.y < b.y || w.y > b.y + b.h) continue;
      let rowY = ROW_NORMAL.rowH;
      for (let i = 0; i < b.rows.length; i++) {
        const h = rowH(b.rows[i]);
        if (w.y < b.y + rowY + h / 2) return { node: id, index: i };
        rowY += h;
      }
      return { node: id, index: b.rows.length };
    }
    return null;
  }

  /** 落とし先を線で示す */
  private showCardDrop(): void {
    const d = this.cardDrop;
    if (!d) {
      this.dropLine.setAttribute("visibility", "hidden");
      return;
    }
    const b = this.boxes.get(d.node);
    if (!b) return;
    let rowY = ROW_NORMAL.rowH;
    for (let i = 0; i < d.index; i++) rowY += rowH(b.rows[i]);
    const y = b.y + rowY;
    this.dropLine.setAttribute("x1", String(b.x + ROW_NORMAL.padX));
    this.dropLine.setAttribute("y1", String(y));
    this.dropLine.setAttribute("x2", String(b.x + b.w - ROW_NORMAL.padX));
    this.dropLine.setAttribute("y2", String(y));
    this.dropLine.setAttribute("visibility", "visible");
  }
```

座標変換は既存の `toWorld(clientX, clientY)`（`src/mindmap.ts:243`）をそのまま使う。

- [ ] **Step 5: 離したら動かす**

pointerup の先頭に挿入:

```typescript
      if (this.cardDrag) {
        const from = this.cardDrag.ref;
        const to = this.cardDrop;
        this.cardDrag = null;
        this.cardDrop = null;
        this.dropLine.setAttribute("visibility", "hidden");
        if (to) this.host.moveCardTo(from, to.node, to.index);
        return;
      }
```

- [ ] **Step 6: 型チェックとテストを通す**

Run: `pnpm run check && pnpm test 2>&1 | grep -E "^ℹ (tests|pass|fail)"`
Expected: fail 0

- [ ] **Step 7: ブラウザで確かめる**

選んだカードを同じノードの別位置へ / 別ノードへ落とす。**選んでいないカードの上からはノードが動く**ことも必ず確認する（既存の D&D を壊していない証拠）。`Mod+Z` で 1 回で戻ること。

- [ ] **Step 8: コミット**

```bash
git add src/mindmap.ts src/main.ts
git commit -m "feat: ✨ カードをドラッグで動かせるようにする"
```

---

### Task 8: README を実態に合わせる

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1〜7 の完成した振る舞い
- Produces: なし

- [ ] **Step 1: コンテンツカードの節を書き換える**

「クリックで選択」が画像限定になっている記述を 4 種へ広げ、キー表に次を足す:

```markdown
| カードをクリック | 選ぶ / もう一度で外す |
| カードをダブルクリック・`Mod+Enter` | その場で編集 |
| カード選択中の `↑↓` / `←` | 隣のカードへ / 持ち主のノードへ |
| カード選択中の `Alt+↑↓` | 並べ替え（端で止まる） |
| カード選択中の `Delete` | 削除 |
| 選んだカードをドラッグ | 別ノードへ移動 / ノード内で順番変更 |
```

選択の不変条件（ノードとカードはどちらか一方）も 1 文で書く。

- [ ] **Step 2: 構成図に新しいファイルを足す**

`map/` の説明に `cardEdit(カードの削除・移動の計算)` を足す。

- [ ] **Step 3: コミット**

```bash
git add README.md
git commit -m "docs: 📝 カードの操作を README に反映する"
```

---

## 自己レビュー

**仕様の網羅:**
- 「カードは `{node, index}` で指す」→ Task 3（`CardRef`）
- 「4 種すべてに `from`/`to`」→ Task 1
- 「選択は main.ts が一括、どちらか一方」→ Task 3
- 「クリック選択・× を 4 種へ」→ Task 4
- 「その場編集を 4 種へ」→ Task 5
- 「`Delete` / `↑↓` / `←` / `Alt+↑↓`」→ Task 6
- 「D&D、掴めるのは選んでいるカードだけ」→ Task 7
- 「オフセット計算を純粋関数にして単体テスト」→ Task 2
- 「コアは変えない」→ 全タスクで `core.replaceText` のみ使用

**型の一貫性:**
- `CardRef { node, index }` は Task 3 で定義し、Task 4〜7 で同じ名前・同じ形で使う
- `TextEdit { from, to, insert }` は Task 2 で定義し、Task 3・6・7 で `core.replaceText(e.from, e.to, e.insert, tag)` へ渡す
- `removeCard` / `moveCard` の引数順は `(text, from, to[, at])` で統一

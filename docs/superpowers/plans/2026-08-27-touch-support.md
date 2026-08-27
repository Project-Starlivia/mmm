# タッチデバイス対応 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 指だけの機械でマップを動かし・ノードを足し・ペインを行き来できるようにする。

**Architecture:** モードは持たず、`e.pointerType` でその場の作法が決まる。算術は
`map/view.ts`（DOM を触らない層）へ、指の台帳は `map/gesture.ts` へ切り出し、
`mindmap.ts` の既存 5 状態は増やさない。唯一の設定は「選択ノードの上下左右 `+` を
出すか」で、`localStorage` に持ち、無ければ機械に従う。

**Tech Stack:** TypeScript（バンドラは Vite）、DOM/Pointer Events、`node:test`。
MoonBit コアには**一切触らない**。

**Spec:** `docs/superpowers/specs/2026-08-27-touch-support-design.md`

## Global Constraints

- **`as T` と `!`（非 null 表明）を書かない。** `test/assertions.test.ts` が全 `src`/`test` を
  走査して落とす。`instanceof` / 絞り込み / 既定値で**確かめる**。
- **画面に出る文字は英語。** コードのコメントと docs は日本語。
- **数字を 2 か所に置かない。** 定数は 1 か所で名前を持つ。
- コミットは Semantic Commit: `<Type>: <Emoji> <Title>`（日本語のタイトル）。
- 各タスクの最後に `pnpm run check` と `pnpm test` を通してからコミットする。
  **壊れた状態のコミットを残さない。**
- `pnpm test` は `node --test "test/*.test.ts"`。**DOM は無い** — 試験できるのは
  純粋な層だけ。DOM を持つ変更の検証はブラウザで行う（各タスクに手順を書いた）。
- 開発サーバ: `pnpm run dev`（http://localhost:13131）。`core/` を触らないので
  `pnpm run core` は初回だけでよい。

---

## ファイルの割り付け

| ファイル | 責任 | タスク |
|---|---|---|
| `src/map/view.ts` | world ⇄ 画面の算術。`zoomTo` / `pinch` を足す | 1 |
| `test/view.test.ts` | 上記の値の固定 | 1 |
| `src/mindmap.ts` | ホバー `+` の削除、パンの 3 つ目の入り口、gesture と addButtons の配線 | 2, 3, 5, 6, 7 |
| `src/map/addButtons.ts` | 選択ノードの上下左右 `+`。置き場所の算術と、その 1 個の印 | 3 |
| `test/addButtons.test.ts` | 置き場所の算術 | 3 |
| `src/app/persist.ts` | `LS_ADDS` の宣言 | 4 |
| `src/main.ts` | `⋯` の 1 行、既定の判定と保存、Files の無効化 | 4, 10 |
| `src/map/gesture.ts` | 指の台帳（DOM を知らない） | 6 |
| `test/gesture.test.ts` | 台帳の振る舞い | 6 |
| `src/app/panes.ts` | 分割線の居場所を幅の関数に。`.narrow` の付け外し | 8 |
| `test/panes.test.ts` | 居場所と射影 | 8 |
| `src/app/io.ts` / `src/app/assets.ts` | File System Access API の存在を確かめる | 10 |
| `src/style.css` | `touch-action` / `.add-btn` / `.narrow` / `hover: none` / `pointer: coarse` | 3, 5, 8, 9 |
| `README.md` | 指の作法と、狭いときの居場所 2 つ | 11 |

---

## Task 1: `view.ts` に `zoomTo` と `pinch` を足す

**Files:**
- Modify: `src/map/view.ts`
- Test: `test/view.test.ts`

**Interfaces:**
- Consumes: 既存の `View` / `panBy` / `MIN_ZOOM` / `MAX_ZOOM`、`./geometry.ts` の `Pt`
- Produces:
  - `export interface Span { a: Pt; b: Pt }` — 2 本指の位置（ペインの左上から測った画面 px）
  - `export function zoomTo(view: View, x: number, y: number, k: number): View`
  - `export function pinch(view: View, from: Span, to: Span): View`
  - `zoomAt` はシグネチャを変えずに残る（`zoomTo` の上に組み直すだけ）

- [ ] **Step 1: 失敗する試験を書く**

`test/view.test.ts` の import に `pinch`, `zoomTo`, `type Span` を足し、ファイル末尾に足す:

```ts
const span = (ax: number, ay: number, bx: number, by: number): Span => ({
  a: { x: ax, y: ay },
  b: { x: bx, y: by },
});

test("zoomTo は、その点の下の world を動かさない", () => {
  for (const start of [{ k: 1, tx: 60, ty: 60 }, { k: 0.3, tx: -200, ty: 90 }]) {
    for (const k of [0.2, 0.5, 1, 2.5]) {
      const before = toWorld(start, 512, 331);
      const after = toWorld(zoomTo(start, 512, 331, k), 512, 331);
      assert.ok(Math.abs(before.x - after.x) < 1e-9);
      assert.ok(Math.abs(before.y - after.y) < 1e-9);
    }
  }
});

test("zoomTo も上下の限界で止まる", () => {
  assert.equal(zoomTo(V, 0, 0, 99).k, MAX_ZOOM);
  assert.equal(zoomTo(V, 0, 0, 0.001).k, MIN_ZOOM);
});

test("2 本指を離すと拡大、近づけると縮小", () => {
  const from = span(100, 100, 200, 100);
  assert.ok(pinch(V, from, span(50, 100, 250, 100)).k > V.k);
  assert.ok(pinch(V, from, span(140, 100, 160, 100)).k < V.k);
});

test("pinch は、2 点の中点の下の world を中点へ運ぶ", () => {
  // 拡大しながら指をずらしても、掴んでいた場所が指の下に留まる
  const from = span(100, 200, 300, 200); // 中点 (200, 200)
  const to = span(140, 260, 460, 260); // 中点 (300, 260)、距離は 1.6 倍
  const w = toWorld(V, 200, 200);
  const after = pinch(V, from, to);
  assert.ok(Math.abs(w.x * after.k + after.tx - 300) < 1e-9);
  assert.ok(Math.abs(w.y * after.k + after.ty - 260) < 1e-9);
});

test("距離が変わらない 2 本指は、ただのパン", () => {
  const after = pinch(V, span(0, 0, 100, 0), span(30, -20, 130, -20));
  assert.deepEqual(after, { k: 1, tx: 90, ty: 40 });
});

test("2 本の指が重なっても倍率は壊れない", () => {
  // 距離 0 で割ると Infinity/NaN が k に流れ込み、以降すべての描画が消える
  const after = pinch(V, span(50, 50, 50, 50), span(60, 60, 80, 80));
  assert.equal(after.k, V.k);
});
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `pnpm test`
Expected: FAIL — `zoomTo`/`pinch`/`Span` が `../src/map/view.ts` から出ていない旨の型/実行時エラー

- [ ] **Step 3: 最小の実装を書く**

`src/map/view.ts` の import に `Pt` を足す:

```ts
import { type Pt, type Rect, unionRect } from "./geometry.ts";
```

`zoomAt` を `zoomTo` の上に組み直し（既存の `zoomAt` 本体を差し替える）:

```ts
/** 倍率だけを限界に収める */
const clampZoom = (k: number): number =>
  Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, k));

/**
 * その点を基点に、倍率を `k` にする。**その点の下にある world の位置が
 * 動かない**ように平行移動を合わせる — 合わせないと、拡大するたびに
 * 見ていた場所が画面の外へ逃げる。
 */
export function zoomTo(view: View, x: number, y: number, k: number): View {
  const next = clampZoom(k);
  const ratio = next / view.k;
  return {
    k: next,
    tx: x - (x - view.tx) * ratio,
    ty: y - (y - view.ty) * ratio,
  };
}

/** ホイールの目盛りを倍率に読み替えて `zoomTo` に渡すだけ */
export const zoomAt = (view: View, x: number, y: number, deltaY: number): View =>
  zoomTo(view, x, y, view.k * Math.exp(-deltaY * ZOOM_RATE));
```

ファイル末尾に足す:

```ts
/** 2 本指の位置（ペインの左上から測った画面 px） */
export interface Span {
  a: Pt;
  b: Pt;
}

const dist = (p: Pt, q: Pt): number => Math.hypot(q.x - p.x, q.y - p.y);
const mid = (p: Pt, q: Pt): Pt => ({ x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 });

/**
 * 2 本指の前後の位置から、見え方を 1 つ出す。
 *
 * **拡大とパンを別々の話にしない** — 指は同時に離れながら動くので、
 * 「中点を基点に倍率を変える」→「中点のずれだけ平行移動する」の 2 つを
 * 順に当てれば、掴んでいた場所は指の下に留まる。
 *
 * 2 本が重なると距離が 0 になる。割ると `Infinity` が倍率へ流れ込み、以降
 * すべての描画が消えるので、そのときは倍率を据え置く。
 */
export function pinch(view: View, from: Span, to: Span): View {
  const d0 = dist(from.a, from.b);
  const m0 = mid(from.a, from.b);
  const m1 = mid(to.a, to.b);
  const k = d0 > 0 ? view.k * (dist(to.a, to.b) / d0) : view.k;
  return panBy(zoomTo(view, m0.x, m0.y, k), m1.x - m0.x, m1.y - m0.y);
}
```

- [ ] **Step 4: 通ることを確かめる**

Run: `pnpm test` → PASS（既存の `zoomAt` の 3 本も通り続けること）
Run: `pnpm run check` → エラー無し

- [ ] **Step 5: コミット**

```bash
git add src/map/view.ts test/view.test.ts
git commit -m "feat: ✨ 2 本指のための算術を view に足す"
```

---

## Task 2: ホバーの `+` を捨てる

**Files:**
- Modify: `src/mindmap.ts`
- Modify: `src/style.css`

**Interfaces:**
- Consumes: なし
- Produces: `addItems(id)` は**残す**（右クリックメニューの `Add ▸` が使っている）

- [ ] **Step 1: `mindmap.ts` から消す**

以下をすべて削除する:

- フィールド `private plusBtn: SVGGElement;`
- フィールド `private hoverId = -1;`
- コンストラクタの `const makePlus = (): SVGGElement => { ... };` と `this.plusBtn = makePlus();`
- `this.viewport.append(...)` の引数から `this.plusBtn`
- メソッド `updatePlus()` とその見出しコメント `// ---------- hover plus button ----------`
- `updatePlus()` の呼び出しすべて。`grep -n "updatePlus" src/mindmap.ts` で全部拾ってから消す
- `bindClick()` の `pane.addEventListener("pointerover", ...)` の塊
- `this.plusBtn.addEventListener("pointerdown", ...)` と `this.plusBtn.addEventListener("click", ...)` の 2 つ
- メソッド `private overPlus(e: Event): boolean { ... }`

`rightOf` が `mindmap.ts` の他所で使われていなければ import からも外す
（`grep -n "rightOf" src/mindmap.ts` で確かめる）。

- [ ] **Step 2: `style.css` から `.plus-btn` の塊を消す**

```css
.plus-btn {
  cursor: pointer;

  & circle { fill: var(--accent); }
  & line { stroke: #fff; stroke-width: 2; stroke-linecap: round; }
}
```

- [ ] **Step 3: 型と試験を通す**

Run: `pnpm run check` → エラー無し（使われなくなった import が残っていれば落ちる）
Run: `pnpm test` → PASS

- [ ] **Step 4: ブラウザで確かめる**

`pnpm run dev` → ノードにマウスを乗せる。
Expected: **`+` が出ない**。ノードの選択・ドラッグ・右クリックメニューの `Add ▸` は今までどおり動く。

- [ ] **Step 5: コミット**

```bash
git add src/mindmap.ts src/style.css
git commit -m "refactor: 🔥 ホバーで出る + ボタンを捨てる"
```

---

## Task 3: 選択ノードの上下左右 `+`

**Files:**
- Create: `src/map/addButtons.ts`
- Create: `test/addButtons.test.ts`
- Modify: `src/mindmap.ts`
- Modify: `src/style.css`

**Interfaces:**
- Consumes: `./geometry.ts` の `Rect`、`MapHost.addChild/addSibling/addSiblingBefore/addParent`
- Produces:
  - `export type AddDir = "child" | "below" | "above" | "parent"`
  - `export interface AddSpot { dir: AddDir; x: number; y: number }`
  - `export function addSpots(b: Rect, gap: number, canParent: boolean): AddSpot[]`
  - `export class AddButtons { readonly el: SVGGElement; show(b: Rect, k: number, canParent: boolean): void; hide(): void }`
  - `MindMap.setAddButtons(on: boolean): void`（Task 4 が呼ぶ）

- [ ] **Step 1: 置き場所の算術に、失敗する試験を書く**

`test/addButtons.test.ts` を作る:

```ts
// 選択ノードの周りの `+` の置き場所。向きと木の意味が食い違うと、
// 「右を押したのに上に増えた」になる。目では気づきにくいので値で固定する。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type AddDir, addSpots } from "../src/map/addButtons.ts";

const BOX = { x: 100, y: 200, w: 60, h: 20 };

const dirs = (canParent: boolean): AddDir[] =>
  addSpots(BOX, 10, canParent).map((s) => s.dir);

const at = (dir: AddDir): { x: number; y: number } => {
  const found = addSpots(BOX, 10, true).find((s) => s.dir === dir);
  if (!found) throw new Error(`${dir} が無い`);
  return { x: found.x, y: found.y };
};

test("マップが伸びる向きと木の意味が一致する", () => {
  // 右が子、左が親。上下が兄弟 — 覚えるものを「向き」1 つで済ませる
  assert.deepEqual(at("child"), { x: 170, y: 210 });
  assert.deepEqual(at("parent"), { x: 90, y: 210 });
  assert.deepEqual(at("above"), { x: 130, y: 190 });
  assert.deepEqual(at("below"), { x: 130, y: 230 });
});

test("ルートには親を足せないので、その置き場所も出さない", () => {
  // core の cmd_add_parent は深さ 1 を弾く。押せるのに何も起きない
  // ボタンを置かない
  assert.equal(dirs(true).length, 4);
  assert.deepEqual(dirs(false).sort(), ["above", "below", "child"]);
});

test("隙間は箱の外側へ開く", () => {
  const wide = addSpots(BOX, 40, true);
  const near = addSpots(BOX, 10, true);
  const x = (list: AddSpotList, dir: AddDir): number => {
    const found = list.find((s) => s.dir === dir);
    if (!found) throw new Error(`${dir} が無い`);
    return found.x;
  };
  assert.ok(x(wide, "child") > x(near, "child"));
  assert.ok(x(wide, "parent") < x(near, "parent"));
});
```

`AddSpotList` は試験の中だけの別名。import 行の下に置く:

```ts
type AddSpotList = ReturnType<typeof addSpots>;
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `pnpm test`
Expected: FAIL — `../src/map/addButtons.ts` が無い

- [ ] **Step 3: `src/map/addButtons.ts` を書く**

```ts
// 選んでいるノードの上下左右に出る `+`。
//
// **選択の anchor は常に高々 1 つ**なので、置き場所も 1 つでよい
// （map/pick.ts の「選んだカードの枠と ×」と同じ立場）。
//
// **向きと木の意味を一致させる。** マップは左から右へ伸びるので、右が子・
// 左が親・上下が兄弟。4 つ揃って初めて、覚えるものが「向き」1 つで済む。
//
// 以前はホバーで 1 つだけ出て、押すと 4 項目のメニューが開いていた。押しに
// 行くとホバーが外れて押せず、そもそも指にホバーは無い。

import type { Rect } from "./geometry.ts";
import { svgEl } from "./svg.ts";

export type AddDir = "child" | "below" | "above" | "parent";

/** world 座標の置き場所（ボタンの中心） */
export interface AddSpot {
  dir: AddDir;
  x: number;
  y: number;
}

/**
 * その箱の周りの置き場所。`gap` は箱の縁から中心までの world 距離
 * （**画面 px を `k` で割ったものを渡す** — ボタンの大きさは倍率に
 * 引きずられないため）。`canParent` が false なら親の口を出さない。
 */
export function addSpots(b: Rect, gap: number, canParent: boolean): AddSpot[] {
  const cx = b.x + b.w / 2;
  const cy = b.y + b.h / 2;
  const spots: AddSpot[] = [
    { dir: "child", x: b.x + b.w + gap, y: cy },
    { dir: "above", x: cx, y: b.y - gap },
    { dir: "below", x: cx, y: b.y + b.h + gap },
  ];
  if (canParent) spots.push({ dir: "parent", x: b.x - gap, y: cy });
  return spots;
}

/** 縁から中心までの画面距離 */
const GAP = 26;
/** 指の的。見えている丸（R）より広く取る */
const HIT = 22;
/** 見えている丸の半径。的いっぱいの丸を 4 つ並べると、ノードより目立つ */
const R = 9;
/** 十字の腕の長さ */
const ARM = 4;

export class AddButtons {
  /** viewport（world 座標）に入れる。ノード層より上に置くこと */
  readonly el = svgEl("g", { id: "add-buttons", visibility: "hidden" });

  /**
   * `b` の周りに置く。`k` はいまの倍率で、**打ち消して**画面上の大きさを
   * 一定に保つ（`MIN_ZOOM` まで引いても押せる粒でなくならない）。
   */
  show(b: Rect, k: number, canParent: boolean): void {
    this.el.setAttribute("visibility", "visible");
    this.el.replaceChildren();
    for (const spot of addSpots(b, GAP / k, canParent)) {
      const btn = svgEl("g", {
        class: "add-btn",
        "data-add": spot.dir,
        transform: `translate(${spot.x} ${spot.y}) scale(${1 / k})`,
      });
      // `svgEl` は数も受ける。**呼ぶ側に `String(...)` を書かせない**
      // （map/svg.ts の明文の規約 — 意味を持たない皮を積まない）
      btn.append(
        // 的は見た目より広い。指は 9px の丸の縁を正確には狙えない
        svgEl("circle", { class: "hit", r: HIT }),
        svgEl("circle", { class: "face", r: R }),
        svgEl("line", { x1: -ARM, y1: 0, x2: ARM, y2: 0 }),
        svgEl("line", { x1: 0, y1: -ARM, x2: 0, y2: ARM }),
      );
      this.el.append(btn);
    }
  }

  hide(): void {
    this.el.setAttribute("visibility", "hidden");
    // 隠れていても当たり判定は残るので、中身ごと捨てる
    this.el.replaceChildren();
  }
}
```

- [ ] **Step 4: 試験が通ることを確かめる**

Run: `pnpm test` → PASS
Run: `pnpm run check` → エラー無し

- [ ] **Step 5: コミット（算術だけ先に）**

```bash
git add src/map/addButtons.ts test/addButtons.test.ts
git commit -m "feat: ✨ 選択ノードの上下左右に出す + の置き場所"
```

- [ ] **Step 6: `mindmap.ts` に繋ぐ**

import に足す:

```ts
import { AddButtons } from "./map/addButtons.ts";
```

フィールドを足す（`private pick = new CardPick();` の隣）:

```ts
/** 選んでいるノードの上下左右に出る `+`（出すかどうかは人が決める） */
private adds = new AddButtons();
private addsOn = false;
```

コンストラクタの `this.viewport.append(...)` に `this.adds.el` を足す
（`this.pick.el` の直後 = ノード層より上）。

**`updatePlus` があった場所**に、見出しコメントごと書く:

```ts
// ---------- 選択ノードの `+` ----------

/**
 * 出すかどうかを切り替える。**保存も既定の判定もここは知らない** —
 * 「いま出すか」だけを受け取る（main.ts が持ち主）。
 */
setAddButtons(on: boolean): void {
  this.addsOn = on;
  this.updateAdds();
}

/**
 * 出す条件は「迷いようが無いとき」だけ — 選択がちょうど 1 つ、カードを
 * 選んでいない、編集中でない、ドラッグ中でない。
 */
private updateAdds(): void {
  const id = this.host.anchor();
  const b = this.boxes.get(id);
  if (
    !this.addsOn ||
    !b ||
    this.host.selection().size !== 1 ||
    this.host.pickedCard() !== null ||
    this.dragging ||
    this.isEditing()
  ) {
    this.adds.hide();
    return;
  }
  // ルートは親で包めない（core の cmd_add_parent が深さ 1 を弾く）
  const depth = this.host.doc().nodes.find((n) => n.id === id)?.depth ?? 1;
  this.adds.show(b, this.k, depth > 1);
}
```

Task 2 で `updatePlus()` を消した各所に `this.updateAdds();` を置く。
`setView` にも足す — **倍率が変われば打ち消しの `scale(1/k)` も引き直す**:

```ts
private setView(v: View): void {
  this.k = v.k;
  this.tx = v.tx;
  this.ty = v.ty;
  this.applyTransform();
  this.updateIndicator();
  this.updateAdds();
}
```

`bindClick()` の `pane.addEventListener("click", ...)`（`suppressClick` を見ている塊）の
**`kill` を見る行の直前**に足す:

```ts
// `+` は選んでいるノードにだけ出ている。押されたらその向きに 1 つ足す
const add = targetIn(e, "[data-add]")?.getAttribute("data-add");
if (add === "child" || add === "below" || add === "above" || add === "parent") {
  const id = this.host.anchor();
  if (id !== -1) {
    if (add === "child") this.host.addChild(id);
    else if (add === "below") this.host.addSibling(id);
    else if (add === "above") this.host.addSiblingBefore(id);
    else this.host.addParent(id);
  }
  return;
}
```

`bindPointer()` の `pointerdown` の**いちばん先頭**（`this.suppressClick = false;` の直後）に
足す。**押しても下へ抜けさせない** — 抜けると背景が矩形選択を始めてポインタを
捕まえ、`click` がそもそも起きない（`app/paneTool.ts` と同じ理由）:

```ts
// `+` の上での押下は、そのボタンのもの。下のキャンバスへ渡さない
if (targetIn(e, "[data-add]")) {
  e.stopPropagation();
  return;
}
```

- [ ] **Step 7: `style.css` に見た目を足す**

`.plus-btn` を消した場所（`#drop-line` の直前）に置く:

```css
/* 選んでいるノードの上下左右に出る `+`。**的は見た目より広い** —
   指は 9px の丸の縁を正確には狙えないので、透明な当たり判定を被せる
   （見えている丸まで指の的の大きさにすると、ノードより目立つ） */
.add-btn {
  cursor: pointer;

  & .hit { fill: transparent; }
  & .face { fill: var(--accent); }
  & line { stroke: #fff; stroke-width: 2; stroke-linecap: round; }
  &:hover .face { filter: brightness(1.25); }
}
```

- [ ] **Step 8: 型と試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 9: ブラウザで確かめる**

`setAddButtons` はまだ誰も呼ばないので、`mindmap.ts` の `private addsOn = false;` を
一時的に `= true` にして確認し、**確認後に false へ戻す**。

- ノードを 1 つ選ぶ → 上下左右に `+` が 4 つ出る
- ルートを選ぶ → 左（親）が出ない、3 つ
- `+` を押す → その向きにノードが増え、編集に入る
- 2 つ以上選ぶ / カードを選ぶ / 編集に入る → 消える
- ホイールで拡大縮小 → **`+` の大きさが変わらない**
- `+` を押しても矩形選択が始まらない

- [ ] **Step 10: コミット**

```bash
git add src/mindmap.ts src/style.css
git commit -m "feat: ✨ 選択ノードの上下左右の + を出せるようにする"
```

---

## Task 4: トグルと保存

**Files:**
- Modify: `src/app/persist.ts`
- Modify: `src/main.ts`

**Interfaces:**
- Consumes: `MindMap.setAddButtons(on: boolean)`（Task 3）、`persist.ts` の `load` / `store`
- Produces: `export const LS_ADDS = "mmm.addButtons"`

- [ ] **Step 1: `persist.ts` に鍵を足す**

```ts
/** 選択ノードの上下左右の `+` を出すか（main.ts が持ち主）。
 *  無ければ「その機械に従う」 — 保存するのは**人が押したときだけ** */
export const LS_ADDS = "mmm.addButtons";
```

`OWNED` に載せる（**載せないと `sweep()` が毎回捨てる**）:

```ts
const OWNED: readonly string[] = [LS_THEME, LS_COLOR, LS_WAY, LS_ADDS];
```

- [ ] **Step 2: `main.ts` の import を直す**

```ts
import { LS_ADDS, load, store, sweep } from "./app/persist.ts";
```

- [ ] **Step 3: 既定の判定と切り替えを書く**

`const theme = initTheme({ ... });` の直後に置く:

```ts
// **物理キーボードの有無は Web からは分からない。**代わりに「主たるポインタが
// 指か」を見る。Surface はキーボードを外すと OS が主ポインタを指へ切り替える
// ので、この 1 本で狙いどおりに振れる。近似であることは承知の上で、外れても
// 人が押して直せる形にしてある（`⋯` の 1 行）。
//
// `any-pointer` ではなく `pointer` を使う: マウスも刺さっている機械で
// 「指もある」だけを理由に出しっぱなしにはしない。
const TOUCH_FIRST = "(pointer: coarse) and (hover: none)";

// localStorage の中身は何でもありうる。名乗らせずに確かめる
const savedAdds = load(LS_ADDS);
let addsOn =
  savedAdds === "on"
    ? true
    : savedAdds === "off"
      ? false
      : (window.matchMedia?.(TOUCH_FIRST).matches ?? false);

const setAdds = (on: boolean): void => {
  addsOn = on;
  store(LS_ADDS, on ? "on" : "off");
  map.setAddButtons(on);
};
map.setAddButtons(addsOn);
```

`mindmap.ts` の `private addsOn = false;` を一時的に `true` にしていたら**戻す**。

- [ ] **Step 4: `⋯` に 1 行足す**

`openOnClick(btnMore, () => [ ... ])` の中、テーマの行の直後（同じ塊）に:

```ts
{ label: theme.isLight() ? "Dark theme" : "Light theme", run: () => theme.toggle() },
// 見た目の好み同士なのでテーマの隣。**押せばどうなるか**を名乗る（テーマと同じ流儀）
{ label: addsOn ? "Hide add buttons" : "Show add buttons", run: () => setAdds(!addsOn) },
```

- [ ] **Step 5: 型と試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 6: ブラウザで確かめる**

- `⋯` → `Show add buttons` → 選択ノードに `+` が 4 つ出て、行が `Hide add buttons` に変わる
- **再読み込みしても出たまま**（`localStorage` の `mmm.addButtons` が `"on"`）
- `Hide add buttons` → 消える。再読み込みしても消えたまま
- コンソールで `localStorage.removeItem("mmm.addButtons")` → 再読み込み →
  デスクトップでは**出ない**（主ポインタが指ではないため）
- DevTools の device toolbar でモバイルを選んで再読み込み → **出る**
- `localStorage` に `mmm.theme` / `mmm.color` / `mmm.exportWay` / `mmm.addButtons` が
  残っている（`sweep()` に捨てられていない）

- [ ] **Step 7: コミット**

```bash
git add src/app/persist.ts src/main.ts
git commit -m "feat: ✨ + ボタンの出し入れを ⋯ に置き、機械ごとの既定を持つ"
```

---

## Task 5: 指 1 本の作法（パンと、揺れ）

**Files:**
- Modify: `src/style.css`
- Modify: `src/mindmap.ts`

**Interfaces:**
- Consumes: 既存の `panning` 状態、`nodeAt`、`cardAt`
- Produces: `slopOf(e: PointerEvent): number`（`mindmap.ts` の中だけ。Task 7 も使う）

- [ ] **Step 1: `#map-pane` にブラウザのジェスチャを渡さない**

`src/style.css` の `#map-pane { ... }` の中に足す:

```css
  /* 指やペンでも動かせるように、ブラウザのスクロール/ズームへ渡さない
     （`.popup-canvas` と同じ理由）。**md ペインには敷かない** —
     CodeMirror のネイティブなスクロールを奪わない */
  touch-action: none;
```

- [ ] **Step 2: 指の揺れのぶん、ドラッグの閾値を広げる**

`const DRAG_SLOP2 = 64;` の直後に足す:

```ts
/** 指のときの閾値。マウスより揺れるので、タップが勝手にドラッグへ化ける */
const TOUCH_SLOP2 = 256;

/** その出来事に効く閾値（px の 2 乗） */
const slopOf = (e: PointerEvent): number =>
  e.pointerType === "touch" ? TOUCH_SLOP2 : DRAG_SLOP2;
```

`bindPointer()` の `pointermove` の中、2 か所を差し替える:

```ts
// cardDrag の中
if (!this.cardDrag.moved && dx * dx + dy * dy <= slopOf(e)) return;
```

```ts
// dragCand の中
if (dx * dx + dy * dy > slopOf(e)) this.startDrag();
```

- [ ] **Step 3: パンの 3 つ目の入り口を足す**

`bindPointer()` の `pointerdown`、既存のパンの塊を差し替える:

```ts
// パンは 3 つ入り口を持つ: 中クリックはマウスだけで完結し、Space+ドラッグは
// キーボードに手がある時に届き、**指は背景をなぞる**。担当する手が違うので、
// どれか 1 つでは塞がる場面がある（指には中ボタンも Space も無く、背景の
// ドラッグを矩形選択に取られると、地図が 1mm も動かせない）
const touchPan =
  e.pointerType === "touch" &&
  this.nodeAt(e.clientX, e.clientY) === -1 &&
  this.cardAt(e.clientX, e.clientY, "data-card") === null;
if (e.button === 1 || (e.button === 0 && this.spaceDown) || touchPan) {
  this.panning = {
    px: e.clientX,
    py: e.clientY,
    ox: this.tx,
    oy: this.ty,
  };
  pane.style.cursor = "grabbing";
  pane.setPointerCapture(e.pointerId);
  e.preventDefault();
  return;
}
```

- [ ] **Step 4: 型と試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 5: ブラウザで確かめる（DevTools の device toolbar = touch エミュレート）**

- 背景をなぞる → **地図が動く**（矩形選択の枠が出ない）
- ノードをなぞる → 今までどおりノードが動く
- ノードを軽く叩く → 選択に入る（少し指がずれてもドラッグに化けない）
- **マウスでの操作が 1 つも変わっていない**: 背景ドラッグ = 矩形選択、
  中ボタン = パン、`Space`+ドラッグ = パン

- [ ] **Step 6: コミット**

```bash
git add src/style.css src/mindmap.ts
git commit -m "feat: ✨ 指 1 本で地図を動かせるようにする"
```

---

## Task 6: 2 本指の pinch

**Files:**
- Create: `src/map/gesture.ts`
- Create: `test/gesture.test.ts`
- Modify: `src/mindmap.ts`

**Interfaces:**
- Consumes: `map/view.ts` の `Span` / `pinch`（Task 1）
- Produces:
  - `export class Fingers`
    - `down(id: number, x: number, y: number): void`
    - `move(id: number, x: number, y: number): { from: Span; to: Span } | null`
    - `up(id: number): void`
    - `clear(): void`
    - `get pinching(): boolean`
  - 座標は**ペインの左上から測った画面 px**（`Fingers` は DOM を知らない）
  - `MindMap.local(clientX, clientY)` — private の助け

- [ ] **Step 1: 失敗する試験を書く**

`test/gesture.test.ts` を作る:

```ts
// 指の台帳。「いま何本か」を取り違えると、2 本目を置いた瞬間に地図が
// 跳ねたり、1 本離しても掴んだままになったりする。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { Fingers } from "../src/map/gesture.ts";

test("1 本だけでは何も言わない", () => {
  const f = new Fingers();
  f.down(1, 10, 10);
  assert.equal(f.pinching, false);
  assert.equal(f.move(1, 20, 20), null);
});

test("2 本目が乗ると pinch が始まる", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  assert.equal(f.pinching, true);
});

test("2 本目が動くと、前後の位置が出る", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  const g = f.move(2, 140, 0);
  assert.deepEqual(g, {
    from: { a: { x: 0, y: 0 }, b: { x: 100, y: 0 } },
    to: { a: { x: 0, y: 0 }, b: { x: 140, y: 0 } },
  });
});

test("動いた分だけを次の起点にする", () => {
  // 覚え直さないと、2 回目以降が「最初の位置からの差」になって加速する
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.move(2, 140, 0);
  const g = f.move(2, 160, 0);
  assert.deepEqual(g?.from.b, { x: 140, y: 0 });
});

test("動いていない指は何も言わない", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  assert.equal(f.move(2, 100, 0), null);
});

test("1 本離すと pinch は終わる", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.up(2);
  assert.equal(f.pinching, false);
  assert.equal(f.move(1, 50, 50), null);
});

test("3 本目は組に入れない — 最初の 2 本を使い続ける", () => {
  // 途中で組が入れ替わると、指を足した瞬間に地図が跳ぶ
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.down(3, 200, 0);
  assert.equal(f.move(3, 260, 0), null);
  assert.deepEqual(f.move(2, 140, 0)?.to.b, { x: 140, y: 0 });
});

test("clear ですべて忘れる", () => {
  const f = new Fingers();
  f.down(1, 0, 0);
  f.down(2, 100, 0);
  f.clear();
  assert.equal(f.pinching, false);
});
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `pnpm test`
Expected: FAIL — `../src/map/gesture.ts` が無い

- [ ] **Step 3: `src/map/gesture.ts` を書く**

```ts
// 指の台帳。**何本が生きていて、前回どこに居たか**だけを持つ。
//
// 「いま何本の指か」は、mindmap.ts の 5 つの状態（パン / 矩形選択 /
// ノードのドラッグ / カードのドラッグ / ドラッグ候補）とは別の次元なので、
// 混ぜない。1 本のときは何も言わず、既存の 1 ポインタの流れがそのまま担う。
//
// **DOM を知らない。** 受け取るのはペインの左上から測った画面 px で、
// 出すのは `map/view.ts` の `Span`。だから値として試験できる。

import type { Span } from "./view.ts";

/** 組にする 2 本。**途中で入れ替えない** — 入れ替わると地図が跳ぶ */
type Pair = [number, number];

export class Fingers {
  private at = new Map<number, { x: number; y: number }>();
  private pair: Pair | null = null;

  get pinching(): boolean {
    return this.pair !== null;
  }

  /** 2 本以上あって組が無いなら、いま生きている先頭の 2 本で組む */
  private form(): void {
    if (this.pair !== null || this.at.size < 2) return;
    const [a, b] = [...this.at.keys()];
    if (a !== undefined && b !== undefined) this.pair = [a, b];
  }

  down(id: number, x: number, y: number): void {
    this.at.set(id, { x, y });
    // 3 本目以降は台帳には載るが、組は最初の 2 本のまま
    this.form();
  }

  /** 組の片方が実際に動いたときだけ、その前後を返す */
  move(id: number, x: number, y: number): { from: Span; to: Span } | null {
    const known = this.at.get(id);
    if (!known) return null;
    this.at.set(id, { x, y });
    const pair = this.pair;
    if (!pair || (pair[0] !== id && pair[1] !== id)) return null;
    if (known.x === x && known.y === y) return null;
    const other = this.at.get(pair[0] === id ? pair[1] : pair[0]);
    if (!other) return null;
    return {
      from: { a: { x: other.x, y: other.y }, b: { x: known.x, y: known.y } },
      to: { a: { x: other.x, y: other.y }, b: { x, y } },
    };
  }

  up(id: number): void {
    this.at.delete(id);
    if (!this.pair) return;
    if (this.pair[0] !== id && this.pair[1] !== id) return;
    // 組の片方が離れた。3 本置いて 1 本離した場合は残りで組み直す
    this.pair = null;
    this.form();
  }

  clear(): void {
    this.at.clear();
    this.pair = null;
  }
}
```

- [ ] **Step 4: 通ることを確かめる**

Run: `pnpm test` → PASS
Run: `pnpm run check` → エラー無し

- [ ] **Step 5: コミット（台帳だけ先に）**

```bash
git add src/map/gesture.ts test/gesture.test.ts
git commit -m "feat: ✨ 指の台帳を、状態機械から切り離して持つ"
```

- [ ] **Step 6: `mindmap.ts` に繋ぐ**

import に足す:

```ts
import { Fingers } from "./map/gesture.ts";
```

`./map/view.ts` からの import に `pinch` を足す。

フィールドを足す（`private spaceDown = false;` の隣）:

```ts
/** 2 本目の指。1 本のあいだは何も言わないので、既存の状態は増えない */
private fingers = new Fingers();
```

`toWorld` の隣に助けを足す:

```ts
/** ペインの左上から測った画面 px（`map/view.ts` が使う座標系） */
private local(clientX: number, clientY: number): { x: number; y: number } {
  const r = this.pane.getBoundingClientRect();
  return { x: clientX - r.left, y: clientY - r.top };
}
```

`bindPointer()` の `pointerdown`、**`+` の stopPropagation の直後**に足す:

```ts
if (e.pointerType === "touch") {
  const p = this.local(e.clientX, e.clientY);
  this.fingers.down(e.pointerId, p.x, p.y);
  // 2 本目が乗った時点で、1 本ぶんの操作はすべて畳む。**指を足しただけで
  // ノードが動いたり範囲が選ばれたりしない**
  if (this.fingers.pinching) {
    this.panning = null;
    this.rubberStart = null;
    this.rubber.style.display = "none";
    this.dragCand = null;
    if (this.dragging) this.stopDragVisuals();
    pane.style.cursor = "";
    return;
  }
}
```

`pointermove` の**いちばん先頭**に足す:

```ts
if (e.pointerType === "touch") {
  const p = this.local(e.clientX, e.clientY);
  const g = this.fingers.move(e.pointerId, p.x, p.y);
  if (g) {
    this.setView(pinch(this.view(), g.from, g.to));
    return;
  }
  // 2 本乗っているあいだは、1 本ぶんの続きを進めない
  if (this.fingers.pinching) return;
}
```

`pointerup` の**いちばん先頭**に足す:

```ts
if (e.pointerType === "touch") {
  const wasPinching = this.fingers.pinching;
  this.fingers.up(e.pointerId);
  // 2 本目を離した指で、選択やドラッグの後始末を走らせない
  if (wasPinching) return;
}
```

`pointercancel` のハンドラの先頭に `this.fingers.clear();` を足す。

- [ ] **Step 7: 型と試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 8: ブラウザで確かめる**

DevTools の device toolbar は 2 本指を出せないので、**実機**か
Chrome の device toolbar の `Shift`+ドラッグ（pinch エミュレート）を使う。

- 2 本指を離す → 拡大。近づける → 縮小
- 2 本指を平行に動かす → パン
- **拡大しながら指をずらしても、掴んでいた場所が指の下に留まる**
- 2 本目を置いた瞬間に地図が跳ばない
- 1 本離してもう 1 本を動かす → 地図が動く（1 本のパンに戻る）
- **マウスでの操作が 1 つも変わっていない**

- [ ] **Step 9: コミット**

```bash
git add src/mindmap.ts
git commit -m "feat: ✨ 2 本指で拡大縮小できるようにする"
```

---

## Task 7: 長押しのメニューを確かめる

**Files:**
- Modify: `src/mindmap.ts`（**届かなかったときだけ**）

**Interfaces:**
- Consumes: 既存の `bindMenu()` の `contextmenu` ハンドラ、`slopOf`（Task 5）
- Produces: なし

**確認結果:** （Step 3 でここに 1 行書く）

**なぜ確かめてから書くか:** README が「Chromium 系でしか動かない」と言い切っている
以上、長押し → `contextmenu` はブラウザが出す。**届くのに自前で書けば、同じメニューが
2 回開く道を作る**ことになる。

- [ ] **Step 1: 実機（またはタッチのある Chromium）で確かめる**

`pnpm run dev` → ノードを長押しする。`touch-action: none`（Task 5）を敷いた状態で試すこと。

Expected（届く場合）: 右クリックと同じメニューが指の位置に開く。
→ **その場合はコードを 1 行も足さない。Step 2 を飛ばして Step 3 へ。**

- [ ] **Step 2: 届かなかったときだけ — 自前の長押し**

`const TOUCH_SLOP2 = 256;` の隣に足す:

```ts
/** 長押しと見なす時間（ms）。Chromium のネイティブと同じ体感に合わせる */
const HOLD_MS = 500;
```

フィールドを足す:

```ts
/** 長押しの見張り。指が動くか離れたら取り消す */
private hold: ReturnType<typeof setTimeout> | null = null;
/** 見張りを始めた位置。閾値を越えて動いたら取り消す */
private holdAt: { x: number; y: number } | null = null;
```

取り消しを 1 か所にまとめる（`updateAdds` の隣に置く）:

```ts
/** 長押しの見張りを解く。指が動いた・離れた・攫われた、のどれでも */
private dropHold(): void {
  if (this.hold !== null) clearTimeout(this.hold);
  this.hold = null;
  this.holdAt = null;
}
```

`bindPointer()` の `pointerdown`、`fingers.down` の塊の直後に足す:

```ts
if (e.pointerType === "touch" && !this.fingers.pinching) {
  const { clientX, clientY } = e;
  this.holdAt = { x: clientX, y: clientY };
  this.hold = setTimeout(() => {
    this.dropHold();
    const id = this.nodeAt(clientX, clientY);
    if (id === -1) return;
    if (!this.host.selection().has(id)) this.host.setSelection([id], id);
    this.menu.show(clientX, clientY, this.menuItems());
  }, HOLD_MS);
}
```

`pointermove` の、指の塊の直後に足す（**閾値を越えたときだけ**解く —
指はじっとしていても揺れる）:

```ts
if (this.holdAt) {
  const dx = e.clientX - this.holdAt.x;
  const dy = e.clientY - this.holdAt.y;
  if (dx * dx + dy * dy > slopOf(e)) this.dropHold();
}
```

`pointerup` と `pointercancel` の先頭に `this.dropHold();` を足す。

- [ ] **Step 3: 確かめたことを記録して、型と試験を通す**

このタスクの **確認結果:** に 1 行書く。例:

```
**確認結果:** 2026-08-27 / Chrome on Android: `touch-action: none` でも
contextmenu が届いたので、コードは 1 行も足していない。
```

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 4: コミット**

コードを足した場合:

```bash
git add src/mindmap.ts docs/superpowers/plans/2026-08-27-touch-support.md
git commit -m "feat: ✨ 長押しでノードのメニューを開く"
```

足さなかった場合は、計画への記録だけを Task 11 のコミットに含める。

---

## Task 8: 狭いときは、左右どちらか 1 つに統一する

**Files:**
- Modify: `src/app/panes.ts`
- Create: `test/panes.test.ts`
- Modify: `src/style.css`

**Interfaces:**
- Consumes: なし
- Produces:
  - `export interface Vis { md: boolean; map: boolean }`
  - `export function spotsFor(narrow: boolean): readonly Vis[]`
  - `export function project(v: Vis, list: readonly Vis[]): Vis`
  - `<html class="narrow">` — CSS が見る印

- [ ] **Step 1: 失敗する試験を書く**

`test/panes.test.ts` を作る:

```ts
// 分割線の居場所。狭いときに「両方」を残すと、CSS が片方を隠して
// **状態が 2 つになり食い違う**（矢印は行けない場所を指す）。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { type Vis, project, spotsFor } from "../src/app/panes.ts";

const MD_ONLY: Vis = { md: true, map: false };
const BOTH: Vis = { md: true, map: true };
const MAP_ONLY: Vis = { md: false, map: true };

test("広いときは 3 つ、狭いときは 2 つ", () => {
  assert.deepEqual(spotsFor(false), [MAP_ONLY, BOTH, MD_ONLY]);
  assert.deepEqual(spotsFor(true), [MAP_ONLY, MD_ONLY]);
});

test("左から右へ並ぶ順は、狭くても変わらない", () => {
  // `‹` はいつでも「分割線を左へ 1 つ」。行き先が減るだけ
  for (const narrow of [false, true]) {
    const list = spotsFor(narrow);
    assert.deepEqual(list[0], MAP_ONLY);
    assert.deepEqual(list[list.length - 1], MD_ONLY);
  }
});

test("居場所にある形は、そのまま", () => {
  assert.deepEqual(project(BOTH, spotsFor(false)), BOTH);
  assert.deepEqual(project(MD_ONLY, spotsFor(true)), MD_ONLY);
});

test("狭いところへ「両方」が来たら、マップを残す", () => {
  assert.deepEqual(project(BOTH, spotsFor(true)), MAP_ONLY);
});

test("「両方消えた」は作らない", () => {
  const none: Vis = { md: false, map: false };
  // 広いときは両方に戻す（今までと同じ）。狭いときはマップだけ
  assert.deepEqual(project(none, spotsFor(false)), BOTH);
  assert.deepEqual(project(none, spotsFor(true)), MAP_ONLY);
});
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `pnpm test`
Expected: FAIL — `project` / `spotsFor` / `Vis` が `panes.ts` から出ていない

- [ ] **Step 3: `panes.ts` の純粋な部分を書く**

先頭のコメントの末尾に足す:

```ts
// **狭いときは「両方」が居場所から消える。** 並べられない幅で「両方」を
// 残すと、CSS が片方を隠して**状態が 2 つになり食い違う** — 矢印は行けない
// 場所を指し、`disabled` は画面に無い世界を説明する。
```

既存の `SPOTS` と `type Vis` と `spotOf` と `describe` を、次で置き換える:

```ts
/** 見えているペイン。**「両方消えた」は作らない** */
export interface Vis {
  md: boolean;
  map: boolean;
}

/**
 * 分割線の居場所。左端 = md が無い / 真ん中 = 両方 / 右端 = マップが無い。
 * **狭いときは真ん中が消えて 2 つになる** — 左から右へ並ぶ順は変わらない
 * ので、`‹` は狭くても「分割線を左へ 1 つ」のまま。
 */
export function spotsFor(narrow: boolean): readonly Vis[] {
  const mapOnly: Vis = { md: false, map: true };
  const mdOnly: Vis = { md: true, map: false };
  return narrow ? [mapOnly, mdOnly] : [mapOnly, { md: true, map: true }, mdOnly];
}

/**
 * 要求された見え方を、いまの居場所へ射影する。**居場所に無い形は 2 つだけ** —
 * 「両方消えた」と、狭いときの「両方」。どちらも**マップを必ず残し、md は
 * 残せるなら残す**（この道具がマップのために在るから）。
 */
export function project(v: Vis, list: readonly Vis[]): Vis {
  const hit = list.find((s) => s.md === v.md && s.map === v.map);
  if (hit) return hit;
  return list.find((s) => s.md && s.map) ?? list[0];
}

const spotOf = (list: readonly Vis[], v: Vis): number =>
  list.findIndex((s) => s.md === v.md && s.map === v.map);

/** その一手で何が起きるかを言う（矢印は向きを変えないので、言葉が担う） */
function describe(from: Vis | undefined, to: Vis | undefined): string {
  if (!from || !to) return "";
  // 狭いときは両方が入れ替わる。そのときは**行き先の名前**を言う
  if (from.md !== to.md && from.map !== to.map) {
    return to.md ? "Show the Markdown pane" : "Show the map";
  }
  if (from.md !== to.md) {
    return to.md ? "Show the Markdown pane" : "Hide the Markdown pane";
  }
  return to.map ? "Show the map" : "Hide the map";
}
```

`spotsFor(true)` は `list[0]` が必ず `{md:false,map:true}` = マップだけなので、
`project` の最後の `?? list[0]` がそのまま「マップを残す」になる。

- [ ] **Step 4: 試験が通ることを確かめる**

Run: `pnpm test` → PASS
Run: `pnpm run check` → `initPanes` の中がまだ古い形を指していて落ちる。次で直す

- [ ] **Step 5: `initPanes` を新しい形に繋ぐ**

`let paneVis: Vis = { md: true, map: true };` の直後に足す:

```ts
// **`720px` を 2 か所に置かない。** メディアクエリでは CSS 変数を使えないので、
// 唯一の源を JS に置き、CSS は `<html class="narrow">` を見る
const NARROW = "(max-width: 720px)";
const narrow = window.matchMedia(NARROW);
const spots = (): readonly Vis[] => spotsFor(narrow.matches);
```

`applyPaneVis` を差し替える:

```ts
const applyPaneVis = (want: Vis): void => {
  const list = spots();
  const v = project(want, list);
  paneVis = v;
  document.documentElement.classList.toggle("narrow", narrow.matches);
  mdPane.classList.toggle("pane-off", !v.md);
  mapPane.classList.toggle("pane-off", !v.map);
  panesEl.classList.toggle("no-map", !v.map);
  panesEl.classList.toggle("no-md", !v.md);
  // 端では、その先が無いので押せない
  const spot = spotOf(list, v);
  goLeft.disabled = spot <= 0;
  goRight.disabled = spot >= list.length - 1;
  goLeft.title = describe(list[spot], list[spot - 1]);
  goRight.title = describe(list[spot], list[spot + 1]);
  // focus must not stay in a hidden pane
  if (!v.md && mdPane.contains(document.activeElement)) mapPane.focus();
  if (!v.map && mapPane.contains(document.activeElement)) args.focusEditor();
};
```

`slide` を差し替える:

```ts
/** 分割線を 1 つ動かす。端は動かない */
const slide = (step: -1 | 1): void => {
  const list = spots();
  const next = list[spotOf(list, paneVis) + step];
  if (next) applyPaneVis({ ...next });
};
```

`togglePaneVis` を差し替える（**「両方消えた」の手当ては `project` が持つ**）:

```ts
const togglePaneVis = (which: "md" | "map"): void => {
  applyPaneVis({ ...paneVis, [which]: !paneVis[which] });
};
```

スプリッタの `pointerdown` の先頭に足す:

```ts
  // 狭いときは分割そのものが無い。掴む先も、戻る先も無い
  if (narrow.matches) return;
```

最後の `applyPaneVis(paneVis);` の直前に足す:

```ts
// 幅が境目をまたいだら、いまの見え方を新しい居場所へ射影し直す
narrow.addEventListener("change", () => applyPaneVis(paneVis));
```

- [ ] **Step 6: `style.css` の狭いときの規則を直す**

`@media (max-width: 720px)` の中身から**2 行を消す**:

```css
  #splitter { display: none; }
  #panes:not(.no-map) #md-pane { display: none; }
```

`#panes.no-md #pane-switch { ... }` の直後に足す:

```css
/* 狭いときは、居場所が 2 つしか無い（`app/panes.ts` の `spotsFor`）。
   **分割線は線としての性質だけを落とす** — 動かせない境目を「掴めます」と
   いう顔で見せない。要素は 0 幅で残す: flex がそれを縁まで押し出すので、
   `#pane-switch` は今までどおり同じ 1 か所に居られる（角と角に分けると、
   片方だけスクロールバー避けの分ずれて見える）。
   居場所が 2 つなら `button:disabled { display: none }` により、
   **画面に出る矢印は常に 1 本**になる */
.narrow #splitter {
  width: 0;
  background: none;
  cursor: default;
}
```

`#panes.no-map #pane-switch` の `right` を直す:

```css
/* 片方だけの時は、境目が窓の縁に来る。md を出しているときの右端は
   CodeMirror のスクローラの帯（15〜17px）で、ブラウザが押下を横取りする
   （z-index では前に出せない）。`#md-pane .pane-tool` と同じだけ避ける */
#panes.no-map #pane-switch { left: auto; right: 28px; transform: none; }
```

- [ ] **Step 7: 型と試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 8: ブラウザで確かめる**

窓を広く（>720px）:
- 3 つの居場所を `‹ ›` で行き来できる。真ん中で分割線を掴んで幅が変わる
- md だけのとき、`›` が**スクロールバーに食われず押せる**

窓を狭く（<720px）:
- **分割線の線が見えない**
- **矢印は常に 1 本だけ**出ていて、押すと向こう側へ切り替わる
- 分割線のあった場所を押しても何も起きない
- `Alt+1` / `Alt+2` / `Mod+/` でも同じ 2 つを行き来する（「両方」にならない）

境目をまたぐ:
- 広い状態で「両方」→ 窓を狭める → **マップが残る**
- 狭い状態で md → 窓を広げる → md のまま（勝手に両方は開かない）

- [ ] **Step 9: コミット**

```bash
git add src/app/panes.ts test/panes.test.ts src/style.css
git commit -m "fix: 🐛 狭いときのペインを、左右どちらか 1 つに統一する"
```

---

## Task 9: 指では致命的な、既存の 3 点

**Files:**
- Modify: `src/style.css`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: `.pane-tool` の塊の直後に、指のための 2 つを足す**

```css
/* **指にホバーは無い。** 沈めたままだと、起こす手段が無いまま半透明で
   居続ける（ペイン切り替えの矢印・書き方ピッカー・視点を寄せるボタン、
   3 つとも）。触って起こせないなら、最初から起きている */
@media (hover: none) {
  .pane-tool { opacity: 1; }
}

/* 指の的。**幅ではなく入力の質で決まる話**なので `.narrow` ではなく
   メディアクエリで見る（狭くしただけのデスクトップの窓を太らせない）。
   狭いところでは、切り替えの矢印がペインを行き来する唯一の手段になる */
@media (pointer: coarse) {
  .pane-tool button { min-height: 44px; }
  #pane-switch button { width: 44px; height: 44px; }
  #pane-switch button .icon { width: 16px; height: 16px; }
}
```

- [ ] **Step 2: 試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS

- [ ] **Step 3: ブラウザで確かめる（DevTools の device toolbar = モバイル）**

- ペイン切り替えの矢印・書き方ピッカー（H / n+ / L）・視点を寄せるボタンが
  **最初から濃く出ている**
- 矢印が指で押せる大きさになっている
- デスクトップ（マウス）では**今までどおり半透明で、触れると起きる**

- [ ] **Step 4: コミット**

```bash
git add src/style.css
git commit -m "fix: 🐛 ペインの隅の道具を、指でも起こして押せるようにする"
```

---

## Task 10: File System Access API の存在を確かめる

**Files:**
- Modify: `src/app/io.ts`
- Modify: `src/app/assets.ts`
- Modify: `src/main.ts`

**Interfaces:**
- Consumes: なし
- Produces:
  - `io.canOpen(): boolean` / `io.canSaveAs(): boolean`
  - `initAssets` の戻りに `canChooseFolder(): boolean`

- [ ] **Step 1: 宣言を「あるかもしれない」に直す**

`src/app/io.ts` の `interface Window` の 3 つを任意にする。**型は名乗らせず
確かめる** — 必須と宣言したままだと、無い環境で `TypeError` が飛ぶことを
型が隠してしまう:

```ts
  interface Window {
    showOpenFilePicker?: (options?: {
      multiple?: boolean;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }) => Promise<FileSystemFileHandle[]>;
    showSaveFilePicker?: (options?: {
      suggestedName?: string;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }) => Promise<FileSystemFileHandle>;
    showDirectoryPicker?: (options?: {
      startIn?: FileSystemHandle;
      mode?: "read" | "readwrite";
    }) => Promise<FileSystemDirectoryHandle>;
  }
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `pnpm run check`
Expected: FAIL — `io.ts` の 2 か所と `assets.ts` の 1 か所で
「オブジェクトは 'undefined' である可能性があります」

- [ ] **Step 3: 呼ぶ前に確かめる**

`src/app/io.ts` の `io` オブジェクトに 2 つ足す（`openDialog` の直前）:

```ts
  /** このブラウザがファイルを開けるか。**スマホには無い** —
   *  `docs/web.md` のとおりフォールバックは持たないので、無いなら無いと言う */
  canOpen: (): boolean => typeof window.showOpenFilePicker === "function",
  canSaveAs: (): boolean => typeof window.showSaveFilePicker === "function",
```

`openDialog` と `saveAs` を差し替える:

```ts
  async openDialog(): Promise<Doc | null> {
    const pick = window.showOpenFilePicker;
    if (!pick) return null;
    try {
      const [file] = await pick({ multiple: false, types: MARKDOWN });
      return file ? use(file) : null;
    } catch (error) {
      if (isCancel(error)) return null;
      throw error;
    }
  },
```

```ts
  async saveAs(suggested: string, text: string): Promise<Doc | null> {
    const pick = window.showSaveFilePicker;
    if (!pick) return null;
    try {
      const file = await pick({ suggestedName: suggested, types: MARKDOWN });
      await write(file, text);
      current = file;
      await handles.saveFile(file);
      return { name: file.name, text };
    } catch (error) {
      if (isCancel(error)) return null;
      throw error;
    }
  },
```

`src/app/assets.ts` の `showDirectoryPicker` を呼ぶ行を差し替える。
**戻り型に合う値を返すこと** — `grep -n "chooseFolder" src/app/assets.ts` で
確かめてから書く（`Promise<void>` なら `return;`）:

```ts
      const pick = window.showDirectoryPicker;
      if (!pick) return;
      directory = await pick({ startIn: file, mode: "readwrite" });
```

`assets.ts` 先頭の `interface Assets`（`folderName` / `chooseFolder` /
`saveToDisk` が並ぶ）に足す — **実装だけ足しても、呼ぶ側の型は知らない**:

```ts
  /** このブラウザがフォルダを選べるか */
  canChooseFolder(): boolean;
```

`initAssets` の戻りにも足す:

```ts
    canChooseFolder: (): boolean =>
      typeof window.showDirectoryPicker === "function",
```

- [ ] **Step 4: `Files` に、なぜ押せないかを言わせる**

`src/main.ts` の `openOnClick(btnFile, () => [ ... ])` を差し替える:

```ts
openOnClick(btnFile, () => {
  // **無いものを黙って落とさない。** スマホのブラウザには File System
  // Access API が無く、`docs/web.md` のとおり 2 本目の道は作らない。
  // 押せない理由だけは言う
  const canOpen = io.canOpen();
  const canSave = io.canSaveAs();
  return [
    { label: "New", key: "Mod+Alt+N", run: () => void newFile() },
    { label: "Open", key: "Mod+O", run: () => void openFile(), disabled: !canOpen },
    ...(canOpen && canSave
      ? []
      : [{ caption: "This browser cannot open or save files" }]),
    { caption: savedName ?? "not saved yet" },
    { label: "Rename", run: () => void renameFile(), disabled: savedName === null },
    { label: "Save", key: "Mod+S", run: () => void saveFile(), disabled: !canSave },
    { label: "Save as", key: "Mod+Shift+S", run: () => void saveFile(true), disabled: !canSave },
    { caption: assets.folderName() ?? "none" },
    {
      label: "Images Folder",
      run: () => void assets.chooseFolder(),
      disabled: !assets.canChooseFolder(),
    },
  ];
});
```

型が合わないときは、配列に `MenuEntry[]` の注釈を付けて返す
（`import { type MenuEntry, openOnClick } from "./map/menu.ts";`）。

- [ ] **Step 5: 型と試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS（`assertions.test.ts` が `as` / `!` を見つけないこと）

- [ ] **Step 6: ブラウザで確かめる**

- デスクトップ Chromium: `Files` の全項目が今までどおり押せて、開く・保存できる
- コンソールで
  `delete window.showOpenFilePicker; delete window.showSaveFilePicker; delete window.showDirectoryPicker;`
  → `Files` を開く → **Open / Save / Save as / Images Folder が無効になり、
  `This browser cannot open or save files` が出る**。押しても例外が飛ばない

- [ ] **Step 7: コミット**

```bash
git add src/app/io.ts src/app/assets.ts src/main.ts
git commit -m "fix: 🐛 ファイルの道が無いブラウザで、黙って落ちないようにする"
```

---

## Task 11: README を今に合わせる

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-08-27-touch-support.md`（Task 7 の結果）

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: 構成の表に、増えた 3 つを足す**

`src/map/` の列挙に（`pick` の隣が読みやすい）:

```
                 addButtons(選んだノードの上下左右に出す + の置き場所) /
                 gesture(指の台帳。2 本目からを引き受ける) /
```

`test/` の列挙に「ペインの居場所 / + の置き場所 / 指の台帳」を足す。

- [ ] **Step 2: 「狭いとき」の節を書き直す**

現在の記述（`720px` を切ると片方だけを出す／どちらを出すかは持たない）を
差し替える:

```
`720px` を切ると**居場所が 2 つになる** — md だけか、マップだけか。
「両方」は消える(並べられない幅で残すと、状態が 2 つになって食い違う)。

**分割線は線としての性質だけを落とす**(0 幅・掴めない)。要素は残るので、
`‹ ›` はいつもと同じ 1 か所に居られる。行き先が 2 つなら**出る矢印は
常に 1 本**で、押せば向こう側へ移る。切り替えは `Alt+1` / `Alt+2` /
`Mod+/` もそのまま担う。
```

- [ ] **Step 3: 指の作法を書く節を足す**

「狭いとき」の直後に新しい節を置く:

```
### 指で使う

**モードは無い。** 触れたものが答えを持っているので、指なら指の作法、
マウスならマウスの作法がその場で決まる(`pointerType`)。

| 指 | どこ | 何が起きる |
|---|---|---|
| 1 本 | 背景 | 動かす |
| 1 本 | ノード | 叩けば選ぶ / なぞれば動かす |
| 2 本 | どこでも | 拡大縮小(同時に動かす) |
| 長押し | ノード | 右クリックと同じメニュー |

**指では矩形選択が出ない** — 背景をパンに明け渡したため。叩いて 1 つずつ選ぶ。

**ノードを足すボタン**は `⋯` の `Show add buttons` で出す。選んだノードの
上下左右に `+` が出て、右が子・左が親・上下が兄弟(`Tab` / `Shift+Tab` /
`Enter` / `Shift+Enter` と同じ)。ルートは親で包めないので左は出ない。
**指が主のときは既定で出ている** — 物理キーボードの有無は分からないので、
「主たるポインタが指か」で代用する。

**スマホではファイルを開けない・保存できない。** File System Access API が
無く、`docs/web.md` のとおり 2 本目の道は作らない。`Files` の該当行は
理由とともに無効になる。書いて書き出すことはできる。
```

- [ ] **Step 4: Task 7 の結果が計画に残っていることを確かめる**

- [ ] **Step 5: 試験を通す**

Run: `pnpm run check` → エラー無し
Run: `pnpm test` → PASS
Run: `pnpm run build` → 通る

- [ ] **Step 6: コミット**

```bash
git add README.md docs/superpowers/plans/2026-08-27-touch-support.md
git commit -m "docs: 📝 指の作法と、狭いときの居場所 2 つを README に書く"
```

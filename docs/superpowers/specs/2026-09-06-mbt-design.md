# mbt — TS を MoonBit に回す（設計）

Issue: #143。#137（配置と描画を core へ）の続き。

## なぜ

打鍵ごとに core は木と箱を JSON にして TS へ渡している（5000 ノードで 50 ms × 2。
MoonBit の stringify）。TS が木と箱を読むのは、**木と箱を歩く判断**（選択の当たり・
落とし先・矢印・キーの表・カーソル → ノード・コピーの切り出し …）が TS に在るから。
JSON は症状で、原因は判断の置き場。判断を core に移せば、TS は木を読む理由を失い、JSON は消える。

wasm は効かない — 重いのは計算ではなく境界の綴りで、wasm では境界がさらに重くなる。
js backend で struct を TS に読ませる手（B）も無い — `.d.ts` は struct を `any` と書き、
enum は `0/1` と `_0/_1`、Map は自前の表になる。約束のある型は
**数・文字列・真偽・タプル・FixedArray・`T?`（`T | undefined`）** だけ。

## 決め

**木も箱も core から出ない。境界は数・文字列・真偽・持ち手と、操作 1 回ぶんの小さな JSON。**

```
TS ── md ───────────────────────────> core.survey → 持ち手
TS ── 持ち手・座標・キー・id ────────> core.〜     → id / 数 / タプル / 小さな JSON（Intent・Drop・メニューの行）
TS ── Op ───────────────────────────> core.edit   → edits + focus（今のまま）
TS ── 持ち手・閉包 ─────────────────> core.draw   → DOM（今のまま）
```

TS に残るのはブラウザでなければできないことだけ:

| 残る | 理由 |
|---|---|
| CodeMirror（md ペイン、履歴、状態の field） | TS のライブラリ。真実は md の文字列で、そこに居る |
| DOM のイベントを**受ける**配線（pointer / key / wheel / focus） | ブラウザから来る。受けたら core に渡す |
| canvas の実測、CSS の字の綴り | ブラウザの都合 |
| ファイル / 画像フォルダ / クリップボード / 書き出しの API | ブラウザの API |
| `<input>` の重ね、メニューの器、しらせ・たずねの器 | HTML の部品（段 3 以降で core/render に寄せられるものは寄せる） |

**wasm-gc に行く日も、この境界なら同じ形で通る。**

## 語彙

- 判断の関数は今の TS の名のまま core へ（`hit` / `rubber` / `arrow` / `resolve` / `keyed` / `items` / `fit` / `pinch` …）。
  意味を変えない移送なので、名を変える理由が無い
- `Intent` / `Drop` / `Selection` / `Key` / `Camera` / `Pane` / `Reach` は core/map の語になる。
  TS は Intent を**実行する**だけ（`act`）
- 出口は `mmm` + 動詞。引数は持ち手と数、返りは数・タプル・`T?`・小さな JSON

## 型（段 1: 箱の判断）

```moonbit
// core/map — 選択
pub(all) struct Selection { ids : Array[Int]; anchor : Int? }     // 文書順の id と、範囲・矢印の基点
pub(all) enum Modifier { NoMod; Shift; Mod }
pub(all) struct Reach { pad : Double; edge : Double }              // exact / grab
pub fn click(sel, id, mod, order) -> Selection
pub fn rubber(l : Layout, r : Rect) -> Selection
pub fn hit(l, x, y, reach) -> Int?
pub fn arrow(l, anchor : Int?, key : Arrow) -> Int?
pub fn extend(sel, next) -> Selection
pub fn all(l) -> Selection
pub fn parent_of / prev_sibling / next_sibling / solo

// core/map — 落とし先
pub(all) enum Drop { Node(id~, pos~ : Int); Side(root~, left~ : Bool) }
pub fn resolve(l, at : Pt, dragging : Array[Int]) -> Drop?
pub fn drop_op(d : Drop, ids) -> @op.Op

// core/map — キーと右クリック
pub(all) struct Key { key : String; shift : Bool; mod : Bool; alt : Bool }
pub(all) enum Intent {
  Op(op~ : @op.Op, edit~ : Bool)
  Edit(id~ : Int, seed~ : String?)
  Select(sel~ : Selection, reveal~ : Bool)
  Center
  Pick(id~ : Int?)
  EditCard(id~ : Int)
  Link(id~ : Int)
  Code(id~ : Int)
  Draw(id~ : Int)
  Paste
  Copy(cut~ : Intent?)
} derive(ToJson)
pub fn keyed(l, sel, k) -> Intent?
pub fn keyed_card(l, picked, k) -> Intent?
pub(all) struct Item { label; key : String?; mark : String?; intent : Intent?; why : String?; items : Array[Item]? }
pub(all) enum Entry { Item(Item); Sep }
pub fn items(l, sel) -> Array[Entry]                                 // 右クリックの行

// core/map — 視点と針と指
pub(all) struct Camera { k; tx; ty }   pub(all) struct Pane { width; height }
pub fn to_world / zoom_to / zoom_at / pan_by / pan_to_show / fit / center_on / pinch
pub fn is_lost / nearest / indicator_for -> (x, y, angle)
pub struct Fingers   pub fn Fingers::down / move / up / only / pinching

// core/map — 欄の重ね（label / card の Placement）
pub fn label_place(b : Box, cam, text_w) -> Placement
pub fn card_place(rect, cam, lines, widest) -> Placement
```

**出口（tree/js）**: `mmmHit(l, x, y, grab) -> Int?`、`mmmRubber(l, x, y, w, h) -> FixedArray[Int]`、
`mmmArrow(l, anchor, key) -> Int?`、`mmmKeyed(l, ids, anchor, key, shift, mod, alt) -> String`（Intent の JSON。無ければ ""）、
`mmmKeyedCard`、`mmmContext(l, ids, anchor) -> String`（行の JSON）、`mmmDrop(l, x, y, dragging) -> String`、
`mmmDropOp(dropJson, ids) -> String`（Op の JSON）、`mmmRects(l, ids) -> FixedArray[(x, y, w, h)]`、
`mmmCardRect(l, block) -> (x, y, w, h)?`（world）、`mmmBlockAt(l, node, i) -> Int?`、`mmmSubtree(l, ids)`、
`mmmFit(l, w, h, margin) -> (k, tx, ty)?`、`mmmCenter(l, ids, k, tx, ty, w, h) -> (k, tx, ty)?`、
`mmmShow(l, id, k, tx, ty, w, h, margin)`、`mmmIndicator(l, ids, k, tx, ty, w, h) -> (x, y, angle)?`、
`mmmLabelPlace(l, id, k, tx, ty, textW) -> (left, top, width, height, fontSize, padding)?`、
`mmmCardPlace(l, block, k, tx, ty, lines, widest)`、`mmmLabel(l, id) -> String?`。

TS の `Intent` / メニューの行は JSON から読む（今の Op と同じ道。1 操作ぶんで小さい）。
`Layout` の JSON と `mmmMetrics` は消える。`coreApi.ts` から `Layout` / `Box` / `metrics` / `rowOf` / `ownerOf` / `rootBox` が消え、
`Handle` と問い合わせの薄い皮だけになる。

## 段（feat/mbt に積む）

| 段 | 何 | 消える境界 |
|---|---|---|
| 1 | 箱の判断 → core/map（select / drop / keys / context / camera / indicator / gesture / geometry / label・card の Placement）。mindmap は問い合わせに | Layout の JSON、metrics |
| 2 | 木の判断 → core（caret の導出 / isNode / copy の切り出し / name / head の frontmatter）。survey は持ち手だけ | View の JSON |
| 3 | 地図の入力と印 → core/render（pointer / key / wheel の受け、輪・矩形・落とし先の線・カードの枠、label / card の欄、menu） | mindmap.ts の大半 |
| 4 | app/ を少しずつ（assets / io / handles / persist / dnd / draw / export / notice / ask / theme / panes / shortcuts …） | — |
| 5 | 出口の名付け直し（`tree/js` →）と coreApi の整理 | — |

段 1 が終わった時点で打鍵は #137 前の main より速くなる（stringify が消えるため）。

## 測った（段 1）

- 5000 ノードで末尾に 1 字打つ 1 打鍵: 48〜76 ms（#137 直後 68〜85、その前の main 50〜67）。
  Layout の JSON（50 ms）が消え、残るのは View の JSON（survey。段 2 で消える）と字の実測
- 段 2 の後: 5000 ノードで 1 打鍵 41〜54 ms（段 1 の 48〜76 から）。View の JSON も消え、残るのは字の実測（measure のキャッシュは 4000 で
  5000 ラベルに足りない — 次の手）
- 段 3 の後: 5000 ノードで 1 打鍵は main と同じ環境で 135〜195 ms（main 183〜199。機械の負荷で絶対値は日により動く — 段 2 の日は 41〜54 だった）。Node で mmmSurvey だけ測ると 14〜18 ms（main 24〜34）。host の関数は名前引き（`_call`）でなく関数そのものを取って直に呼ぶ（measure は 1 打鍵に 5000 回）。mindmap.ts は host の配線だけ（886 → 約 150 行）、map/label・card・pick と
  地図の問い合わせの出口 30 本が消えた。happy-dom の WheelEvent は init の修飾キーを落とす
  （出来事に直に置く）、ResizeObserver は window にしか無い（global には無い）
- **タプルは JS では object（`_0`, `_1` …）になる。** `.d.ts` は `[number, …]` と書くが嘘。
  約束のある型は数・文字列・真偽・`FixedArray`・`T?` だけと読み直す。数の組は
  `FixedArray[Double]` で渡し、ts が長さを確かめる

## 却下した案

- **T: タプルで木と箱を渡す** — 型は付くが、TS が木を読む形は変わらない。判断が core に在れば渡す必要そのものが無い
- **B: struct をそのまま TS に読ませる** — `.d.ts` は `any`。内部表現に頼る
- **wasm-gc** — 境界の綴りが重い形には効かない。計算が太くなった日の手

## 未決

- 段 3 で CodeMirror との境界（state.ts の field に持ち手を置く形）をどうするか
- `Selection` の値の置き場（今は CodeMirror の field）。段 2 で導出が core に行ったとき、値も core の持ち手にするか

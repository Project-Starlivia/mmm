# holder — 選択の持ち主を 1 つに（設計）

issue #49。**選択は 1 つで、持っている側（フォーカスのあるペイン）が決める。**
md が持つ間はカーソルから導く値、地図が持つ間は地図が置いた位置から導く値。
どちらも**テキストの中の位置**から毎サイクル導き、サイクルを越えて持つ id は無い。

## いま何が苦しいか

選択を木の座標（id）で持っている。id は読みのサイクルの中でしか通じないので、
「前のサイクルの id は今のどれか」を誰かが答える必要があり、答えが 3 通りある。

| 場面 | 誰が答えるか |
|---|---|
| md の打鍵 | core の `follow`（目印を編集列で写す）と ts の幽霊 |
| 中身の Delete | core の focus（持ち主） |
| ノードの Delete | ts の `neighbor` が隣を決め、`keep` で目印に追わせる |

さらに、カードの選択には同一性が無く（番号が振り直されても `spots.has` で残る）、
畳まれて箱を失ったノードが選択に残り、地図が持つ間の undo は core を通らず根拠が無い。
core が選択の都合（目印）を知っていて、「core が意味・TS が見せ方」の境界を跨いでいる。

## 何で同一性を取るか

テキストが真実で id が無いとき、再解析をまたぐ同一性の情報源は 3 つしか無い
（2026-09-05 に調べた。CodeMirror / ProseMirror / Emacs marker / Lezer は**位置を編集で写す**、
React / tree-sitter は**前後を比べる**（比べる前に位置を写す）、Logseq / org-mode は
**id をテキストに書く**）。VS Code / Obsidian のアウトラインは同一性を持たず、
**カーソルから毎回導く**。

- md が持つ間は**カーソルから導く**（アウトライン型）。持ち越すものが無い
- 地図が持つ間は**位置**を持ち越す。位置は編集で写るだけで、翻訳は要らない。
  写すのは CodeMirror（薄塗りの装飾を写しているのと同じ `map(tr.changes)`）
- 比較と id は使わない

地図が独自の選択を持つと決めた以上、持ち越すものが 1 つ要る。その最小が位置で、
自作せず CodeMirror に預ける。

## パイプライン

```
入力                      状態（EditorState だけ）                   導出（1 トランザクション = 1 サイクル）
──────────────────        ─────────────────────────────              ─────────────────────────────────────
打鍵 ───────────────────→ doc                                        survey(doc) → View + spots
undo / redo ────────────→ 履歴が doc と selection を戻す                        ↓
地図の操作 → Op → edit ─→ 編集列を dispatch                          choice = derive(view, spots, holder, ranges, anchors)
地図で選ぶ ─────────────→ anchors を effect で dispatch                          ↓ 箱のあるものだけ
                          doc が変わるたび CodeMirror が                 layout → render / 輪 or 枠 / 薄塗り
                          selection と anchors を写す
フォーカスの移動 ───────→ holder（md | map）
```

**状態は 3 つ + 1 bit。** `doc`（真実）、`selection`（md のカーソル。CodeMirror のもの）、
`anchors`（地図の選択の位置。StateField）、`holder`。main.ts の `doc` / `spots` / `choice` は
サイクルの中で導いた値の置き場で、サイクルを越えて意味を持たない。

core と render は選択を知らない。core は「md を読む・操作を md に映す」以外の入力を持たず
（`survey(md)` に引数は無い）、render は「この集合を塗れ」以外を受けない。
選択の規則は `derive` と `anchors` の 2 か所にしか無い。

## 型

```ts
// editor.ts — CodeMirror の StateField。doc の変更で写される（mapPos, assoc = -1）
type Anchors =
  | { kind: "nodes"; at: number[]; anchor: number | null }   // ラベルの頭の位置。anchor は矢印・宛先の基点
  | { kind: "card"; at: number }                              // 中身の原文の頭
  | null;

type Holder = "md" | "map";

// caret.ts — 純関数。選択の規則はここだけ
derive(view: View, spots: Map<number, Spot>, holder: Holder, ranges: Range[], anchors: Anchors): Choice
```

`derive`:

- `holder === "md"` → `caretIds(view, spots, ranges)`（今の輪と同じ）。anchor は主カーソルの
  `head` に掛かるノード。カードは選ばない（カードは地図側の分類で、md にカードは無い。
  カーソルが中身の中なら持ち主のノード）
- `holder === "map"`、`anchors.kind === "nodes"` → 各点に掛かる最深のノード。anchor は
  `anchors.anchor` の点に掛かるノード（無ければ末尾）
- `holder === "map"`、`anchors.kind === "card"` → その点を範囲に含む中身。無ければ何も選ばない
- **選択に居るのは箱のあるものだけ。** 畳まれて埋もれたノード（`fold !== null` の子孫）は
  最後に落とす。`buried(view): Set<number>` は View だけから出る純関数

位置は**ラベルの頭**（`Spot.label`）。follow と同じ理由 — 行の頭だと `## a` → `### a` や
項目の字下げで挿入がちょうど頭に当たり、`assoc` の向きで結果が割れる。ラベルの頭なら
`#` を足しても字下げしても素直にずれ、ラベルの頭に字を打てばその字がラベルの先頭
（assoc = -1 は挿入の前に留まる）。マーカーが丸ごと消えて位置が潰れれば、そこに掛かる
ノードへ移る（follow は死んで空にしていた。ここだけ良くなる）。

`caretIds` の**点の規則を変える**: 点が継ぎ目ちょうどなら**始まる側 1 つ**（`from === p`
の最深のノードが在ればそれ、無ければ自身の文が p で閉じる最深のもの）。範囲は掛かる全部（変えない）。
今は継ぎ目で両側を返し、そのまま選択にすると地図へ移った直後の Delete が 2 つ消す。
輪も継ぎ目で 1 つになる。文書の末尾で追記している間に印が出る（閉じ際は中）のは保つ。

## 動き

**holder** は `focusin` で決める。md ペイン（CodeMirror の中）に入れば `md`、地図ペイン
（ラベル欄・カード欄を含む）に入れば `map`。窓（`<dialog>`）・メニュー・帯へ抜けても
変わらない（粘る）。起動は `md`。

**md → map（引き継ぎ）。** その瞬間の `caretIds` のノードのラベルの頭を `anchors` に書いて
dispatch する。Implicit は行が無いので入れない。以後は `anchors` が持つ。

**map → md。** `anchors` を `null` にして dispatch する。md のカーソルは動かさない
（地図で選んでも動かさない）。どちらの移動も dispatch を通るので、`derive` と塗り直しが
同じ道で走る。

**地図で選ぶ**（クリック・矩形・矢印・Esc・Mod+A・カード）。`Selection`（id）を受けた host が
`spots` で位置に写し、`anchors` の effect を dispatch する。doc は変わらないので parse は
走らず、`derive` だけが走る。`reveal` は anchor の位置へ md をスクロールする（今と同じ。
スクロールはカーソルではない）。

**操作。** `edit(text, op)` の編集列を dispatch → サイクル（parse 1 回）→ 返った focus を
新しい `spots` で位置に写し、`anchors` に dispatch（2 回目。parse は走らない）。focus が
ノードなら nodes、中身なら card。`edit` なら focus のその場編集を開く。編集も focus も
無い（できない操作）ときは `failed`（今と同じ）。編集は有るが focus が無い（最後の根を
消した）ときは `anchors` を null に。holder が md のまま操作が来たら（ファイルの投下、
帯からの宣言の書き換え）、`anchors` は書くが `derive` はカーソルから導くので効かない
— 持ち主が md なら md が決める、で一貫させる。

**core の `delete` はノードを消しても focus を返す。** 消す並びの先頭（文書順）の
**次の兄弟 → 前の兄弟 → 親**。消えるもの（ids とその子孫）は飛ばす。親が Implicit で
子が尽きて消えるなら、その親。根の兄弟は根。何も残らなければ None。兄弟と親は、消した
ノードが見えていれば見えている（畳まれるのは子孫）ので、埋もれたノードに落ちない。
中身を消した focus は持ち主のまま。**「消した後に何を選ぶか」は core の focus 1 本**になる。

**undo / redo。** 規則は無い。履歴が doc を戻し、CodeMirror が `anchors` を写し、`derive` が
走る。位置が消えた点に潰れれば、そこに掛かるノード（隣）。埋もれていれば空。

**md の打鍵。** holder は md なので `derive` はカーソルから導く。`anchors` は null。

**複数選択**は今のまま任意の集合。md 側は範囲・複数カーソルが掛かる全部、地図側は
Mod+クリック / 矩形 / Shift+矢印。Op は既に任意集合を受ける。

## 見せ方

spec.md「二つをまたぐ印」の表はそのまま。意味だけ変わる。

| holder | 地図 | md |
|---|---|---|
| md | 選択を**輪**（内側）で出す | 何も塗らない |
| map | 選択を **`selected`**（枠）で出す | 選択の範囲を薄塗り |

輪と枠はもう「カーソル vs 選択」ではなく「誰が持っているか」の印。`paintSelection` /
`showCaret` / `highlight` の 3 つはそのまま使い、main.ts が holder で振り分ける。

## 消えるもの

- core: `follow.mbt` / `follow_wbtest.mbt`、`Mark` / `Trail`、`mmmSurvey(md, edits, marks)` →
  `mmmSurvey(md)`、`law_wbtest.mbt` の「目印の生存」。`Spot.label` は残る（anchors の位置）
- ts: `ghosts` / `Carried` と `sync` の目印の詰め替え、`Intent.keep`、`select.ts` の
  `neighbor` / `under`、`apply` の `keep` と `MapHost.apply` の第 3 引数、`editor.caret()` の
  フォーカス条件（位置は holder が決めるので、いつでも返す）
- docs: design.md「同一性は 2 系統」→ focus 1 本、follow の行。core.md「同一性 — follow.mbt」
  （地番の `label` の行は理由を anchors に書き換える）。spec.md「二つをまたぐ印」を
  「選択の持ち主」に書き直す

過去の spec（select-design / ops-design）は記録なので触らない。

## 増えるもの

- editor.ts: `anchors` の StateField と effect、`ranges()`（いつでも）、更新の通知に
  「anchors が変わった」を足す（doc が変わらなくても derive を走らせる）
- caret.ts: `derive`、`buried`、点の規則
- main.ts: `holder`（focusin 2 本）、引き継ぎ、`choose` が位置に写して dispatch
- core `op/apply.mbt` の `delete`: 隣の focus。law_wbtest に「Delete の focus は消えていない
  兄弟か親で、埋もれていない」を足す
- design.md「段の間の法則」に所見 4 を足す: **id の順 = 文書順**（select.ts の sort、
  `Layout.order`）、**中身は子より前に書かれる**（caret.ts の自身の文）

## 構成

```
core/op/apply.mbt            delete の focus（次の兄弟 → 前 → 親）
core/edit/law_wbtest.mbt     目印の生存を外し、Delete の focus の法則を足す
core/tree/js/exports.mbt     mmmSurvey(md)
src/coreApi.ts               survey(md)。Mark / Trail / Survey.trails を外す
src/editor.ts                anchors の StateField、ranges()、onUpdate
src/caret.ts                 caretIds（点の規則）、derive、buried
src/map/select.ts            neighbor / under を外す
src/map/keys.ts              Intent.keep を外す
src/mindmap.ts               apply の第 3 引数を外す。塗りは host の値をそのまま
src/main.ts                  holder、引き継ぎ、choose → anchors、apply → focus → anchors
docs/design.md, spec.md, core.md
```

## 試験

- `core/op/*_wbtest.mbt` — Delete の focus の表（次 / 前 / 親 / 複数 / 根 / Implicit の親が消える）
- `core/edit/law_wbtest.mbt` — Delete の focus は消えていない兄弟か親。目印の生存は消す
- `test/caret.test.ts` — 点の規則（継ぎ目で始まる側 1 つ、末尾の閉じ際）、`derive` の表
  （holder × anchors の種類 × 埋もれ）、`buried`
- `test/keys.test.ts` / `test/select.test.ts` — keep / neighbor の行を消す
- `test/coreApi.test.ts` — `survey(md)` の形
- ブラウザは煙試験だけ: md で打つと輪が動く、地図へ移ると輪が枠になり md が薄塗りになる、
  地図で Delete すると隣が選ばれる、undo で戻っても選択が残る、md へ戻るとカーソルの
  ノードが輪になる

## 段

`feat/holder`（`.worktrees/feat/holder`、main から）。1 段 1 コミット、最後に 1 PR で main に
squash。#59（refactor/parts-anywhere）が mindmap.ts と style.css を触っているので、
先に入れば merge で取り込む（rebase はしない）。

1. core — `delete` の focus と法則、`follow` の撤去、`mmmSurvey(md)`
2. ts 純粋層 — caret.ts（点の規則・`derive`・`buried`）、select.ts / keys.ts から keep 系を外す
3. ts 配線 — editor.ts の anchors、main.ts の holder / 引き継ぎ / choose / apply、mindmap.ts
4. docs — design.md / spec.md / core.md

## 将来

- 全ノードのラベルの頭を同じ器（CodeMirror の位置）に置けば、前のサイクルの id と今の id の
  対応が同じ仕組みで取れる。render の差分（上に足すと以降が作り直される）を詰めるときの入口
- 地図で選んだとき md のカーソルも動かす（アウトライン型に寄せる）と `anchors` も要らなくなる。
  「md に戻ったとき手元が飛ぶ」を受け入れるかの話で、今回は動かさないほうを採った

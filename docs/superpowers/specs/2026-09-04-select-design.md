# select — 選択（設計）

UI の段の 1 つ目。**何を選んでいるかを持ち、md の打鍵をまたいでも同じノードを
指し続け、md のカーソルと地図の選択を互いに映す。** 操作は 1 つも無い（Delete も
Enter も次の段）。

この段が要る理由: 選択はこの後の全部（名前・新規・構造・ドラッグ・カード）の
前提で、しかも操作を含まないので「UI + 操作」の結合を持ち込まずに固定できる。

## 位置づけ

```
段 1  選択            ← この設計
段 2  名前と新規      Rename / AddNode / Wrap と、その場編集
段 3  構造            Delete / 並べ替え / 段下げ / 畳み / Flip / 右クリック / +
段 4  ドラッグ
段 5  カードと貼り付け
```

決めの根拠は spec.md「Mindmap 側」「二つをまたぐ印」「指で使う」。ここでは
その意味を**どこが持つか**と、**md が変わったあと選択がどうなるか**だけを決める。

## 選択とは

**値。** `{ ids: number[], anchor: number | null }`（ids は文書順）。main.ts が
1 つ持ち、地図は持たない（旧 UI と同じ向き。地図は値を受けて塗るだけ）。

**選択とカーソルは別のもの。** 操作の対象は選択だけが決め、md のカーソルが
動いても入れ替わらない。外から掴むのが選択、中に居るのがカーソル（spec.md）。

**id は読みのサイクルを越えて持たない**（core.md）。だから選択の値に入っている
id は「いまの木」でしか通じず、md が変わるたびに引き直す。引き直しは下の
「同一性」が担う。

## 同一性 — core の `follow`

**問い: md がこう変わった。前のサイクルで選んでいたノードは、いまどれか。**

答えられる情報源は 2 つしか無い。前後の木の似かより（reconcile。当てにならず、
要らないと決めた）と、**変化そのもの**（エディタが出す編集列。どの範囲が何文字に
置き換わったか正確に持っている）。だから同一性は**位置**で持ち越し、位置を編集列で
写す。写した先に骨格の頭が在れば、それが同じノード。

### 目印はラベルの頭

骨格の行の頭（`#` の位置）ではなく**ラベルの頭**（`## ` の後ろ、`- ` の後ろ）を
目印にする。頭だと `## a` → `### a`（頭に `#` を足す）で挿入がちょうど頭になり、
写す向きで結果が割れる。ラベルの頭なら `#` を足しても字下げしても素直にずれる。

```
"# r\n\n## a\n"        a のラベルの頭は 8
上に "## n\n\n" を 5 に差す
"# r\n\n## n\n\n## a\n"   8 → 15。ラベルの頭が 15 のノードは a。n は 8 なので当たらない
```

ラベルの頭は**読みの規則**（マーカーの読み飛ばし）なので core が地番に足す。
TS で `#` や `-` を読み飛ばすと、規則を UI で書き直すことになる。

### いつ死ぬか

**目印（行の頭からラベルの頭まで = マーカー）が丸ごと消されたら死ぬ。** それ以外は
位置を写し続け、毎サイクル引き直す。当たらない間は黙って持ち越すだけ（捨てない）。

| md の操作 | 結果 |
|---|---|
| 行ごと消す | マーカーが消える → 死ぬ |
| `##` と空白を消して地の文にする | 死ぬ |
| `##` の 1 つだけ消す（`# a`） | マーカーは残る → `# a` に当たる |
| ラベルを全部消して打ち直す | マーカーは残る → 生きる |
| 行を選んでまるごと打ち直す | 死ぬ（書き直したので妥当） |
| 頭にカーソルを置いて `## n` を打ち、それから Enter | 打った瞬間は `## n## a` で当たらない。Enter で写した位置が `## a` のラベルに戻る |
| ラベルの頭が消された範囲の中に落ちる（`## a` の `# a` を消す） | 死ぬ |

「当たらなければ捨てる」だと途中のサイクルで捨ててしまい、「ずっと持つ」だと
消した行の位置が漂って後で別のノードに当たる。マーカーの生死で切るのがその間。

**Implicit** は行が無いので目印も無い。md を触ったら Implicit の選択は捨てる
（稀で、捨てても困らない。将来「最初の子孫の目印 + 段数」で持ち越せる）。

### 関数

```
Spot { from, label: Int?, to }              // 地番。label はラベルの頭。Implicit は None
survey(md) -> (Doc, Map[Int, Spot])         // 今の地番に label が増えるだけ

Mark { from, label }                         // 前のサイクルの目印（TS が地番から抜く）
follow(spots, edits, marks) -> [Int?]       // 目印ごとに、いまの id。無ければ None
```

`edits` は反映の `Edit { from, to, insert }` と同じ形（前の座標、from 順、重ならない）。
写し方は算術: 目印より前の編集ぶんずらす。マーカー `[from, label)` を丸ごと覆う消去が
あれば None。ラベルの頭が消去の内側（`from < label < to`）に落ちても None。
ちょうど頭への挿入（`from == to == label`）は動かさない（挿入の前に留まる）。

**core は状態を持たない。** 前のサイクルの目印は TS が渡す。core が前の md を
覚えることも、読み直すことも無い。

### 呼び出しは 1 回

打鍵ごとの parse は 1 回に保つ。`mmmSurvey(md, editsJson, marksJson)` が
View・地番・引き直した id を 1 度に返す。

```
mmmSurvey(md, edits, marks) -> { view, spots: { id: [from, label?, to] }, carried: [id?] }
```

`mmmViewJson` は lab のために残す。

## 派生値 — 二つをまたぐ印

状態ではなく、毎サイクル引き直す値。

- **カーソルの輪**（md → 地図）: md のカーソル（範囲・複数カーソルも）が掛かる
  **最も深い**ノード。地番は入れ子なので「最深」が旧 caret.ts の「自身の文」と
  同じ意味になる。閉じ際は中と見なす（`n.from <= s.to && n.to >= s.from`）。
  描かれていない（畳まれて埋もれた）ノードには出さない。地図は動かさない
- **md 側の薄塗り**（地図 → md）: 選んでいる id の地番 `[from, to)`（子孫込み）を
  CodeMirror の装飾で塗る。実選択にはしない（カーソルを奪う）。選択が地図で
  変わったときだけ anchor の頭へスクロール（`reveal`）

## 入力 → 選択

全部 `map/select.ts` の純粋関数。DOM と地図は入力を値にして渡すだけ。

| 入力 | 関数 | 意味（spec.md） |
|---|---|---|
| クリック | `click(sel, id, mod)` | 選ぶ。`Shift` は anchor から文書順に範囲、`Mod` は足す・外す |
| 背景ドラッグ（マウス） | `rubber(layout, rect)` | 矩形に触れる箱を全部。ドラッグ中も更新する。指では出ない |
| `↑↓` `←→` | `arrow(layout, anchor, key)` | 上下は同じ深さの列（いとこ込み・端でループ）、左右は画面の向きで親・子（左の枝は鏡像）。子が無ければ先頭へ |
| `Shift+矢印` | `extend(sel, next)` | 行き先を足す。既に選んでいれば今居た側を外す |
| `Mod+A` / `Esc` | `all(layout)` / `none()` | |
| `Home` | （地図の寄せ。選択は変えない） | 選択（無ければ根）を中心へ |
| 指で叩く | `click(sel, id, "none")` | |
| 背景クリック | `none()` | |

`hit(layout, wx, wy)` — world 座標の点がどの箱に居るか（重なりは文書順の後ろが上）。

**背景の左ドラッグは矩形選択になる**ので、パンは `Space+ドラッグ` / 中クリック /
指の 1 本に移る（spec.md「Mindmap 側」の表のとおり。いまは左ドラッグがパン）。

深さは `Box.parent` を辿って数える（Layout は深さを持たない）。左右の向きは
`dirOf` だけが読む。

## 描画

- 選ばれた箱に `selected` クラス（renderer が `nodeEl(id)` に toggle。レイアウトを
  見直さない軽い塗り替え）
- カーソルの輪は world に浮かぶ別の印（ノードの子にすると、カーソルが動くたびに
  中身が作り直される）。本数が変わったときだけ作り足す
- 地図の `Home` / 右下の的は選択を中心へ

## 構成

```
core/tree/build.mbt          Spot に label を足す（head_start / 項目のマーカーの後ろ）
core/tree/follow.mbt         follow(spots, edits, marks)
core/tree/js/exports.mbt     mmmSurvey
src/coreApi.ts               survey(md, edits, marks) -> { view, spots, carried }
src/editor.ts                onChange(text, edits) / onCaret(ranges) / highlight / reveal / caret
src/caret.ts                 caretIds(spots, order, ranges) — 最深
src/map/select.ts            Selection と click / rubber / arrow / extend / all / none / hit
src/mindmap.ts               叩く・矩形・キーを値にして host へ。selected と輪を塗る
src/main.ts                  選択を 1 つ持つ。sync(text, edits) → survey → 選択を引き直す
```

## 試験

- `follow_wbtest.mbt` — 上の表の行を 1 つずつ（挿入・`#` の増減・字下げ・行の削除・
  ラベルの打ち直し・途中のサイクル・Implicit）。地番の指紋に label を足す
- `test/select.test.ts` — 手で組んだ Layout で click / rubber / arrow / extend
- `test/caret.test.ts` — 最深・閉じ際・埋もれたノード
- `test/coreApi.test.ts` — survey の JSON の形
- ブラウザは煙試験だけ（叩いて選べる、打鍵しても選択が残る、輪が動く）

## 段

`feat/select`（`.worktrees/feat/select`、feat/tree から）。1 段 1 コミット、最後に
1 PR で feat/tree に squash。#36〜#38 には依存しない。

1. core — `Spot.label` と指紋
2. core — `follow` と法則の表
3. core — `mmmSurvey`、ts — `coreApi.survey`
4. ts — `select.ts` / `caret.ts`（純粋層と試験）
5. ts — editor（編集列とカーソルを外へ）、mindmap（入力と塗り）、main（配線）
6. docs — spec.md「構成」、core.md「地番」に label と follow

## 将来

「前の表 + 編集列で位置を写し、外れたら作り直す」は差分計算の型で、描画の差分
（先頭に見出しを足すと id が全部ずれて 95ms、末尾なら 24ms）にそのまま流用できる。
`follow` を全ノードに掛ければ、触っていない箱は作り直さずに済む。性能は一通り
作り切ってから。

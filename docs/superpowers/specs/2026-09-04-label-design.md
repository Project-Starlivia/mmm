# label — 名前と新規（設計）

UI の段の 2 つ目。**地図から md を初めて書く。** ラベルをその場で打ち、
Enter / Tab で新しいノードを足して、そのまま打ち始める。それ以外の操作
（消す・並べ替え・畳む・動かす・カード）は次の段。

段 1（選択）と境界（`core.edit`）の上に載る。ここで初めて
「地図の入力 → Op → `core.edit` → CodeMirror → 読み → 描画 → focus」の 1 本が通る。

## 位置づけ

```
段 1  選択            済（PR #39）
段 2  名前と新規      ← この設計
段 3  構造            Delete / 並べ替え / 段下げ / 畳み / Flip / 右クリック / +
段 4  ドラッグ
段 5  カードと貼り付け
```

決めの根拠は spec.md「Mindmap 側」の**編集**と**新規作成**、shortcuts.md の
「編集」「新規作成」。core.md「操作」「境界」。ここでは**どこが何を持つか**だけを決める。

## 操作の入口 — `apply(op)`

main.ts に 1 本。地図はこれを呼ぶだけで、md に触らない。

```
apply(op, edit?):
  r = core.edit(text, op)
  r.edits が空（core が None と言った）→ failed("Couldn't …") で終わり
  editor.dispatch(r.edits)             // CodeMirror の 1 トランザクション。sync が走る
  r.focus が有れば selection = { ids: [focus], anchor: focus }
  edit なら map.beginEdit(focus)
```

- **操作 1 回 = CodeMirror の 1 トランザクション。** undo は CodeMirror の履歴のまま。
  core は状態を持たない（境界の決め）
- **操作の直後は core の focus が選択を決める。** sync は目印で選択を引き直すが、
  新しいノードには目印が無い（前のサイクルに居ない）ので、dispatch の後で上書きする
  （core.md「操作の後は操作の結果から」）
- **できない操作は雑に断る。** `edit` が空を返したら `failed` のしらせを出すだけ。
  押す前に沈める（`Fold` の理由を hover に出す等）は問題が出てから

## その場編集 — `map/label.ts`

地図の中に `<input>` が 1 つ。箱の上に重ねる（旧 UI と同じ形）。

- **開く**: 値はラベル、カーソルは末尾（全選択しない）。Implicit（ラベル無し）も
  開ける — `Rename` で見出しになる（op の決め）
- **打つたびに書く**: `input` のたびに `apply(Rename(id, 値))`。箱の幅がその場で
  追従し、md 側にも字が出ていく。**キャンセルは存在しない** — 打った字はもう md に
  在る（spec.md）。IME の変換中（`isComposing`）は書かず、確定で書く
- **閉じる**: `Enter` / `Esc` / 欄の外を押す / md 側に触る（フォーカスが移る）。
  閉じるときに書くものは無い（もう書いてある）。編集中の `Tab` は無効
- **位置は箱に追従する**: 書くたびに sync が走って箱が変わるので、その後に置き直す。
  寸法（フォント・余白）は `map/metrics.ts` の値を使い、CSS で別に持たない
- 編集中のノードへのクリックは欄のカーソル移動で、確定ではない

打鍵のたびに core が md を読み直すのは md で打つのと同じ道で、性能は同じ。

## 新規 — Op の後に編集開始

全部 `apply(op, edit=true)` の 1 形。ラベルは空 `""` で足す（`## ` が書かれ、
読めば label `""`）。Esc で空のまま残るのは spec.md が許容している。

| 入力 | Op |
|---|---|
| `Enter` | `AddNode(After(anchor), [""])` |
| `Shift+Enter` | `AddNode(Before(anchor), [""])` |
| `Tab` | `AddNode(In(anchor), [""])` |
| `Shift+Tab` | `Wrap(anchor, "")` |
| ノードが 1 つも無いときの `Enter` | `AddNode(In(doc_id), [""])`（最初の根） |

綴り（見出しか項目か）は op が隣に従って決める（core.md「操作の決め」）。
複数選んでいるときは anchor に対して行う（`Tab` / `Shift+Tab` の段下げ・上げは段 3）。

## 「埋めるが先」と「打ち始めれば書ける」

名前がまだ無いノード（label が `""`。Implicit は label 無しなので含めない）を
1 つだけ選んでいるとき:

- `Enter` は足さずに**そのノードの編集に入る**（空のまま足しても名無しが 2 つ並ぶだけ）
- **印字可能な 1 文字**（Space は除く。パンに使う）を打てば、**その字を初期値に**編集に入る。
  Enter を挟まない。文字は `e.key` のまま（CapsLock の正規化を通さない）
- 名前のあるノードでは何も起きない（打鍵でラベルを壊さない）

## キー → 何をするか — `map/keys.ts`

地図のキー処理は**純粋関数 1 つ**にする。DOM と host は入力を値にして渡し、
返った「何をするか」を実行するだけ。段 1 の矢印・Esc・Mod+A・Home もここに畳む。

```
Intent = { kind: "op", op: Op, edit: boolean }   // apply して、edit なら focus を編集開始
       | { kind: "edit", id: number, seed: string | null }   // その場編集に入る（seed は最初の字）
       | { kind: "select", sel: Selection, reveal: boolean }
       | { kind: "center" }

keyed(layout, sel, key: { key, shift, mod, alt }) -> Intent | null
```

ラベルは Layout の Box が持つので View は要らない。

`null` は「拾わない」（ブラウザに渡す）。段 3 以降のキーはここに行を足すだけ。

| キー | Intent |
|---|---|
| `Mod+Enter` | anchor が 1 つ → `edit`。ノードが無い → 最初の根 |
| `Enter` | 無 → 最初の根 / 空ラベル 1 つ → `edit` / それ以外 → `AddNode(After)` |
| `Shift+Enter` | `AddNode(Before)` |
| `Tab` / `Shift+Tab` | `AddNode(In)` / `Wrap`（1 つ選んでいるとき） |
| 印字可能な 1 字 | 空ラベル 1 つ → `edit` with seed |
| 矢印 / `Shift+矢印` / `Esc` / `Mod+A` / `Home` | 段 1 のまま（`select` / `center`） |

## 描画

編集の欄が開いている間、そのノードは選択されたまま（選択の印は外の枠、欄は上に
乗る）。md 側の薄塗りは打つたびに sync が引き直す（目印はラベルの頭なので、ラベル
の中を打っても同じノードに留まる — 段 1 の規則）。

## 構成

```
src/main.ts            apply(op, edit?)。selection の上書きと map.beginEdit の呼び出し
src/map/keys.ts        keyed(layout, sel, key) -> Intent | null（純粋）
src/map/label.ts       LabelEditor — <input> の器。開く / 打つたびに host.rename / 閉じる / 追従
src/mindmap.ts         keydown → keyed → host.act(intent)。ダブルクリック → edit。段 1 の
                       キー処理は keys.ts へ移す
src/coreApi.ts         変更なし（Op と edit は #38）
test/keys.test.ts      keyed の表（上の表を 1 行ずつ）
```

## 試験

- `test/keys.test.ts` — 手で組んだ View / Layout / Selection で、キーごとの Intent
- `test/coreApi.test.ts` — `edit` の往復は #38 で済み
- ブラウザの煙試験: `Enter` で足してそのまま打てる、`Tab` で子、`Shift+Tab` で包む、
  md 側に同時に出る、`Mod+Z` で 1 手戻る、空ノードで字を打つとその字から始まる、
  IME で日本語を打って確定する

## 段

`feat/label`（`.worktrees/feat/label`、feat/tree から）。**#38 と #39 が feat/tree に
入ってから** `git merge feat/tree` で土台を揃える。1 段 1 コミット、最後に 1 PR で squash。

1. ts — `keys.ts`（純粋層と試験。段 1 のキーも移す）
2. ts — `main.apply` と host の口
3. ts — `label.ts` と mindmap の配線、CSS
4. docs — spec.md「構成」、shortcuts.md は既に在る行のまま
5. 煙試験 → PR

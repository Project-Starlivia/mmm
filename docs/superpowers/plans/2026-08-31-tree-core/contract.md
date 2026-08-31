# 新 core 実装契約（確定版）

2026-08-31。憲法（`docs/superpowers/specs/2026-08-29-doc-model-design.md`）・カタログ
（`2026-08-29-op-cases.md`）・型の再設計（`2026-08-31-structure-redesign.md`）を実装の言葉に落とし、
**査読 3 本の指摘 47 件（致命 10 / 重大 18 / 軽微 19）と統括の裁定 7 件を全部反映した確定版**。

これが**後続 5 群の唯一の参照元**。5 群の計画（`g1.md`〜`g5.md`）にある「契約の表に足すこと」
「⚠」の申し送り 21 件は**本書で全部取り込み済み**なので、5 群は申し送りの文言を計画から削ること。
計画と本書が食い違ったら、**本書が正**。

ここに書いた型・関数・コマンド・文言は、すべて使い捨てモジュール（`scratchpad/v2/lock/`・`probe-a/`・
`g1v/`・`g2/`・`g3probe/`・`g4probe/`）で実際にコンパイル・実行して確かめてある。
**通らないものは 1 行も書いていない。** 唯一の例外は G5 で、裁定 7 により**着手前に `scratchpad/v2/g5v/` で
実測して数値を確定させる**（§17 G5）。

---

## §1. 前版から変えたところ（裁定 7 件と査読 47 件の反映位置）

| 裁定 | 変えたところ |
|---|---|
| 1. `<summary>` は details の直後の 1 行を無条件に読み飛ばす | §9 の読みの規則、§19 G2 Task 25、§19 G3 Task 46（カタログ C8）、§9 の爆風半径 |
| 2. ファイルの所有権を厳守。他群のファイルに触らない | §2（`spell.mbt` = G1 / `same_side` = G3 / `reflect_json` = G4 / `test/` = G4）、§19 G4 |
| 3. 依存順の確定 | §3。`reflect_json` を G4 へ移し、G5 の `reflect` は `Reflection` を返す純関数に |
| 4. `flip_side` も頂点集合の正規化を通す | §10 の細目、§19 G5 Task 86 |
| 5. 腕数の定義を 1 つに統一 | §11。契約が定義を持ち、逐語コメントも契約が固定する |
| 6. 契約への申し送り 21 件は契約側を先に直す | §5（台帳）。全 21 件を本文へ取り込み済み |
| 7. G5 は実測で裏を取る | §17 G5 の冒頭。`scratchpad/v2/g5v/` で Task 84〜92 を実走 |

査読 47 件の処理は §18 の台帳に 1 件ずつ載せた。**致命 10 件・重大 18 件は 1 件も落としていない。**

---

## §2. ファイルの所有権

**表に無いファイルは作らない。** 所有者だけがそのファイルを書く。
**他群のファイルには 1 バイトも書かない — スタブも、投機的な追加も、警告を消すための小細工も禁止。**
他群のファイルに直しが要ると分かったら、**そのファイルを書かずに該当群へ差し戻す**（§17 の差し戻しの手順）。

### 新しく作るファイル（33 本）

| パス | 所有 | 責務 | 他群の権限 |
|---|---|---|---|
| `core/tree/moon.pkg` | **G1** | `pkgtype(kind: "library")` の 1 行 | 読み |
| `core/tree/doc.mbt` | **G1** | 型の定義。木そのもの | 読み（全群が型を使う） |
| `core/tree/check.mbt` | **G1** | 関係的な不変条件の検査 | 読み（G5 が `is_item` を呼ぶ） |
| `core/tree/sig.mbt` | **G1** | 指紋。法則 1・2 の比較子 | 読み（全群のテストが `sig` を呼ぶ） |
| `core/tree/scan.mbt` | **G1** | md → Token の列 | 読み（G2 が `scan` を呼ぶ） |
| `core/tree/spell.mbt` | **G1** | 正規形の綴り定数 1 か所 + `eol_text` | 読み（G2・G3・G4 が `spell` を読む） |
| `core/tree/make_wbtest.mbt` | **G1** | 木を手で組む葉の道具 `make_*` 6 本 | **呼ぶ**（G3・G4・G5 のテストが使う）。定義は足さない |
| `core/tree/sig_wbtest.mbt` | **G1** | 指紋の固定 | — |
| `core/tree/check_wbtest.mbt` | **G1** | 6 条件の破れ | — |
| `core/tree/scan_wbtest.mbt` | **G1** | Token の列・方言・封筒・改行の流儀 | — |
| `core/tree/parse.mbt` | **G2** | Token の列 → Doc | 読み（呼ぶのは `parse` だけ） |
| `core/tree/parse_wbtest.mbt` | **G2** | 読みの見張り | — |
| `core/tree/serialize.mbt` | **G3** | Doc → 正規形の md | 読み（`serialize` と `same_side` を呼ぶ） |
| `core/tree/serialize_wbtest.mbt` | **G3** | 正規形の逐語 | — |
| `core/tree/tool.mbt` | **G5** | 道具 5 本と `Sub`。型の異種性の牢獄 | — |
| `core/tree/op.mbt` | **G5** | move / flipSide / delete と回復 | 読み（3 本の操作を呼ぶ） |
| `core/tree/diff.mbt` | **G5** | `Edit` / `Reflection` / `reflect` / `diff` / `apply` | 読み（G4 が `Reflection` を受ける） |
| `core/tree/tool_wbtest.mbt` | **G5** | 道具と腕数 | — |
| `core/tree/op_wbtest.mbt` | **G5** | move 9 組合せ / flipSide / delete / 拒否 | — |
| `core/tree/diff_wbtest.mbt` | **G5** | diff → apply の往復・自己検査 | — |
| `docs/ops.md` | **G5** | 回復・拒否・爆風半径・腕数の判定 | — |
| `core/tree/json.mbt` | **G4** | `quote` / `strings` / `hex` / `reflect_json` | — |
| `core/tree/json_wbtest.mbt` | **G4** | 逃がし規則と境界の JSON | — |
| `core/tree/project.mbt` | **G4** | Doc → MindmapTree の JSON | — |
| `core/tree/project_wbtest.mbt` | **G4** | バケツ分け・buried・implied | — |
| `core/tree/laws_wbtest.mbt` | **G4** | 木の生成器と法則 1 の本丸 | — |
| `core/tree/js/moon.pkg` | **G4** | `foreign_library` + import 1 本 | — |
| `core/tree/js/exports.mbt` | **G4** | `#export_name` 7 本 | — |
| `test/_tree.ts` | **G4** | 新 core の窓口・生成器・コーパス・縮小器 | — |
| `test/treeLaws.test.ts` | **G4** | 法則 1・2・3 | — |
| `test/treeDialect.test.ts` | **G4** | 法則 4（外部審判 + 方言表 + 読みの裁定） | — |
| `test/treeCases.test.ts` | **G4** | カタログ C1〜C17 | — |
| `test/treeOps.test.ts` | **G4** | 操作の性質のファズ（設計は G5 由来） | — |

### 変更するファイル（4 本）

| パス | 所有 | 変更 |
|---|---|---|
| `package.json` | **G4** | scripts に `test:core` の書き替えと `fmt:doc` の追加 |
| `test/tsconfig.json` | **G4** | 死んだ 2 行（`"../src/relevel.ts"` / `"../src/app/externalChange.ts"`）を掃く |
| `.github/workflows/ci.yml` | **G4** | 新パッケージのテスト・整形・`Total tests: 0` の検知 |
| `docs/superpowers/specs/2026-08-29-op-cases.md` | **G3** | カタログ C8 の期待 md を `<summary>` 込みに訂正（Task 46）。**他のケースには触らない** |

### 触らないファイル

`src/` の全部（`coreApi.ts` / `main.ts` / `paste.ts` を含む）/ 旧 core（`core/*.mbt` と `core/js/`）/
`test/_helpers.ts` / 既存の `test/*.test.ts` / `core/moon.mod` / `core/moon.pkg`。
`moon.mod` にも上位の `moon.pkg` にも新パッケージの登録は要らない（ディレクトリに `moon.pkg` を置くだけで発見される）。

### 所有権が動いたもの（前版からの差分。理由つき）

| もの | 前版 | 確定版 | 理由 |
|---|---|---|---|
| `core/tree/spell.mbt` | G3 | **G1** | G2 Task 22 / 25 が `spell` を読むのに G2 と G3 は並行。G1 が置けば依存が消える（裁定 2）。査読 3 は「G3 据え置き + 依存順を割る」を提案したが、**裁定 2 が G1 を選んだ**ので所有ごと動かす |
| `same_side` | G3 と G4 に 1 本ずつ | **G3 の 1 本だけ** | 同じ判定が 2 か所に割れる負債。G4 は `same` を作らず `same_side` を呼ぶ（裁定 2） |
| `hashes` | G2 と G4 に 1 本ずつ | **G2 の `hashes(level, label) -> String` だけ** | 同一パッケージのトップレベル名は一意（`[4051]`）。7 個以上の `#` の読みは G1 の `head_at` が既に持つので G4 版は不要（裁定 2） |
| `reflect_json` | G5（diff.mbt） | **G4（json.mbt）** | `reflect_json` は `quote` を呼ぶ。G4 へ移せば G5 が G4 に依存しなくなり、依存順が 1 本道になる（裁定 3） |
| `test/treeOps.test.ts` | G5 | **G4** | `test/` は G4 の所有（裁定 2）。G5 → G4 の順なので、G4 の `_tree.ts` と `exports.mbt` を待つ必要も消える |
| `docs/superpowers/specs/2026-08-29-op-cases.md` | 誰も持たない | **G3** | C8 の期待 md の訂正が要る（裁定 1）。G3 Task 46 が唯一の書き手 |

---

## §3. 依存順（裁定 3）

```
G1（型・走査・spell・指紋・不変条件）
  │
  ├─→ G2（読み: parse）      ┐
  └─→ G3（書き: serialize）  ┘ … 並行。互いの関数を 1 つも呼ばない
        │
        └─→ G5（道具・操作・反映 reflect）
              │
              └─→ G4（境界・投影・法則・カタログ・CI）
```

**根拠:**

1. **G2 と G3 は G1 の型・`spell`・`sig`・`check` の上にだけ建つ。** G2 は `serialize` を呼ばず、
   G3 は `parse` を呼ばない。両者が使う名前は `spell`（G1）と、G4 だけが跨ぐ `same_side`（G3）に限られる
2. **G5 の `reflect` は `parse`（G2）と `serialize`（G3）を実際に呼ぶ。** 前版の「parse / serialize が
   スタブでも通る」は成立しない（裁定 2 により**スタブも他群のファイルへの書き込みなので禁止**）。
   よって G5 は G2・G3 の完了を待つ
3. **G5 は G4 に依存しない。** `reflect_json` を G4 へ移したので、`quote` を待つ理由が消えた
4. **G4 が最後。** 境界（`exports.mbt`）は 5 群全部を呼び、法則 1・2・4 とカタログは全部が揃って初めて緑になる。
   `reflect_json` は G5 の `Reflection` を受ける
5. **帰結**: G4 のタスクは「テストを書く → 赤を確認 → 該当群へ渡す」ではなく、
   **G1〜G3・G5 が緑にした後に走る検証タスク**。G4 の Step 3 には**自分の所有ファイル内の実際のコード**を書く。
   赤が出たら他群へ差し戻す（§17 G4 の差し戻し表）

**群の中の着手順**（各群の計画のとおり。変更点だけ記す）:

- G1: Task 1 → 2 / 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → **10.5（新設: spell.mbt）** → 11
- G2: Task 20 → 26 の一直線
- G3: Task 40 → 46 の一直線（Task 40 は「G1 が置いた `spell.mbt` の値を固定する」だけに変わる）
- G5: Task 80 → 92 → **94**（旧 Task 93 は G4 Task 72 へ移管）
- G4: Task 60 → 71 → **72（新設: treeOps.test.ts）**

---

## §4. 名前の割り当て（パッケージ内で一意）

同一パッケージ `mmm-app/core/tree` のトップレベル名は、`*_wbtest.mbt` を含む**全ファイルで一意**でなければ
ならない（`Error: [4051] The toplevel identifier X is declared twice`）。
**下の表に無い名前をトップレベルに置いてはならない。** 足したくなったら、まず本書を直す。

### G1 — `doc.mbt` / `check.mbt` / `sig.mbt` / `scan.mbt` / `spell.mbt` / `make_wbtest.mbt` ほか

| 住所 | 名前 |
|---|---|
| `doc.mbt`（型） | `Doc` `Root` `Wing` `Branch` `Node` `Sign` `Side` `Eol` `Block` `Content` `Verdict` |
| `doc.mbt`（構築子） | `Implicit` `Explicit` `Heading` `Item` `Right` `Left` `Lf` `Crlf` `Content` `Rule` `Opaque` `Image` `Link` `Code` `Svg` `Applied` `Rejected` |
| `doc.mbt`（定数） | `doc_id`（= 1）`first_id`（= 2） |
| `check.mbt` | `check`（pub）`fault` `check_branch` `check_one` `check_kin` `is_item` |
| `sig.mbt` | `sig`（pub）`sig_root` `sig_branch` `sig_node` `sig_blocks` `sig_content` `sig_text` |
| `scan.mbt`（型） | `Token`（構築子 `Blank` `Head` `Bullet` `Bar` `Fence` `Open` `Close` `Verse`）`Scan` |
| `scan.mbt` | `scan`（pub）`Row` `rows_of` `row_of` `envelope` `is_front` `head_at` `setext_at` `setext` `bar_at` `bullet_at` `fence_at` `fenced` `close_len` `indented` `is_fold_open` `is_fold_close` `opens_comment` `closes_comment` `starts` `strip` `trim_end` `is_blank` `cut` `joined` |
| `spell.mbt` | `Spell` `spell`（pub）`eol_text`（pub） |
| `make_wbtest.mbt` | `make_doc` `make_root` `make_wing` `make_branch` `make_head` **`make_item`** |
| `scan_wbtest.mbt` | `scan_sig` `scan_flat` |
| `sig_wbtest.mbt` / `check_wbtest.mbt` | **ヘルパを持たない**（`sig_` は `sig.mbt` が使い切っている。木は `make_*` で組む） |

- **`make_list` → `make_item` に改名。** 型は `Sign::Item`、G3 も独立に `write_item` と名乗った。
  同じものを 2 つの語彙（Item / list）で呼ばない
- `make_wbtest.mbt` の役割は「**G1 が置き、G3・G4・G5 のテストが葉の組み立てに使う**」。
  前版の「全群が使う」は事実に反していたので、**事実のほうを揃える**（§18 R1-12 / R3-16）

### G2 — `parse.mbt` / `parse_wbtest.mbt`

`parse`（pub）`read` `Frame` `Build` `Pend` `top` `item` `bud` `to_root` `to_branch` `bone`
`grow` **`hashes`**（`(level : Int, label : String) -> String`）`shed` `knit` `card` `pair`
`spill` `spill_at` **`is_summary`**（新設・裁定 1）/ テスト: `parse_sig` `parse_ids` `parse_walk` `parse_faults`

### G3 — `serialize.mbt` / `serialize_wbtest.mbt`

`serialize`（pub）`Voice`（構築子 `Loud` `Quiet`）`Pen` `is_loud` `put` `split_nl` `repeat`
`write_front` `write_root` `write_wings` `turned` **`same_side`** `write_branch` `inner_steps`
`write_node` `write_fold_open` `write_fold_close` `write_body` `write_blocks` `write_block`
`write_content` `fence_for` / テスト: `write_tree` `write_head` `write_item` `write_gap`

- **`write_of` と `write_wing` は削除**（`make_doc` / `make_wing` と 1 バイトも違わない）
- 残す 4 本は `make_*` の合成として書く（生の struct リテラルを書かない）。例:
  `fn write_head(id : Int, label : String, children : Array[Branch]) -> Branch { make_branch(id, make_head(label), children) }`
- **`split_nl` / `repeat` / `same_side` は名前が汎用。** 他群は再定義せずこれを呼ぶ
  （`Side` に `Eq` は無いので `same_side` は G4 の `map_bucket` が要る）

### G4 — `json.mbt` / `project.mbt` / `laws_wbtest.mbt` / `js/exports.mbt` ほか

| 住所 | 名前 |
|---|---|
| `json.mbt` | `quote`（pub）`strings`（pub）`hex` **`reflect_json`（pub）** |
| `project.mbt` | `project`（pub）`map_bucket` `map_branch` `map_node` `map_card` |
| `project_wbtest.mbt` | （新設なし。木の組み立ては G1 の `make_*` を呼ぶ） |
| `json_wbtest.mbt` | ヘルパを持たない（`json_` を予約） |
| `laws_wbtest.mbt` | `Law` `law_pick` `law_id` `law_head_label` `law_item_label` `law_block` `law_side` `law_node` `law_branches` `law_branch` `law_wings` `law_implicit_root` `law_doc` |
| `js/exports.mbt`（別パッケージ） | `sig` `format` `check` `project` `move_nodes` `flip_side` `delete_nodes` |
| `test/_tree.ts` | `Edit` `Reflection` `Card` `MapNode` `MapBranch` `MapTree` `Mindmap` `doc` `mbt` `apply` `cardText` `rng` `randomDoc` `pathological` `shrink` `corpus` `fuzzCases` `brief` |
| `test/treeDialect.test.ts` | `outerNodes` `mmmNodes` `DIALECT` **`READING`** |
| `test/treeCases.test.ts` | `idOf` |
| `test/treeOps.test.ts` | `idsOf` `holds` |
| `package.json` | `fmt:doc` |

- **`same` は作らない。** `map_bucket` は G3 の `same_side` を呼ぶ（§18 R2-12 / R3-10）
- **`hashes(line, at) -> Int` は作らない。** 7 個以上の `#` は G1 の `head_at`（level に上限なし）が既に読む（§18 R1-02 / R2-03 / R3-01）
- `project_wbtest.mbt` は新しいヘルパを置かない（木の組み立ては G1 の `make_*`）。
  どうしても要るときの接頭辞は **`proj_`**（`map_` は `project.mbt` が使い切っている）
- `js/exports.mbt` は別パッケージなので `sig` / `check` / `project` が `core/tree` と同名でも衝突しない

### G5 — `tool.mbt` / `op.mbt` / `diff.mbt`

| 住所 | 名前 |
|---|---|
| `tool.mbt` | `Sub`（構築子 `Tree` `Part`）`resolve` `find_in` `branch_at` **`kin_at`** **`parent_at`** `pluck` `graft` `amend` `set_side` `as_root` `as_branch` |
| `op.mbt` | `move_nodes`（pub）`flip_side`（pub）`delete_nodes`（pub）`crown` **`ahead`** `under` `dest` `clamp` `flipped` `pick` `missing` `cyclic` `shallow` `prune` `alive` `conform` `sink` `raised` `itemed`（private 16 本） |
| `diff.mbt` | `Edit`（pub(all)）**`Reflection`（pub(all)）** `reflect`（pub）`diff`（pub）`apply`（pub）`safe_edits` `line_start` `line_end` `code_at` |
| wbtest | `tool_doc` `tool_fold` `op_doc` `op_said` `op_shape` `op_implied` `op_limb` `op_signs` `op_sign_branch` `op_mark` `diff_*`（`diff_` 接頭辞。`diff_holds` を含む） |

- **`ahead` を予約する**（`crown` が文書順に挿すのに使う。前版は一覧から漏れていた。§18 R2-14 / R3-11）
- **`op_head` / `op_item` は削除**（`make_head` / `make_item` を呼ぶ）
- **`under` の第 2 引数は `anc`、`crown` の局所変数は `keep`。** G2 の `fn top(b : Build) -> Frame` を
  影にしない（§18 R3-12）
- `Sub` は `priv`。**op の外に出さない**

---

## §5. 申し送り 21 件の取り込み台帳（裁定 6）

5 群が「契約の表に足すこと」と書いた 21 件は、全部この確定版に入っている。
**5 群は自分の計画から申し送りの段落を削ること**（残すと、直った契約と食い違ったままの指示が残る）。

| # | 出どころ | 申し送り | 取り込んだ場所 |
|---|---|---|---|
| S1 | G1 | §12 の表に `core/tree/make_wbtest.mbt`(G1) を足す | §2 の所有表・§13 のテスト表。加えて `make_*` を全群の葉の組み立てに統一（§4） |
| S2 | G2 | `spell.mbt` は G1 が置く | §2（所有 = G1）・§17 G1 Task 10.5 |
| S3 | G2 | Token の `col` / `hang` / 改行の前提 3 つ | §6「走査の前提」 |
| S4 | G2 | `moon -C core test tree/<file>_wbtest.mbt` を §10 の表に | §14 のコマンド表 |
| S5 | G3 | モデルの中の改行は常に LF・末尾に改行を含まない（4 か所） | §6「モデルの中の文字列」 |
| S6 | G3 | `Opaque` / `Svg` / `Code.text` は列 0 基準の逐語 | §6「モデルの中の文字列」 |
| S7 | G3 | parse は `<summary>` を畳みの飾りとして読み飛ばす | §8（裁定 1 で**位置つきの規則に強化**） |
| S8 | G3 | カタログ C8 の期待 md が `<summary>` を欠く | §8 の C8 逐語・§2 の所有表（op-cases.md = G3）・§17 G3 Task 46 |
| S9 | G3 | ファイル指定のテストコマンドを §10 の表に | §14（S4 と同じ結論。2 群から独立に出たので 2 件と数える） |
| S10 | G3 | 法則 4 は封筒を剥がした後の本文に掛ける | §17 G4 Task 69 |
| S11 | G4 | §12 に `core/tree/json_wbtest.mbt` を足す | §13 のテスト表 |
| S12 | G4 | §12 に `core/tree/laws_wbtest.mbt` を足す | §13 のテスト表 |
| S13 | G4 | `project_wbtest.mbt` の接頭辞を `map_` → `proj_` | §4 の名前表・§13 |
| S14 | G4 | `test/_tree.ts` に 4 つ（`pathological` / `shrink` / 強化 `randomDoc` / 出力の存在検査） | §11 に 3 つを採る。**「出力の存在検査」は却下** — 静的 import が先に `ERR_MODULE_NOT_FOUND` で落ちるので到達しない（§18 R1-14 / R2-10 / R3-13） |
| S15 | G4 | 「反映 v0 は全文正規形」の帰結（C7 の `---`→`***`、C15 の無操作でも綴りは正規形へ寄る） | §12「反映 v0 の帰結」 |
| S16 | G5 | `kin_at` / `parent_at` を道具に足す | §4 の名前表・§7 の道具層 |
| S17 | G5 | op.mbt の private ヘルパ 16 本 | §4 の名前表 |
| S18 | G5 | diff.mbt の private ヘルパ 5 本 | §4 の名前表 |
| S19 | G5 | `test/treeOps.test.ts` を §12 の表に | §13 のテスト表（**所有は G4**。裁定 2） |
| S20 | G5 | `docs/ops.md` を所有ファイルに | §2 の所有表（G5） |
| S21 | G5 | 腕数の定義と、その定義で測り直した数字 | §7「腕数の定義」（裁定 5） |

---

## §6. 型の全文

`core/tree/doc.mbt`（**この逐語で `moon check` 0 errors**。前版から 1 バイトも変えていない）。

```moonbit
// 型の定義。md が表現できる構造だけを、md の語彙で持つ木。
// 綴り（空行の数・マーカーの銘柄）は持たないので Ast ではない。

///|
/// 文書は深さ 0 の器。frontmatter と eol は綴りのダイヤルで、意味は body と roots。
pub(all) struct Doc {
  frontmatter : String? // 封筒の逐語（`---` の柵は含まない）
  eol : Eol
  body : Array[Block] // 最初の骨格より前の散文
  roots : Array[Root]
}

///|
/// 親が文書のノード。root 専用の操作語彙は無い（文書を親とする move / add）。
pub(all) struct Root {
  id : Int
  node : Node
  wings : Array[Wing]
}

///|
/// 翼 = 場所。占有者を問わず側を持ち、id は持たない。
/// side が「root 直下の翼 → 側」の部分写像であることが、そのまま型になっている。
pub(all) struct Wing {
  side : Side
  branch : Branch
}

///|
/// 深さ 3 以降は一様。
pub(all) struct Branch {
  id : Int
  node : Node
  children : Array[Branch]
}

///|
/// 骨格行の有無。Implicit は「飛びが綴り」なので label も body も型ごと無い。
pub(all) enum Node {
  Implicit
  Explicit(sign~ : Sign, label~ : String, folded~ : Bool, body~ : Array[Block])
}

///|
/// 見出しか項目か。Implicit を入れないのは setSign の引数型だから。
pub(all) enum Sign {
  Heading
  Item
}

///|
pub(all) enum Side {
  Right
  Left
}

///|
pub(all) enum Eol {
  Lf
  Crlf
}

///|
/// 骨格に貼り付く中身。Content だけが絵になる（Rule と Opaque は buried）。
pub(all) enum Block {
  Content(Content)
  Rule
  Opaque(String)
}

///|
pub(all) enum Content {
  Image(alt~ : String, src~ : String)
  Link(text~ : String, href~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
}

///|
/// 操作の結果。拒否の理由は文字列 1 本（境界では reason に載る）。
pub(all) enum Verdict {
  Applied
  Rejected(String)
}

///|
/// 文書の id。親を指すときの番兵で、どのノードも名乗ってはならない。
pub let doc_id : Int = 1

///|
/// parse が配る最初の id。文書順に 1 つずつ増える。
pub let first_id : Int = 2
```

### 確定した細目（実測に基づく）

- **`mut` は 1 つも要らない。** 不変 struct + 可変 Array で、道具 5 本も操作 3 本も書ける
  （唯一の例外は G2 の `Build` の 1 ビット。§8）
- **可視性は全型 `pub(all)`。** 消去法で 1 択:
  - `priv` は不可 — `pub fn parse(text : String) -> Doc` が `[4046] A public definition cannot depend on private type` で落ちる
  - `pub` では別パッケージから**構築できない**（`[4036] Cannot create values of the read-only type`）
  - `pub` に封じ込めの効果は無い — **配列の中身は `pub` のままでも素通しで壊せる**（実測）
- **`String?` はそのまま通る**（`match doc.frontmatter { Some(s) => …; None => … }`）
- **相互再帰は宣言順に関係なく通る**
- **ラベル付き enum ペイロードの綴り**: 定義と `match` は `~`、**呼び出し側だけ `=`**。
  `Explicit(sign=Heading, label="a", folded=false, body=[])` が正。`sign~=Heading` は `[3016]`
- **別パッケージからの列挙子は修飾が要る**（式の位置）: `@tree.Left` / `@tree.Implicit`。
  `match` のパターン位置では無修飾で通る
- 構築子名はパッケージ内で一意。`Sign::Item` が居るので、`Token` のリスト項目は **`Bullet`**

### 走査の前提（Token の意味。申し送り S3）

`scan` が出す `Token` の座標は、G1 と G2 がこの 3 つで揃う。**`scan_wbtest.mbt` と `parse_wbtest.mbt` の
両方がこれを固定する。**

| # | 前提 | 例 |
|---|---|---|
| 1 | `col` = **行頭の空白を除いた最初の非空白の列**（トークン自身の書き出し位置）。タブは 4 で数える | `  - a` の Bullet は `col = 2`、`## a` の Head は `col = 0` |
| 2 | `Bullet.hang` = **ラベルの始まる列**（マーカーと後ろの空白を食べた後）。子の字下げと領土の境目はこれ | `  - a` は `hang = 4`、`- a` は `hang = 2`、`10. a` は `hang = 4` |
| 3 | `Fence.text` と `Verse.text` の**改行は LF、行頭の字下げは剥がしてある**。Verse は物理行 1 本で 1 枚（綴じるのは parse の仕事） | CRLF の文書でも `Fence.text` は `"a\nb"` |

### モデルの中の文字列（申し送り S5・S6）

- **改行は必ず `"\n"`、末尾に改行を含まない。** 対象は `Doc.frontmatter` / `Block::Opaque` /
  `Content::Code.text` / `Content::Svg` の 4 か所。`Eol` は `Doc` のダイヤル 1 つだけが持ち、
  serialize が書き出しのときに翻訳する。**`scan`（G1）と `parse`（G2）は行末の `\r` を落として持つ**
  — ここが揃っていないと CRLF 文書で法則 1 が破れる
- **`Opaque` / `Svg` / `Code.text` は列 0 基準の逐語で持つ。** 項目の中身の列への字下げは
  serialize が塊ごと足す（相対字下げは保たれる）

---

## §7. 不変条件

型で死んだもの（**ここに書かない**）: doc の汚れ / 深いノードの side / 側つきで綴り無し /
implicit×label / implicit×body / implicit×folded / implicit×Item / setSign(Implicit) / sides と children の整合。

残る関係的なものは 6 つ。**`check(doc) -> Array[String]` は破れを全部集めて返す**（空 = 健全）。
違反の綴りは 1 つだけ — `<破れ> (id=<n>)`。

| # | 条件 | 違反メッセージ（逐語） |
|---|---|---|
| 1 | id は文書内で一意。番兵 `doc_id`（= 1）を先に登録してから走査するので、文書 id を名乗ったノードもここで落ちる | `id が重なっている (id=1)` |
| 2 | Implicit は子を持つ限りにおいて存在する（子が空なら居てはならない） | `Implicit に子が無い (id=7)` |
| 3 | Implicit の前の兄弟はすべて項目（見出しも Implicit も前に置けない — どちらも見出しを綴るので、飛びが後ろの兄弟に飲まれて読み戻せない） | `Implicit の前に項目でない兄弟が居る (id=7)` |
| 4 | **Implicit の子に項目は居ない**（子は見出しか Implicit。Implicit の連鎖は C16 の綴りそのものなので合法）。id は違反した**子**を指す | **`Implicit の子が項目 (id=7)`** |
| 5 | 同じ親の子は項目が先、見出しが後（Implicit は見出しの側）。id は違反した**項目**を指す | `見出しの後ろに項目が居る (id=7)` |
| 6 | 単調性 — 項目の子孫はすべて項目（Explicit(Item) 以外は違反。Implicit も違反） | `項目の子孫が項目でない (id=7)` |

`(id=` と `)` の間は 10 進の整数。前後に空白は無い。`fault()` は 1 本だけ:

```moonbit
///|
/// 違反の綴りは 1 つ。`<破れ> (id=<n>)`。
fn fault(what : String, id : Int) -> String {
  what + " (id=" + id.to_string() + ")"
}
```

**条件 4 の文言とメッセージを直した理由**（前版は「Implicit の子はすべて見出し」/
`Implicit の子が見出しでない`）: 実装は `if is_item(k.1) { fault(...) }` で **Implicit の子に Implicit を許す**
（許さないと C16 の `Ni[Ni[Neh_1:b()[]]]` が check を通らない）。`Node` は Implicit / Heading / Item の
3 つしかないので、破れの実体はちょうど「子が項目」。**メッセージが破れの実体を名指していないのは負債**なので、
文言もメッセージも実体に揃える。査読は「G1 のテストが逐語で固定しているから据え置き」を提案したが、
G1 は未着手であり据え置きの理由が成立しない。

**条件 3 が「見出しの兄弟が前に居ない」でなく「前の兄弟がすべて項目」なのはなぜか**: Implicit の子は
見出しか Implicit（条件 4）なので、Implicit 自身も見出しを綴る。`[Item, Implicit, Item, Implicit]` は
前者の綴りでは通ってしまうが、書き出すと 2 本目の Implicit の子が 1 本目の見出し節に食われて読み戻せない。
**綴れる形だけを合法にする。**

---

## §8. 指紋（sig）の形式

法則 1（`parse(serialize(M)) = M`）と法則 2（serialize の冪等）の**唯一の比較子**。id を含まない。
Doc / Root / Wing / Branch の 4 型を歩く。

文字列はすべて**長さ前置**（`<10進の長さ>:<中身>`）なので、逃がし規則が要らず、どの文字が中身に入っていても
曖昧さが構造的に生じない。長さは UTF-16 コード単位（`String::length()`）。

### 文法（1 文字も曖昧さを残さない）

```
Doc      := "D" front eol blocks "[" root* "]"
front    := "-"                                  frontmatter = None
          | "+" text                             frontmatter = Some
eol      := "n"                                  Lf
          | "r"                                  Crlf
root     := "R" skel "[" wing* "]"
wing   := ">" branch                             side = Right
          | "<" branch                             side = Left
branch     := "N" skel "[" branch* "]"
skel     := "i"                                  Implicit
          | "e" sign fold text blocks            Explicit
sign     := "h"                                  Heading
          | "l"                                  Item
fold     := "^"                                  folded = true
          | "_"                                  folded = false
blocks   := "(" block* ")"
block    := "c" content                          Content
          | "r"                                  Rule
          | "o" text                             Opaque
content  := "i" text text                        Image(alt, src)
          | "l" text text                        Link(text, href)
          | "c" text text                        Code(info, text)
          | "s" text                             Svg
text     := <10進の長さ> ":" <中身の逐語>
```

区切り文字は一切入れない（`join` しない）。`[`〜`]` と `(`〜`)` が入れ子の唯一の目印。

### 例 3 つ（**すべて `moon test` で実測**）

**例 1** — `# r` + `## a`

```
D-n()[Reh_1:r()[>Neh_1:a()[]]]
```

**例 2** — `# r` + `---` + `#### b`（C16。先頭翼が左、占有者は Implicit 2 段）

```
D-n()[Reh_1:r()[<Ni[Ni[Neh_1:b()[]]]]]
```

**例 3** — 封筒つき・CRLF・doc の散文・畳んだ項目 root・飾りの水平線・コードカード

```
D+17:image-folder: imgr(o5:intro)[Rel^1:c(r)[>Neh_1:x(cc2:js1:1)[]]]
```

読み方: `D` → `+17:image-folder: img`（封筒）→ `r`（CRLF）→ `(o5:intro)`（doc の散文 1 枚）→
`[` `R` `el^1:c`（Item・畳んだ・ラベル `c`）`(r)`（飾りの水平線 1 本）`[` `>` `N` `eh_1:x`
`(cc2:js1:1)`（`js` のコード `1`）`[]` `]` `]`。`imgr` の `r` が eol の印なのは、直前の text が
長さ前置で終端が確定しているから。

### 実装（`core/tree/sig.mbt`、`moon fmt` 済みの逐語）

```moonbit
///|
pub fn sig(doc : Doc) -> String {
  let sb = StringBuilder::new()
  sb.write_string("D")
  match doc.frontmatter {
    None => sb.write_string("-")
    Some(s) => {
      sb.write_string("+")
      sig_text(sb, s)
    }
  }
  sb.write_string(
    match doc.eol {
      Lf => "n"
      Crlf => "r"
    },
  )
  sig_blocks(sb, doc.body)
  sb.write_string("[")
  for r in doc.roots {
    sig_root(sb, r)
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn sig_root(sb : StringBuilder, root : Root) -> Unit {
  sb.write_string("R")
  sig_node(sb, root.node)
  sb.write_string("[")
  for b in root.wings {
    sb.write_string(
      match b.side {
        Right => ">"
        Left => "<"
      },
    )
    sig_branch(sb, b.branch)
  }
  sb.write_string("]")
}

///|
fn sig_branch(sb : StringBuilder, branch : Branch) -> Unit {
  sb.write_string("N")
  sig_node(sb, branch.node)
  sb.write_string("[")
  for c in branch.children {
    sig_branch(sb, c)
  }
  sb.write_string("]")
}

///|
fn sig_node(sb : StringBuilder, node : Node) -> Unit {
  match node {
    Implicit => sb.write_string("i")
    Explicit(sign~, label~, folded~, body~) => {
      sb.write_string("e")
      sb.write_string(
        match sign {
          Heading => "h"
          Item => "l"
        },
      )
      sb.write_string(if folded { "^" } else { "_" })
      sig_text(sb, label)
      sig_blocks(sb, body)
    }
  }
}

///|
fn sig_blocks(sb : StringBuilder, blocks : Array[Block]) -> Unit {
  sb.write_string("(")
  for b in blocks {
    match b {
      Rule => sb.write_string("r")
      Opaque(s) => {
        sb.write_string("o")
        sig_text(sb, s)
      }
      Content(c) => {
        sb.write_string("c")
        sig_content(sb, c)
      }
    }
  }
  sb.write_string(")")
}

///|
fn sig_content(sb : StringBuilder, content : Content) -> Unit {
  match content {
    Image(alt~, src~) => {
      sb.write_string("i")
      sig_text(sb, alt)
      sig_text(sb, src)
    }
    Link(text~, href~) => {
      sb.write_string("l")
      sig_text(sb, text)
      sig_text(sb, href)
    }
    Code(info~, text~) => {
      sb.write_string("c")
      sig_text(sb, info)
      sig_text(sb, text)
    }
    Svg(s) => {
      sb.write_string("s")
      sig_text(sb, s)
    }
  }
}

///|
/// 長さ前置の文字列。長さは UTF-16 コード単位（`String::length()`）。
fn sig_text(sb : StringBuilder, s : String) -> Unit {
  sb.write_string(s.length().to_string())
  sb.write_string(":")
  sb.write_string(s)
}
```

---

## §9. 畳みと `<summary>`（裁定 1）

**serialize は畳んだノードに `<details>` と `<summary>label</summary>` を必ず書く**（憲法 §4）。
**parse は `<details>` の直後の `<summary>…</summary>` 行を、内容を見ずに読み飛ばす。**

### 規則（1 文字も曖昧さを残さない）

> `Open`（`<details>`）を読んだあと、**次に来る非空行**が `<summary>` で始まり `</summary>` で終わる
> `Verse` なら、その **1 枚だけ**を捨てる（body に積まない）。捨てるのは 1 枚だけで、
> 2 枚目以降の `<summary>` や、`Open` の直後でない `<summary>` は `Opaque` として残る。

- **内容が label と一致するかは見ない。** 一致判定にすると、手書きの別内容が Opaque として残り、
  serialize が label 版と合わせて **2 枚書いて増殖する**
- **位置は「details の直後」に限る。** 位置を問わないと、body の途中に手で置かれた `<summary>` まで消える
- 捨てるとき `spill` も `shed` も呼ばない（直前の `Open` の腕が済ませている）

### 冪等であることの確認

手書きの `<summary>old</summary>` が畳んだノードの直後に居る場合:

（`is_summary` は `<summary>` の完全前置と `</summary>` の後置で見るので、
`<summary class="x">` のような属性つきは**捨てられず Opaque として残る**。
その場合 serialize がラベル版を別に 1 枚足すため、往復は安定するが
属性つきの summary が 1 枚余分に居続ける — 爆風半径の一項として引き受ける）

内容だけの `<summary>old</summary>` が直後に居る場合:

1. 1 回目の parse: `Open` の直後なので**捨てられる**（意味の損失。爆風半径に載せる）
2. serialize: `<details>` → 空行 → `<summary>label</summary>` → 空行 → 本文
3. 2 回目の parse: `Open` の直後の 1 枚（label 版）を捨て、以降は Opaque として残る → **同じ木**
4. 3 回目以降も不動。法則 1・2 が保たれる

### 実装（G2）

```moonbit
///|
/// `<summary>…</summary>` は serialize が label から毎回作る飾り（憲法 §4）。
fn is_summary(text : String) -> Bool {
  text.has_prefix(spell.label_open) && text.has_suffix(spell.label_close)
}
```

`Build` に 1 ビット足す（**このパッケージで唯一の `mut` フィールド**。`Open` の腕で必ず書くので
`[0015] unused_mut` は出ない）:

```moonbit
priv struct Build {
  // …既存のフィールド…
  mut fresh : Bool // 直前が <details>（間の空行は数えない）
}
```

`read` の `match` の規律:

- `Open(col~)` の腕: 従来の処理のあと `b.fresh = true`
- `Blank` の腕: `b.fresh` を**変えない**（`<details>` と `<summary>` の間の空行を跨ぐ）
- `Verse(col~, text~)` の腕: `if b.fresh && is_summary(text) { b.fresh = false }`（何もしない）
  でなければ `b.fresh = false` してから従来の処理
- それ以外のすべての腕: 先頭で `b.fresh = false`

### 爆風半径（`docs/ops.md` に 1 行足す。裁定 1）

> **手で書いた `<summary>` は残らない。** 畳んだノードの `<details>` の直後に書かれた `<summary>` は
> 読みで捨てられ、書き出すときラベルから作り直される。別の文言を書いても、そのノードを触った瞬間に
> ラベル版へ置き換わる。ラベルと違う見出しを畳みに付けたい、という要求はこの設計では表現できない。

### カタログ C8 の期待 md（G3 Task 46 が `2026-08-29-op-cases.md` を直す）

**元 md**:

```md
# r

## a

### b

<details>

<summary>b</summary>

#### c

</details>
```

**新 md**（`fold(a)` のあと）:

```md
# r

## a

<details>

<summary>a</summary>

### b

<details>

<summary>b</summary>

#### c

</details>

</details>
```

指紋: 元 = `D-n()[Reh_1:r()[>Neh_1:a()[Neh^1:b()[Neh_1:c()[]]]]]` /
新 = `D-n()[Reh_1:r()[>Neh^1:a()[Neh^1:b()[Neh_1:c()[]]]]]`。
mermaid の `〔畳〕` は c に付いているが、憲法 §4「骨格行は外、本文と子だけ包む」に従えば
`<details>` の持ち主は b。**md と指紋が正で、mermaid は直さない**（絵の話）。

---

## §10. 公開関数のシグネチャ

`mmm-app/core/tree` が外（= `core/tree/js` と wbtest）へ見せるもの。**これが全部。**

```moonbit
// --- 走査（G1） -------------------------------------------------------------
/// 走査の 1 単位。物理行 1 本と 1 対 1 だが、フェンスだけは開きから閉じまでで 1 枚。
/// col はタブを 4 で数えた「中身の始まる列」。
pub(all) enum Token {
  Blank
  Head(col~ : Int, level~ : Int, label~ : String)
  Bullet(col~ : Int, hang~ : Int, label~ : String)
  Bar(col~ : Int, dash~ : Bool)
  Fence(col~ : Int, info~ : String, text~ : String)
  Open(col~ : Int)
  Close(col~ : Int)
  Verse(col~ : Int, text~ : String)
}

///|
/// 走査の全部。封筒と改行の流儀は Doc へそのまま渡る。
pub(all) struct Scan {
  frontmatter : String?
  eol : Eol
  tokens : Array[Token]
}

pub fn scan(text : String) -> Scan

// --- 不変条件（G1） ---------------------------------------------------------
pub fn check(doc : Doc) -> Array[String]

// --- 指紋（G1） -------------------------------------------------------------
pub fn sig(doc : Doc) -> String

// --- 綴り（G1。spell.mbt） --------------------------------------------------
pub let spell : Spell
pub fn eol_text(eol : Eol) -> String

// --- 読み（G2） -------------------------------------------------------------
pub fn parse(text : String) -> Doc

// --- 書き（G3） -------------------------------------------------------------
pub fn serialize(doc : Doc) -> String

// --- 操作（G5） -------------------------------------------------------------
pub fn move_nodes(doc : Doc, ids : Array[Int], parent : Int, at : Int, side : Side) -> Verdict
pub fn flip_side(doc : Doc, ids : Array[Int]) -> Verdict
pub fn delete_nodes(doc : Doc, ids : Array[Int]) -> Verdict

// --- 反映 v0（G5） ----------------------------------------------------------
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
}

///|
/// 操作 1 回ぶんの往復の結果。JSON にするのは G4 の reflect_json。
pub(all) struct Reflection {
  ok : Bool
  reason : String
  text : String
  edits : Array[Edit]
}

pub fn reflect(md : String, op : (Doc) -> Verdict) -> Reflection
pub fn diff(before : String, after : String) -> Array[Edit]
pub fn apply(text : String, edits : Array[Edit]) -> String

// --- 投影（G4） -------------------------------------------------------------
pub fn project(doc : Doc) -> String

// --- JSON の綴り（G4） ------------------------------------------------------
pub fn quote(s : String) -> String
pub fn strings(xs : Array[String]) -> String
pub fn reflect_json(r : Reflection) -> String
```

### 契約の細目

- **操作は `Doc` をその場で書き替え、戻りは `Verdict`。** 元の doc が別物にならないので、
  呼ぶ側は「誰が最新の Doc を持つか」を考えなくてよい（実測: struct は参照）
- `move_nodes` の `parent` は **id**。文書直下は番兵 `doc_id`（= 1）
- `move_nodes` の `at` は **wings / children / roots の index**（バケツの index ではない）。
  バケツ index → wings index の写像は UI 翻訳層の仕事
- `move_nodes` の `side` は**行き先の側**。root 直下の翼へ挿すときだけ効き、それ以外では捨てられる
- `flip_side` は資格の無い id を**黙って飛ばす**。1 つも効かなければ `Rejected`
- **複数選択は `move_nodes` / `flip_side` / `delete_nodes` の 3 本とも、内部で頂点集合に正規化する**
  （子孫は祖先に吸収）。憲法 §5 の「複数選択は頂点集合に正規化してから適用」は操作一般の規則であり、
  前版が move / delete に限定していたのは翻訳漏れ（裁定 4）。`flip_side` が `crown` を通らないと、
  root とその直下の枝を同時に選んだとき二重反転して枝が元に戻る
- `reflect` が操作を closure で受けるのは、腕を生やさずに op を差し替えるため。
  **統一サイクルの唯一の書き手**がここ 1 本になる
- `reflect` は `Reflection` を返す**純関数**。JSON にするのは G4 の `reflect_json` 1 本
- `diff` は共通接頭辞・接尾辞を刈った 1 ハンク（v0）。**間違えても壊れない部品** —
  正しさは serialize が持ち、`safe_edits` が `apply(md, edits) == text` を確かめ、
  合わなければ全文置換 1 ハンクへ落とす
- `apply` の edits は互いに重ならず、`from` の昇順であることを前提にする

### 拒否の文言（3 つだけ。逐語）

```
見つからない (id=7)
子孫へは動かせない (id=7)
側を変えられるのは root と root 直下の枝だけ (id=7)
```

---

## §11. 道具層と腕数（裁定 5）

### 腕数の定義（これが「殺す条件」の物差し。定義は 1 つだけ）

> **容器の腕** = その関数の `match path` の枝のうち、**3 つの容器（`doc.roots` / `Root::wings` /
> `Branch::children`）のどれかを読むか書くもの**の数。何もしない・拒否するだけの番兵枝（`[]`）は数えない。
>
> **意味の腕** = 仕様が定めた場合分けの数（flipSide の資格 3 段など）。容器の異種性とは無関係なので、
> 殺す条件の物差しには入れない。

前版は `pluck 3` / `amend 4` と書いていたが、この 2 つは数え方が揃っていなかった
（`amend` だけ番兵枝を数えていた）。**物差しが 2 つあると殺す条件が測れない**ので、
契約が定義を 1 つ持ち、G5 はそれに従う。

### 現在の数字（この定義で測ったもの）

道具は **5 本**: `resolve` / `kin_at` / `pluck` / `graft` / `amend`。
増えた 1 本（`kin_at`）は**読む道具**で、変換の住所は `graft` のまま 1 か所。

| 関数 | 容器の腕 | 役 |
|---|---|---|
| `resolve(doc, id) -> Array[Int]?` | 0 | id → 居場所 |
| `find_in(branch, id) -> Array[Int]?` | 0 | `resolve` の下請け |
| `branch_at(doc, path) -> Branch` | 1 | 深さ 2 以降のノードそのもの |
| `kin_at(doc, path) -> Array[Node]` | 3 | path が居る列（自分を含む兄弟）の骨格 |
| `parent_at(doc, path) -> Node?` | 0 | 親の骨格（None = 文書）。`kin_at` の上に建つ |
| `pluck(doc, path) -> Sub?` | 3 | 抜く |
| `graft(doc, parent, at, sub, side)` | 3 | 挿す + 変換の唯一の住所 |
| `amend(doc, path, f)` | 3 | 骨格を書き替える（2 段包み 1 本） |
| `set_side(doc, i, j, side)` | 1 | 翼の側を差し替える |
| `as_root(sub)` / `as_branch(sub)` | — | graft の変換 2 本 |

- 操作 3 本（`move_nodes` / `flip_side` / `delete_nodes`）の容器の腕: **0**
- 回復 2 本（`prune` / `conform`）の容器の腕: **0**
- `Sub` を変換する場所: **1 か所**
- 2 段包み（Wing と Branch を両方作り直す枝）: **1 本**（`amend` の `[i, j]`）
- **判定: 合格**

### 判定基準

- **合格**（この設計は生きている）
  - 道具の容器の腕がすべて **3 以下**
  - 操作 3 本の容器の腕が **0**
  - 回復 2 本の容器の腕が **0**
  - `Sub` を変換する場所が **1 か所**
  - 2 段包みが **1 本以下**
- **警告**（設計は生きているが、次の一手を打つ）
  - どれかの道具が **4 腕**になった → `Wing` に `mut branch` を 1 つ足して 3 へ戻せるか検討する
    （実測済み: 足せば `amend` の 2 段包みが消える）
  - 道具が **6 本目**になった → 増えたのが「読む道具」か「書く道具」かを見る。
    書く道具なら、変換の住所が 2 か所に割れていないか疑う
- **死**（設計を作り直す）
  - どれかの道具が **5 腕**になった
  - 操作 3 本のどれかが `match path` を自前で持ち始めた（道具の幽閉が破れた）
  - `Sub` を変換する場所が **2 か所以上**になった

### 逐語コメント（これを写す。1 文字も変えない）

`core/tree/tool.mbt` のファイル冒頭:

```moonbit
// 道具 5 本。型の異種性はここに幽閉する（操作には腕を生やさない）。
// Path = Array[Int]（[] = doc、[i] = root、[i, j] = 翼、以深 = children）。
// 殺す条件の観測点: 容器の腕が 3 で止まらなくなったら負け。
```

`amend` の直前:

```moonbit
///|
/// 骨格を書き替える。容器 3 腕 — `[i, j]` だけは Wing と Branch の 2 段を包み直す。
/// （`Wing` に `mut branch` を 1 つ足せば 2 段包みが消える。腕が 4 本目になったら検討する）
```

### 道具の逐語（`moon fmt` 済み・`moon check` 0 errors・実測済み）

`kin_at` / `parent_at` を除く 4 本 + 補助は前版のまま。**`kin_at` / `parent_at` は G5 Task 81 が
実測して確定させる**（裁定 7）。

```moonbit
///|
/// 運搬の通貨。**一度しか graft してはならない**（struct は参照なので、
/// 二度挿すと中の Branch が物理共有される）。この型は op の外に出ない。
priv enum Sub {
  Whole(Root)
  Part(Branch)
}

///|
/// id からその居場所へ。腕なし。
fn resolve(doc : Doc, id : Int) -> Array[Int]? {
  for i, r in doc.roots {
    if r.id == id {
      return Some([i])
    }
    for j, b in r.wings {
      if find_in(b.branch, id) is Some(tail) {
        let path = [i, j]
        path.append(tail)
        return Some(path)
      }
    }
  }
  None
}

///|
fn find_in(branch : Branch, id : Int) -> Array[Int]? {
  if branch.id == id {
    return Some([])
  }
  for k, c in branch.children {
    if find_in(c, id) is Some(tail) {
      let path = [k]
      path.append(tail)
      return Some(path)
    }
  }
  None
}

///|
/// 抜き取る。容器 3 腕（roots / wings / children）。
/// **抜いた瞬間 doc から消える** — graft までの間に落とすと木が壊れる。
fn pluck(doc : Doc, path : Array[Int]) -> Sub? {
  match path {
    [] => None
    [i] => Some(Whole(doc.roots.remove(i)))
    [i, j] => Some(Part(doc.roots[i].wings.remove(j).branch))
    [.. head, last] => Some(Part(branch_at(doc, head).children.remove(last)))
  }
}

///|
/// 挿す。容器 3 腕 + 変換の唯一の住所。
/// at は呼ぶ側が clamp する（`Array::insert` の範囲外は catch 不能な panic）。
fn graft(
  doc : Doc,
  parent : Array[Int],
  at : Int,
  sub : Sub,
  side : Side,
) -> Unit {
  match parent {
    [] => doc.roots.insert(at, as_root(sub))
    [i] => doc.roots[i].wings.insert(at, { side, branch: as_branch(sub) })
    _ => branch_at(doc, parent[:]).children.insert(at, as_branch(sub))
  }
}

///|
/// 骨格を書き替える。容器 3 腕 — `[i, j]` だけは Wing と Branch の 2 段を包み直す。
/// （`Wing` に `mut branch` を 1 つ足せば 2 段包みが消える。腕が 4 本目になったら検討する）
fn amend(doc : Doc, path : Array[Int], f : (Node) -> Node) -> Unit {
  match path {
    [] => ()
    [i] => {
      let r = doc.roots[i]
      doc.roots[i] = { ..r, node: f(r.node) }
    }
    [i, j] => {
      let b = doc.roots[i].wings[j]
      doc.roots[i].wings[j] = {
        ..b,
        branch: { ..b.branch, node: f(b.branch.node) },
      }
    }
    [.. head, last] => {
      let owner = branch_at(doc, head)
      let n = owner.children[last]
      owner.children[last] = { ..n, node: f(n.node) }
    }
  }
}

///|
/// 翼の側を差し替える（side は場所の属性なので amend では届かない）。
fn set_side(doc : Doc, i : Int, j : Int, side : Side) -> Unit {
  let b = doc.roots[i].wings[j]
  doc.roots[i].wings[j] = { ..b, side, }
}

///|
/// 深さ 2 以降のノードそのもの。道具が共有する唯一の座標系。
fn branch_at(doc : Doc, path : ArrayView[Int]) -> Branch {
  guard! path is [i, j, .. rest]
  let mut n = doc.roots[i].wings[j].branch
  for k in rest {
    n = n.children[k]
  }
  n
}

///|
/// doc へ: Part → Root 化（children を Wing(Right) で包む）/ Whole → 無変換
fn as_root(sub : Sub) -> Root {
  match sub {
    Whole(r) => r
    Part(n) =>
      {
        id: n.id,
        node: n.node,
        wings: n.children.map(fn(c) { { side: Right, branch: c } }),
      }
  }
}

///|
/// root / branch へ: Whole → 解体（sides は深さの物理で消滅）/ Part → そのまま
fn as_branch(sub : Sub) -> Branch {
  match sub {
    Whole(r) =>
      {
        id: r.id,
        node: r.node,
        children: r.wings.map(fn(b) { b.branch }),
      }
    Part(n) => n
  }
}
```

### 綴りの規律

- **`graft` の前に必ず `at` を clamp する。** `Array::insert` の範囲外は `abort` で panic し、
  `try?` では捕まらない（末尾ちょうど `insert(len, v)` は通る）
- **`Sub` は一度しか graft してはならない。** 同じ `Sub` を 2 回挿すと **2 段目から物理共有**される
- **`pluck` は即座に doc を壊す。** 抜いてから挿すまでの間に return / panic すると木を落とす
- `.. rest` の束縛は `ArrayView[Int]`。内部ヘルパは `ArrayView[Int]` で受け、公開の `Array[Int]` からは `path[:]`
- `guard!` は意図的な panic（`else` を書かないと `[0087] guard_inexhaustive` 警告）

### graft の変換表

| 行き先 | `Sub` = `Whole(Root)` | `Sub` = `Part(Branch)` |
|---|---|---|
| **doc**（`parent = []`） | 無変換。sides が無傷で旅する | **Root 化** — `children` を `Wing(Right)` で包む。`side` 引数は使わない |
| **root**（`parent = [i]`） | **解体** — `wings` を捨てて `children` に（sides は深さの物理で消滅）。新しい `side` は**引数が決める** | `Wing(side)` で包む |
| **branch**（2 段以上） | **解体**（同上）。`side` 引数は捨てられる | そのまま。`side` 引数は捨てられる |

### `amend` の unused_value 警告について

`amend` の呼び手（fold / setSign）は今回のスコープ外なので、`moon check` は
`Warning: [0001] Warning (unused_value): Unused function 'amend'` を 1 本出す。
**`pub` にして黙らせてはならない**（道具の幽閉が破れる）。
CI の合格条件は `0 errors` であって `0 warnings` ではない。

---

## §12. 正規形の綴り定数（`core/tree/spell.mbt`。所有 = G1）

**綴りに関わる値はここ以外に書いてはならない。** `serialize.mbt` に生の `"#"` や `"  "` を書いたら負債。

```moonbit
// 正規形の綴り。将来の lint 的な設定化に備えて 1 か所に括る（設定 UI は作らない）。

///|
pub(all) struct Spell {
  marker : String // リストのマーカー
  step : String // ネスト 1 段の字下げ
  hash : String // 見出しの刻み
  toggle : String // 側の変わり目（トグル専用）
  rule : String // 飾りの水平線（チャンネル分離）
  fence : String // コードの囲いの 1 文字
  fence_min : Int // 囲いの最短の長さ
  fold_open : String // 畳みの開き
  fold_close : String // 畳みの閉じ
  label_open : String // 畳みの中に書くラベルの飾りの開き
  label_close : String // 同じく閉じ
  front : String // 封筒の柵
  gap : Int // 継ぎ目の空行の本数
  lf : String
  crlf : String
}

///|
pub let spell : Spell = {
  marker: "-",
  step: "  ",
  hash: "#",
  toggle: "---",
  rule: "***",
  fence: "`",
  fence_min: 3,
  fold_open: "<details>",
  fold_close: "</details>",
  label_open: "<summary>",
  label_close: "</summary>",
  front: "---",
  gap: 1,
  lf: "\n",
  crlf: "\r\n",
}

///|
/// 改行の逐語。
pub fn eol_text(eol : Eol) -> String {
  match eol {
    Lf => spell.lf
    Crlf => spell.crlf
  }
}
```

読みの側の受け入れ（`scan` が読むが `serialize` は書かない綴り）は定数にしない — `*` `+` のマーカー、
順序リスト、4 スペース字下げ、setext、インデントコード、閉じ `#`、`___` の水平線、`- - -`。
これらは方言表（§15）の側の話。

`fence_min` の使い方: 中身に含まれる `` ` `` の最長連続長 + 1 と `fence_min` の大きい方。

**G1 Task 10.5 の直後は `spell` の読み手が居ないので警告が出うる。** `0 errors` なら合格で、
警告を消すために可視性を下げたり読み捨てのコードを足したりしないこと（値を固定するのは G3 Task 40 の 2 本）。

### 反映 v0 の帰結（申し送り S15）

- **v0 の反映は全文正規形。** 触っていない範囲も正規形になる。触った所だけを残すすげ替えは v1
- カタログ **C7 の「新 md」はすげ替え（v1）の姿**。v0 では a の body の飾りの `---` が
  チャンネル分離により `***` へ寄る。**Task 70 は v0 の姿を固定する**
- カタログ **C15 の「無操作は無編集」**も、`format` を通せば綴りは正規形へ寄る（**指紋は不動**）。
  `reflect` が編集ゼロを返すのは、**md が既に正規形のとき**と、**拒否のとき**（拒否は md が
  正規形でなくても必ず編集ゼロ）

---

## §13. 境界の設計

### 原則

**struct を 1 つも跨がせない。** 出入りは `String` と `Array[Int]` と `Int` と `Bool` だけ。
構造は JSON 文字列にして渡す。理由は 2 つ — `Array[Int]` は `js.d.ts` で `any` に落ちるので、
構造を渡すなら JSON が唯一の型の付く道であること。そして `JSON.parse` の 1 行を
**唯一の信頼境界**に保てること。

新 core は**純関数**でモジュールグローバルな状態を持たない。旧 core の `initDoc` に当たるものは無い。

### `moon.pkg` の逐語（**別名は書かない** — `moon fmt` が最終パスセグメントと同じ別名を剥がす）

`core/tree/moon.pkg`:

```
pkgtype(kind: "library")
```

`core/tree/js/moon.pkg`:

```
pkgtype(kind: "foreign_library")

import {
  "mmm-app/core/tree",
}
```

呼び出しは `@tree.parse(md)`。

### `#export_name` の一覧（`core/tree/js/exports.mbt`、逐語。7 本）

```moonbit
// mmm-app/core/tree の薄い JS 層。struct は 1 つも跨がず、出入りは String だけ。
// library パッケージを `moon test` で叩けるように、ここだけ分けてある。

///|
#export_name("sig")
pub fn sig(md : String) -> String {
  @tree.sig(@tree.parse(md))
}

///|
#export_name("format")
pub fn format(md : String) -> String {
  @tree.serialize(@tree.parse(md))
}

///|
#export_name("check")
pub fn check(md : String) -> String {
  @tree.strings(@tree.check(@tree.parse(md)))
}

///|
#export_name("project")
pub fn project(md : String) -> String {
  @tree.project(@tree.parse(md))
}

///|
#export_name("moveNodes")
pub fn move_nodes(
  md : String,
  ids : Array[Int],
  parent : Int,
  at : Int,
  left : Bool,
) -> String {
  @tree.reflect_json(
    @tree.reflect(md, fn(d) {
      @tree.move_nodes(
        d,
        ids,
        parent,
        at,
        if left {
          @tree.Left
        } else {
          @tree.Right
        },
      )
    }),
  )
}

///|
#export_name("flipSide")
pub fn flip_side(md : String, ids : Array[Int]) -> String {
  @tree.reflect_json(@tree.reflect(md, fn(d) { @tree.flip_side(d, ids) }))
}

///|
#export_name("deleteNodes")
pub fn delete_nodes(md : String, ids : Array[Int]) -> String {
  @tree.reflect_json(@tree.reflect(md, fn(d) { @tree.delete_nodes(d, ids) }))
}
```

命名規則は旧 core と同じ — **mbt 側は `snake_case`、`#export_name` は `camelCase`**。
`delete` は JS の予約語なので `deleteNodes`（`move` も操作が複数 id を取るので `moveNodes`）。

生成される `js.d.ts`（実測の逐語）:

```ts
import type * as MoonBit from "./moonbit.d.ts";

export function deleteNodes(md: MoonBit.String,
                            ids: any): MoonBit.String;

export function flipSide(md: MoonBit.String,
                         ids: any): MoonBit.String;

export function moveNodes(md: MoonBit.String,
                          ids: any,
                          parent: MoonBit.Int,
                          at: MoonBit.Int,
                          left: MoonBit.Bool): MoonBit.String;

export function project(md: MoonBit.String): MoonBit.String;

export function check(md: MoonBit.String): MoonBit.String;

export function format(md: MoonBit.String): MoonBit.String;

export function sig(md: MoonBit.String): MoonBit.String;
```

**生成物の置き場所**: `core/_build/js/release/build/tree/js/js.js`
（旧 core は `core/_build/js/release/build/js/js.js`。実測で 2 つが同時に建つ）。

### 反映の JSON（`reflect_json` の出力）

```json
{"ok":true,"reason":"","text":"# r\n","edits":[{"from":0,"to":3,"insert":"x"}]}
```

- フィールドの順は **`ok` → `reason` → `text` → `edits`** で固定。`edits` の各要素は
  **`from` → `to` → `insert`** で固定
- `ok = false` のとき `text` は**元の md そのまま**・`edits` は空・`reason` に拒否の理由
- `edits` のオフセットは**旧文書上の UTF-16**。`from` 昇順で互いに重ならない
- `reflect` は `safe_edits` で自己検査（`apply(md, edits) == text`）を済ませている。
  合わなかった場合は全文置換 1 ハンクに落ちている（正しさは保たれ、カーソルだけ跳ぶ）

`reflect_json` の逐語（`core/tree/json.mbt`、G4 所有）:

```moonbit
///|
/// 境界を渡る唯一の形。struct は跨がず、文字列 1 本で渡す。
pub fn reflect_json(r : Reflection) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"ok\":")
  sb.write_string(if r.ok { "true" } else { "false" })
  sb.write_string(",\"reason\":")
  sb.write_string(quote(r.reason))
  sb.write_string(",\"text\":")
  sb.write_string(quote(r.text))
  sb.write_string(",\"edits\":[")
  for k, e in r.edits {
    if k > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"from\":")
    sb.write_string(e.from.to_string())
    sb.write_string(",\"to\":")
    sb.write_string(e.to.to_string())
    sb.write_string(",\"insert\":")
    sb.write_string(quote(e.insert))
    sb.write_string("}")
  }
  sb.write_string("]}")
  sb.to_string()
}
```

### TS 側の窓口 — `test/_tree.ts`（全文。**tsc `strict` + `noUnusedLocals` で 0 errors**）

```typescript
// 新 core の窓口。JSON の形（フィールド名・並び）を決めるのは
// core/tree/project.mbt と core/tree/json.mbt で、この `JSON.parse` が唯一の信頼境界。
//
// 重要: 新 core は純関数。モジュールグローバルな状態を持たないので、
// どのテストも md 文字列から始めてよい（initDoc に当たるものは無い）。
//
// 出力が無いと ERR_MODULE_NOT_FOUND で落ちる。先に `pnpm run core` を実行すること。

import { readdirSync, readFileSync, statSync } from "branch:fs";
import { join } from "branch:path";
import * as mbt from "../core/_build/js/release/build/tree/js/js.js";

/** 法則 3（map への矢印は project 1 本）を数えるために名前空間ごと出す */
export { mbt };

/** 旧文書上の UTF-16 オフセット。境界を渡る唯一の編集の形 */
export interface Edit {
  readonly from: number;
  readonly to: number;
  readonly insert: string;
}

/** 操作 1 回ぶんの往復。ok が false なら text は元のまま・edits は空 */
export interface Reflection {
  readonly ok: boolean;
  readonly reason: string;
  readonly text: string;
  readonly edits: readonly Edit[];
}

/** ノードの箱に積む 1 枚。Block の Content と 1 対 1 */
export type Card =
  | { readonly kind: "image"; readonly alt: string; readonly src: string }
  | { readonly kind: "link"; readonly text: string; readonly href: string }
  | { readonly kind: "code"; readonly info: string; readonly text: string }
  | { readonly kind: "svg"; readonly svg: string };

/** 判別可能ユニオンの絞り込み。kind で分岐すれば各腕のフィールドが型で見える */
export function cardText(card: Card): string {
  switch (card.kind) {
    case "image":
      return card.alt;
    case "link":
      return card.text;
    case "code":
      return card.text;
    case "svg":
      return card.svg;
  }
}

export interface MapNode {
  readonly id: number;
  readonly label: string;
  /** 骨格行を持たない（飛びが綴り）。中空に描くかは render の自由 */
  readonly implied: boolean;
  readonly folded: boolean;
  readonly sign: "heading" | "item";
  readonly cards: readonly Card[];
  /** 絵に描かれない Block の数（Rule と Opaque）。cards.length + buried = body の数 */
  readonly buried: number;
}

export interface MapBranch {
  readonly branch: MapNode;
  readonly children: readonly MapBranch[];
}

export interface MapTree {
  readonly branch: MapNode;
  readonly right: readonly MapBranch[];
  readonly left: readonly MapBranch[];
}

export interface Mindmap {
  readonly trees: readonly MapTree[];
  /** 最初の骨格より前の散文の数。箱が無いので 1 枚も絵にならない */
  readonly buried: number;
}

export const doc = {
  /** id を含まない木の綴り。法則 1・2 の比較子 */
  sig: (md: string): string => mbt.sig(md),
  /** parse → serialize。法則 2 はこれの冪等性 */
  format: (md: string): string => mbt.format(md),
  /** 破れの一覧。空なら健全 */
  check: (md: string): string[] => JSON.parse(mbt.check(md)),
  project: (md: string): Mindmap => JSON.parse(mbt.project(md)),
  /** parent は id（文書は 1）。left は行き先の側で、root 直下でだけ効く */
  moveNodes: (
    md: string,
    ids: number[],
    parent: number,
    at: number,
    left: boolean,
  ): Reflection => JSON.parse(mbt.moveNodes(md, ids, parent, at, left)),
  flipSide: (md: string, ids: number[]): Reflection =>
    JSON.parse(mbt.flipSide(md, ids)),
  deleteNodes: (md: string, ids: number[]): Reflection =>
    JSON.parse(mbt.deleteNodes(md, ids)),
};

/** edits を旧文書へ当てる。core の自己検査と同じ算術を TS 側でもう一度踏む */
export function apply(text: string, edits: readonly Edit[]): string {
  let out = "";
  let at = 0;
  for (const e of edits) {
    out += text.slice(at, e.from) + e.insert;
    at = e.to;
  }
  return out + text.slice(at);
}

/** 決定論的な乱数（xorshift）。seed が同じなら必ず同じ文書が出る */
export function rng(seed: number): () => number {
  let s = seed | 0 || 1;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 4294967296;
  };
}

const LABELS = [
  "a",
  "",
  "  spaced  ",
  "日本語",
  "🙂",
  "### not a heading",
  "[x] done",
  "1. numbered",
  "--",
  "a\tb",
];

const BODIES = [
  "text",
  "***",
  "---",
  "```js\ncode\n```",
  "```\n```` inner\n```",
  "![alt](./img/a.png)",
  "[title](https://example.com)",
  "<svg><rect/></svg>",
  "> quote",
  "| a | b |\n| - | - |",
  "<!-- comment -->",
];

/** 法則のファズが食わせる文書。飛び・区切り・畳み・CRLF・末尾改行なしを狙って踏む */
export function randomDoc(seed: number): string {
  const r = rng(seed);
  const pick = <T>(xs: T[]): T => xs[Math.floor(r() * xs.length)]!;
  const out: string[] = [];
  if (r() < 0.15) out.push("---\nimage-folder: img\n---\n");
  if (r() < 0.15) out.push("---\n");
  let level = 1;
  const n = 1 + Math.floor(r() * 12);
  for (let i = 0; i < n; i++) {
    level = Math.max(1, Math.min(7, level + Math.floor(r() * 5) - 2));
    const label = pick(LABELS);
    out.push(
      r() < 0.35
        ? `${"  ".repeat(level - 1)}- ${label}\n`
        : `${"#".repeat(level)} ${label}\n`,
    );
    out.push("\n");
    if (r() < 0.4) out.push(`${pick(BODIES)}\n\n`);
    if (r() < 0.1) out.push("---\n\n");
    if (r() < 0.1) out.push("<details>\n\n<summary>x</summary>\n\n");
    if (r() < 0.1) out.push("</details>\n\n");
  }
  let text = out.join("");
  if (r() < 0.2) text = text.replace(/\n/g, "\r\n");
  if (r() < 0.25) text = text.replace(/\n$/, "");
  return text;
}

/** リポジトリ内の実文書。docs/ の md がそのまま法則 1・2 の入力になる */
export function corpus(root = "."): { path: string; text: string }[] {
  const skip = new Set([
    "node_modules",
    "_build",
    ".git",
    "target",
    ".worktrees",
  ]);
  const out: { path: string; text: string }[] = [];
  const walk = (dir: string, depth: number): void => {
    if (depth > 3) return;
    for (const name of readdirSync(dir)) {
      if (skip.has(name)) continue;
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p, depth + 1);
      else if (name.endsWith(".md"))
        out.push({ path: p, text: readFileSync(p, "utf8") });
    }
  };
  walk(root, 0);
  return out;
}

/** ケース数のダイヤル。PowerShell では `$env:MMM_FUZZ = '5000'; pnpm test` */
export function fuzzCases(fallback: number): number {
  const v = Number(process.env["MMM_FUZZ"]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

/** 失敗したときに何を食わせたかを 1 行で見せる */
export function brief(md: string): string {
  return JSON.stringify(md.length > 200 ? md.slice(0, 200) + "…" : md);
}
```

`pathological()`（手で選んだ病的な md、**29 本以上**）と `shrink()`（最小反例の縮小）も
このファイルに置く（申し送り S14）。`pathological()` の各行は `{ name, md }` で、
**`name` は中身を正直に名乗ること** — `["空白だけの行", "# a\n\n \n"]` と
`["NUL", "# a\n\n\u0000\n"]` は別の行（§18 R3-17）。

`test/tsconfig.json` への追加は不要（`include` の `"."` が拾う）。ただし現状の `include` に
**死んだ 2 行**があるので G4 が掃く: `"../src/relevel.ts"` と `"../src/app/externalChange.ts"` は
どちらも実在しない。

---

## §14. MindmapTree（`project` の出力）

```typescript
type Card =
  | { kind: "image"; alt: string; src: string }
  | { kind: "link"; text: string; href: string }
  | { kind: "code"; info: string; text: string }
  | { kind: "svg"; svg: string };

interface MapNode {
  id: number;
  label: string;
  implied: boolean;
  folded: boolean;
  sign: "heading" | "item";
  cards: Card[];
  buried: number;
}

interface MapBranch { branch: MapNode; children: MapBranch[] }
interface MapTree   { branch: MapNode; right: MapBranch[]; left: MapBranch[] }
interface Mindmap   { trees: MapTree[]; buried: number }
```

### 決めごと

- **`buried` = 絵に描かれない Block の数。** `MapNode.buried` は body のうち `Rule` と `Opaque` の数
  （`cards.length + buried == body.length`）。`Mindmap.buried` は `Doc.body` の全数 —
  文書には箱が無いので 1 枚も絵にならない
- **`cards` は `Content` と 1 対 1。** 解釈も畳み込みもしない
- **`folded` でも children は出す。** 境界は事実を渡し、描くかどうかは render が決める
- **`implied` のノードは** `label: ""` / `sign: "heading"` / `folded: false` / `cards: []` / `buried: 0`
- **バケツ分けは `wings` の filter。** `right` と `left` それぞれの中では wings の順序を保つ。
  **側をまたぐ読み順はここで意図的に落ちる**。判定は G3 の `same_side` を呼ぶ
- `Doc.frontmatter` と `Doc.eol` は綴りなので投影されない
- **MindmapTree は絶対に変異させない**（一方向ループ。投影の逆写像を作らない）。
  TS 側の型は全フィールド `readonly` で、逆写像を書いた瞬間 tsc が止まる（法則 3 の型による見張り）

---

## §15. 方言表と、読みの裁定

### 方言表（read が CommonMark と異なる点。憲法 §4）

setext は読む・`<!---`/`--->` 許容・**`#######`（7 個以上）も見出しとして読む**（lezer は段落と読むので
法則 4 の期待差分）・blockquote / table / 一般 HTML / 項目内の見出しは Opaque。
捨てた方言: `- - -` は CommonMark どおり水平線。

**法則 4 の照合は封筒を剥がした後の本文に掛ける**（申し送り S10）— 封筒は lezer では
`HorizontalRule` + `SetextHeading2` に読まれる（実測）。

### 読みの裁定 9 件（G1 が憲法・契約の隙間を埋めたもの。**G4 の方言表に載せる**）

| # | 裁定 | 固定する場所 |
|---|---|---|
| 1 | **setext の下線が付いた段落が複数行なら、最後の 1 行だけが見出し。** 手前の行は散文のまま残る（行を結合すると内容が変わるが、残せば意味は 1 ビットも落ちない） | `READING` 表（必須） |
| 2 | **怠惰な継続（lazy continuation）は読まない。** 列が浅い行は項目の領土から出る | `READING` 表（必須） |
| 3 | **インデントコードは空行の直後だけ開く。** 段落の続きを巻き込まない | `READING` 表（必須） |
| 4 | **インデントコードは `Fence` Token（`info` 無し）に落ちる。** 「読めるが書かない」が Token の段階で保証される | `scan_wbtest.mbt` |
| 5 | **`<summary>` 行は Verse として parse へ渡る。** 捨てるのは parse の仕事（§9） | `scan_wbtest.mbt` + `parse_wbtest.mbt` |
| 6 | **`<details>` は属性つきの形も受ける。** 読みは書きより広い | `scan_wbtest.mbt` |
| 7 | **順序リスト（`1.` `1)`）は Bullet に落ち、番号は Token に残らない** | `scan_wbtest.mbt` |
| 8 | **マーカーの後ろの空白が 5 桁以上でも hang は 1 桁ぶん。** 余りはラベルに入らない | `scan_wbtest.mbt` |
| 9 | **HTML コメント（`<!--` 〜 `-->`）の中の行はすべて Verse。** 中の `#` は見出しにならない | `READING` 表（必須） |

`DIALECT`（骨格の数を lezer と比べる表）は**数しか見ないので、裁定 1・2 のように
「数は合うが読んだ中身が違う」差を捕まえられない**。だから `test/treeDialect.test.ts` に
**2 つ目の表 `READING`**（md → 指紋）を置く。最低限この 4 行は必須:

```typescript
const READING: { md: string; sig: string; why: string }[] = [
  { md: "x\ny\n---\n", sig: "D-n(o1:x)[Ri[>Neh_1:y()[]]]",
    why: "setext の複数行段落は最後の 1 行だけが見出し。手前は散文のまま残す（憲法 §0）" },
  { md: "- a\ntext\n", sig: "D-n()[Rel_1:a(o4:text)[]]",
    why: "怠惰な継続は読まない。列が浅い行は項目の領土から出る" },
  { md: "# r\n\np\n    q\n", sig: "D-n()[Reh_1:r(o3:p\nq)[]]",
    why: "インデントコードは空行の直後だけ開く（段落の続きを巻き込まない）" },
  { md: "# r\n\n<!--\n# x\n-->\n", sig: "D-n()[Reh_1:r(o12:<!--\n# x\n-->)[]]",
    why: "HTML コメントの中の # は見出しにならない" },
];
```

残る 5 件は `scan_wbtest.mbt` で固定済みである旨を `why` に添えて表に併記する。

---

## §16. テストファイルの命名と置き場所

### mbt 側（`core/tree/` の中）

- **ホワイトボックス**: `<機能>_wbtest.mbt`。同じパッケージの private を直接見る。今回の主戦場
- **ブラックボックス**: 今回は作らない — カタログの固定は TS 側（md in / md out）に置くほうが読みやすい

| ファイル | 群 | 見るもの | 本数 |
|---|---|---|---|
| `core/tree/make_wbtest.mbt` | G1 | 木を組む葉の道具 + 組み立ての見張り 1 本 | 1 |
| `core/tree/scan_wbtest.mbt` | G1 | Token の列（方言・封筒・改行の流儀） | — |
| `core/tree/check_wbtest.mbt` | G1 | 6 条件それぞれの破れと、健全な木で空になること | — |
| `core/tree/sig_wbtest.mbt` | G1 | §8 の例 3 つ + 長さ前置の曖昧さの無さ | — |
| （G1 合計） | | | **25** |
| `core/tree/parse_wbtest.mbt` | G2 | 骨格の認定・Implicit の導出・側の割り当て・畳み・`<summary>` | **25** |
| `core/tree/serialize_wbtest.mbt` | G3 | 正規形の綴り 1 つずつ + `spell` の値 | **21** |
| `core/tree/tool_wbtest.mbt` | G5 | 道具 5 本・graft の変換表・腕数 | 6 |
| `core/tree/op_wbtest.mbt` | G5 | move 9 組合せ / flipSide / delete / 拒否 | 19 |
| `core/tree/diff_wbtest.mbt` | G5 | diff → apply の往復・自己検査 | 7 |
| （G5 合計） | | | **32** |
| `core/tree/json_wbtest.mbt` | G4 | 逃がし規則 + `reflect_json` の逐語 | 5 |
| `core/tree/project_wbtest.mbt` | G4 | バケツ分け・buried・implied（ヘルパは `proj_`） | 3 |
| `core/tree/laws_wbtest.mbt` | G4 | 木の生成器と法則 1 の本丸 | 2 |
| （G4 mbt 合計） | | | **10** |

**mbt 合計 113 本。**

**制約（実測）**: 同一パッケージの `*_wbtest.mbt` は名前空間を共有し、同名のトップレベル定義は
`Error: [4051] ... is declared twice`。**ヘルパ名はそのファイルの接頭辞で始めること**
（`make_` / `scan_` / `parse_` / `write_` / `tool_` / `op_` / `diff_` / `json_` / `proj_` / `law_`）。

**書式（既存 repo の慣習）**: ファイル先頭は `//` の素のコメントで役割を日本語で数行 /
**すべてのトップレベル定義の直前に `///|` が 1 行** / アサーションは **`assert_eq` のみ**
（`inspect` / snapshot は使わない。落としたいときは `abort("...")`）/ テスト名は日本語の 1 文。

### TS 側（`test/`）

| ファイル | 群 | 見るもの | 本数 |
|---|---|---|---|
| `test/_tree.ts` | G4 | 窓口・生成器・コーパス・縮小器（§13 に全文） | — |
| `test/treeLaws.test.ts` | G4 | 法則 1・2・3 | **12** |
| `test/treeDialect.test.ts` | G4 | 法則 4（`DIALECT` + `READING`） | **3** |
| `test/treeCases.test.ts` | G4 | カタログ C1〜C17 | **17** |
| `test/treeOps.test.ts` | G4 | 操作の性質のファズ（設計は G5 由来） | **5** |

**TS 合計 37 本。総計 150 本。**

既存の `test/_helpers.ts` と `test/*.test.ts` は**そのまま残す**（旧 core を守る）。
`branch --test "test/*.test.ts"` の glob が新しい 4 本を自動で拾う。`_tree.ts` は `_` 始まりなので
glob に当たらない。法則 4 の踏み台は既存 `test/seps.test.ts` の `itemsOf()` がそのまま使える
（`@lezer/markdown` は devDependencies の 1.7.2。`src/` からは一切使わない）。

---

## §17. コマンド

すべて実測。シェルは PowerShell を既定とする。
**Run 行は絶対パスで書く**（実行エージェントの cwd はツール呼び出しごとに戻る。
隣の `D:/1.atrium/mmm` から叩くと旧 core を測ってしまう）。作業場所は
`D:/1.atrium/mmm/.worktrees/feat/tree-core`（ブランチ `feat/tree-core`）。

| 目的 | コマンド | 成功時 | 失敗時の EXIT |
|---|---|---|---|
| 型検査（新パッケージだけ） | `moon -C <root>/core check tree` | `Finished. moon: ran N tasks, now up to date (M warnings, 0 errors)` EXIT=0 | **127** |
| 型検査（全体） | `moon -C <root>/core check` | 同上 | 127 |
| **テスト（ファイル 1 本）** | `moon -C <root>/core test tree/<file>_wbtest.mbt` | `Total tests: N, passed: N, failed: 0.` EXIT=0 | 2（落ちた）/ **127**（綴り間違い） |
| テスト（群の締め） | `moon -C <root>/core test -p mmm-app/core -p mmm-app/core/tree` | 同上 | **2** / **1**（ビルド不通） |
| 整形の確認 | `moon -C <root>/core fmt --check tree`（G4 の締めだけ `doc tree/js`） | `Finished. moon: ran N tasks, now up to date` EXIT=0 | **127** |
| 整形の適用 | `moon -C <root>/core fmt tree` | その場で書き換わる。EXIT=0 | — |
| JS 生成 | `pnpm run core`（= `cd core && moon build --target js --release`） | `Finished.` EXIT=0 | **127** |
| TS 型検査 | `pnpm run check` | 出力なし EXIT=0 | 1 |
| TS テスト | `pnpm test`（= `branch --test "test/*.test.ts"`） | `ℹ fail 0` EXIT=0 | 1 |
| ファズを増やす | `$env:MMM_FUZZ = '5000'; pnpm test` / 後始末 `Remove-Item Env:MMM_FUZZ` | — | — |

**テストの絞り方は 1 通りに固める**（申し送り S4・S9）:

- **各 Task の Step 2 / Step 4 はファイル指定**（`moon -C <root>/core test tree/<file>_wbtest.mbt`）。
  本数が他群と独立して固定でき、綴りを間違えると
  `Error: Failed to canonicalize input filter directory` で **EXIT=127** になり、黙って緑にならない
- **群の締めだけ `-p`**（`-p mmm-app/core -p mmm-app/core/tree`）。ここでは `Total tests:` が 0 でないことを目で見る

### 罠（全部実測）

- **`-p` を省いた `moon test` は必ず落ちる。** foreign_library の `#export_name` が `[4219]`。EXIT=1
- **`-p` の綴り間違いは EXIT=0 で緑になる。** `Warning: package ... not found` +
  `Total tests: 0, passed: 0, failed: 0.` → CI は `Total tests: 0` を検知すること
- **`moon test -p mmm-app/core/tree/js` は不可**（foreign_library はテストの的にならない）。EXIT=1
- **`moon check` に `-p` は無い**（PATH を取る）。絞るなら `moon -C <root>/core check tree`
- **`moon fmt --check` の失敗は EXIT=127**。`moon fmt` は `moon.pkg` も整形対象
- **旧 `core/js` を fmt の対象に含めた瞬間に赤になる**。**新パッケージのディレクトリだけを対象にする**
- `pnpm run core` は型検査の前提。`core/_build` が古いと `pnpm run check` が `TS2339` で落ちる
- **`docs/` に置く .md は旧 core の往復テスト（P1: バイト同一）の入力になる**
  （`test/_helpers.ts` の `corpus()` が深さ 3 まで全部集める）。`docs/ops.md` は
  ATX の見出しだけ・level を飛ばさない・`-` のリスト・**`---` と `***` と setext を使わない**・
  継ぎ目の空行は 1 本・末尾に改行 1 つ、で書く

### `package.json` の scripts（G4 が書き替える）

```json
"test:core": "cd core && moon test -p mmm-app/core -p mmm-app/core/tree",
"fmt:doc": "cd core && moon fmt --check tree tree/js",
```

`pnpm test` の glob（`test/*.test.ts`）は新しいテストファイルを自動で拾うので触らない。

### git

- ブランチ: `feat/tree-core` / ワークツリー: `.worktrees/feat/tree-core`
- コミット: `<Type>: <Emoji> #<Issue> <Title>`
- **rebase は使わない。** コンフリクトは対象ブランチへの merge で解く
- PR は Squash Merge。作業が終わったらブランチとワークツリーを破棄する

---

## §18. 期待するエラー文言

すべて実測の逐語。診断は `Error: [コード]` が 1 行目、本文は枠の中。

| 場面 | 文言 |
|---|---|
| 未定義の値 | `Error: [4021]` / `The value identifier no_such_fn is unbound.` |
| 未定義の型 | `Error: [4032]` / `The type Ints is undefined.` |
| 型不一致 | `Error: [4014]` / `Expr Type Mismatch` / `has type : Int` / `wanted   : String` |
| 公開定義が private 型に依存 | `Error: [4046]` / `A public definition cannot depend on private type` |
| 別パッケージから `pub` 型を構築 | `Error: [4036]` / `Cannot create values of the read-only type: @mmm-app/core/tree.Wing.` |
| 別パッケージで列挙子を無修飾 | `Error: [4021]` / `The value identifier Left is unbound.` |
| 不変フィールドへの代入 | `Error: [4087]` / `The record field side is immutable.` |
| 別パッケージで `pub` の `mut` を書く | `Error: [4094]` / `Cannot modify a read-only field: side` |
| ラベル引数を `~=` で渡す | `Error: [3016]` / ``The syntax `alt~=..` for supplying labelled argument is invalid, the correct syntax is `alt=..`.`` |
| wbtest 横断の名前衝突 | `Error: [4051]` / `The toplevel identifier helper_a is declared twice: ...` |
| library で `#export_name` | `Error: [4219]` / ``#export_name "sig" can only be used in a foreign library. Add `pkgtype(kind: "foreign_library")` to the package's moon.pkg.`` |
| パッケージ別名の誤り | `Error: [4020]` / `Package "nosuchpkg" not found in the loaded packages.` |
| 未使用の関数 | `Warning: [0001]` / `Warning (unused_value): Unused function 'amend'` |
| 未読のフィールド | `Warning: [0007]` / `Warning (unused_field): Field 'a' is never read` |
| 使われない `mut` | `Error: [0015]` / ``Warning (unused_mut): The mutability of field 'n' is never used, try remove `mut`.``（**警告ではなくビルドが止まる**） |
| `guard` に `else` が無い | `Warning: [0087]` / ``Warning (guard_inexhaustive): ... write `guard!` if the panic is intended.`` |
| 未使用の import | `Warning: [0029]` / `Warning (unused_package): Unused package 'mmm-app/core/tree'` |
| テスト対象のファイル名の綴り間違い | `Error: Failed to canonicalize input filter directory `doc/nope_wbtest.mbt`` EXIT=127 |

**テスト失敗の逐語**（`assert_eq` の形式。EXIT=2）:

```
[mmm-app/core] test tree/scan_wbtest.mbt:44 ("...") failed: doc/scan_wbtest.mbt:46:3-46:40@mmm-app/core FAILED: `"x" != "y"`
diff:
-"x" +"y"
Total tests: 14, passed: 13, failed: 1.
```

**書かない綴り**（deprecated / 存在しない）: `typealias`（`pub type A = B` が正）/ `not(x)`（`!x`）/
`rev_inplace`（`rev_in_place`）/ ArrayView の `to_array`（`to_owned`）/ `Option::or`（`unwrap_or`）/
`String::charcodes`（存在しない）/ `String::substring`（`str[:]` か `String::unsafe_substring`）。
`s[i]` の型は `Char` ではなく **`UInt16`**（整数と比べるなら `.to_int() == 10`）。
`s[a:b]` は端がサロゲート途中だと **panic** するので、任意のオフセットで切るなら
`String::unsafe_substring(s, start~, end~)`。

---

## §19. 各群への個別指示

**共通の規律（5 群とも）:**

1. **自分の所有ファイルしか編集しない**（§2）。他群のファイルへの修正は**差し戻し**で行う。
   スタブも投機的な追加も禁止
2. **Run 行は絶対パス**。Step 2 / 4 は**ファイル指定**、群の締めだけ `-p`（§17）
3. **計画に残っている「契約の表に足すこと」「⚠」の段落は削る**（本書で取り込み済み。§5）
4. 本書と自分の計画が食い違ったら、**本書が正**

### G1 — 型と走査（Task 1〜11 + 新設 10.5）。テスト 24 → **25** 本

| 指摘 | 重み | 直す場所 | 直し方 |
|---|---|---|---|
| R1-04 / R2-02 / R3-05 | 重大・致命 | **新設 Task 10.5**（Task 10 と Task 11 の間） | `core/tree/spell.mbt` を **Create**。中身は §12 の逐語（`pub(all) struct Spell` / `pub let spell` / `pub fn eol_text`）。**テストは足さない**（値の固定は G3 Task 40 の 2 本が持つ）。Step 4 Expected: `Total tests: 25, passed: 25, failed: 0.`（Task 3 の +1 を含む）。`moon check` は `0 errors`（読み手がまだ居ないので警告は出うる。**可視性を下げて黙らせない**）。コミット: `feat: ✨ 正規形の綴りを 1 か所に括る` |
| R1-11 | 軽微 | **Task 3**（check） | 条件 4 の文言を「**Implicit の子に項目は居ない**」に、違反メッセージを **`Implicit の子が項目 (id=7)`** に直す（§7）。テストを 1 本足して意図を固定する — `test "条件 4: Implicit の連鎖は合法（C16）" { let doc = make_doc([make_root(2, make_head("r"), [make_wing(Left, make_branch(3, Implicit, [make_branch(4, Implicit, [make_branch(5, make_head("b"), [])])]))])]); assert_eq(check(doc), []) }`。Task 3 の Expected を 12 → **13**、以降の本数を全部 +1 |
| R1-12 / R3-16 | 軽微 | **Task 1**（make_wbtest.mbt） | `make_list` → **`make_item`** に改名（型は `Sign::Item`。同じものを 2 つの語彙で呼ばない）。役割欄の「**全群が使う**」を「**G1 が置き、G3・G4・G5 のテストが葉の組み立てに使う**」に直す（本書 §4 で事実のほうを揃えたので、この記述は正しくなる） |
| R1-07 | 重大 | **Task 11 Step 9** | 申し送り 1・2 を削る（本書 §5・§15 が取り込み済み）。代わりに「**§15 の裁定 9 件が本書に載っていることを確認する**」だけを残す。申し送り 3（G2 への引き継ぎ）は本書 §6・§9 に入ったので、こちらも削る |
| R3-15 | 軽微 | 全 Task の Run 行 | 既に絶対パス。**Step 2 / 4 のテストはファイル指定に揃える**（`moon -C <root>/core test tree/<file>_wbtest.mbt`）。締め（Task 11）だけ `-p` |

**G1 の終わりの形**: `moon -C <root>/core check tree` が 0 errors /
`moon -C <root>/core test -p mmm-app/core/tree` が `Total tests: 25, failed: 0` /
`moon -C <root>/core fmt --check tree` が EXIT=0 / 旧 core の JS が今までどおり建つ。

### G2 — 読み（Task 20〜26）。テスト 22 → **23** 本

| 指摘 | 重み | 直す場所 | 直し方 |
|---|---|---|---|
| **R1-01 / R2-01 / R3-02** | **致命（3 人全員）** | **Task 25**（畳み） | §9 の規則を実装する。(1) `fn is_summary(text : String) -> Bool { text.has_prefix(spell.label_open) && text.has_suffix(spell.label_close) }` を `parse.mbt` に置く。(2) `Build` に `mut fresh : Bool` を足し、既定は `false`。(3) `Open` の腕の末尾で `b.fresh = true`、`Blank` の腕では**変えない**、`Verse` の腕は `if b.fresh && is_summary(text) { b.fresh = false }`（何もしない）／でなければ `b.fresh = false` してから従来の処理、**その他すべての腕は先頭で `b.fresh = false`**。(4) テストを 1 本足す — `test "summary は details の直後の 1 枚だけ読み飛ばす（法則 1・2 の要）" { assert_eq(parse_sig("# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n</details>\n"), "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b()[]]]]") }`。Task 25 の Expected を 19 → **20**、Task 26 を 22 → **23** |
| R1-01 追記 | 致命 | **Task 25** | **位置を無視する実装（前置/後置だけ見る）にしてはならない。** body の途中に手で置かれた `<summary>` まで消え、意味の損失が広がる。査読が提案した「位置は問わない」版は**裁定 1 で却下**されている |
| R2-02 / R3-05 | 重大・致命 | **前提 §2** | 「`spell.mbt` が置いてあること」の段落から **⚠ の申し送りを削り**、「**前提: G1 Task 10.5 が済んでいること**」に書き替える |
| R2-09 | 軽微 | **概要 99 行目** | 「綴りを間違えたときは `Total tests: 0` になる」を差し替える → 「ファイル指定は綴りを間違えると `Error: Failed to canonicalize input filter directory` で **EXIT=127** になり、黙って緑にはならない（`Total tests: 0` で緑になるのは `-p` の綴り間違いだけ。§17 の罠）」 |
| R2-13 | 軽微 | **Task 22 Step 2** | Expected を差し替える → 「領土の判定がまだ無いので、見出しが項目の子になる。`Total tests: 9, passed: 6, failed: 3.` EXIT=2」（Step 1 はテストしか足さないので `[4021]` は起きない） |
| R2-15 / R3-15 | 軽微 | 全 Task の Run 行 | `moon -C core ...` を絶対パスへ（`moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`） |
| R1-02 / R2-03 / R3-01 | 致命 | **Task 22（現状維持）** | `hashes(level : Int, label : String) -> String` は **G2 の所有として本書 §4 に登録済み**。G2 は何も変えない。衝突する G4 側が削除される |
| S3 | 申し送り | **概要「G1 と共有する前提」** | 本書 §6「走査の前提」に入ったので、計画からは「契約の表に足すこと」の文言だけ削り、表は残してよい |

**受け入れ条件**: `parse` が出した Doc は**必ず `check` が空**（Task 26 の網で確かめる）。

### G3 — 書き（Task 40〜46）。テスト **21** 本（変わらず）

| 指摘 | 重み | 直す場所 | 直し方 |
|---|---|---|---|
| R1-04 / R2-02 | 重大 | **Task 40** | Files の **Create を削る**（`core/tree/spell.mbt` は G1 Task 10.5 が置き済み）。Step 3 を「**実装は無い。G1 が置いた `spell.mbt` が §12 の逐語であることを確認し、差分があれば §12 に揃えるよう G1 へ差し戻す**」に書き替える。Step 1 の 2 本のテスト（`spell` の値の固定）は**そのまま残す** — これが `spell` の唯一の見張り |
| **裁定 1 / R1-03 / R2-07 / R3-03** | **致命** | **Task 46** | カタログ C8 の**元 md と新 md の両方**を `<summary>` 込みに訂正する（§9 の逐語をそのまま書く）。触るのは `docs/superpowers/specs/2026-08-29-op-cases.md` の C8 だけで、他のケースには 1 バイトも触らない。mermaid の `〔畳〕` は直さない |
| R2-12 / R3-10 | 軽微・重大 | **概要「新設する名前の一覧」** | `same_side` の説明から「**G5 の flip_side でも要る**」を削り、「**G4 の `project.mbt` のバケツ分けで要る**」に直す（G5 は `flipped` しか使わない） |
| R1-12 / R3-16 | 軽微 | **Task 41 の wbtest ヘルパ** | `write_of` と `write_wing` を**削除**して `make_doc` / `make_wing` を呼ぶ。`write_tree` / `write_head` / `write_item` / `write_gap` は残すが、中身を `make_*` の合成で書く（生の struct リテラルを書かない） |
| S1・S5・S6・S7・S8・S9・S10 | 申し送り | **概要「契約・カタログへ足すこと」** | **節ごと削る**（6 件とも本書 §2・§5・§6・§9・§17 に取り込み済み） |
| R3-15 | 軽微 | Run 行 | 既に絶対パス。Step 2 / 4 のファイル指定はそのままでよい |

**受け入れ条件（変えない）**: **空行の判断が `put` の外に 1 つも無いこと**
（`pen.sb.write_string(pen.eol)` が `put` 以外に現れない）。
綴りに関わる値が `spell` 以外に無いこと。出力は必ず改行で終わる（空文書だけが空文字列）。

### G5 — 操作（Task 80〜92 + 94。旧 Task 93 は G4 へ移管）。テスト **32** 本

**着手前に必ずやること（裁定 7）**: `scratchpad/v2/g5v/` に `lock` モジュールを写し、
`core/tree` へ道具層と `op.mbt` / `diff.mbt` / 各 wbtest を置いて **Task 84〜92 を段階ごとに実走**する。
`g2.md` の §「実測の裏付け」と同じ形式で、**各 Task の終わりの本数表**と
**`op_shape` の期待文字列**を実測値に置き換えてから計画を確定させる。
とくに **Task 89 の move 9 組合せの 9 行**、**Task 87 の conform 4 本**、
**Task 91 の `edits[0].from` / `to` の数値**は、実測前に着手してはならない。

| 指摘 | 重み | 直す場所 | 直し方 |
|---|---|---|---|
| **裁定 4 / R1-09** | **重大** | **Task 86**（flipSide） | ループの前に `let tops = crown(doc, ids)` を挟み、`for id in tops` に変える（`crown` は resolve できない id を落とすので、`hit` が false のまま抜けたときの `pick(ids)` はそのまま使える）。テストを 1 本足す — `test "root とその直下の枝を同時に選んでも二重には反転しない" { let doc = op_doc(); assert_eq(op_said(flip_side(doc, [2, 3])), "ok"); assert_eq(op_shape(doc), "doc(R2[<3(4(5))] R6[<7])") }`（**期待文字列は g5v の実測で確定させる**）。Task 86 の Expected を +3 → **+4**、G5 累計 31 → **32** |
| **裁定 3 / R2-08 / R3-06** | **致命** | **Task 92**（reflect） | (1) 前提を「**G2 の `parse` と G3 の `serialize` が置かれていること。無ければ Task 91 で止める。スタブは 1 バイトも書かない**」に書き替え、「parse / serialize がスタブでも通る」の 2 行を**削除**する。(2) `reflect_json` を**書かない**（G4 の `json.mbt` へ移管）。`quote` への言及と「G4 より先に着手する場合は…」の但し書きを削除する。(3) `diff.mbt` に `pub(all) struct Reflection { ok : Bool; reason : String; text : String; edits : Array[Edit] }` を新設し、`reflect` の戻りを `String` から **`Reflection`** に変える:<br>`pub fn reflect(md : String, op : (Doc) -> Verdict) -> Reflection { let doc = parse(md); match op(doc) { Rejected(reason) => { ok: false, reason, text: md, edits: [] }; Applied => { let text = serialize(doc); { ok: true, reason: "", text, edits: safe_edits(md, text) } } } }`。(4) 「拒否は無編集」のテストを JSON 比較からフィールド比較に変える（`assert_eq(r.ok, false)` / `assert_eq(r.reason, "見つからない (id=7)")` / `assert_eq(r.text, "#  r  \n\n## a\n")` / `assert_eq(r.edits.length(), 0)`）。JSON の逐語は G4 の `json_wbtest.mbt` が固定する。**本数は 2 本のまま** |
| **R1-10** | **重大** | **概要** | §「実測の裏付け」を新設し、上の g5v の実測結果（本数表と期待文字列）を貼る |
| 裁定 5 / R2-16 / R3-07 | 重大 | **Task 80・83・94** | 腕数の定義と数字は**本書 §11 が正**。Task 94 の「腕数の定義」節は本書 §11 を指すだけにし、判定基準の数字（合格 3 以下・警告 4 腕・死 5 腕）と**逐語コメント 2 か所**（`tool.mbt` の冒頭と `amend` の直前）を §11 からそのまま写す。「契約 §6 の数字を直すこと」の申し送りは削る |
| R2-14 / R3-11 | 軽微 | **Task 84 と名前の一覧** | `fn ahead(a : Array[Int], b : Array[Int]) -> Bool` を Produces と一覧に足す（op.mbt の private は **16 本**） |
| R3-12 | 軽微 | **Task 84** | `under(path, top)` の第 2 引数を **`anc`** に、`crown` の `let mut top = true` を **`let mut keep = true`** に改名（`if above.length() < path.length() && under(path, above) { keep = false }` / `if keep && !twice`）。G2 の `fn top(b : Build) -> Frame` を影にしない |
| R3-14 | 軽微 | **Task 94 Step 4** | `moon ... fmt --check tree` の**ままでよい**。査読は `doc tree/js` を提案したが、裁定 3 の依存順で G5 は G4 より前に走るので `tree/js` はまだ存在しない。`doc tree/js` は **G4 Task 71** が持つ |
| 裁定 1 | 致命の随伴 | **Task 94 Step 3**（`docs/ops.md`） | 「注意: rename はリンクを壊す」の隣に、**§9 の爆風半径の 1 行**（手で書いた `<summary>` は残らない）を節として足す。綴りは `docs/` の制約（`---` と `***` と setext を使わない）に従う |
| R3-08 / R3-09 | 重大 | **Task 93 → 移管** | Task 93（`test/treeOps.test.ts`）は **G4 Task 72 へ移す**。G5 は着手しない。2 件の直しも G4 が入れる |
| S16〜S21 | 申し送り | **概要「契約に無く、この群で足すもの」** | **表ごと削る**（6 件とも本書に取り込み済み） |

**受け入れ条件（変えない）**: 操作 3 本と回復 2 本の**容器の腕が 0**。`Sub` を変換する場所が 1 か所。
`Verdict` に `derive` を足さない。

### G4 — 境界・法則・カタログ（Task 60〜71 + 新設 72）。mbt **10** 本 / TS **37** 本

**この群は最後に走る検証群**（裁定 3）。G1〜G3・G5 が緑にした後に着手する。
**Step 3 に書くのは自分の所有ファイルの実際のコードだけ。** 赤が出たら、下の表で担当群へ差し戻す。

**赤の差し戻し表**（Task 66〜70 の Step 3 に共通して置く）:

| 赤の見え方 | 差し戻し先 |
|---|---|
| 指紋の `e` の後の `^` / `_` が違う | 畳み — G3 Task 44 / G2 Task 25 |
| `>` / `<` が違う | 側 — G3 Task 43 / G2 Task 24 |
| `i` が増減する | Implicit の導出 — G2 Task 21 |
| `i` が `eh_` に化けた | **serialize が勝手に昇格している**。G3 Task 41 へ差し戻す（昇格は G5 の `conform` が model 側で済ませている） |
| `(...)` の中身が違う | 中身の認定 — G2 Task 23 |
| 末尾改行・空行の本数 | G3 Task 41 の `put` |
| `o…:<summary>…` が増える | **`<summary>` の読み飛ばし** — G2 Task 25（§9） |
| `check` が空でない木が出た | **parse のバグ**（serialize でも sig でもない）— G2 |

差し戻すときは**該当群の wbtest に固定を 1 本足してもらってから**この Task に戻る。
**G4 はテストを 1 行も緩めない。**

| 指摘 | 重み | 直す場所 | 直し方 |
|---|---|---|---|
| **R1-02 / R2-03 / R3-01** | **致命** | **Task 69 Step 3** | `fn hashes(line : String, at : Int) -> Int` のコードブロックを**丸ごと削除**。本文を差し替える → 「**新しい実装は書かない。** 7 個以上の `#` は G1 の `head_at`（level に上限なし）が、項目の領土内の見出しの Opaque 化は G2 Task 22 が既に担当している。赤が出たらその 2 か所へ差し戻す。この Task で `core/tree/scan.mbt` と `core/tree/parse.mbt` に手を入れてはならない（同名の `hashes` を置くと `[4051]` でビルドが止まる）」。Step 5 のコミット対象を `test/treeDialect.test.ts` **だけ**にする |
| **R1-03 / R2-07 / R3-03** | **致命** | **Task 70（C8）** | 2 つの md を §9 の逐語に揃える。`const md = "# r\n\n## a\n\n### b\n\n<details>\n\n<summary>b</summary>\n\n#### c\n\n</details>\n";` / `const after = "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n<details>\n\n<summary>b</summary>\n\n#### c\n\n</details>\n\n</details>\n";`。**指紋の期待値はそのまま**。冒頭「カタログを読むときの注意」に 1 行足す → 「**C8 の md は `<summary>` 行を含む形が正**（G3 Task 46 が op-cases.md を先に直す）」 |
| **R1-05 / R2-06** | **重大** | **Task 67 Step 3** | `fn spellable(kin, at)` と「`write_branch` の Implicit の腕を 2 択にする」を**削除**。差し戻しの指定に差し替え、1 行足す → 「**飛びが表現できない位置の implied は G5 Task 87 の `conform`（`raised(s, true)`）が操作の側で潰している。** ここで serialize に安全弁を二重に置かない。serialize が model と違うものを書いたら**法則 1 が定義ごと壊れる**。それでも法則 1 が落ちるなら、落ちた木が `check` を通っているかを先に見る」 |
| **R1-06 / R2-04 / R2-05 / R3-04** | **重大・致命** | **Task 66 / 68 / 69 / 70 の Step 3** | `gap` / `trim_tail` / `spellable` / `fold_owner` / `hashes` / `close_items` の **6 つのコードブロックを全部削除**。上の差し戻し表に置き換える。とくに: `trim_tail` は不要（`put` が各行に eol を 1 つ付けるので出力は必ず改行 1 本で終わる）／`gap` は G3 の受け入れ条件（空行の判断は `put` 1 本）を正面から破る／`sb` と `nl` は G3 のスコープに存在しない（`pen.sb` / `pen.eol`）／`fold_owner` の `open[...] + depth * 0` は無意味／`close_items(stack : Array[Int], ...)` は G2 の `Array[Frame]` と型が合わない。**Step 5 のコミット対象から `core/tree/serialize.mbt` / `parse.mbt` / `scan.mbt` を全部外す**（Task 66 は `test/treeLaws.test.ts` のみ、Task 68 は `core/tree/laws_wbtest.mbt` のみ、Task 69 は `test/treeDialect.test.ts` のみ、Task 70 は `test/treeCases.test.ts` のみ） |
| **R1-07** | **重大** | **Task 69** | `DIALECT`（骨格の数）に加えて **2 つ目の表 `READING`**（md → 指紋）を置く。§15 の 4 行は必須。残る 5 件は `scan_wbtest.mbt` で固定済みである旨を `why` に併記する。treeDialect の本数を 2 → **3** に直す。あわせて**法則 4 は封筒を剥がした後の本文に掛ける**（申し送り S10。封筒は lezer では `HorizontalRule` + `SetextHeading2` に読まれる） |
| **裁定 3** | **致命の随伴** | **Task 60（json.mbt）** | `reflect_json(r : Reflection) -> String` を **G4 が実装する**（§13 の逐語）。`json_wbtest.mbt` に 1 本足す — `test "reflect_json は境界の形をちょうど 1 つ吐く" { assert_eq(reflect_json({ ok: false, reason: "見つからない (id=7)", text: "#  r  \n\n## a\n", edits: [] }), "{\"ok\":false,\"reason\":\"見つからない (id=7)\",\"text\":\"#  r  \\n\\n## a\\n\",\"edits\":[]}") }`。json_wbtest 4 → **5** |
| **裁定 3** | **致命の随伴** | **Task 62（exports.mbt）** | 3 本の操作を `@tree.reflect_json(@tree.reflect(md, fn(d) { … }))` の形にする（§13 の逐語） |
| R2-12 / R3-10 | 重大 | **Task 61 Step 3** | `fn same(a : Side, b : Side) -> Bool` を**削除**し、`map_bucket` の中を `if same_side(b.side, side) {` に変える。Interfaces の Produces から `same` を外し、Consumes に `same_side`（G3 `serialize.mbt`）を足す。§新設する名前の一覧からも `same` を削る |
| R1-13 | 軽微 | **Task 63 / Task 66** | (1) `test/_tree.ts` の `Edit` / `Reflection` / `Card` / `MapNode` / `MapBranch` / `MapTree` / `Mindmap` を全フィールド **`readonly`**、配列を `readonly T[]` にする（法則 3 と「MindmapTree は変異させない」を型で見張る。実行時コストはゼロ）。`export { mbt }` を足す。(2) `test/treeLaws.test.ts` に 1 本足す — `test("法則 3: 境界から木の形で出る口は project だけ", () => { assert.deepEqual(Object.keys(mbt).sort(), ["check","deleteNodes","flipSide","format","moveNodes","project","sig"]) })`。treeLaws 11 → **12** |
| R1-14 / R2-10 / R3-13 | 軽微 | **Task 63 Step 3** | `existsSync` / `dirname` / `fileURLToPath` の import、`CORE_JS` の宣言、`if (!existsSync(CORE_JS)) { throw ... }` を**全部削除**し、import 行の上にコメント 1 行を置く → `// 出力が無いと ERR_MODULE_NOT_FOUND で落ちる。先に \`pnpm run core\` を実行すること。`（静的 import が先に評価されるのでガードには到達しない）。`readdirSync, readFileSync, statSync` の import は残す。**申し送り S14 の「出力の存在検査」は却下**なので、その 1 件を申し送りから落とす |
| R2-11 | 軽微 | **Task 71 Step 1**（ci.yml） | 代入で失敗を握り潰さない形に直す（`bash -e` は `out=$(...)` が非ゼロで終わった瞬間にステップを打ち切り、`echo "$out"` に到達しない）:<br>`set +e` / `out=$(pnpm run test:core 2>&1)` / `status=$?` / `set -e` / `echo "$out"` / `if [ $status -ne 0 ]; then exit $status; fi` / `if echo "$out" \| grep -q "Total tests: 0,"; then echo "テストが 1 本も走っていない（-p の綴りを疑う）"; exit 1; fi` |
| R3-17 | 軽微 | **Task 64**（pathological） | `["NUL", "# a\n\n \n"]` を `["空白だけの行", "# a\n\n \n"]` に改名し、**本当に NUL を含む行**を 1 本足す（`["NUL", "# a\n\n\u0000\n"]`）。下限は 28 → **29** |
| R2-15 / R3-15 | 軽微 | 全 Task の Run 行 | `moon -C core ...` / `pnpm ...` を絶対パスに揃え、`pnpm` を使う Step には「（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`。別のワークツリーから叩くと旧 core を測る）」の 1 行を足す |
| S11・S12・S13・S14・S15 | 申し送り | **概要「契約に足すこと（5 件）」** | **節ごと削る**（本書 §13・§16 に取り込み済み。S14 の 4 件目だけは却下） |
| **R3-08 / R3-09** | **重大** | **新設 Task 72**（`test/treeOps.test.ts`、G5 Task 93 から移管） | g5.md Task 93 の逐語をそのまま持ってきて、**2 か所だけ直す**。(1) delete のテストは id の同一性ではなく**ノード数**で見る（parse は `first_id` から振り直すので、消した id を次のノードが名乗る）:<br>`const before = idsOf(doc.project(md)).length;` / `const r = doc.deleteNodes(md, [victim]);` / `holds(md, r, "delete");` / `if (r.ok) { assert.ok(idsOf(doc.project(r.text)).length < before, \`delete でノードが減っていない: ${brief(md)}\`); }`<br>(2) 「無操作は無編集」のテストは**左の枝が居る文書を飛ばす** — `if (root.right.length === 0) continue;` の直後に `if (root.left.length > 0) continue; // at は wings の index。バケツの index ではない` を足す。treeOps は **5** 本 |

**G4 の終わりの形**: `pnpm run core` / `pnpm run check` / `pnpm run test:core`
（`Total tests: 111` 以上・`Total tests: 0` でない）/ `pnpm test`（`ℹ fail 0`）/
`moon -C <root>/core fmt --check tree tree/js` が EXIT=0 / CI が新パッケージを乗せている。

---

## §20. 査読 47 件の処理台帳

**致命 10 / 重大 18 / 軽微 19。1 件も落としていない。**
「反映先」は本書の節、「実行先」は §19 の指示。

| ID | 重み | 主題 | 反映先 | 実行先 |
|---|---|---|---|---|
| R1-01 | 致命 | `<summary>` の読み飛ばしが G2 に無い | §9 | G2 Task 25 |
| R1-02 | 致命 | `hashes` の二重定義 | §4 | G4 Task 69 |
| R1-03 | 致命 | C8 の期待 md に `<summary>` が無い | §9 | G4 Task 70 / G3 Task 46 |
| R1-04 | 重大 | `spell.mbt` の所有が二重 | §2 | G1 Task 10.5 / G3 Task 40 |
| R1-05 | 重大 | `spellable`（serialize が Implicit を昇格） | §19 の差し戻し表 | G4 Task 67 |
| R1-06 | 重大 | Task 66/68/70 の投機コード | §2・§19 | G4 Task 66/68/70 |
| R1-07 | 重大 | 読みの裁定 9 件が方言表に無い | §15 | G4 Task 69 / G1 Task 11 |
| R1-08 | 重大 | 申し送り 21 件を実行する Task が無い | §5（本書が実行） | 全群（文言の削除） |
| R1-09 | 重大 | `flip_side` が `crown` を通らない | §10（裁定 4） | G5 Task 86 |
| R1-10 | 重大 | G5 に実測が無い | §19 G5 の冒頭（裁定 7） | G5 全体（g5v） |
| R1-11 | 軽微 | 条件 4 の文言と実装の齟齬 | §7 | G1 Task 3 |
| R1-12 | 軽微 | テストヘルパの四重化 | §4 | G1 Task 1 / G3 / G4 / G5 |
| R1-13 | 軽微 | 法則 3 に検証が無い | §14・§13 | G4 Task 63 / 66 |
| R1-14 | 軽微 | `existsSync` に到達しない | §13 | G4 Task 63 |
| R2-01 | 致命 | `<summary>`（R1-01 と同一） | §9 | G2 Task 25 |
| R2-02 | 重大 | g1.md に spell の Task が無い | §2 | G1 Task 10.5 |
| R2-03 | 重大 | `hashes`（R1-02 と同一） | §4 | G4 Task 69 |
| R2-04 | 重大 | Task 66〜70 の Step 3 に Green が無い | §19 の差し戻し表 | G4 Task 66〜70 |
| R2-05 | 重大 | `trim_tail` が参照する `nl` / `sb` が無い | §19 | G4 Task 66 |
| R2-06 | 重大 | `spellable`（R1-05 と同一） | §19 | G4 Task 67 |
| R2-07 | 重大 | C8（R1-03 と同一） | §9 | G4 Task 70 |
| R2-08 | 重大 | Task 92 の依存（parse/serialize/quote） | §3（裁定 3） | G5 Task 92 |
| R2-09 | 軽微 | g2 の `Total tests: 0` 誤記 | §17 | G2 概要 |
| R2-10 | 軽微 | `existsSync`（R1-14 と同一） | §13 | G4 Task 63 |
| R2-11 | 軽微 | ci.yml が `bash -e` でログを落とす | §19 | G4 Task 71 |
| R2-12 | 軽微 | `same` と `same_side` の二重 | §4 | G4 Task 61 / G3 概要 |
| R2-13 | 軽微 | g2 Task 22 Step 2 の Expected | §19 | G2 Task 22 |
| R2-14 | 軽微 | `ahead` が名前の一覧に無い | §4 | G5 Task 84 |
| R2-15 | 軽微 | cwd の与え方が 2 通り | §17 | G2 / G4 |
| R2-16 | 軽微 | 腕数の定義が 2 つ | §11（裁定 5） | G5 Task 94 |
| R3-01 | 致命 | `hashes`（R1-02 と同一） | §4 | G4 Task 69 |
| R3-02 | 致命 | `<summary>`（R1-01 と同一） | §9 | G2 Task 25 |
| R3-03 | 致命 | C8（R1-03 と同一） | §9 | G4 Task 70 |
| R3-04 | 致命 | G4 が他群の所有ファイルへ commit | §2（裁定 2） | G4 Task 66〜70 |
| R3-05 | 致命 | `spell.mbt` の依存（提案は G3 据え置き） | §2 — **裁定 2 により G1 所有を採る** | G1 Task 10.5 |
| R3-06 | 致命 | `reflect_json` / `quote` の依存 | §3（裁定 3。G4 へ移管して依存ごと消す） | G5 Task 92 / G4 Task 60 |
| R3-07 | 重大 | 腕数の定義（R2-16 と同一） | §11 | G5 Task 94 |
| R3-08 | 重大 | delete のテストが id で偽陽性 | §19 | G4 Task 72 |
| R3-09 | 重大 | 「無操作は無編集」が左バケツで落ちる | §19 | G4 Task 72 |
| R3-10 | 重大 | `same_side`（R2-12 と同一） | §4 | G4 Task 61 |
| R3-11 | 軽微 | `ahead`（R2-14 と同一） | §4 | G5 Task 84 |
| R3-12 | 軽微 | `under` / `top` の名前の影 | §4 | G5 Task 84 |
| R3-13 | 軽微 | `existsSync`（R1-14 と同一） | §13 | G4 Task 63 |
| R3-14 | 軽微 | `fmt --check tree tree/js` | §17 — **裁定 3 で前提が消えた**（G5 は `doc` のまま、`doc tree/js` は G4 の締め） | G5 Task 94 / G4 Task 71 |
| R3-15 | 軽微 | コマンドの綴りが 3 通り | §17 | 全群 |
| R3-16 | 軽微 | `make_*`「全群が使う」は嘘 | §4（**事実のほうを揃えた**） | G1 Task 1 / G3 / G4 / G5 |
| R3-17 | 軽微 | `pathological` の NUL が NUL でない | §13 | G4 Task 64 |

### 査読の提案を採らなかった 3 件（理由つき）

| ID | 査読の提案 | 採らなかった理由 |
|---|---|---|
| R3-05 | `spell.mbt` は G3 のまま。依存順を `G1 → G3 Task 40 → (G2 / G3 / G5) → G4` に割る | **裁定 2** がファイル所有権の厳守を求めており、`spell.mbt` は G1 が Task で作ると定めた。依存順を群の内部タスクの粒度で割ると、5 群の並行の単位が崩れる |
| R1-11 | 違反メッセージ `Implicit の子が見出しでない (id=7)` は据え置き | 据え置きの理由（G1 のテストが逐語で固定している）は **G1 が未着手である以上成立しない**。破れの実体は「子が項目」なので、文言もメッセージも実体に揃える（§7） |
| S14 の 4 件目 | `test/_tree.ts` に「出力の存在検査」を足す | R1-14 / R2-10 / R3-13 のとおり、静的 import が先に `ERR_MODULE_NOT_FOUND` で落ちるのでガードに到達しない。**動かないコードは負債**なので、素直にエラーを読ませる |

---

## §21. スコープ外（作らない）

UI 接続 / TS の書き換え（`src/coreApi.ts` `src/main.ts` `src/app/paste.ts` は触らない）/
すげ替え v1 / add・rename・fold・setSign・indent・outdent・content 系 / convert・format コマンド /
旧 core の削除 / render の接続。
`amend` はスコープ外の fold・setSign のための住所として置くだけ（§11 の警告の話）。

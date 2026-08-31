# 新 core（MmmTree）実装計画

> **エージェント実行者へ:** 必須サブスキル — `superpowers:subagent-driven-development`（推奨）
> または `superpowers:executing-plans` を使い、タスクごとに実装すること。
> ステップは `- [ ]` のチェックボックス形式で進捗を追う。

**Goal:** md と同型の文書モデルを MoonBit に新設し、parse / serialize / 操作 3 種 /
反映 v0 までを、法則のファズで検証しながら作る。

**Architecture:** テキストが真実。`parse` が md を役割型の木（Doc > Root > Wing > Branch）に読み、
`serialize` が正規形の md を吐く。操作は木を直接変異させ、差分を editSets として返す。
型の異種性は**道具 4 つ（resolve / pluck / graft / amend）に幽閉**し、操作に腕を生やさない。
正しさは 4 つの法則が持ち、実在コーパスとランダム生成の両方で機械検証する。

**Tech Stack:** MoonBit（新パッケージ `mmm-app/core/tree`。外部依存ゼロ）/
TypeScript（`branch --test`。`@lezer/markdown` は法則 4 の外部審判）/ 旧 core とは別パッケージで共存。

**Spec:**
- [文書モデル設計（憲法）](../../specs/2026-08-29-doc-model-design.md)
- [操作ケースカタログ C1〜C17](../../specs/2026-08-29-op-cases.md)
- [型の再設計](../../specs/2026-08-31-structure-redesign.md)
- [実装契約](contract.md) — **型・名前・所有権・コマンドの唯一の参照元**
- [MoonBit 実測](moonbit-semantics.md) — 意味論と構文の実測記録（**契約と食い違ったらこちらが真**）

---

## Global Constraints

この節の要求は、全タスクの要件に暗黙に含まれる。

- **パッケージ**: `mmm-app/core/tree`（新設）。旧 `mmm-app/core` は 1 バイトも触らない
- **テスト**: 各タスクは**ファイル指定**で走らせる
  （`moon -C <repo>/core test tree/<file>_wbtest.mbt`）。群の締めだけ `-p mmm-app/core/tree`。
  **`-p` の綴りを間違えると黙って EXIT=0（`Total tests: 0`）**になるので、
  Step 4 の Expected には必ず本数を書く
- **整形**: `moon -C <repo>/core fmt tree` → `fmt --check tree`。掲載コードは fmt 前の姿なので、
  当てた差分ごとコミットする（`fmt --check` の失敗は EXIT=127）
- **綴りの規律（実測由来）**: `pub type X = Y`（`typealias` は無い）/ 否定は `!x` /
  ラベル付きペイロードの呼び出しは `Image(alt="a")`（`alt~=` は `Error: [3016]`）/
  未定義の値は `Error: [4021] The value identifier X is unbound.` /
  **構造体は参照**（コピーされない。配列を掴んで remove / insert すれば元の木に効く）/
  不変フィールドの差し替えは「所有する配列 + index への struct-update 代入」
  （直接代入は `Error: [4087]`）/ `pub` は別パッケージからの構築を許さない（`pub(all)` が要る）/
  `*_wbtest.mbt` はパッケージ内で名前空間を共有する（同名は `Error: [4051]`）
- **環境変数の前置き（`VAR=値 コマンド`）は使わない** — Windows / PowerShell で構文エラー
- **パスは絶対パス**、git は `git -C <repo>` 形。コミットは `<Type>: <絵文字> <日本語タイトル>`
- **1 ファイルは 1 群が所有する**（契約 §2 の表）。**他群のファイルには 1 バイトも書かない** —
  他群の直しが要るときはスタブも置かず、契約 §19 の差し戻し表で担当群へ返す

## スコープ

**作る**: 型 / parse / serialize / 法則 1・2・4 の検証基盤 / 操作 3 種（move・flipSide・delete）/
反映 v0（全文正規形 → diff → editSets）/ project（MindmapTree の JSON まで）。

**作らない**（殺す条件の判定後に別計画）: UI 接続 / TS の書き換え / すげ替え v1 /
add・rename・fold・setSign・indent・outdent・content 系 / convert・format コマンド /
render の接続 / 旧 core の削除。

**殺す条件**: 道具（resolve / pluck / graft / amend）の腕が 3 で止まらなくなったら、
この設計は死んでいる。判定は Task 94 が行い、結果を `docs/ops.md` に書き残す。

## 規模

53 タスク / テスト 150 本（MoonBit 113・TypeScript 37）/ 新規 33 ファイル + 既存 4 ファイルの変更。

## 群と着手順

**依存順（この順で着手する）**: G1 → G2 / G3（並行）→ G5 → G4

| 群 | 範囲 | 内容 |
|---|---|---|
| [1. 型と走査](1-types-scan.md) | Task 1〜11 | 型・指紋・不変条件・行の走査・綴りの定数 |
| [2. 読み](2-parse.md) | Task 20〜26 | 骨格の積み上げ・Implicit・単調性・側・畳み・中身の認定 |
| [3. 書き](3-serialize.md) | Task 40〜46 | 正規形の全規則と、通しの検算 |
| [4. 境界と法則](4-laws.md) | Task 60〜72 | JSON・投影・生成器・法則 1/2/4・カタログ・CI |
| [5. 操作](5-ops.md) | Task 80〜94 | 道具層・delete / flipSide / move・反映 v0・殺す条件の判定 |

G4 が最後なのは、**全群を検証する群だから**。G4 のタスクで赤が出たら、
G4 は自分では直さず契約 §19 の差し戻し表に従って担当群へ返す。

### タスク一覧

**1. 型と走査**（Task 1〜11）— パッケージの新設と型 / 指紋 / 不変条件 / 走査の骨 /
見出し / 水平線と setext / リスト項目と容器のスタック / フェンスとインデントコード /
畳みの開閉と HTML コメント / 封筒の裁定 / 綴りの定数 / 群の締め

**2. 読み**（Task 20〜26）— 読みの器と骨格の積み上げ / 飛びは Implicit が埋める /
単調性（項目を閉じてから見出しを積む）/ 中身の認定 / 側の割り当て /
畳みと `<summary>` の読み飛ばし / 網（封筒・流儀・健全性）

**3. 書き**（Task 40〜46）— 綴りの定数の固定 / 筆と骨格行 / 中身 / 側の区切り /
畳みの details / 封筒と文書の散文 / 通しの検算とカタログ C8 の訂正

**4. 境界と法則**（Task 60〜72）— JSON / 投影 / 境界（JS へ 7 本）/ TS の窓口 /
病的な md の生成器 / 最小反例の縮小 / 法則 2 / 法則 1（md 種）/ 法則 1 の本丸（木の生成器）/
法則 4（外部審判）/ カタログ C1〜C17 / CI / 操作の性質のファズ

**5. 操作**（Task 80〜94）— 道具の座標系 / 道具の読み / 抜き挿しと変換表 / 書き替え /
拒否の文言と頂点集合 / delete / flipSide / 回復（conform）/ move / move の 9 組合せ /
Edit と apply / diff / 反映 v0 / 殺す条件の判定

## この計画が仕様を直させた 5 件

計画を実際のコードの粒度まで書き下ろす過程で、憲法の穴が見つかり、仕様側を改訂して塞いだ。

1. **トグルの帰属** — 「implied は side を持てない（昇格を伴う flipSide）」は誤りで撤回。
   トグルは隙間に付き、翼の占有者を問わない（C16 改訂）
2. **`- - -` の裁定** — 旧 core の方言（項目として読む）を捨て、CommonMark の水平線に揃えた
3. **項目の後ろの見出しは Item の子にならない** — 開いている項目を閉じてから付ける。
   implied の位置制約は「children の先頭」ではなく「前に見出しが居ない」（C17）
4. **文書頭の `---` の裁定** — 直後が空行でなく閉じがあれば封筒。空行規律が両者を分ける
5. **`<summary>` の読み飛ばし** — serialize が書く summary を parse が読み飛ばさないと、
   往復のたびに 1 枚ずつ増殖して法則 1 が壊れる。「details の直後の 1 枚を内容を見ずに捨てる」
   （代償として手書きの独自 summary はそのノードを触ったとき label 版に置き換わる — 爆風半径）

## 検証の経緯

計画は 2 巡の査読を経ている（致命 10 / 重大 18 → 致命 0 / 重大 0）。
主な発見は、`<summary>` の実装漏れ（3 人が独立に指摘）・同一パッケージ内の名前衝突・
他群のファイルへの投機的な書き込み・依存順の循環。
G1・G2・G3・G5 は使い捨てモジュールで**実際にコンパイルと実行を通してある**
（G1 25 本・G2 25 本・G3 21 本・G5 32 本）。

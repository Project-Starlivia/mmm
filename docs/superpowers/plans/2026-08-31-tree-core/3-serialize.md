# G3 — 書き（Doc → 正規形の md）

確定版の契約（`scratchpad/v2/contract2.md`）§10・§12・§16・§19 の G3。憲法 §4 の正規形の表を、
実際に動く 1 本の関数に落とす。**契約と食い違ったら契約が正。**

**この計画のコードはすべて実測済み。** 使い捨てモジュール
`C:/Users/taker/AppData/Local/Temp/claude/D--1-atrium-mmm--claude-worktrees-dnd-ux-improvement-1ebfc6/954c84b6-8b11-46ca-bd0f-361864110df4/scratchpad/v2/g3probe/`
（`moon.mod` + `doc/`（library、契約 §6 の型の逐語 + spell.mbt + serialize.mbt + serialize_wbtest.mbt））で、
Task 40〜45 の**各段階を順に組み立てて**通した。最終状態は
`moon check` 0 errors / `moon test tree/serialize_wbtest.mbt` **21 passed** / `moon fmt --check tree` EXIT=0。
書き出した md は `@lezer/markdown` 1.7.2 にも食わせて、外のパーサが同じ木に読むことを確かめてある（§外の審判）。
doc-model リポジトリは 1 バイトも変更していない。

**実測との差分は 1 つだけ** — 確定版の契約 §4 に従い、wbtest のヘルパ `write_of` / `write_slot` を
削除して G1 の `make_doc` / `make_slot` を呼ぶ形に、`write_tree` / `write_head` / `write_item` /
`write_gap` を `make_*` の合成に書き替えた。**組み上がる木も、書き出される md も、テスト本数 21 も
1 バイト・1 本も動かない**（`write_of` は `make_doc` と、`write_slot` は `make_slot` と定義が同一）。

---

## この群の概要

### 担当範囲

| ファイル | 所有 | 中身 |
|---|---|---|
| `core/tree/serialize.mbt` | **G3** | `serialize(doc) -> String` + 補助 19 本 + priv 型 2 つ |
| `core/tree/serialize_wbtest.mbt` | **G3** | `spell` の値 2 本 + カタログの md を逐語で固定する 19 本（計 21 本） |
| `docs/superpowers/specs/2026-08-29-op-cases.md` | **G3** | カタログ C8 の期待 md の訂正だけ（Task 46）。**他のケースには 1 バイトも触らない** |

**読むだけのファイル（1 バイトも書かない）**: `core/tree/doc.mbt`（型）/ `core/tree/spell.mbt`（綴り定数）/
`core/tree/make_wbtest.mbt`（木を組む葉の道具）— **3 本とも G1 の所有**。

**スコープ外**: `parse`（G2）/ 法則 1・2 のファズ（G4）/ 投影・境界（G4）/ 操作（G5）/
convert・format コマンド / すげ替え v1。この群が主張できるのは「同じ Doc からは常に同じ綴りが出る」ことと
「その綴りがカタログと一致する」ことだけで、往復（法則 1・2）は G2 が入って G4 が回す。

### 前提（契約 §3 の依存順）

`G1 → G2 / G3（並行）→ G5 → G4`。G3 が待つのは **G1 だけ**。

- **G1 の Task 1 が済んでいること** — `core/tree/make_wbtest.mbt` の
  `make_doc` / `make_center` / `make_slot` / `make_branch` / `make_head` / `make_item` を wbtest が呼ぶ
- **G1 の Task 10.5 が済んでいること** — `core/tree/spell.mbt`（`Spell` / `spell` / `eol_text`）。
  無いと Task 40 が `Error: [4021] The value identifier spell is unbound.` で止まる
- **G1 の Task 2 が済んでいること** — `core/tree/moon.pkg` と `core/tree/doc.mbt`（契約 §6 の型）が
  無いと 1 行もコンパイルできない。`check` / `sig` / `scan` には依存しない
- G2・G5 とは同じパッケージを共有するだけで、関数の依存は無い（並行して進めてよい）。
  G3 は `parse` を 1 回も呼ばない
- 綴りに関わる値は `spell` 以外に書かない。`serialize.mbt` に生の `"#"` や `"  "` を
  書いたらそれは負債

### 着手順

Task 40（綴りの見張り）→ 41（筆と骨格行）→ 42（中身）→ 43（側のトグル）→ 44（畳み）→
45（封筒と改行の流儀）→ 46（通しの検算とカタログ C8 の訂正）。
41 以降は前のタスクの出力を壊さない足し算で、各段階が `moon check` 0 errors・テスト緑。

### 新設する名前の一覧（パッケージ内で予約するもの。契約 §4 の G3 の節と一致）

同一パッケージの `*_wbtest.mbt` は名前空間を共有するので（`[4051] declared twice`）、
G1・G2・G4・G5 はこの一覧の名前を使わないこと。

- 型（priv）: `Voice`（構築子 `Loud` / `Quiet`）/ `Pen`
- 公開: `serialize`
- 補助: `is_loud` `put` `split_nl` `repeat` `write_front` `write_center` `write_slots`
  `turned` `same_side` `write_branch` `inner_steps` `write_skeleton` `write_fold_open`
  `write_fold_close` `write_body` `write_blocks` `write_block` `write_content` `fence_for`
- wbtest の組み立て: `write_tree` `write_head` `write_item` `write_gap`

**この一覧に `spell` / `eol_text` / `Spell` は入らない** — G1 の `spell.mbt` の持ち物で、G3 は読むだけ。

**`split_nl` / `repeat` / `same_side` は名前が汎用なので、他群が同じものを要るときは
再定義せずこれを呼ぶこと**。`same_side` は `Side` に `Eq` が無いために要る判定で、
**G4 の `project.mbt` のバケツ分け（`map_bucket`）が呼ぶ**（契約 §4・§14）。
G5 は `flipped` しか使わないので `same_side` は要らない。

### 正規形の全体像（書き出す順番）

```
封筒（---・逐語・---）
文書の散文（Doc.body — 最初の骨格より前）
center ごとに:
  骨格行（Implicit は書かない）
  <details> と <summary>label</summary>（folded のとき）
  中身（body の Block を順に）
  スロットの列（側の変わり目に ---、先頭が左なら先頭にも ---）
    枝の頂点 = 深さ 2 のノード。以下同じ形で再帰
  </details>（folded のとき）
```

- **level = 深さ**。center が 1、スロットの占有者が 2、以下 +1。`#` の数がそのまま深さで、
  7 個以上も書く（憲法 §4「level は無制限」）
- **字下げは段数（steps）で数える**。1 段 = `spell.step`（2 スペース）。
  見出しは常に 0 段、項目は親の中身の段 + 1、Implicit は何も書かないので親の段のまま
  （Implicit の子は必ず見出し = 0 段なので、この腕は実際には効かない）
- 出力は必ず改行で終わる。空文書だけが空文字列
- **serialize は木のとおりに書く。** Implicit を黙って見出しへ昇格させたりしない
  （書き替えたら法則 1 が定義ごと壊れる。契約 §19 の G4 Task 67 の項）

### 空行の規律 — この群の唯一の発明

憲法 §4 は「見出しの継ぎ目は 1 本、リスト内は必要最小限（無いと意味が壊れる場所だけ）、
段落直後のトグルは setext 化するので空行が要る」と言う。これを **2 値に畳んだ**:

> **うるさい行に触れる継ぎ目は空ける。静かな行どうしは詰める。**

| 声 | 行 | 理由 |
|---|---|---|
| **Loud** | 見出し行 | 憲法「見出しの継ぎ目は 1 本」 |
| **Loud** | トグル `---` | 段落の直後だと setext の下線に化ける（安全装置） |
| **Loud** | 段落として読まれる塊 — Opaque / Image / Link / Svg / `<details>` / `<summary>` / `</details>` | 段落は段落を中断できない。詰めると次の行が段落に融合する |
| **Quiet** | 項目行 `- x` | 兄弟は tight が正規形（憲法 §4） |
| **Quiet** | コードのフェンス | フェンスは段落を中断できるので詰めて安全 |
| **Quiet** | 飾りの水平線 `***` | 水平線は段落を中断できる。`---` と違い setext にならないから静かでいられる |

空行の本数は `spell.gap`（= 1）。**この判断は `put` 1 本にしか住まない** —
書き手はどれも「自分の声」を宣言するだけで、継ぎ目の勘定をしない。

この規律の帰結（実測でカタログと一致）:

- `# r` → `## a` → `- b` → `- c` は `# r\n\n## a\n\n- b\n- c\n`（C1）
- 項目の中身がある節点は loose になる（段落を挟むので md の規則上そうなる）が、
  中身がコードだけなら tight のまま（`- x` の直後にフェンス、閉じフェンスの直後に子項目）

### 他群への引き継ぎ（契約への申し送りではない。契約は改訂済み）

1. **爆風半径の 1 行は G5 が書く。** 手で書いた `<summary>` は読みで捨てられ、ラベル版へ
   置き換わる（意味の損失）。逐語は契約 §9 の「爆風半径」にあり、書き足す先は
   `docs/ops.md`（**G5 Task 94 Step 3 の所有**）。G3 は `docs/ops.md` に触らない
2. **`spell.mbt` に §12 との差分があったら G1 へ差し戻す**（Task 40）。G3 は spell.mbt を書かない
3. **G4 が serialize へ足そうとしていた 3 本は、どれも要らない**（契約 §19 の G4 の表で削除済み）。
   G3 の判断と理由を残す:
   - `trim_tail(text, nl)` — **不要**。`put` は 1 行ごとに `pen.eol` をちょうど 1 つ書くので、
     出力は構造的に必ず改行 1 本で終わる。末尾を後から削る余地がない（空文書は `put` が
     1 回も呼ばれないので空文字列。これも正しい）
   - `gap(sb, nl)` — **不要かつ有害**。空行の判断は `put` の `match pen.last` 1 か所だけに住む
     というのがこの群の受け入れ条件で、2 か所目を作った時点で規律が死ぬ
   - `spellable(kin, at)` — **不要**。`write_branch` は兄弟の列も自分の index も受け取らないので
     呼ぶ術が構造的に無く、シグネチャを変えれば設計ごと変わる。そして「飛びが表現できない
     位置の implied」は G5 Task 87 の `conform`（`raised(s, true)`）が model の側で潰しており、
     check 条件 3（Implicit の前の兄弟はすべて項目）が健全な木でそれを保証している。
     serialize に安全弁を二重に置かない

---

## Task 40: 綴りの定数が §12 の逐語であることを固定する

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`
- Read only: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/spell.mbt`（**G1 Task 10.5 の所有**）

**Interfaces:**
- Consumes: `Spell` / `spell` / `eol_text` / `Eol`（`Lf` / `Crlf`）— G1 の `spell.mbt` と `doc.mbt`
- Produces: 無し（**このタスクで G3 は 1 本も関数を書かない**）

**このタスクの位置づけ**: G3 が実装を持たない唯一のタスク。`spell.mbt` は G1 の所有なので、
赤→緑の「緑」を G3 が書くことはできない。ここは**赤を差し戻しの合図として定義する見張り**で、
G1 が置いたものが契約 §12 の逐語ならそのまま緑、違えば赤が出て G1 へ戻す。
この 2 本が `spell` の値の唯一の見張りなので、G1 側へ移さずここに置く（契約 §19 G3）。

- [ ] **Step 1: 綴りを固定するテストを書く**

`core/tree/serialize_wbtest.mbt` を新規に作る。

```moonbit
// 正規形の綴りを 1 つずつ固定する。期待値はカタログの md の逐語。
// spell.mbt は G1 の所有。この 2 本が「G1 が置いた値が契約 §12 のとおりか」の唯一の見張り。

///|
test "綴りの定数は spell 1 か所に集まっている" {
  assert_eq(spell.marker, "-")
  assert_eq(spell.step, "  ")
  assert_eq(spell.hash, "#")
  assert_eq(spell.toggle, "---")
  assert_eq(spell.rule, "***")
  assert_eq(spell.fence, "`")
  assert_eq(spell.fence_min, 3)
  assert_eq(spell.fold_open, "<details>")
  assert_eq(spell.fold_close, "</details>")
  assert_eq(spell.label_open, "<summary>")
  assert_eq(spell.label_close, "</summary>")
  assert_eq(spell.front, "---")
  assert_eq(spell.gap, 1)
}

///|
test "改行の流儀を逐語にするのは eol_text だけ" {
  assert_eq(eol_text(Lf), "\n")
  assert_eq(eol_text(Crlf), "\r\n")
}
```

- [ ] **Step 2: テストを走らせて、G1 の置いたものを確かめる**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected（G1 Task 10.5 が契約 §12 の逐語を置いていれば緑）:
```
Total tests: 2, passed: 2, failed: 0.
```

- **`Error: [4021] The value identifier spell is unbound.` EXIT=1 が出たら** — G1 Task 10.5 が
  まだ済んでいない。**`spell.mbt` を自分で作らずに待つ**（他群のファイルは 1 バイトも書かない）
- **`assert_eq` が落ちたら（EXIT=2）** — G1 が置いた値が契約 §12 と違う。落ちた逐語の形:
  ```
  [mmm-app/core] test tree/serialize_wbtest.mbt:5 ("綴りの定数は spell 1 か所に集まっている") failed: ... FAILED: `"*" != "-"`
  ```
  **`serialize_wbtest.mbt` の期待値を実装に合わせて緩めてはならない。** 契約 §12 の逐語を添えて
  G1 へ差し戻し、G1 が直してからこの Step に戻る

- [ ] **Step 3: 実装は書かない**

**G3 はこのタスクでコードを 1 行も書かない。** `core/tree/spell.mbt` が契約 §12 の逐語
（`pub(all) struct Spell` の 15 フィールド / `pub let spell` の 15 の値 / `pub fn eol_text`）
であることを目で確かめるだけ。差分があれば Step 2 の指示どおり G1 へ差し戻す。

- [ ] **Step 4: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 正規形の綴りの値を固定する"
```

---

## Task 41: 筆と骨格行

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc` / `Center` / `Slot` / `Branch` / `Skeleton` / `Form` / `Side` / `Eol`（G1 `doc.mbt`）、
  `spell` / `eol_text`（G1 `spell.mbt`）、
  `make_doc` / `make_center` / `make_slot` / `make_branch` / `make_head` / `make_item`（G1 `make_wbtest.mbt`）
- Produces:
  - `pub fn serialize(doc : Doc) -> String`
  - `priv enum Voice { Loud; Quiet }` / `priv struct Pen { sb : StringBuilder; eol : String; mut last : Voice? }`
  - `fn is_loud(voice : Voice) -> Bool`
  - `fn put(pen : Pen, voice : Voice, steps : Int, text : String) -> Unit`
  - `fn split_nl(text : String) -> Array[String]` / `fn repeat(unit : String, n : Int) -> String`
  - `fn write_center(pen : Pen, center : Center) -> Unit`
  - `fn write_branch(pen : Pen, branch : Branch, depth : Int, steps : Int) -> Unit`
  - `fn inner_steps(skeleton : Skeleton, steps : Int) -> Int`
  - `fn write_skeleton(pen : Pen, skeleton : Skeleton, depth : Int, steps : Int) -> Unit`
  - wbtest: `write_tree` / `write_head` / `write_item` / `write_gap`（**すべて `make_*` の合成**）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/serialize_wbtest.mbt` の末尾に足す（備考: 憲法 §4 / カタログ C1・C3・C6・C15）。
ヘルパは 4 本だけで、どれも G1 の `make_*` を合成しただけの短縮形（生の struct リテラルは書かない）。
文書そのものは `make_doc`、スロットは `make_slot` を直に呼ぶ。

```moonbit
///|
/// center ひとつ。見出し・畳まず・中身なし。
fn write_tree(id : Int, label : String, slots : Array[Slot]) -> Center {
  make_center(id, make_head(label), slots)
}

///|
/// 見出しのノード。畳まず・中身なし。
fn write_head(id : Int, label : String, children : Array[Branch]) -> Branch {
  make_branch(id, make_head(label), children)
}

///|
/// 項目のノード。畳まず・中身なし。
fn write_item(id : Int, label : String, children : Array[Branch]) -> Branch {
  make_branch(id, make_item(label), children)
}

///|
/// 飛び。骨格行を持たないので label も中身も型ごと無い。
fn write_gap(id : Int, children : Array[Branch]) -> Branch {
  make_branch(id, Implicit, children)
}

///|
test "空の文書は 1 バイトも書かない" {
  assert_eq(serialize(make_doc([])), "")
}

///|
test "C3: 見出しの兄弟は空行 1 本で継ぐ（右どうしなので区切りは 0 本）" {
  let doc = make_doc([
    write_tree(2, "r", [
      make_slot(Right, write_head(3, "a", [])),
      make_slot(Right, write_head(4, "c", [])),
    ]),
  ])
  assert_eq(serialize(doc), "# r\n\n## a\n\n## c\n")
}

///|
test "C1: 項目どうしの継ぎ目は詰める。空ラベルでも印と空白は書く" {
  let a = write_head(3, "a", [
    write_item(4, "b", []),
    write_item(5, "c", []),
    write_item(6, "", []),
  ])
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, a)])])
  assert_eq(serialize(doc), "# r\n\n## a\n\n- b\n- c\n- \n")
}

///|
test "C6: 飛びは Implicit のまま何も書かず、level は深さそのもの" {
  let a = write_head(3, "a", [write_gap(4, [write_head(5, "b", [])])])
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, a)])])
  assert_eq(serialize(doc), "# r\n\n## a\n\n#### b\n")
}

///|
test "level は無制限。7 個以上の見出しも書く" {
  let deep = write_head(4, "z", [])
  let mid = write_head(3, "y", [
    write_head(5, "a", [
      write_head(6, "b", [write_head(7, "c", [write_head(8, "d", [deep])])]),
    ]),
  ])
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, mid)])])
  assert_eq(
    serialize(doc),
    "# r\n\n## y\n\n### a\n\n#### b\n\n##### c\n\n###### d\n\n####### z\n",
  )
}

///|
test "C15: 項目 center の子は 1 段字下げ（入れ子は相対記法）" {
  let center = make_center(2, make_item("center"), [
    make_slot(Right, write_item(3, "a", [write_item(4, "b", [])])),
    make_slot(Right, write_item(5, "c", [])),
  ])
  assert_eq(serialize(make_doc([center])), "- center\n  - a\n    - b\n  - c\n")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected（実測の逐語。EXIT=1 = ビルドが通らない）:
```
Error: [4021]
   │   assert_eq(serialize(make_doc([])), "")
   │             ────┬────
   │                 ╰──── The value identifier serialize is unbound.
```

- [ ] **Step 3: 筆を書く**

`core/tree/serialize.mbt` を新規に作る。まずファイル冒頭と筆だけ。

```moonbit
// Doc → 正規形の md。綴りの逐語は spell.mbt（G1）にしか無く、ここは並べ方だけを決める。
// 木は木のとおりに書く（Implicit を昇格させたら法則 1 が定義ごと壊れる）。
//
// 空行の規律は 1 本 —「うるさい行に触れる継ぎ目は空ける、静かな行どうしは詰める」。
// うるさい = 見出し・トグル・段落（段落は段落を中断できず、直後の `---` は setext に化ける）。
// 静か = 項目・フェンス・飾りの水平線（どれも段落を中断できるので詰めて安全）。

///|
/// 行の声。継ぎ目の空行の要否はこの 2 値だけで決まる。
priv enum Voice {
  Loud
  Quiet
}

///|
fn is_loud(voice : Voice) -> Bool {
  match voice {
    Loud => true
    Quiet => false
  }
}

///|
/// 書き出しの筆。空行の規律と字下げの綴りがここに集まる。
priv struct Pen {
  sb : StringBuilder
  eol : String
  mut last : Voice?
}

///|
/// 1 塊を書く。改行を含むテキストは 1 塊として扱い、中の行の間には継ぎ目を入れない
/// （コードとよそ者の逐語を崩さないため）。空行には字下げを付けない。
/// 各行に eol をちょうど 1 つ付けるので、出力は必ず改行 1 本で終わる（末尾の後処理は要らない）。
fn put(pen : Pen, voice : Voice, steps : Int, text : String) -> Unit {
  match pen.last {
    None => ()
    Some(prev) =>
      if is_loud(prev) || is_loud(voice) {
        let mut n = 0
        while n < spell.gap {
          pen.sb.write_string(pen.eol)
          n = n + 1
        }
      }
  }
  for line in split_nl(text) {
    if line != "" {
      let mut k = 0
      while k < steps {
        pen.sb.write_string(spell.step)
        k = k + 1
      }
    }
    pen.sb.write_string(line)
    pen.sb.write_string(pen.eol)
  }
  pen.last = Some(voice)
}

///|
/// モデルの中の改行は必ず "\n"（eol は Doc のダイヤル 1 つだけが持つ。契約 §6）。
fn split_nl(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  for i in 0..<text.length() {
    if text[i].to_int() == 10 {
      out.push(String::unsafe_substring(text, start~, end=i))
      start = i + 1
    }
  }
  out.push(String::unsafe_substring(text, start~, end=text.length()))
  out
}

///|
/// 同じ綴りを n 回。
fn repeat(unit : String, n : Int) -> String {
  let sb = StringBuilder::new()
  let mut k = 0
  while k < n {
    sb.write_string(unit)
    k = k + 1
  }
  sb.to_string()
}
```

備考: `s[i]` は `Char` ではなく `UInt16`（`.to_int() == 10` が改行。契約 §18）。
`String::unsafe_substring` を使うのは、`s[a:b]` が端のサロゲート途中で panic するため
（`String::sub` の `guard`）。ここは必ず改行境界で切るので不安全ではない。

- [ ] **Step 4: 木の歩きを書く**

`core/tree/serialize.mbt` の末尾に足す。

```moonbit
///|
/// 正規形の md。決定的で、2 回目から不動（法則 2）。
pub fn serialize(doc : Doc) -> String {
  let pen = { sb: StringBuilder::new(), eol: eol_text(doc.eol), last: None }
  for center in doc.centers {
    write_center(pen, center)
  }
  pen.sb.to_string()
}

///|
fn write_center(pen : Pen, center : Center) -> Unit {
  write_skeleton(pen, center.skeleton, 1, 0)
  let inner = inner_steps(center.skeleton, 0)
  for slot in center.slots {
    write_branch(pen, slot.branch, 2, inner)
  }
}

///|
fn write_branch(pen : Pen, branch : Branch, depth : Int, steps : Int) -> Unit {
  write_skeleton(pen, branch.skeleton, depth, steps)
  let inner = inner_steps(branch.skeleton, steps)
  for child in branch.children {
    write_branch(pen, child, depth + 1, inner)
  }
}

///|
/// 中身と子を置く字下げ。項目は 1 段深く、見出しは常に列 0、
/// Implicit は何も書かないので親の列のまま（子はすべて見出し = 列 0）。
fn inner_steps(skeleton : Skeleton, steps : Int) -> Int {
  match skeleton {
    Implicit => steps
    Explicit(form~, ..) =>
      match form {
        Heading => 0
        Item => steps + 1
      }
  }
}

///|
/// 骨格行。Implicit は何も書かない（飛びが綴り）。
fn write_skeleton(
  pen : Pen,
  skeleton : Skeleton,
  depth : Int,
  steps : Int,
) -> Unit {
  match skeleton {
    Implicit => ()
    Explicit(form~, label~, ..) =>
      match form {
        Heading => put(pen, Loud, 0, repeat(spell.hash, depth) + " " + label)
        Item => put(pen, Quiet, steps, spell.marker + " " + label)
      }
  }
}
```

- [ ] **Step 5: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected:
```
Total tests: 8, passed: 8, failed: 0.
```

- [ ] **Step 6: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize.mbt core/tree/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 骨格行だけの正規形を書き出す"
```

---

## Task 42: 中身をノードの列へ書く

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`

**Interfaces:**
- Consumes: `Block`（`Content` / `Rule` / `Opaque`）/ `Content`（`Image` / `Link` / `Code` / `Svg`）（G1）、
  `put` / `inner_steps` / `repeat`（Task 41）、`make_branch` / `make_doc` / `make_slot`（G1）
- Produces:
  - `fn write_body(pen : Pen, skeleton : Skeleton, steps : Int) -> Unit`
  - `fn write_blocks(pen : Pen, blocks : Array[Block], steps : Int) -> Unit`
  - `fn write_block(pen : Pen, block : Block, steps : Int) -> Unit`
  - `fn write_content(pen : Pen, content : Content, steps : Int) -> Unit`
  - `fn fence_for(text : String) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/serialize_wbtest.mbt` の末尾に足す（備考: 憲法 §4 の「コード」「区切り」、カタログ C5・C9）。
中身を持つ骨格は `make_head` / `make_item` の守備範囲外（あれは中身なし・畳まずの短縮形）なので、
`make_branch` に `Explicit(...)` を直に渡して組む。

```moonbit
///|
test "C5: 中身は骨格行の下へ。飾りの水平線は *** で書く" {
  let head = make_branch(
    4,
    Explicit(form=Heading, label="head", folded=false, body=[
      Opaque("content01"),
      Rule,
      Opaque("content02"),
    ]),
    [],
  )
  let head2 = write_head(3, "head2", [head])
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, head2)])])
  assert_eq(
    serialize(doc),
    "# r\n\n## head2\n\n### head\n\ncontent01\n\n***\n\ncontent02\n",
  )
}

///|
test "C9: コードは常にフェンス。info が空でも囲いは 3 本" {
  let b = make_branch(
    4,
    Explicit(form=Heading, label="b", folded=false, body=[
      Content(Code(info="", text="code")),
    ]),
    [],
  )
  let doc = make_doc([
    write_tree(2, "r", [
      make_slot(Right, write_head(3, "a", [])),
      make_slot(Right, b),
    ]),
  ])
  assert_eq(serialize(doc), "# r\n\n## a\n\n## b\n\n```\ncode\n```\n")
}

///|
test "囲いは中身の最長のバッククォート連なりより 1 本長い" {
  let n = make_branch(
    3,
    Explicit(form=Heading, label="a", folded=false, body=[
      Content(Code(info="js", text="```\nx")),
    ]),
    [],
  )
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, n)])])
  assert_eq(serialize(doc), "# r\n\n## a\n\n````js\n```\nx\n````\n")
}

///|
test "絵・リンク・svg はそれぞれの正規綴りで 1 行に書く" {
  let a = make_branch(
    3,
    Explicit(form=Heading, label="a", folded=false, body=[
      Content(Image(alt="alt", src="./img/a.png")),
      Content(Link(text="title", href="https://example.com")),
      Content(Svg("<svg><rect/></svg>")),
    ]),
    [],
  )
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, a)])])
  assert_eq(
    serialize(doc),
    "# r\n\n## a\n\n![alt](./img/a.png)\n\n[title](https://example.com)\n\n<svg><rect/></svg>\n",
  )
}

///|
/// 外の Markdown パーサでも同じ木に読める形であること。判定材料は 3 つ —
/// 中身の行が項目の中身の列まで字下げされていること、ラベルと中身の間に空行が
/// あること、兄弟の間に空行が無いこと。1 つでも崩れると、外のパーサはそこで
/// リストを閉じ、続く項目は別のリスト・深い字下げはコードブロックに化ける。
test "項目の中身は逐語のまま、その項目の中身の列へ塊で入る" {
  let a = make_branch(
    3,
    Explicit(form=Item, label="a", folded=false, body=[
      Opaque("| x | y |\n| - | - |"),
    ]),
    [write_item(4, "b", [])],
  )
  let doc = make_doc([
    write_tree(2, "r", [
      make_slot(Right, a),
      make_slot(Right, write_item(5, "c", [])),
    ]),
  ])
  assert_eq(
    serialize(doc),
    "# r\n\n- a\n\n  | x | y |\n  | - | - |\n\n  - b\n- c\n",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected（EXIT=2。中身が 1 行も出ないので 5 本が落ちる）:
```
Total tests: 13, passed: 8, failed: 5.
```
落ち方の形（1 本目の逐語の骨格）:
```
[mmm-app/core] test tree/serialize_wbtest.mbt:NN ("C5: 中身は骨格行の下へ。飾りの水平線は *** で書く") failed: ... FAILED: `"# r\n\n## head2\n\n### head\n" != "# r\n\n## head2\n\n### head\n\ncontent01\n\n***\n\ncontent02\n"`
```

- [ ] **Step 3: 中身の書き手を足す**

`core/tree/serialize.mbt` の末尾に足す。

```moonbit
///|
fn write_body(pen : Pen, skeleton : Skeleton, steps : Int) -> Unit {
  match skeleton {
    Implicit => ()
    Explicit(body~, ..) => write_blocks(pen, body, steps)
  }
}

///|
fn write_blocks(pen : Pen, blocks : Array[Block], steps : Int) -> Unit {
  for block in blocks {
    write_block(pen, block, steps)
  }
}

///|
fn write_block(pen : Pen, block : Block, steps : Int) -> Unit {
  match block {
    Rule => put(pen, Quiet, steps, spell.rule)
    Opaque(text) => put(pen, Loud, steps, text)
    Content(content) => write_content(pen, content, steps)
  }
}

///|
fn write_content(pen : Pen, content : Content, steps : Int) -> Unit {
  match content {
    Image(alt~, src~) => put(pen, Loud, steps, "![" + alt + "](" + src + ")")
    Link(text~, href~) => put(pen, Loud, steps, "[" + text + "](" + href + ")")
    Svg(svg) => put(pen, Loud, steps, svg)
    Code(info~, text~) => {
      let bar = fence_for(text)
      let inside = if text == "" { "" } else { text + "\n" }
      put(pen, Quiet, steps, bar + info + "\n" + inside + bar)
    }
  }
}

///|
/// 囲いは中身の最長のバッククォート連なりより 1 つ長く、最短は spell.fence_min。
fn fence_for(text : String) -> String {
  let mut best = 0
  let mut run = 0
  for i in 0..<text.length() {
    if text[i].to_int() == 96 {
      run = run + 1
      if run > best {
        best = run
      }
    } else {
      run = 0
    }
  }
  let n = if best + 1 > spell.fence_min { best + 1 } else { spell.fence_min }
  repeat(spell.fence, n)
}
```

- [ ] **Step 4: 中身を歩きに繋ぐ**

`write_center` と `write_branch` の 2 か所に 1 行ずつ足す。差し替え後の全文:

```moonbit
///|
fn write_center(pen : Pen, center : Center) -> Unit {
  write_skeleton(pen, center.skeleton, 1, 0)
  let inner = inner_steps(center.skeleton, 0)
  write_body(pen, center.skeleton, inner)
  for slot in center.slots {
    write_branch(pen, slot.branch, 2, inner)
  }
}

///|
fn write_branch(pen : Pen, branch : Branch, depth : Int, steps : Int) -> Unit {
  write_skeleton(pen, branch.skeleton, depth, steps)
  let inner = inner_steps(branch.skeleton, steps)
  write_body(pen, branch.skeleton, inner)
  for child in branch.children {
    write_branch(pen, child, depth + 1, inner)
  }
}
```

- [ ] **Step 5: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected:
```
Total tests: 13, passed: 13, failed: 0.
```

- [ ] **Step 6: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize.mbt core/tree/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 中身をノードの列へ書き出す"
```

---

## Task 43: 側の変わり目に区切りを 1 本だけ書く

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`

**Interfaces:**
- Consumes: `Slot` / `Side`（G1）、`put` / `write_branch`（Task 41）
- Produces:
  - `fn write_slots(pen : Pen, slots : Array[Slot], steps : Int) -> Unit`
  - `fn turned(prev : Side?, side : Side) -> Bool`
  - `fn same_side(a : Side, b : Side) -> Bool`（`Side` に `Eq` は無い。**G4 の `map_bucket` もこれを呼ぶ**）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/serialize_wbtest.mbt` の末尾に足す（備考: 憲法 §4「区切り」「先頭トグル」、カタログ C4・C16・C15）。

```moonbit
///|
test "C4: 先頭が左ならスロットの前に 1 本、変わり目にも 1 本" {
  let doc = make_doc([
    write_tree(2, "r", [
      make_slot(Left, write_head(3, "a", [])),
      make_slot(Right, write_head(4, "b", [])),
    ]),
  ])
  assert_eq(serialize(doc), "# r\n\n---\n\n## a\n\n---\n\n## b\n")
}

///|
test "C16: 占有者が Implicit でも隙間にトグルは書ける" {
  let deep = write_gap(3, [write_gap(4, [write_head(5, "b", [])])])
  let doc = make_doc([write_tree(2, "r", [make_slot(Left, deep)])])
  assert_eq(serialize(doc), "# r\n\n---\n\n#### b\n")
}

///|
test "C15: 項目 center のトグルは center の中身の列に置く" {
  let center = make_center(2, make_item("center"), [
    make_slot(Right, write_item(3, "a", [])),
    make_slot(Right, write_item(4, "b", [])),
    make_slot(Left, write_item(5, "c", [])),
  ])
  assert_eq(
    serialize(make_doc([center])),
    "- center\n  - a\n  - b\n\n  ---\n\n  - c\n",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected（EXIT=2。区切りが 1 本も出ないので 3 本が落ちる）:
```
Total tests: 16, passed: 13, failed: 3.
```
1 本目の落ち方: `"# r\n\n## a\n\n## b\n" != "# r\n\n---\n\n## a\n\n---\n\n## b\n"`

- [ ] **Step 3: スロットの列を書く**

`core/tree/serialize.mbt` の `write_center` の直後に足す。

```moonbit
///|
/// スロットの列。側の変わり目にちょうど 1 本、先頭が左ならその前にも 1 本。
fn write_slots(pen : Pen, slots : Array[Slot], steps : Int) -> Unit {
  let mut prev : Side? = None
  for slot in slots {
    if turned(prev, slot.side) {
      put(pen, Loud, steps, spell.toggle)
    }
    write_branch(pen, slot.branch, 2, steps)
    prev = Some(slot.side)
  }
}

///|
/// 側の変わり目か。先頭は左のときだけ変わり目（先頭トグル = 左開始）。
fn turned(prev : Side?, side : Side) -> Bool {
  match prev {
    None =>
      match side {
        Left => true
        Right => false
      }
    Some(p) => !same_side(p, side)
  }
}

///|
/// Side の等値。`Side` に `Eq` は無いので、同じ判定が要る群はこれを呼ぶ
/// （G4 の `map_bucket` がバケツ分けで使う）。
fn same_side(a : Side, b : Side) -> Bool {
  match a {
    Right =>
      match b {
        Right => true
        Left => false
      }
    Left =>
      match b {
        Left => true
        Right => false
      }
  }
}
```

- [ ] **Step 4: center の枝の並びを差し替える**

`write_center` の `for` を 1 行に置き換える。差し替え後の全文:

```moonbit
///|
fn write_center(pen : Pen, center : Center) -> Unit {
  write_skeleton(pen, center.skeleton, 1, 0)
  let inner = inner_steps(center.skeleton, 0)
  write_body(pen, center.skeleton, inner)
  write_slots(pen, center.slots, inner)
}
```

- [ ] **Step 5: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected:
```
Total tests: 16, passed: 16, failed: 0.
```

- [ ] **Step 6: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize.mbt core/tree/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 側の変わり目に区切りを 1 本だけ書く"
```

---

## Task 44: 畳みを details で包む

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`

**Interfaces:**
- Consumes: `Skeleton::Explicit(folded~, label~, ..)`（G1）、`put`（Task 41）、
  `spell.fold_open` / `spell.fold_close` / `spell.label_open` / `spell.label_close`（G1 `spell.mbt`）
- Produces:
  - `fn write_fold_open(pen : Pen, skeleton : Skeleton, steps : Int) -> Unit`
  - `fn write_fold_close(pen : Pen, skeleton : Skeleton, steps : Int) -> Unit`

**この Task が固定するもの（契約 §9・裁定 1）**: serialize は畳んだノードに `<details>` と
`<summary>label</summary>` を**必ず**書く。下の 2 本のテストが、`<summary>` 行の**綴りそのもの**
（開き・ラベル・閉じの並びと、その前後の空行 1 本）を md の逐語で固定する。
`parse` 側の読み飛ばしは G2 Task 25 の仕事で、G3 は 1 バイトも触らない。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/serialize_wbtest.mbt` の末尾に足す（備考: 憲法 §4「畳み」、カタログ C8。
**期待 md は契約 §9 の C8「新 md」の逐語と 1 文字も違わない**。カタログ側の訂正は Task 46）。

```moonbit
///|
test "C8: details は骨格行の外、summary に label。ネストは残る" {
  let b = make_branch(
    4,
    Explicit(form=Heading, label="b", folded=true, body=[]),
    [write_head(5, "c", [])],
  )
  let a = make_branch(
    3,
    Explicit(form=Heading, label="a", folded=true, body=[]),
    [b],
  )
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, a)])])
  assert_eq(
    serialize(doc),
    "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n<details>\n\n<summary>b</summary>\n\n#### c\n\n</details>\n\n</details>\n",
  )
}

///|
test "項目の畳みも中身も、その項目の中身の列に入る" {
  let x = make_branch(
    3,
    Explicit(form=Item, label="x", folded=true, body=[
      Opaque("text"),
      Content(Code(info="", text="1")),
    ]),
    [write_item(4, "y", [])],
  )
  let doc = make_doc([write_tree(2, "r", [make_slot(Right, x)])])
  assert_eq(
    serialize(doc),
    "# r\n\n- x\n\n  <details>\n\n  <summary>x</summary>\n\n  text\n\n  ```\n  1\n  ```\n  - y\n\n  </details>\n",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected（EXIT=2）:
```
Total tests: 18, passed: 16, failed: 2.
```
1 本目の落ち方: `"# r\n\n## a\n\n### b\n\n#### c\n" != "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n<details>\n\n<summary>b</summary>\n\n#### c\n\n</details>\n\n</details>\n"`

- [ ] **Step 3: 畳みの開きと閉じを書く**

`core/tree/serialize.mbt` の `write_skeleton` の直後に足す。

```moonbit
///|
/// 畳みの開き。骨格行は外、本文と子だけを包む。
/// summary は label から毎回作る飾り（parse は details の直後の 1 枚を読み飛ばす。契約 §9）。
fn write_fold_open(pen : Pen, skeleton : Skeleton, steps : Int) -> Unit {
  match skeleton {
    Implicit => ()
    Explicit(folded~, label~, ..) =>
      if folded {
        put(pen, Loud, steps, spell.fold_open)
        put(pen, Loud, steps, spell.label_open + label + spell.label_close)
      }
  }
}

///|
fn write_fold_close(pen : Pen, skeleton : Skeleton, steps : Int) -> Unit {
  match skeleton {
    Implicit => ()
    Explicit(folded~, ..) =>
      if folded {
        put(pen, Loud, steps, spell.fold_close)
      }
  }
}
```

- [ ] **Step 4: 包みを歩きに繋ぐ**

`write_center` と `write_branch` に開きと閉じを挟む。差し替え後の全文:

```moonbit
///|
fn write_center(pen : Pen, center : Center) -> Unit {
  write_skeleton(pen, center.skeleton, 1, 0)
  let inner = inner_steps(center.skeleton, 0)
  write_fold_open(pen, center.skeleton, inner)
  write_body(pen, center.skeleton, inner)
  write_slots(pen, center.slots, inner)
  write_fold_close(pen, center.skeleton, inner)
}

///|
fn write_branch(pen : Pen, branch : Branch, depth : Int, steps : Int) -> Unit {
  write_skeleton(pen, branch.skeleton, depth, steps)
  let inner = inner_steps(branch.skeleton, steps)
  write_fold_open(pen, branch.skeleton, inner)
  write_body(pen, branch.skeleton, inner)
  for child in branch.children {
    write_branch(pen, child, depth + 1, inner)
  }
  write_fold_close(pen, branch.skeleton, inner)
}
```

- [ ] **Step 5: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected:
```
Total tests: 18, passed: 18, failed: 0.
```

- [ ] **Step 6: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize.mbt core/tree/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 畳みを details で包む"
```

---

## Task 45: 封筒と文書の散文を書き戻す

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc.frontmatter : String?` / `Doc.body : Array[Block]` / `Doc.eol`（G1）、
  `write_blocks`（Task 42）、`spell.front`（G1 `spell.mbt`）
- Produces: `fn write_front(pen : Pen, front : String?) -> Unit`（`serialize` の全文が完成する）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/serialize_wbtest.mbt` の末尾に足す（備考: 憲法 §4「frontmatter」「EOL」、カタログ C11）。
`make_doc` は封筒なし・Lf・散文なしの短縮形なので、**ダイヤルを試すこの 3 本だけ `Doc` を直に組む**。

```moonbit
///|
test "C11: 封筒は柵ごと逐語。CRLF は 1 つのダイヤルで全行に効く" {
  let doc = {
    frontmatter: Some("image-folder: img"),
    eol: Crlf,
    body: [],
    centers: [write_tree(2, "r", [make_slot(Left, write_head(3, "a", []))])],
  }
  assert_eq(
    serialize(doc),
    "---\r\nimage-folder: img\r\n---\r\n\r\n# r\r\n\r\n---\r\n\r\n## a\r\n",
  )
}

///|
test "空の封筒も柵だけで書ける" {
  let doc = {
    frontmatter: Some(""),
    eol: Lf,
    body: [],
    centers: [write_tree(2, "r", [])],
  }
  assert_eq(serialize(doc), "---\n---\n\n# r\n")
}

///|
test "文書の散文は最初の骨格より前に置かれる" {
  let doc = {
    frontmatter: None,
    eol: Lf,
    body: [Opaque("intro")],
    centers: [write_tree(2, "r", [])],
  }
  assert_eq(serialize(doc), "intro\n\n# r\n")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected（EXIT=2）:
```
Total tests: 21, passed: 18, failed: 3.
```

- [ ] **Step 3: 封筒を書く**

`core/tree/serialize.mbt` の `serialize` の直後に足す。

```moonbit
///|
/// 封筒。柵と中身は 1 塊（間に空行を入れると封筒でなくなる）。
fn write_front(pen : Pen, front : String?) -> Unit {
  match front {
    None => ()
    Some(text) => {
      let inside = if text == "" { "" } else { text + "\n" }
      put(pen, Loud, 0, spell.front + "\n" + inside + spell.front)
    }
  }
}
```

備考: 封筒の 3 行を 1 塊で `put` に渡すのは、柵と中身の間に空行を入れないため
（`put` は塊の中には継ぎ目を作らない）。声が `Loud` なので封筒の後ろには必ず空行が 1 本入る（C11）。
塊の中の改行は `"\n"` を書き、`put` が `split_nl` で割ってから `pen.eol` で継ぐので、
CRLF のダイヤルは封筒の中にも効く（契約 §6「モデルの中の改行は必ず `"\n"`」）。

- [ ] **Step 4: serialize の入口に繋ぐ**

差し替え後の全文:

```moonbit
///|
/// 正規形の md。決定的で、2 回目から不動（法則 2）。
pub fn serialize(doc : Doc) -> String {
  let pen = { sb: StringBuilder::new(), eol: eol_text(doc.eol), last: None }
  write_front(pen, doc.frontmatter)
  write_blocks(pen, doc.body, 0)
  for center in doc.centers {
    write_center(pen, center)
  }
  pen.sb.to_string()
}
```

- [ ] **Step 5: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
```
Expected:
```
Total tests: 21, passed: 21, failed: 0.
```

- [ ] **Step 6: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize.mbt core/tree/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 封筒と改行の流儀を書き戻す"
```

---

## Task 46: 通しの検算と、カタログ C8 の訂正

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize.mbt`（`moon fmt` の結果のみ）
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/serialize_wbtest.mbt`（同上）
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/docs/superpowers/specs/2026-08-29-op-cases.md`
  （**契約 §2 で G3 が唯一の書き手。C8 だけを触る**）

**Interfaces:**
- Consumes: Task 40〜45 の全部
- Produces: 無し（検算とドキュメントの訂正）

- [ ] **Step 1: 整形を当てる**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
```
Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0。
`moon fmt` は `moon.pkg` も対象なので、**`doc` ディレクトリだけを渡すこと**
（`js` や `.` を巻き込むと旧 core の差分で即 EXIT=127）。`tree/js` は G4 が建てるのでまだ無い
（`doc tree/js` は G4 Task 71 の締めが使う。契約 §17）。

- [ ] **Step 2: 整形の確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree
```
Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0。
差分があると EXIT=127（1 でも 2 でもない）で `Error: failed when formatting project`。

- [ ] **Step 3: 型検査**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree
```
Expected: 末尾が `Finished. moon: ran N tasks, now up to date`（警告があれば `(M warnings, 0 errors)`）
で EXIT=0。**合格条件は `0 errors`**。`moon check` は wbtest を勘定に入れないので、
wbtest でしか使っていない構築子の `unused_constructor` 警告は残ってよい。
**警告を消すために可視性を下げたり、読み捨てのコードを足したりしないこと。**

- [ ] **Step 4: 自分のテストと、パッケージ全体のテスト**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree
```
Expected: 1 本目が `Total tests: 21, passed: 21, failed: 0.`。
2 本目は他の群のぶんを含むので本数は動くが、**`failed: 0` かつ `Total tests: 0` でないこと**
（`-p` の綴りを間違えると警告だけ出して EXIT=0 で緑になる。契約 §17 の罠）。
このコマンドは旧 core（`mmm-app/core` の 192 本）も含むので、G1 が終わっていれば `Total tests: 238`（旧 192 + G1 25 + G3 21）。**238 未満なら旧 core を壊したか `-p` の綴りを間違えている。**

- [ ] **Step 5: カタログ C8 の期待 md を summary 込みに直す**

`docs/superpowers/specs/2026-08-29-op-cases.md` の C8 の**「元 md」と「新 md」の 2 つ**の
コードブロックを、憲法 §4（`<summary>` には label を書く）と契約 §9 の逐語に差し替える。
**C8 以外のケースには 1 バイトも触らない。** mermaid の `〔畳〕` も直さない（絵の話で、
md と指紋のほうが正。契約 §9）。

差し替え後の「元 md」:

````md
```md
# r

## a

### b

<details>

<summary>b</summary>

#### c

</details>
```
````

差し替え後の「新 md」（`fold(a)` のあと）:

````md
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
````

指紋は動かない（元 = `D-n()[Reh_1:r()[>Neh_1:a()[Neh^1:b()[Neh_1:c()[]]]]]` /
新 = `D-n()[Reh_1:r()[>Neh^1:a()[Neh^1:b()[Neh_1:c()[]]]]]`）。parse が details の直後の
`<summary>` を読み飛ばすので、md に行が増えても木は同じ（契約 §9）。

備考も 1 行足す: 「`<summary>` は serialize が label から毎回作る飾りで、parse は
`<details>` の直後の 1 枚を無条件に読み飛ばす（契約 §9）。**この新 md が Task 44 のテストの
期待値そのもの**」。

- [ ] **Step 6: 旧 core の往復テストが緑のままであることを確かめる**

`docs/` の .md は旧 core の往復テスト（corpus）の入力なので、直した後に確かめる。

Run（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`。別のワークツリーから叩くと旧 core を測る）:
```
pnpm test
```
Expected: `ℹ fail 0` EXIT=0。コードブロックの中を触るだけなので通る。
落ちたら**カタログ側の綴りを直す**（旧 core の実装には触らない）。

- [ ] **Step 7: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/serialize.mbt core/tree/serialize_wbtest.mbt docs/superpowers/specs/2026-08-29-op-cases.md
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "docs: 📝 畳みの正規形に summary を書き足す"
```

---

## 外の審判（記録）

Task 45 まで通した実際の出力を `@lezer/markdown` 1.7.2 に食わせ、外の CommonMark パーサが
同じ木に読むことを確かめた（読み取り専用。`test/seps.test.ts` の `itemsOf()` と同じ手口）。

| 入れた綴り | lezer の読み |
|---|---|
| `# r` + `- a` + 中身 2 行 + `  - b` + `- c` | `ListItem "- a"` の中に `Paragraph` と `ListItem "- b"`、その外に `ListItem "- c"` — **入れ子が保たれる** |
| `- x` + `  <details>` … `  ```` ` + `  - y` | `HTMLBlock` と `FencedCode` の後に `ListItem "- y"` が x の中へ入る（閉じフェンスの直後に空行が無くても割れない） |
| `- center` + `  - a` + `  - b` + `  ---` + `  - c` | `HorizontalRule` は center の項目の中に立ち、子リストがそこで割れて `- c` が再び入れ子になる（C15 の「読み書き一意」の実物） |
| `# r` + `---` + `## a` + `---` + `## b` | `HorizontalRule` が見出しの兄弟として 2 本（C4） |
| `## a` + `<details>` + `<summary>a</summary>` + `### b` … | `HTMLBlock` と `ATXHeading` が兄弟のまま並ぶ（details が見出しを飲まない） |
| `####### z` | `Paragraph` — **憲法 §4 が予告した方言差**。契約 §15 の方言表に取り込み済み |
| `---` + `image-folder: img` + `---` | `HorizontalRule` + `SetextHeading2` — **封筒は lezer には見えない**。契約 §15「法則 4 の照合は封筒を剥がした後の本文に掛ける」に取り込み済み |

---

## この群の終わりの形

- G3 が書いたのは `core/tree/serialize.mbt` と `core/tree/serialize_wbtest.mbt` の 2 本
  （`core/tree/spell.mbt` は G1 の所有。**G3 は 1 バイトも書いていない**）
- カタログ `docs/superpowers/specs/2026-08-29-op-cases.md` は C8 の 2 つの md だけが変わっている
- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree` が **0 errors**
- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree` が EXIT=0
- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/serialize_wbtest.mbt` が
  **21 passed / 0 failed**
- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree`
  が `failed: 0` かつ `Total tests: 0` でない
- 綴りに関わる値が `spell` の外に 1 つも無いこと（`serialize.mbt` に生の `"#"` `"- "` `"  "`
  `"---"` `"***"` `` "`" `` `"<details>"` `"<summary>"` が現れない。現れたら負債）
- **空行の判断が `put` の外に 1 つも無いこと**（`pen.sb.write_string(pen.eol)` が `put` 以外に無い）
- 出力は必ず改行で終わる（空文書だけが空文字列）。末尾を削る後処理は 1 つも無い

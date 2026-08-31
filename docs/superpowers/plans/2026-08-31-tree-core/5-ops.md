# G5 — 操作

新 core 実装計画の第 5 群。**唯一の参照元は `scratchpad/v2/contract2.md`（確定版の契約）**で、
本書と契約が食い違ったら契約が正。対応するのは契約 §2（所有）・§3（依存順）・§4（名前）・
§10（公開シグネチャ）・§11（道具層と腕数）・§16（テストの本数）・§17（コマンド）。

## この群の概要

### 担当範囲

木の道（構造を変える者は文字列に触れない）の全部。**道具層**（型の異種性の牢獄）、
**回復**（不変条件の直し）、**操作 3 本**（move / flipSide / delete）、**反映 v0**
（serialize 全文 → diff → edits）、そして**殺す条件の判定**。

所有ファイル（契約 §2 の G5 の行。**ここに無いファイルには 1 バイトも書かない**）:

- `core/tree/tool.mbt` — 道具 5 本と `Sub`。型の異種性の牢獄
- `core/tree/op.mbt` — move_nodes / flip_side / delete_nodes と、回復（prune / conform）
- `core/tree/diff.mbt` — `Edit` / `Reflection` / `reflect` / `diff` / `apply`
- `core/tree/tool_wbtest.mbt` / `core/tree/op_wbtest.mbt` / `core/tree/diff_wbtest.mbt`
- `docs/ops.md`

### 前提（契約 §3 の依存順。裁定 3）

依存順は `G1 → (G2 / G3) → G5 → G4`。**G5 は G2・G3 の後、G4 の前**。

- **G1 が終わっていること。** `Doc` / `Center` / `Slot` / `Branch` / `Skeleton` / `Side` /
  `Verdict` / `doc_id`（`core/tree/doc.mbt`）、`sig`（`sig.mbt`）、`check` と `is_item`
  （`check.mbt`）、木を組む `make_doc` / `make_center` / `make_slot` / `make_branch` /
  `make_head` / `make_item`（`make_wbtest.mbt`）を使う。`is_item` と `make_*` は private だが
  同一パッケージなので見える
- **G2 の `parse` と G3 の `serialize` が置かれていること。** Task 92 の `reflect` が実際に呼ぶ。
  無ければ **Task 91 で止める**（`Total tests` は Task 91 までの 30 本で据え置き）。
  **スタブは 1 バイトも書かない** — parse.mbt / serialize.mbt は他群の所有ファイル（契約 §2）
- **G4 には依存しない。** 境界の JSON（`reflect_json`）は G4 の `json.mbt` の所有へ移った（裁定 3）。
  G5 が書くのは `Reflection` を返す純関数の `reflect` まで。`quote` は 1 度も呼ばない
- **`test/treeOps.test.ts`（操作の性質のファズ）は G4 Task 72 の所有**（旧 Task 93 から移管。裁定 2）。
  G5 は着手しない。設計の出どころが G5 であることだけが `test/` の表に残る

### 着手順

```
T80 → T81 → T82 → T83        道具層（tool.mbt）
      ↓
T84 → T85 → T86               拒否・delete・flipSide（op.mbt）
      ↓
T87 → T88 → T89               回復と move（op.mbt）
      ↓
T90 → T91 → T92               反映 v0（diff.mbt）
      ↓
T94                           殺す条件の判定と docs/ops.md
```

T84〜T89 と T90〜T91 は互いに独立（diff.mbt は op.mbt の名前を 1 つも使わない）。
T92 だけが G2・G3 を待つ。

### 新設する名前（契約 §4 の G5 の行。ここに無い名前をトップレベルに置かない）

**`core/tree/tool.mbt`**（`priv` / `fn` — この群の外へは 1 つも出さない）

| 名前 | 何 | 容器の腕 |
|---|---|---|
| `Sub` | 運搬の通貨 `Whole(Center) \| Part(Branch)` | — |
| `resolve(doc, id) -> Array[Int]?` | id → 居場所 | 0 |
| `find_in(branch, id) -> Array[Int]?` | resolve の下請け | 0 |
| `branch_at(doc, path) -> Branch` | 深さ 2 以降のノードそのもの | 1 |
| `kin_at(doc, path) -> Array[Skeleton]` | path が居る列（自分を含む兄弟）の骨格 | 3 |
| `parent_at(doc, path) -> Skeleton?` | 親の骨格（None = 文書）。`kin_at` の上に建つ | 0 |
| `pluck(doc, path) -> Sub?` | 抜く | 3 |
| `graft(doc, parent, at, sub, side)` | 挿す + 変換の唯一の住所 | 3 |
| `amend(doc, path, f)` | 骨格を書き替える | 3 |
| `set_side(doc, i, j, side)` | スロットの側を差し替える | 1 |
| `as_center(sub) -> Center` / `as_branch(sub) -> Branch` | graft の変換 2 本 | — |

**`core/tree/op.mbt`**

`move_nodes` / `flip_side` / `delete_nodes`（pub）、
`crown` / `ahead` / `under` / `dest` / `clamp` / `flipped` / `pick` / `missing` / `cyclic` /
`shallow` / `prune` / `alive` / `conform` / `sink` / `raised` / `itemed`（private **16 本**）

**`core/tree/diff.mbt`**

`Edit`（pub(all)）/ `Reflection`（pub(all)）/ `reflect` / `diff` / `apply`（pub）、
`safe_edits` / `line_start` / `line_end` / `code_at`（private **4 本**）。
**`reflect_json` はここには置かない** — 契約 §4 では G4 の `json.mbt` の所有（裁定 3）。

**wbtest のヘルパ**（契約 §16「ヘルパ名はそのファイルの接頭辞で始めること」）

- `tool_wbtest.mbt`: `tool_doc` / `tool_fold`
- `op_wbtest.mbt`: `op_doc` / `op_implied` / `op_shape` / `op_limb` / `op_forms` /
  `op_form_branch` / `op_mark` / `op_said`
- `diff_wbtest.mbt`: `diff_holds`

**`op_head` / `op_item` は作らない。** G1 の `make_head` / `make_item` を呼ぶ
（同じ木を組む道具を群ごとに持たない。契約 §4）。

> **名前の衝突について**: 同一パッケージのトップレベル名は `*_wbtest.mbt` を含む全ファイルで
> 一意でなければならない（`Error: [4051] ... is declared twice`）。上の名前は契約 §4 の表に
> 登録済みで、G1〜G4 のどれとも衝突しない。`under` の第 2 引数を `anc`、`crown` の局所変数を
> `keep` にしてあるのは、G2 の `fn top(b : Build) -> Frame` を影にしないため。

### この群を貫く 3 つの決めごと

1. **操作 3 本に容器の腕を生やさない。** `move_nodes` / `flip_side` / `delete_nodes` は
   `match path` を 1 つも持たない。型の異種性は tool.mbt に幽閉する
2. **回復は 2 本に割る。** 抜いた側（source）で壊れうるのは「Implicit の存在条件」だけ
   → `prune`（全域）。挿した側（destination）で壊れうるのは「順序法則・Implicit の位置・
   単調性」→ `conform`（局所）。全域の順序法則スイープを書かないのは、
   衝突する 2 つの兄弟のどちらを直すか全域からは決められないから（比例性の原則）
3. **`Verdict` に `derive` を足さない。** `assert_eq` は `Eq + Show` を要るが、
   `Verdict` は契約 §6 の逐語（derive 無し）。テストは `op_said(verdict) -> String` で
   1 行に畳んでから比べる

---

## 実測の裏付け（裁定 7）

**この計画の期待値は、全部 `scratchpad/v2/g5v/` の使い捨てモジュールで実際に走らせて確かめてある。
通らないものは 1 行も書いていない。**

### 実測の場所と手順

`scratchpad/v2/g5v/` に `moon.mod`（`name = "g5v"`）と `core/tree/moon.pkg`
（`pkgtype(kind: "library")`）を置き、そこへ次を写した。

- G1 の確定分（`doc.mbt` / `check.mbt` / `sig.mbt` / `scan.mbt` / `spell.mbt`）と、
  契約 §4 の `make_wbtest.mbt`（`make_list` → `make_item` の改名込み）
- G2 の `parse.mbt` と G3 の `serialize.mbt` は**暫定版**（`scratchpad/v2/lock/` の版）。
  Task 92 の実測は**拒否の経路しか通らない**ので、この 2 本の中身は測る値に影響しない
- 本書 Task 80〜92 の `tool.mbt` / `op.mbt` / `diff.mbt` と 3 本の wbtest（逐語そのまま）

走らせたコマンド（実測モジュールの `core/tree` は、実装先の `<root>/core` の `doc` に当たる）:

```
moon -C <scratchpad>/v2/g5v check core/tree
moon -C <scratchpad>/v2/g5v fmt --check core/tree
moon -C <scratchpad>/v2/g5v test core/tree/<file>_wbtest.mbt
moon -C <scratchpad>/v2/g5v test -p g5v/core/tree
```

### 実測 1: 各 Task の終わりの本数（累計）

wbtest を Task の境目で切り詰めて 13 段階を順に走らせた結果。

| Task | tool | op | diff | 累計（`-p` の `Total tests:`） |
|---|---|---|---|---|
| T80 | 1 | 0 | 0 | **1** |
| T81 | 2 | 0 | 0 | **2** |
| T82 | 4 | 0 | 0 | **4** |
| T83 | 6 | 0 | 0 | **6** |
| T84 | 6 | 2 | 0 | **8** |
| T85 | 6 | 5 | 0 | **11** |
| T86 | 6 | 9 | 0 | **15** |
| T87 | 6 | 13 | 0 | **19** |
| T88 | 6 | 16 | 0 | **22** |
| T89 | 6 | 19 | 0 | **25** |
| T90 | 6 | 19 | 2 | **27** |
| T91 | 6 | 19 | 5 | **30** |
| T92 | 6 | 19 | 7 | **32** |

13 段階すべて `failed: 0.`。**G5 が足すのは 32 本**（tool 6 / op 19 / diff 7）で、
契約 §16 の表と一致する。

### 実測 2: 完成時点の型検査と整形

```
moon -C <scratchpad>/v2/g5v check core/tree
Finished. moon: ran 3 tasks, now up to date
```

EXIT=0。**警告 0・エラー 0**（警告が 1 本も出ないのは、道具・回復・操作が互いを使い切るため。
契約 §11 が触れている `amend` の未使用警告は「呼び手が居ない状態」の話で、G5 完成時点では
`conform` が `amend` を呼ぶので出ない。CI の合格条件が `0 errors` であることは変わらない）。

`moon fmt --check core/tree` は EXIT=0。**本書の逐語はすべて `moon fmt` を通した後の姿**で、
写してもう一度 `moon fmt` を掛けても 1 バイトも動かない。

### 実測 3: EXIT コード（Step 2 / Step 4 の読み方）

ファイル指定のテストコマンドで測った 3 通り。

| 状態 | 出力 | EXIT |
|---|---|---|
| 実装がまだ無い（`[4021] The value identifier crown is unbound.`） | 診断が並ぶ | **1** |
| 期待値が違う（`assert_eq` の失敗） | `Total tests: 19, passed: 18, failed: 1.` | **2** |
| ファイル名の綴り間違い | `Error: Failed to canonicalize input filter directory` | **127** |

**綴りを間違えても黙って緑にはならない。** `Total tests: 0` で緑になるのは `-p` の綴り間違いだけ
（契約 §17 の罠）。

### 実測 4: `op_shape` の期待文字列（Task 85〜89 の全行）

`op_doc()` = `doc(R2[>3(4(5))] R6[<7])` を出発点に、下の 21 行は**全部走らせて一致を確認した**。

| Task | 操作 | 結果 |
|---|---|---|
| 85 | `delete_nodes([3])` | `doc(R2[] R6[<7])` |
| 85 | `delete_nodes([4, 5])` | `doc(R2[>3] R6[<7])` |
| 85 | `delete_nodes([99])` | 拒否・`doc(R2[>3(4(5))] R6[<7])` |
| 85 | `op_implied()` に `delete_nodes([5])` | `doc(R2[])` |
| 85 | Implicit の center に `delete_nodes([3])` | `doc()` |
| 86 | `flip_side([2])`（center = 鏡像） | `doc(R2[<3(4(5))] R6[<7])` |
| 86 | `flip_side([3])`（スロット） | `doc(R2[<3(4(5))] R6[<7])` |
| 86 | `flip_side([3])` を 2 回 | `doc(R2[>3(4(5))] R6[<7])` |
| 86 | **`flip_side([2, 3])`（center と直下の枝）** | **`doc(R2[<3(4(5))] R6[<7])`** |
| 86 | `op_implied()` に `flip_side([3])` | `doc(R2[>3(4(5))])` |
| 86 | `flip_side([4])` / `flip_side([1])` | 拒否・木は不動 |
| 86 | `flip_side([4, 7])` | `doc(R2[>3(4(5))] R6[>7])` |
| 88 | `move_nodes([7], 2, 1, Right)` | `doc(R2[>3(4(5)) >7] R6[])` |
| 88 | `move_nodes([3], 2, 0, Left)` | `doc(R2[<3(4(5))] R6[<7])` |
| 88 | `move_nodes([7, 4], 2, 0, Right)` | `doc(R2[>4(5) >7 >3] R6[])` |
| 89-1 | `move_nodes([2], 1, 1, Right)` | `doc(R6[<7] R2[>3(4(5))])` |
| 89-2 | `move_nodes([2], 6, 0, Left)` | `doc(R6[<2(3(4(5))) <7])` |
| 89-3 | `move_nodes([2], 7, 0, Right)` | `doc(R6[<7(2(3(4(5))))])` |
| 89-4 | `move_nodes([3], 1, 2, Right)` | `doc(R2[] R6[<7] R3[>4(5)])` |
| 89-5 | `move_nodes([3], 6, 1, Left)` | `doc(R2[] R6[<7 <3(4(5))])` |
| 89-6 | `move_nodes([3], 7, 0, Right)` | `doc(R2[] R6[<7(3(4(5)))])` |
| 89-7 | `move_nodes([4], 1, 0, Right)` | `doc(R4[>5] R2[>3] R6[<7])` |
| 89-8 | `move_nodes([4], 6, 0, Right)` | `doc(R2[>3] R6[>4(5) <7])` |
| 89-9 | `move_nodes([4], 7, 0, Right)` | `doc(R2[>3] R6[<7(4(5))])` |

Task 87 の `conform` 4 本の `op_forms` も実測済み — `llhhh`→`llllh` / `hhlh`→`hhhh` /
`hlhhh`→`hllhh` / `hhhih`→`hhhhh`。4 本とも直後の `check(doc)` は空。

### 実測 5: 裁定 4 の逆検証（`crown` を外すと本当に落ちる）

`flip_side` の `let tops = crown(doc, ids)` を外して `for id in ids` に戻すと、
新しいテストだけが落ちる:

```
[g5neg] test core/tree/op_wbtest.mbt:198 ("center とその直下の枝を同時に選んでも二重には反転しない")
failed: ... FAILED: `"doc(R2[>3(4(5))] R6[<7])" != "doc(R2[<3(4(5))] R6[<7])"`
Total tests: 32, passed: 31, failed: 1.
```

center の鏡像で 1 回、枝自身で もう 1 回反転して `>3` に戻る。**裁定 4 の不具合は実在し、
`crown` を通せば消える**ことを両向きで確かめた。

### 実測 6: Task 91 の diff の数値

`diff("# r\n\n## a\n\n## b\n", "# r\n\n## x\n\n## b\n")` は 1 ハンクで
`from = 5` / `to = 10` / `insert = "## x\n"`。**机上ではなく実測値**。

---

## Task 80: 道具の座標系 — Sub / resolve / branch_at

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool.mbt`
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc` / `Center` / `Slot` / `Branch` / `Skeleton` / `Side`（G1 の `doc.mbt`）、
  `sig(doc) -> String`（G1 の `sig.mbt`）、
  `make_doc` / `make_center` / `make_slot` / `make_branch` / `make_head`（G1 の `make_wbtest.mbt`）
- Produces: `priv enum Sub { Whole(Center); Part(Branch) }` /
  `fn resolve(doc : Doc, id : Int) -> Array[Int]?` /
  `fn find_in(branch : Branch, id : Int) -> Array[Int]?` /
  `fn branch_at(doc : Doc, path : ArrayView[Int]) -> Branch`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/tool_wbtest.mbt` を新規作成する。

```moonbit
// 道具の実測。ヘルパ名は `tool_` で始める（wbtest は名前空間を共有する）。

///|
/// `# r` に枝 2 本、深部 1 つの木。
fn tool_doc() -> Doc {
  make_doc([
    make_center(2, make_head("r"), [
      make_slot(
        Right,
        make_branch(3, make_head("a"), [make_branch(4, make_head("x"), [])]),
      ),
      make_slot(Left, make_branch(5, make_head("b"), [])),
    ]),
  ])
}

///|
/// 憲法 §2「id で語る」の足場。腕を 1 本も持たずに 3 つの容器を横断する。
test "resolve は id から居場所を返す" {
  let doc = tool_doc()
  assert_eq(resolve(doc, 2), Some([0]))
  assert_eq(resolve(doc, 3), Some([0, 0]))
  assert_eq(resolve(doc, 4), Some([0, 0, 0]))
  assert_eq(resolve(doc, 5), Some([0, 1]))
  assert_eq(resolve(doc, 99), None)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: **EXIT=1**（実測 3）。
```
Error: [4021]
The value identifier resolve is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/tool.mbt` を新規作成する。ファイル冒頭の 3 行は**契約 §11 の逐語コメント**
（1 文字も変えない）。

```moonbit
// 道具 5 本。型の異種性はここに幽閉する（操作には腕を生やさない）。
// Path = Array[Int]（[] = doc、[i] = center、[i, j] = スロット、以深 = children）。
// 殺す条件の観測点: 容器の腕が 3 で止まらなくなったら負け。

///|
/// 運搬の通貨。**一度しか graft してはならない**（struct は参照なので、
/// 二度挿すと中の Branch が物理共有される）。この型は op の外に出ない。
priv enum Sub {
  Whole(Center)
  Part(Branch)
}

///|
/// id からその居場所へ。腕なし。
fn resolve(doc : Doc, id : Int) -> Array[Int]? {
  for i, r in doc.centers {
    if r.id == id {
      return Some([i])
    }
    for j, b in r.slots {
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
/// 深さ 2 以降のノードそのもの。道具が共有する唯一の座標系。
fn branch_at(doc : Doc, path : ArrayView[Int]) -> Branch {
  guard! path is [i, j, .. rest]
  let mut n = doc.centers[i].slots[j].branch
  for k in rest {
    n = n.children[k]
  }
  n
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: `Total tests: 1, passed: 1, failed: 0.` EXIT=0（**G5 の累計 1 本**）。
`Warning: [0001] Unused function 'branch_at'` が 1 本出るが、Task 81 で消える。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/tool.mbt core/tree/tool_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 道具の座標系（id から居場所へ）を置く"
```

---

## Task 81: 道具の読み — kin_at / parent_at

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`

**Interfaces:**
- Consumes: `branch_at(doc : Doc, path : ArrayView[Int]) -> Branch`
- Produces: `fn kin_at(doc : Doc, path : Array[Int]) -> Array[Skeleton]` /
  `fn parent_at(doc : Doc, path : Array[Int]) -> Skeleton?`

> **なぜ道具が 2 本増えるのか**: 行き先の順序法則（前に見出し側が居るか / 後ろに項目が
> 居るか）を測るには、挿した場所の**兄弟の列**が要る。その列は 3 つの容器のどれかで、
> これは道具層が幽閉するべき異種性そのもの。op.mbt に置くと操作に腕が生える。
> `parent_at` は `kin_at` の上に建つので腕は 0 本 — **増えたのは読む道具 1 本だけ**
> （契約 §11 の「道具は 5 本」の 5 本目がこれ）。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/tool_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 行き先の順序法則を測るための列。3 つの容器を 1 本の読みに畳む。
test "kin_at は path が居る列を、parent_at はその親を返す" {
  let doc = tool_doc()
  assert_eq(kin_at(doc, [0]).length(), 1) // 文書直下 = centers
  assert_eq(kin_at(doc, [0, 0]).length(), 2) // center 直下 = slots
  assert_eq(kin_at(doc, [0, 0, 0]).length(), 1) // 以深 = children
  assert_eq(kin_at(doc, []).length(), 0)
  // 親が居ない（文書）ときだけ None
  assert_eq(parent_at(doc, [0]) is None, true)
  assert_eq(parent_at(doc, [0, 0]) is Some(_), true)
  assert_eq(parent_at(doc, [0, 0, 0]) is Some(_), true)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier kin_at is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/tool.mbt` の `branch_at` の直後に足す。

```moonbit
///|
/// path が居る列（自分を含む兄弟）の骨格。読み専用の 3 腕。
/// 行き先の順序法則を測るのと、サブツリーを歩くのに要る。
fn kin_at(doc : Doc, path : Array[Int]) -> Array[Skeleton] {
  match path {
    [] => []
    [_] => doc.centers.map(fn(r) { r.skeleton })
    [i, _] => doc.centers[i].slots.map(fn(b) { b.branch.skeleton })
    [.. head, _] => branch_at(doc, head).children.map(fn(c) { c.skeleton })
  }
}

///|
/// 親の骨格（None = 文書）。kin_at の上に建つので容器の腕は生えない。
fn parent_at(doc : Doc, path : Array[Int]) -> Skeleton? {
  if path.length() < 2 {
    return None
  }
  let up = path.copy()
  ignore(up.remove(up.length() - 1))
  Some(kin_at(doc, up)[up[up.length() - 1]])
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: `Total tests: 2, passed: 2, failed: 0.` EXIT=0（**G5 の累計 2 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/tool.mbt core/tree/tool_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 行き先を測る読みの道具（兄弟の列と親）を置く"
```

---

## Task 82: 抜き挿し — pluck / graft と変換表

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`

**Interfaces:**
- Consumes: `Sub` / `branch_at` / `sig(doc) -> String`
- Produces: `fn pluck(doc : Doc, path : Array[Int]) -> Sub?` /
  `fn graft(doc : Doc, parent : Array[Int], at : Int, sub : Sub, side : Side) -> Unit` /
  `fn as_center(sub : Sub) -> Center` / `fn as_branch(sub : Sub) -> Branch`

変換表（契約 §11）:

| 行き先 | `Whole(Center)` | `Part(Branch)` |
|---|---|---|
| doc（`parent = []`） | 無変換。sides が無傷で旅する | **Center 化** — children を `Slot(Right)` で包む。`side` 引数は使わない |
| center（`parent = [i]`） | **解体** — slots を捨てて children にする。新しい side は**引数**が決める | `Slot(side)` で包む |
| branch（2 段以上） | **解体**。`side` 引数は捨てられる | そのまま。`side` 引数は捨てられる |

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/tool_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 憲法 §2「側は場所の属性」— pluck は側を残置し、graft が行き先で決め直す。
test "pluck は抜いた瞬間 doc から消え、graft が行き先で側を決め直す" {
  let doc = tool_doc()
  guard pluck(doc, [0, 0, 0]) is Some(sub) else { abort("no sub") }
  assert_eq(sig(doc), "D-n()[Reh_1:r()[>Neh_1:a()[]<Neh_1:b()[]]]")
  graft(doc, [0], 0, sub, Left)
  assert_eq(sig(doc), "D-n()[Reh_1:r()[<Neh_1:x()[]>Neh_1:a()[]<Neh_1:b()[]]]")
}

///|
/// 変換の唯一の住所。Part を文書へ挿すと Center 化し、children が Right の枝になる。
test "graft は Part を文書へ挿すとき Center 化する" {
  let doc = tool_doc()
  guard pluck(doc, [0, 0]) is Some(sub) else { abort("no sub") }
  graft(doc, [], 0, sub, Left)
  // a が center になり、子の x は Right の枝として包まれた（side 引数は使われない）
  assert_eq(sig(doc), "D-n()[Reh_1:a()[>Neh_1:x()[]]Reh_1:r()[<Neh_1:b()[]]]")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier pluck is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/tool.mbt` の `parent_at` の直後に足す（`as_center` / `as_branch` はファイル末尾）。

```moonbit
///|
/// 抜き取る。容器 3 腕（centers / slots / children）。
/// **抜いた瞬間 doc から消える** — graft までの間に落とすと木が壊れる。
fn pluck(doc : Doc, path : Array[Int]) -> Sub? {
  match path {
    [] => None
    [i] => Some(Whole(doc.centers.remove(i)))
    [i, j] => Some(Part(doc.centers[i].slots.remove(j).branch))
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
    [] => doc.centers.insert(at, as_center(sub))
    [i] => doc.centers[i].slots.insert(at, { side, branch: as_branch(sub) })
    _ => branch_at(doc, parent[:]).children.insert(at, as_branch(sub))
  }
}
```

同じファイルの末尾に足す。

```moonbit
///|
/// doc へ: Part → Center 化（children を Slot(Right) で包む）/ Whole → 無変換
fn as_center(sub : Sub) -> Center {
  match sub {
    Whole(r) => r
    Part(n) =>
      {
        id: n.id,
        skeleton: n.skeleton,
        slots: n.children.map(fn(c) { { side: Right, branch: c } }),
      }
  }
}

///|
/// center / branch へ: Whole → 解体（sides は深さの物理で消滅）/ Part → そのまま
fn as_branch(sub : Sub) -> Branch {
  match sub {
    Whole(r) =>
      {
        id: r.id,
        skeleton: r.skeleton,
        children: r.slots.map(fn(b) { b.branch }),
      }
    Part(n) => n
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: `Total tests: 4, passed: 4, failed: 0.` EXIT=0（**G5 の累計 4 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/tool.mbt core/tree/tool_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 抜き挿しと、変換の唯一の住所を置く"
```

---

## Task 83: 書き替え — amend / set_side

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/tool_wbtest.mbt`

**Interfaces:**
- Consumes: `branch_at` / `Skeleton` / `Side`
- Produces: `fn amend(doc : Doc, path : Array[Int], f : (Skeleton) -> Skeleton) -> Unit` /
  `fn set_side(doc : Doc, i : Int, j : Int, side : Side) -> Unit`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/tool_wbtest.mbt` の末尾に足す。

```moonbit
///|
fn tool_fold(skeleton : Skeleton) -> Skeleton {
  match skeleton {
    Implicit => Implicit
    Explicit(form~, label~, folded=_, body~) =>
      Explicit(form~, label~, folded=true, body~)
  }
}

///|
/// 3 つの容器のどこでも同じ 1 本で届く。`[i, j]` だけ Slot と Branch の 2 段を包み直す。
test "amend は 3 つの容器のどこでも骨格を書き替える" {
  let doc = tool_doc()
  amend(doc, [0], tool_fold)
  amend(doc, [0, 0], tool_fold)
  amend(doc, [0, 0, 0], tool_fold)
  assert_eq(sig(doc), "D-n()[Reh^1:r()[>Neh^1:a()[Neh^1:x()[]]<Neh_1:b()[]]]")
}

///|
/// side は場所の属性なので、骨格を書き替える amend では届かない。
test "set_side はスロットの側だけを差し替える" {
  let doc = tool_doc()
  set_side(doc, 0, 0, Left)
  assert_eq(sig(doc), "D-n()[Reh_1:r()[<Neh_1:a()[Neh_1:x()[]]<Neh_1:b()[]]]")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier amend is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/tool.mbt` の `graft` の直後に足す。`amend` の直前の 3 行は**契約 §11 の逐語コメント**
（1 文字も変えない）。

```moonbit
///|
/// 骨格を書き替える。容器 3 腕 — `[i, j]` だけは Slot と Branch の 2 段を包み直す。
/// （`Slot` に `mut branch` を 1 つ足せば 2 段包みが消える。腕が 4 本目になったら検討する）
fn amend(doc : Doc, path : Array[Int], f : (Skeleton) -> Skeleton) -> Unit {
  match path {
    [] => ()
    [i] => {
      let r = doc.centers[i]
      doc.centers[i] = { ..r, skeleton: f(r.skeleton) }
    }
    [i, j] => {
      let b = doc.centers[i].slots[j]
      doc.centers[i].slots[j] = {
        ..b,
        branch: { ..b.branch, skeleton: f(b.branch.skeleton) },
      }
    }
    [.. head, last] => {
      let owner = branch_at(doc, head)
      let n = owner.children[last]
      owner.children[last] = { ..n, skeleton: f(n.skeleton) }
    }
  }
}

///|
/// スロットの側を差し替える（side は場所の属性なので amend では届かない）。
fn set_side(doc : Doc, i : Int, j : Int, side : Side) -> Unit {
  let b = doc.centers[i].slots[j]
  doc.centers[i].slots[j] = { ..b, side, }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/tool_wbtest.mbt
```
Expected: `Total tests: 6, passed: 6, failed: 0.` EXIT=0（**G5 の累計 6 本**。
`tool_wbtest.mbt` はここで完成し、以降 1 本も増えない）。
`Warning: [0001] Unused function 'set_side'` が 1 本残る（Task 86 で消える）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/tool.mbt core/tree/tool_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 骨格と側の書き替えを置く"
```

---

## Task 84: 拒否の文言と頂点集合

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op.mbt`
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`

**Interfaces:**
- Consumes: `resolve` / `branch_at` / `doc_id`（G1）、`make_*`（G1 の `make_wbtest.mbt`）
- Produces: `fn crown(doc : Doc, ids : Array[Int]) -> Array[Int]` /
  `fn ahead(a : Array[Int], b : Array[Int]) -> Bool` /
  `fn under(path : Array[Int], anc : Array[Int]) -> Bool` /
  `fn dest(doc : Doc, parent : Int) -> Array[Int]?` /
  `fn clamp(doc : Doc, parent : Array[Int], at : Int) -> Int` /
  `fn flipped(side : Side) -> Side` / `fn pick(ids : Array[Int]) -> Int` /
  `fn missing(id : Int) -> String` / `fn cyclic(id : Int) -> String` /
  `fn shallow(id : Int) -> String`

拒否は 3 つだけ（契約 §10）:

```
見つからない (id=7)
子孫へは動かせない (id=7)
側を変えられるのは center と center 直下の枝だけ (id=7)
```

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/op_wbtest.mbt` を新規作成する。

```moonbit
// 操作の実測。ヘルパ名は `op_` で始める（wbtest は名前空間を共有する）。

///|
/// 形: doc(R2[>3(4(5))] R6[<7])
fn op_doc() -> Doc {
  make_doc([
    make_center(2, make_head("r"), [
      make_slot(
        Right,
        make_branch(3, make_head("a"), [
          make_branch(4, make_head("x"), [make_branch(5, make_head("y"), [])]),
        ]),
      ),
    ]),
    make_center(6, make_head("s"), [
      make_slot(Left, make_branch(7, make_head("b"), [])),
    ]),
  ])
}

///|
/// C16 の形 — `# r` + `---` + `#### b`（スロットが左、占有者は Implicit 2 段）。
fn op_implied() -> Doc {
  make_doc([
    make_center(2, make_head("r"), [
      make_slot(
        Left,
        make_branch(3, Implicit, [
          make_branch(4, Implicit, [make_branch(5, make_head("b"), [])]),
        ]),
      ),
    ]),
  ])
}

///|
/// 木の形を 1 行に畳む（id と側だけ）。骨格の中身は sig が見る。
fn op_shape(doc : Doc) -> String {
  let sb = StringBuilder::new()
  sb.write_string("doc(")
  for k, r in doc.centers {
    if k > 0 {
      sb.write_string(" ")
    }
    sb.write_string("R")
    sb.write_string(r.id.to_string())
    sb.write_string("[")
    for j, b in r.slots {
      if j > 0 {
        sb.write_string(" ")
      }
      sb.write_string(
        match b.side {
          Right => ">"
          Left => "<"
        },
      )
      op_limb(sb, b.branch)
    }
    sb.write_string("]")
  }
  sb.write_string(")")
  sb.to_string()
}

///|
fn op_limb(sb : StringBuilder, branch : Branch) -> Unit {
  sb.write_string(branch.id.to_string())
  if !branch.children.is_empty() {
    sb.write_string("(")
    for k, c in branch.children {
      if k > 0 {
        sb.write_string(" ")
      }
      op_limb(sb, c)
    }
    sb.write_string(")")
  }
}

///|
/// 骨格の種類を文書順に（h = 見出し / l = 項目 / i = Implicit）。
fn op_forms(doc : Doc) -> String {
  let sb = StringBuilder::new()
  for r in doc.centers {
    sb.write_string(op_mark(r.skeleton))
    for b in r.slots {
      op_form_branch(sb, b.branch)
    }
  }
  sb.to_string()
}

///|
fn op_form_branch(sb : StringBuilder, branch : Branch) -> Unit {
  sb.write_string(op_mark(branch.skeleton))
  for c in branch.children {
    op_form_branch(sb, c)
  }
}

///|
fn op_mark(skeleton : Skeleton) -> String {
  match skeleton {
    Implicit => "i"
    Explicit(form~, ..) => if form is Heading { "h" } else { "l" }
  }
}

///|
/// 判定を 1 行に（Verdict に derive を足さないため）。
fn op_said(verdict : Verdict) -> String {
  match verdict {
    Applied => "ok"
    Rejected(reason) => reason
  }
}

///|
/// 憲法 §5「複数選択は頂点集合に正規化」。子孫は祖先に吸収され、戻りは文書順。
test "crown は子孫を祖先に吸収し、文書順に並べる" {
  let doc = op_doc()
  assert_eq(crown(doc, [3, 4, 5]), [3])
  assert_eq(crown(doc, [7, 4]), [4, 7]) // 選択の順ではなく文書順
  assert_eq(crown(doc, [2, 7]), [2, 7])
  assert_eq(crown(doc, [99]), [])
  assert_eq(crown(doc, [4, 4]), [4]) // 同じ id を 2 度渡しても 1 本
}

///|
/// 拒否の綴りは 3 つだけ。文言は契約 §10 の逐語。
test "拒否の文言は 3 つだけ" {
  assert_eq(missing(7), "見つからない (id=7)")
  assert_eq(cyclic(7), "子孫へは動かせない (id=7)")
  assert_eq(
    shallow(7),
    "側を変えられるのは center と center 直下の枝だけ (id=7)",
  )
  assert_eq(under([0, 1, 2], [0, 1]), true)
  assert_eq(under([0, 1], [0, 1]), true) // 自分自身も「下」
  assert_eq(under([0, 1], [0, 1, 2]), false)
  assert_eq(under([1], [0]), false)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier crown is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/op.mbt` を新規作成する。

```moonbit
// 木の道。id で語り、道具の合成だけで書く。操作に容器の腕を生やさない。

///|
/// 子孫の選択は祖先に吸収される（憲法 §5 の頂点集合への正規化）。
/// 戻りは文書順 — move が「文書順を保って連続挿入」するため。
fn crown(doc : Doc, ids : Array[Int]) -> Array[Int] {
  let seats : Array[(Array[Int], Int)] = []
  for id in ids {
    guard resolve(doc, id) is Some(path) else { continue }
    let mut keep = true
    for other in ids {
      if other != id && resolve(doc, other) is Some(above) {
        if above.length() < path.length() && under(path, above) {
          keep = false
        }
      }
    }
    let mut twice = false
    for seat in seats {
      if seat.1 == id {
        twice = true
      }
    }
    if keep && !twice {
      // 文書順（path の辞書順）へ挿す
      let mut k = 0
      while k < seats.length() && ahead(seats[k].0, path) {
        k = k + 1
      }
      seats.insert(k, (path, id))
    }
  }
  seats.map(fn(seat) { seat.1 })
}

///|
/// a が b より文書順で前か（path の辞書順）。
fn ahead(a : Array[Int], b : Array[Int]) -> Bool {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for k in 0..<n {
    if a[k] != b[k] {
      return a[k] < b[k]
    }
  }
  a.length() < b.length()
}

///|
/// path が anc の下（anc 自身を含む）に居るか。
fn under(path : Array[Int], anc : Array[Int]) -> Bool {
  if anc.length() > path.length() {
    return false
  }
  for k in 0..<anc.length() {
    if path[k] != anc[k] {
      return false
    }
  }
  true
}

///|
/// 親の id から挿す先の path へ。文書は番兵 `doc_id`（憲法 §5「center は親が文書のノード」）。
fn dest(doc : Doc, parent : Int) -> Array[Int]? {
  if parent == doc_id {
    Some([])
  } else {
    resolve(doc, parent)
  }
}

///|
/// `Array::insert` の範囲外は catch 不能な panic なので、graft の前に必ず通す。
fn clamp(doc : Doc, parent : Array[Int], at : Int) -> Int {
  let len = match parent {
    [] => doc.centers.length()
    [i] => doc.centers[i].slots.length()
    _ => branch_at(doc, parent[:]).children.length()
  }
  if at < 0 {
    0
  } else if at > len {
    len
  } else {
    at
  }
}

///|
fn flipped(side : Side) -> Side {
  match side {
    Right => Left
    Left => Right
  }
}

///|
/// 拒否に載せる id。空の選択は文書を名指す。
fn pick(ids : Array[Int]) -> Int {
  if ids.is_empty() {
    doc_id
  } else {
    ids[0]
  }
}

///|
fn missing(id : Int) -> String {
  "見つからない (id=" + id.to_string() + ")"
}

///|
fn cyclic(id : Int) -> String {
  "子孫へは動かせない (id=" + id.to_string() + ")"
}

///|
fn shallow(id : Int) -> String {
  "側を変えられるのは center と center 直下の枝だけ (id=" +
  id.to_string() +
  ")"
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: `Total tests: 2, passed: 2, failed: 0.` EXIT=0（**G5 の累計 8 本**）。
G5 の名前で未使用の警告が出る（実測 — `crown` / `dest` / `clamp` / `flipped` / `pick` /
`missing` / `cyclic` / `shallow` / `op_implied` / `op_shape` / `op_forms` / `op_said` /
`parent_at` / `pluck` / `graft` / `amend` / `set_side` の 17 本）。Task 85〜89 で全部消える。
**`pub` にして黙らせてはならない**（契約 §11）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/op.mbt core/tree/op_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 頂点集合への正規化と、拒否の文言 3 つを置く"
```

---

## Task 85: delete と、Implicit の存在条件の回復

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`

**Interfaces:**
- Consumes: `crown` / `resolve` / `pluck` / `pick` / `missing` / `check`（G1）
- Produces: `pub fn delete_nodes(doc : Doc, ids : Array[Int]) -> Verdict` /
  `fn prune(doc : Doc) -> Unit` / `fn alive(branch : Branch) -> Bool`

> **回復の範囲（抜いた側）**: 木から要素を取り除いても、順序法則（条件 5）も
> Implicit の位置（条件 3）も単調性（条件 6）も破れない — 並びは変わらないから。
> 壊れうるのは**条件 2（Implicit は子を持つ限りにおいて存在する）だけ**。
> よって抜いた側の回復は `prune` 1 本で足りる。憲法 §2 の言葉では
> 「削除という出来事ではない。導出されなくなるだけ」。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/op_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 憲法 §5「delete もサブツリー削除で統一」。
test "delete はサブツリーごと消し、複数選択は頂点集合に畳む" {
  let one = op_doc()
  assert_eq(op_said(delete_nodes(one, [3])), "ok")
  assert_eq(op_shape(one), "doc(R2[] R6[<7])")
  let two = op_doc()
  assert_eq(op_said(delete_nodes(two, [4, 5])), "ok")
  assert_eq(op_shape(two), "doc(R2[>3] R6[<7])")
  let three = op_doc()
  assert_eq(op_said(delete_nodes(three, [99])), "見つからない (id=99)")
  assert_eq(op_shape(three), "doc(R2[>3(4(5))] R6[<7])")
}

///|
/// 憲法 §2「implied は子を持つ限りにおいて存在する」。空の連鎖は下から順に消える。
test "子を失った Implicit は連鎖ごと導出されなくなる" {
  let doc = op_implied()
  assert_eq(op_said(delete_nodes(doc, [5])), "ok")
  assert_eq(op_shape(doc), "doc(R2[])")
  assert_eq(check(doc).length(), 0)
}

///|
/// center が Implicit の木も同じ規則。文書直下から消える。
test "Implicit の center も子を失えば消える" {
  let doc = make_doc([
    make_center(2, Implicit, [
      make_slot(Right, make_branch(3, make_head("h"), [])),
    ]),
  ])
  assert_eq(op_said(delete_nodes(doc, [3])), "ok")
  assert_eq(op_shape(doc), "doc()")
  assert_eq(check(doc).length(), 0)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier delete_nodes is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/op.mbt` の `crown` の直前に足す（公開 API をファイルの頭に置く）。

```moonbit
///|
/// サブツリーごと消す。複数選択は頂点集合に正規化してから抜く。
pub fn delete_nodes(doc : Doc, ids : Array[Int]) -> Verdict {
  let tops = crown(doc, ids)
  guard !tops.is_empty() else { return Rejected(missing(pick(ids))) }
  for id in tops {
    // 抜くたびに index がずれるので、その都度測り直す
    guard resolve(doc, id) is Some(path) else { return Rejected(missing(id)) }
    ignore(pluck(doc, path))
  }
  prune(doc)
  Applied
}
```

同じファイルの末尾（`shallow` の後）に足す。

```moonbit
///|
/// 回復（抜いた側）。子を失った Implicit は、削除という出来事ではなく
/// 導出されなくなる（憲法 §2 の存在条件）。深いほうから掃くので連鎖が 1 回で消える。
fn prune(doc : Doc) -> Unit {
  for r in doc.centers {
    r.slots.retain(fn(b) { alive(b.branch) })
  }
  doc.centers.retain(fn(r) { !(r.skeleton is Implicit) || !r.slots.is_empty() })
}

///|
/// 子を先に掃いてから自分を判定する（下から上へ）。
fn alive(branch : Branch) -> Bool {
  branch.children.retain(alive)
  !(branch.skeleton is Implicit) || !branch.children.is_empty()
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: `Total tests: 5, passed: 5, failed: 0.` EXIT=0（**G5 の累計 11 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/op.mbt core/tree/op_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ サブツリー削除と、子を失った Implicit の片付けを置く"
```

---

## Task 86: flipSide — center は鏡像、スロットは反転、深部は拒否

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`

**Interfaces:**
- Consumes: `crown` / `resolve` / `set_side` / `flipped` / `pick` / `shallow` / `check`（G1）
- Produces: `pub fn flip_side(doc : Doc, ids : Array[Int]) -> Verdict`

> **憲法 §5 の資格 3 段**: center = 鏡像（全スロット一括反転。木全体が center の
> サブツリーなので比例）/ center 直下の枝 = そのスロットの反転 / 深いノードと文書 = 拒否
> （委譲は効果が選択を上向きにはみ出す）。**占有者が Implicit でも昇格は不要**（C16 —
> トグルは隙間に付き、スロットの占有者を問わない）。
> この 3 段は**意味の腕**であって容器の腕ではない（`resolve` の結果の形で分かれるだけで、
> 3 つの容器を触り分けてはいない。契約 §11 の腕数の定義）。
>
> **`flip_side` も `crown` を通す**（契約 §10 の細目・裁定 4）。憲法 §5 の
> 「複数選択は頂点集合に正規化してから適用」は操作一般の規則で、move / delete に限らない。
> 通さないと、center とその直下の枝を同時に選んだとき **center の鏡像で 1 回・枝自身で 1 回**の
> 二重反転が起き、枝が元の側に戻る（実測 5 で両向きに確認済み）。
> `crown` は resolve できない id を落とすので、`hit` が false のまま抜けたときの
> `pick(ids)` はそのまま使える。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/op_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 憲法 §5「center = 鏡像 / 枝 = そのスロット」。
test "flipSide は center で鏡像、スロットでそのスロットだけ反転する" {
  let mirror = op_doc()
  assert_eq(op_said(flip_side(mirror, [2])), "ok")
  assert_eq(op_shape(mirror), "doc(R2[<3(4(5))] R6[<7])")
  let one = op_doc()
  assert_eq(op_said(flip_side(one, [3])), "ok")
  assert_eq(op_shape(one), "doc(R2[<3(4(5))] R6[<7])")
  let back = op_doc()
  ignore(flip_side(back, [3]))
  ignore(flip_side(back, [3]))
  assert_eq(op_shape(back), "doc(R2[>3(4(5))] R6[<7])") // 2 回で戻る
}

///|
/// 裁定 4 — 頂点集合に畳まないと、center の鏡像と枝の反転で二重に効いて元へ戻る。
test "center とその直下の枝を同時に選んでも二重には反転しない" {
  let doc = op_doc()
  assert_eq(op_said(flip_side(doc, [2, 3])), "ok")
  assert_eq(op_shape(doc), "doc(R2[<3(4(5))] R6[<7])")
}

///|
/// C16 — 占有者が Implicit でも側は立つ。昇格も骨格行も要らない。
test "Implicit のスロットも側を持てる" {
  let doc = op_implied()
  assert_eq(op_said(flip_side(doc, [3])), "ok")
  assert_eq(op_shape(doc), "doc(R2[>3(4(5))])")
  assert_eq(check(doc).length(), 0)
}

///|
/// 深いノードと文書は資格が無い。複数選択では資格のあるものだけに効く。
test "深いノードと文書への flipSide は拒否される" {
  let deep = op_doc()
  assert_eq(
    op_said(flip_side(deep, [4])),
    "側を変えられるのは center と center 直下の枝だけ (id=4)",
  )
  assert_eq(op_shape(deep), "doc(R2[>3(4(5))] R6[<7])")
  let whole = op_doc()
  assert_eq(
    op_said(flip_side(whole, [1])),
    "側を変えられるのは center と center 直下の枝だけ (id=1)",
  )
  let mixed = op_doc()
  assert_eq(op_said(flip_side(mixed, [4, 7])), "ok") // 4 は黙って飛ばす
  assert_eq(op_shape(mixed), "doc(R2[>3(4(5))] R6[>7])")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier flip_side is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/op.mbt` の `delete_nodes` の直前に足す。

```moonbit
///|
/// center と center 直下の枝にだけ効く。center は鏡像（全スロット一括反転）。
/// 資格の無い id は黙って飛ばし、1 つも効かなければ拒否する。
pub fn flip_side(doc : Doc, ids : Array[Int]) -> Verdict {
  let tops = crown(doc, ids)
  let mut hit = false
  for id in tops {
    match resolve(doc, id) {
      Some([i]) => {
        for j, b in doc.centers[i].slots {
          set_side(doc, i, j, flipped(b.side))
        }
        hit = true
      }
      Some([i, j]) => {
        set_side(doc, i, j, flipped(doc.centers[i].slots[j].side))
        hit = true
      }
      _ => ()
    }
  }
  if hit {
    Applied
  } else {
    Rejected(shallow(pick(ids)))
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: `Total tests: 9, passed: 9, failed: 0.` EXIT=0（**G5 の累計 15 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/op.mbt core/tree/op_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 側の反転（頂点集合・center は鏡像・深部は拒否）を置く"
```

---

## Task 87: 回復（挿した側）— conform と sink

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`

**Interfaces:**
- Consumes: `kin_at` / `parent_at` / `amend` / `pluck` / `graft` /
  `is_item`（G1 の `check.mbt`）/ `check`（G1）
- Produces: `fn conform(doc : Doc, path : Array[Int]) -> Unit` /
  `fn sink(doc : Doc, path : Array[Int]) -> Unit` /
  `fn raised(skeleton : Skeleton, promote : Bool) -> Skeleton` /
  `fn itemed(skeleton : Skeleton) -> Skeleton`

> **行き先が決める 3 つの締め付け**（挿した場所の兄弟と親だけを見る）
>
> - **A 親から**: 親が Explicit(Item) → 自分は Item 必須（単調性・条件 6）/
>   親が Implicit → 自分は Item 禁止（条件 4）
> - **B 兄弟から**: 前に見出し側が居る → Item 禁止 / 後ろに項目が居る → Item 必須（条件 5）
> - **C Implicit の位置**: 前に「項目でない兄弟」が居る → Implicit 禁止 = 昇格（条件 3）
>
> 健全な木では「Item 必須」と「Item 禁止」は同時に立たない（親が Item なら兄弟は全部
> Item、親が Implicit なら兄弟に Item は居ない）。**Item 化はサブツリーごと**
> （単調性は下向き）、**Heading 化は頂点だけ**（C14 —「x に子が居れば子は Item のままで合法」）。
>
> **conform が新しい破れを作らないこと**: 頂点を Heading にするのは「前に見出し側が
> 居る」ときだけで、そのとき後ろに項目は居ない（居たら元の木が既に条件 5 を破っている）。
> 頂点を Item にするのは「後ろに項目が居る」か「親が Item」のときだけで、
> そのとき前に見出し側は居ない。よって**健全な木への挿入は、健全な木のままになる**。
>
> **飛びが表現できない位置の Implicit を昇格させるのはここ**（`raised(s, true)`）。
> serialize 側に安全弁を二重に置かない — serialize が model と違うものを書いたら
> 法則 1 が定義ごと壊れる（契約 §19 の G4 Task 67 の差し戻し）。
>
> `sink` は `kin_at` と `amend` の合成だけで書く（容器の腕は 0 本）。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/op_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 憲法 §5「Item 親の下へ move された Heading サブツリーはサブツリーごと Item 化」。
test "conform は Item 親の下でサブツリーごと項目にする" {
  let doc = make_doc([
    make_center(2, make_item("c"), [
      make_slot(Right, make_branch(3, make_item("a"), [])),
    ]),
    make_center(6, make_head("s"), [
      make_slot(
        Right,
        make_branch(7, make_head("b"), [make_branch(8, make_head("d"), [])]),
      ),
    ]),
  ])
  assert_eq(op_forms(doc), "llhhh")
  // branch 3（Item）の子として 7 を置く
  guard pluck(doc, [1, 0]) is Some(sub) else { abort("no sub") }
  graft(doc, [0, 0], 0, sub, Right)
  conform(doc, [0, 0, 0])
  assert_eq(op_forms(doc), "llllh")
  assert_eq(check(doc).length(), 0)
}

///|
/// C14 — 順序法則により、Heading 兄弟の間の Item はそのノードだけ Heading 化する。
test "conform は見出しの兄弟の後ろで頂点だけ見出しにする" {
  let doc = make_doc([
    make_center(2, make_head("r"), [
      make_slot(
        Right,
        make_branch(3, make_head("a"), [make_branch(4, make_item("x"), [])]),
      ),
      make_slot(Right, make_branch(5, make_head("b"), [])),
    ]),
  ])
  assert_eq(op_forms(doc), "hhlh")
  guard pluck(doc, [0, 0, 0]) is Some(sub) else { abort("no sub") }
  graft(doc, [0], 1, sub, Right)
  conform(doc, [0, 1])
  assert_eq(op_forms(doc), "hhhh")
  assert_eq(check(doc).length(), 0)
}

///|
/// 逆向き — 後ろに項目が居る場所へは見出しを書けない（順序法則）。
test "conform は後ろに項目が居る場所で項目にする" {
  let doc = make_doc([
    make_center(2, make_head("r"), [
      make_slot(Right, make_branch(3, make_item("x"), [])),
      make_slot(Right, make_branch(4, make_head("a"), [])),
    ]),
    make_center(5, make_head("s"), [
      make_slot(Right, make_branch(6, make_head("b"), [])),
    ]),
  ])
  assert_eq(op_forms(doc), "hlhhh")
  guard pluck(doc, [1, 0]) is Some(sub) else { abort("no sub") }
  graft(doc, [0], 0, sub, Right)
  conform(doc, [0, 0])
  assert_eq(op_forms(doc), "hllhh")
  assert_eq(check(doc).length(), 0)
}

///|
/// 憲法 §5「綴りは行き先に従う」— 飛びで表現できない位置へ来た Implicit は昇格する。
test "conform は飛びを書けない位置の Implicit を昇格させる" {
  let doc = make_doc([
    make_center(2, make_head("r"), [
      make_slot(Right, make_branch(3, make_head("a"), [])),
    ]),
    make_center(6, make_head("s"), [
      make_slot(
        Right,
        make_branch(7, Implicit, [make_branch(8, make_head("b"), [])]),
      ),
    ]),
  ])
  assert_eq(op_forms(doc), "hhhih")
  guard pluck(doc, [1, 0]) is Some(sub) else { abort("no sub") }
  graft(doc, [0], 1, sub, Right)
  conform(doc, [0, 1])
  assert_eq(op_forms(doc), "hhhhh")
  assert_eq(check(doc).length(), 0)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier conform is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/op.mbt` の `prune` の直後に足す。

```moonbit
///|
/// 回復（挿した側）。form も綴りも行き先に従い、効果はサブツリーの中に収まる
/// （憲法 §5 の比例性の原則）。健全な木への挿入は、健全な木のままになる。
fn conform(doc : Doc, path : Array[Int]) -> Unit {
  if path.is_empty() {
    return
  }
  let at = path[path.length() - 1]
  let kin = kin_at(doc, path)
  let mut headed = false
  for k in 0..<at {
    if !is_item(kin[k]) {
      headed = true
    }
  }
  let mut listed = false
  let after = at + 1
  for k in after..<kin.length() {
    if is_item(kin[k]) {
      listed = true
    }
  }
  let parent = parent_at(doc, path)
  let mut parent_item = false
  let mut parent_implicit = false
  match parent {
    Some(s) => {
      parent_item = is_item(s)
      parent_implicit = s is Implicit
    }
    None => ()
  }
  if listed || parent_item {
    sink(doc, path) // 単調性は下向き — サブツリーごと項目にする
  } else if headed {
    amend(doc, path, fn(s) { raised(s, true) }) // 飛びは書けないので昇格も込み
  } else if parent_implicit {
    amend(doc, path, fn(s) { raised(s, false) }) // Implicit の子は項目でない
  }
}

///|
/// 項目へ沈める。道具（kin_at と amend）の合成だけなので容器の腕は生えない。
fn sink(doc : Doc, path : Array[Int]) -> Unit {
  amend(doc, path, itemed)
  let deep = path.copy()
  deep.push(0)
  let n = kin_at(doc, deep).length()
  for k in 0..<n {
    deep[deep.length() - 1] = k
    sink(doc, deep.copy())
  }
}

///|
/// 見出し側へ。promote が真なら Implicit も骨格行を得て昇格する
/// （飛びが表現できない位置へ来たときの安全弁 — 憲法 §5）。
fn raised(skeleton : Skeleton, promote : Bool) -> Skeleton {
  match skeleton {
    Implicit =>
      if promote {
        Explicit(form=Heading, label="", folded=false, body=[])
      } else {
        Implicit
      }
    Explicit(form=_, label~, folded~, body~) =>
      Explicit(form=Heading, label~, folded~, body~)
  }
}

///|
/// 項目へ。Implicit は相対記法では飛びを書けないので空ラベルで昇格する
/// （convert の list only と同じ綴り。深さは保存される）。
fn itemed(skeleton : Skeleton) -> Skeleton {
  match skeleton {
    Implicit => Explicit(form=Item, label="", folded=false, body=[])
    Explicit(form=_, label~, folded~, body~) =>
      Explicit(form=Item, label~, folded~, body~)
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: `Total tests: 13, passed: 13, failed: 0.` EXIT=0（**G5 の累計 19 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/op.mbt core/tree/op_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 行き先が形を決める回復（順序法則・単調性・昇格）を置く"
```

---

## Task 88: move — 循環の拒否と、側を運ばない付け替え

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`

**Interfaces:**
- Consumes: `dest` / `crown` / `under` / `resolve` / `pluck` / `graft` / `clamp` /
  `conform` / `prune` / `pick` / `missing` / `cyclic`
- Produces: `pub fn move_nodes(doc : Doc, ids : Array[Int], parent : Int, at : Int, side : Side) -> Verdict`

> **契約 §10 の細目**: `parent` は id（文書は番兵 `doc_id` = 1）。`at` は
> slots / children / centers の index（**バケツの index ではない**）。`side` は**行き先の側**で、
> center 直下のスロットへ挿すときだけ効く。
>
> **抜くたびに測り直す**: 複数 id の move では、1 つ抜いた時点で行き先の index も
> ずれる。だから `dest` は**ループの中で毎回**呼ぶ。`resolve` も同じ理由で毎回呼ぶ。
>
> **循環の向き**: 拒否するのは「行き先が動かすものの下に居る」とき = `under(target, path)`。
> 逆向き（動かすものが行き先の下に居る）は**普通の付け替え**なので拒否しない。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/op_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 憲法 §5「構造系の拒否: 子孫への move（循環）」。自分自身への move も同じ。
test "move は子孫と自分自身への行き先を拒否する" {
  let deep = op_doc()
  assert_eq(
    op_said(move_nodes(deep, [3], 5, 0, Right)),
    "子孫へは動かせない (id=3)",
  )
  assert_eq(op_shape(deep), "doc(R2[>3(4(5))] R6[<7])")
  let self_ = op_doc()
  assert_eq(
    op_said(move_nodes(self_, [3], 3, 0, Right)),
    "子孫へは動かせない (id=3)",
  )
  let gone = op_doc()
  assert_eq(
    op_said(move_nodes(gone, [3], 99, 0, Right)),
    "見つからない (id=99)",
  )
  let none = op_doc()
  assert_eq(
    op_said(move_nodes(none, [99], 2, 0, Right)),
    "見つからない (id=99)",
  )
}

///|
/// 憲法 §2「側は場所の属性」— pluck で残置され、graft の引数が決め直す。
test "move で側は運ばれず、行き先の引数が決める" {
  let doc = op_doc()
  // 左のスロット 7 を、別 center の右の列へ
  assert_eq(op_said(move_nodes(doc, [7], 2, 1, Right)), "ok")
  assert_eq(op_shape(doc), "doc(R2[>3(4(5)) >7] R6[])")
  let back = op_doc()
  // 右のスロット 3 を、同じ center の同じ位置へ左指定で挿し直す
  assert_eq(op_said(move_nodes(back, [3], 2, 0, Left)), "ok")
  assert_eq(op_shape(back), "doc(R2[<3(4(5))] R6[<7])")
}

///|
/// 憲法 §5「move は文書順を保って連続挿入」。抜くたびに行き先を測り直す。
test "複数 id の move は文書順に連続で挿さる" {
  let doc = op_doc()
  assert_eq(op_said(move_nodes(doc, [7, 4], 2, 0, Right)), "ok")
  // 文書順は 4（[0,0,0]）が先、7（[1,0]）が後
  assert_eq(op_shape(doc), "doc(R2[>4(5) >7 >3] R6[])")
  assert_eq(check(doc).length(), 0)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier move_nodes is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/op.mbt` の `flip_side` の直前（ファイルの先頭側）に足す。

```moonbit
///|
/// ids を parent の at 番目へ。parent は id（文書は番兵 `doc_id`）。
/// side は行き先の側 — center 直下へ挿すときだけ効き、それ以外では捨てられる
/// （側は場所の属性。pluck では運ばれない）。
pub fn move_nodes(
  doc : Doc,
  ids : Array[Int],
  parent : Int,
  at : Int,
  side : Side,
) -> Verdict {
  guard dest(doc, parent) is Some(target) else {
    return Rejected(missing(parent))
  }
  let tops = crown(doc, ids)
  guard !tops.is_empty() else { return Rejected(missing(pick(ids))) }
  // 行き先が動かすものの下に居たら循環。逆向きは普通の付け替え
  for id in tops {
    guard resolve(doc, id) is Some(path) else { return Rejected(missing(id)) }
    if under(target, path) {
      return Rejected(cyclic(id))
    }
  }
  let mut slot = at
  for id in tops {
    guard resolve(doc, id) is Some(path) else { return Rejected(missing(id)) }
    guard pluck(doc, path) is Some(sub) else { return Rejected(missing(id)) }
    // 抜いた瞬間に index がずれるので、行き先はここで測り直す
    guard dest(doc, parent) is Some(here) else {
      return Rejected(missing(parent))
    }
    let seat = clamp(doc, here, slot)
    graft(doc, here, seat, sub, side)
    let placed = here.copy()
    placed.push(seat)
    conform(doc, placed)
    slot = seat + 1
  }
  prune(doc)
  Applied
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: `Total tests: 16, passed: 16, failed: 0.` EXIT=0（**G5 の累計 22 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/op.mbt core/tree/op_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 付け替え（循環の拒否・側の決め直し・連続挿入）を置く"
```

---

## Task 89: move の 9 組合せの掃引

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/op_wbtest.mbt`

**Interfaces:**
- Consumes: `move_nodes` / `op_doc` / `op_shape` / `op_said` / `check`
- Produces: なし（実装は増えない。**変換表が全部通ることの固定**）

掃引する 9 通り（出どころ 3 × 行き先 3）。`op_doc()` は `doc(R2[>3(4(5))] R6[<7])`。
**下の 9 行は実測 4 の値**。

| # | 出どころ | 行き先 | 変換 | 結果 |
|---|---|---|---|---|
| 1 | center 2 | doc | Tree 無変換 | `doc(R6[<7] R2[>3(4(5))])` |
| 2 | center 2 | center 6 | Tree 解体（側は引数） | `doc(R6[<2(3(4(5))) <7])` |
| 3 | center 2 | branch 7 | Tree 解体（側は捨てる） | `doc(R6[<7(2(3(4(5))))])` |
| 4 | slot 3 | doc | Part → Center 化 | `doc(R2[] R6[<7] R3[>4(5)])` |
| 5 | slot 3 | center 6 | Slot(side) で包む | `doc(R2[] R6[<7 <3(4(5))])` |
| 6 | slot 3 | branch 7 | そのまま | `doc(R2[] R6[<7(3(4(5)))])` |
| 7 | deep 4 | doc | Part → Center 化 | `doc(R4[>5] R2[>3] R6[<7])` |
| 8 | deep 4 | center 6 | Slot(side) で包む | `doc(R2[>3] R6[>4(5) <7])` |
| 9 | deep 4 | branch 7 | そのまま | `doc(R2[>3] R6[<7(4(5))])` |

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/op_wbtest.mbt` の末尾に足す。

```moonbit
///|
/// 出どころ = center。Whole は doc 位置間で無変換、それ以外では解体される。
test "move 9 組合せ: center から doc / center / branch へ" {
  let a = op_doc()
  assert_eq(op_said(move_nodes(a, [2], 1, 1, Right)), "ok")
  assert_eq(op_shape(a), "doc(R6[<7] R2[>3(4(5))])")
  let b = op_doc()
  assert_eq(op_said(move_nodes(b, [2], 6, 0, Left)), "ok")
  assert_eq(op_shape(b), "doc(R6[<2(3(4(5))) <7])")
  let c = op_doc()
  assert_eq(op_said(move_nodes(c, [2], 7, 0, Right)), "ok")
  assert_eq(op_shape(c), "doc(R6[<7(2(3(4(5))))])")
}

///|
/// 出どころ = center 直下のスロット。文書へ出ると Center 化し、children が右の枝になる。
test "move 9 組合せ: スロットから doc / center / branch へ" {
  let a = op_doc()
  assert_eq(op_said(move_nodes(a, [3], 1, 2, Right)), "ok")
  assert_eq(op_shape(a), "doc(R2[] R6[<7] R3[>4(5)])")
  let b = op_doc()
  assert_eq(op_said(move_nodes(b, [3], 6, 1, Left)), "ok")
  assert_eq(op_shape(b), "doc(R2[] R6[<7 <3(4(5))])")
  let c = op_doc()
  assert_eq(op_said(move_nodes(c, [3], 7, 0, Right)), "ok")
  assert_eq(op_shape(c), "doc(R2[] R6[<7(3(4(5)))])")
}

///|
/// 出どころ = 深いノード。どの行き先でも Part のまま旅する。
test "move 9 組合せ: 深いノードから doc / center / branch へ" {
  let a = op_doc()
  assert_eq(op_said(move_nodes(a, [4], 1, 0, Right)), "ok")
  assert_eq(op_shape(a), "doc(R4[>5] R2[>3] R6[<7])")
  let b = op_doc()
  assert_eq(op_said(move_nodes(b, [4], 6, 0, Right)), "ok")
  assert_eq(op_shape(b), "doc(R2[>3] R6[>4(5) <7])")
  let c = op_doc()
  assert_eq(op_said(move_nodes(c, [4], 7, 0, Right)), "ok")
  assert_eq(op_shape(c), "doc(R2[>3] R6[<7(4(5))])")
  assert_eq(check(c).length(), 0)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: **実装は既に居るので、実測どおりならここで緑になる**
（`Total tests: 19, passed: 19, failed: 0.` EXIT=0）。
落ちたら変換表のどこかが違う。落ちたときの逐語は契約 §18 の形（**EXIT=2**）:
```
[mmm-app/core/tree] test tree/op_wbtest.mbt:NN ("move 9 組合せ: ...") failed:
doc/op_wbtest.mbt:NN:NN-NN:NN@tree FAILED: `"..." != "..."`
```

- [ ] **Step 3: 最小の実装を書く**

**実装は増えない。** Task 82 の `as_center` / `as_branch` / `graft` が変換表そのもので、
このタスクはそれが 9 通り全部で正しいことの固定。Step 2 で落ちた場合だけ、
落ちた行の期待値と上の表を突き合わせて `as_center` / `as_branch` のどの腕が違うかを 1 つずつ直す。

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/op_wbtest.mbt
```
Expected: `Total tests: 19, passed: 19, failed: 0.` EXIT=0（**G5 の累計 25 本**。
`op_wbtest.mbt` はここで完成し、以降 1 本も増えない）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/op_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 付け替えの 9 組合せを固定する"
```

---

## Task 90: 境界を渡る編集 — Edit と apply

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff.mbt`
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff_wbtest.mbt`

**Interfaces:**
- Consumes: なし（純粋な文字列の算術）
- Produces: `pub(all) struct Edit { from : Int; to : Int; insert : String }` /
  `pub fn apply(text : String, edits : Array[Edit]) -> String`

> **契約 §10**: `apply` の edits は互いに重ならず、`from` の昇順であることを前提にする。
> オフセットは**旧文書上の UTF-16**。切り出しは `String::unsafe_substring` を使う
> （`s[a:b]` は端がサロゲート途中だと panic する — 契約 §18）。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/diff_wbtest.mbt` を新規作成する。

```moonbit
// 反映の実測。ヘルパ名は `diff_` で始める（wbtest は名前空間を共有する）。

///|
/// 憲法 §5「ts はバイトを選ばない」— 当てる算術は core が持ち、ts は運ぶだけ。
test "apply は旧文書上のオフセットで edits を当てる" {
  assert_eq(apply("# r\n", []), "# r\n")
  assert_eq(apply("# r\n", [{ from: 2, to: 3, insert: "x" }]), "# x\n")
  assert_eq(
    apply("abcdef", [
      { from: 1, to: 2, insert: "B" },
      { from: 4, to: 5, insert: "E" },
    ]),
    "aBcdEf",
  )
  assert_eq(apply("abc", [{ from: 0, to: 3, insert: "" }]), "")
  assert_eq(apply("", [{ from: 0, to: 0, insert: "x" }]), "x")
}

///|
/// サロゲート対を跨ぐ切り出しでも panic しないこと（絵文字は UTF-16 で 2 単位）。
test "apply はサロゲート対の外側で切れば壊れない" {
  let text = "a🙂b"
  assert_eq(text.length(), 4)
  assert_eq(apply(text, [{ from: 3, to: 4, insert: "c" }]), "a🙂c")
  assert_eq(apply(text, [{ from: 1, to: 3, insert: "" }]), "ab")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/diff_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier apply is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/diff.mbt` を新規作成する。

```moonbit
// 反映。統一サイクルの唯一の書き手で、書くのはここだけ。
// v0 = 全文正規形（フォールバック経路そのもの）。v1 のすげ替えはこの上に足す。

///|
/// 旧文書上の UTF-16 オフセット。境界を渡るのはこれだけ。
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
}

///|
/// edits を旧文書へ当てる。互いに重ならず from の昇順であることを前提にする。
pub fn apply(text : String, edits : Array[Edit]) -> String {
  let sb = StringBuilder::new()
  let mut at = 0
  for e in edits {
    sb.write_string(String::unsafe_substring(text, start=at, end=e.from))
    sb.write_string(e.insert)
    at = e.to
  }
  sb.write_string(String::unsafe_substring(text, start=at, end=text.length()))
  sb.to_string()
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/diff_wbtest.mbt
```
Expected: `Total tests: 2, passed: 2, failed: 0.` EXIT=0（**G5 の累計 27 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/diff.mbt core/tree/diff_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 境界を渡る編集の形と、当てる算術を置く"
```

---

## Task 91: diff — 共通の端を刈り、行境界まで広げる

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff_wbtest.mbt`

**Interfaces:**
- Consumes: `Edit` / `apply`
- Produces: `pub fn diff(before : String, after : String) -> Array[Edit]` /
  `fn line_start(s : String, at : Int) -> Int` / `fn line_end(s : String, at : Int) -> Int` /
  `fn code_at(s : String, k : Int) -> String`

> **なぜ行境界まで広げるのか**（3 つ同時に片が付く）
>
> 1. **カーソルが行の中で跳ねない** — CodeMirror の `mapPos` が行の単位で写す
> 2. **サロゲートが割れない** — 行境界は必ず文字境界（改行は ASCII）。
>    だから対を割るコード単位の刈り取りが**構造的に起きない**。
>    守るのは分岐ではなく**テスト**（`diff_holds` のサロゲートの行）。
>    「割れたら直す」分岐を書かないのは、それが死んだコードになるから
> 3. **`---` や畳みの綴りが半端に混ざらない** — ハンクが行の集まりになる
>
> `diff` は「間違えても壊れない部品」（憲法 §5）— 正しさは serialize が持ち、
> `reflect` が当ててから確かめる。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/diff_wbtest.mbt` の末尾に足す。**`from = 5` / `to = 10` は実測 6 の値**。

```moonbit
///|
/// 当てれば必ず後ろになる（diff の唯一の契約）。
fn diff_holds(before : String, after : String) -> Bool {
  apply(before, diff(before, after)) == after
}

///|
/// 同じなら 1 つも編集を出さない（無操作は無編集）。
test "diff は変化が無ければ空を返す" {
  assert_eq(diff("# r\n\n## a\n", "# r\n\n## a\n").length(), 0)
  assert_eq(diff("", "").length(), 0)
}

///|
/// 共通の端を刈ったうえで、ハンクを行の集まりに広げる。
test "diff は行境界まで広げた 1 ハンクを返す" {
  let edits = diff("# r\n\n## a\n\n## b\n", "# r\n\n## x\n\n## b\n")
  assert_eq(edits.length(), 1)
  assert_eq(edits[0].from, 5) // 3 行目の頭
  assert_eq(edits[0].to, 10) // 3 行目の終わり（改行を含む）
  assert_eq(edits[0].insert, "## x\n")
  assert_eq(diff_holds("# r\n\n## a\n\n## b\n", "# r\n\n## x\n\n## b\n"), true)
}

///|
/// 端の場合も、末尾に改行が無い文書も、サロゲートを含む文書も当たること。
test "diff はどの端でも当てれば後ろになる" {
  assert_eq(diff_holds("", "# r\n"), true)
  assert_eq(diff_holds("# r\n", ""), true)
  assert_eq(diff_holds("# r", "# r\n\n## a\n"), true)
  assert_eq(diff_holds("# 🙂\n", "# 🙂🙂\n"), true)
  assert_eq(diff_holds("a🙂b\n", "a🙂c\n"), true)
  assert_eq(diff_holds("# r\r\n\r\n## a\r\n", "# r\r\n\r\n## b\r\n"), true)
  assert_eq(diff_holds("abc", "abc"), true)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/diff_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier diff is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/diff.mbt` の `apply` の直前に `diff` を、`apply` の直後に読みの補助 3 本を足す。

```moonbit
///|
/// 共通接頭辞・接尾辞を刈り、行境界まで広げた 1 ハンク（v0）。
/// 間違えても壊れない部品 — 正しさは serialize が持ち、reflect が当ててから確かめる。
pub fn diff(before : String, after : String) -> Array[Edit] {
  if before == after {
    return []
  }
  let n = before.length()
  let m = after.length()
  let mut head = 0
  while head < n && head < m && before[head] == after[head] {
    head = head + 1
  }
  let mut tail = 0
  while tail < n - head &&
        tail < m - head &&
        before[n - 1 - tail] == after[m - 1 - tail] {
    tail = tail + 1
  }
  // 行境界まで広げる。カーソルが行の中で跳ねず、サロゲート対も割れない
  let from = line_start(before, head)
  let to = line_end(before, n - tail)
  [
    {
      from,
      to,
      insert: String::unsafe_substring(after, start=from, end=m - (n - to)),
    },
  ]
}
```

```moonbit
///|
/// 直前の改行の次（無ければ 0）。
fn line_start(s : String, at : Int) -> Int {
  let mut k = at
  while k > 0 && code_at(s, k - 1) != "\n" {
    k = k - 1
  }
  k
}

///|
/// 次の改行の直後（無ければ末尾）。すでに行境界ならそのまま。
fn line_end(s : String, at : Int) -> Int {
  if at == 0 || code_at(s, at - 1) == "\n" {
    return at
  }
  let mut k = at
  while k < s.length() && code_at(s, k - 1) != "\n" {
    k = k + 1
  }
  k
}

///|
/// 1 コード単位を切り出して見る（`s[k]` は Char ではなく UInt16 なので直接は比べない）。
fn code_at(s : String, k : Int) -> String {
  String::unsafe_substring(s, start=k, end=k + 1)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/diff_wbtest.mbt
```
Expected: `Total tests: 5, passed: 5, failed: 0.` EXIT=0（**G5 の累計 30 本**）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/diff.mbt core/tree/diff_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 行境界まで広げる差分を置く"
```

---

## Task 92: 反映 v0 — Reflection と自己検査

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff_wbtest.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/diff_wbtest.mbt`

**Interfaces:**
- Consumes: `parse`（G2 の `parse.mbt`）/ `serialize`（G3 の `serialize.mbt`）/
  `Doc` / `Verdict`（G1）/ `Edit` / `diff` / `apply`
- Produces: `pub(all) struct Reflection { ok : Bool; reason : String; text : String; edits : Array[Edit] }` /
  `pub fn reflect(md : String, op : (Doc) -> Verdict) -> Reflection` /
  `fn safe_edits(before : String, after : String) -> Array[Edit]`

> **前提**: **G2 の `parse` と G3 の `serialize` が置かれていること。**
> どちらも他群の所有ファイルなので、**G5 はスタブを含め 1 バイトも書かない**（契約 §2）。
> まだ無ければ Task 91 で止め、揃ってから Task 92 に入る（`Total tests` は 30 本で据え置き）。
>
> **`reflect` は `Reflection` を返す純関数**（裁定 3）。境界の JSON にするのは
> **G4 の `json.mbt` の `reflect_json`** で、G5 はそこへ 1 行も書かない。
> したがって G5 は `quote` にも G4 にも依存しない。
>
> `ok = false` のとき `text` は**元の md そのまま**・`edits` は空・`reason` に拒否の理由
> （契約 §13 の反映の JSON がこの 4 フィールドをそのまま並べる）。
>
> **「無操作は無編集」の正確な意味**: v0 の反映は全文正規形なので、`md` が既に正規形の
> ときだけ「変えなければ編集ゼロ」になる。手書きの md に操作をかければ全文が正規化される
> （憲法 §5 の v0 = フォールバック経路そのもの）。触った所だけになるのは v1 のすげ替えから。
> **拒否のときは、md が正規形でなくても必ず編集ゼロ**（契約 §12「反映 v0 の帰結」）。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/diff_wbtest.mbt` の末尾に足す。JSON の逐語は G4 の `json_wbtest.mbt` が固定するので、
ここは**フィールドで比べる**。

```moonbit
///|
/// 自己検査の相方。どんな 2 本の文字列でも、当てれば必ず後ろになる。
test "safe_edits は当てれば必ず後ろになる" {
  assert_eq(apply("# r\n", safe_edits("# r\n", "# r\n")), "# r\n")
  assert_eq(
    apply("# r\n", safe_edits("# r\n", "# x\n\n## a\n")),
    "# x\n\n## a\n",
  )
  assert_eq(apply("", safe_edits("", "# r\n")), "# r\n")
  assert_eq(
    apply("# 🙂\n", safe_edits("# 🙂\n", "# 🙂🙂\n")),
    "# 🙂🙂\n",
  )
}

///|
/// 拒否は無編集。md が正規形でなくても、1 バイトも書き替えない。
test "拒否のとき reflect は元の md をそのまま返す" {
  let r = reflect("#  r  \n\n## a\n", fn(_) {
    Rejected("見つからない (id=7)")
  })
  assert_eq(r.ok, false)
  assert_eq(r.reason, "見つからない (id=7)")
  assert_eq(r.text, "#  r  \n\n## a\n")
  assert_eq(r.edits.length(), 0)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/diff_wbtest.mbt
```
Expected: **EXIT=1**。
```
Error: [4021]
The value identifier safe_edits is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/diff.mbt` の `Edit` の直後に `Reflection` と `reflect` を足す。

```moonbit
///|
/// 操作 1 回ぶんの往復の結果。JSON にするのは G4 の reflect_json。
pub(all) struct Reflection {
  ok : Bool
  reason : String
  text : String
  edits : Array[Edit]
}

///|
/// 操作 1 回ぶんの往復 — 読み、動かし、正規形へ書き戻し、差分を測る。
/// 操作が closure なのは、腕を生やさずに op を差し替えられるようにするため。
/// **統一サイクルで書くのはここ 1 本だけ**（憲法 §5）。
pub fn reflect(md : String, op : (Doc) -> Verdict) -> Reflection {
  let doc = parse(md)
  match op(doc) {
    Rejected(reason) => { ok: false, reason, text: md, edits: [] }
    Applied => {
      let text = serialize(doc)
      { ok: true, reason: "", text, edits: safe_edits(md, text) }
    }
  }
}
```

同じファイルの `code_at` の直後（末尾）に足す。

```moonbit
///|
/// 自己検査つきの差分。当てて一致しなければ全文置換 1 ハンクへ落とす
/// （正しさは serialize が持ち、カーソルだけ跳ぶ — 憲法 §5 の段階フォールバック）。
fn safe_edits(before : String, after : String) -> Array[Edit] {
  let edits = diff(before, after)
  if apply(before, edits) == after {
    edits
  } else {
    [{ from: 0, to: before.length(), insert: after }]
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/diff_wbtest.mbt
```
Expected: `Total tests: 7, passed: 7, failed: 0.` EXIT=0（**G5 の累計 32 本**）。

続けて型検査:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree
```
Expected: **`0 errors`** EXIT=0。実測（g5v）ではこの時点で**警告も 0**
（道具・回復・操作が互いを使い切るため）。他群のファイルが警告を出していても
**CI の合格条件は `0 errors`** なので、警告を消すために可視性を下げたり
読み捨てのコードを足したりしない（契約 §11）。

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/diff.mbt core/tree/diff_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 反映 v0（全文正規形と自己検査）を置く"
```

---

## Task 94: 殺す条件の判定と、docs/ops.md

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/docs/ops.md`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/roundtrip.test.ts`（既存。新しい md が
  旧 core の往復テストの入力になるので、これが緑であることが受け入れ条件）

**Interfaces:**
- Consumes: Task 80〜92 で確定した腕数（契約 §11）と、拒否・回復の一覧
- Produces: `docs/ops.md`（契約 §2 の G5 の所有ファイル）

> **`docs/` に置く md の制約**（契約 §17 の罠）: `test/_helpers.ts` の `corpus()` が
> リポジトリ内の .md を深さ 3 まで全部集め、**旧 core の往復テスト（P1: バイト同一）の
> 入力にする**。だから `docs/ops.md` は旧 core が読んで書き戻してもバイトが変わらない
> 綴りで書く: ATX の見出しだけ・level は飛ばさない・`-` のリスト・
> **`---` と `***` と setext を使わない**・継ぎ目の空行は 1 本・末尾に改行 1 つ。
> 表（`|`）は本文（Opaque）として逐語で残るが、念のため使わずリストで書く。
> **畳みのタグは行頭に置かず、必ず文中のインラインコードで書く**（行頭に置くと旧 core が
> 畳みの綴りとして読む恐れがある）。

### 腕数の定義と判定基準

**定義も数字も契約 §11 が正**（裁定 5）。ここで別の物差しを立てない。契約 §11 の逐語:

> **容器の腕** = その関数の `match path` の枝のうち、**3 つの容器（`doc.centers` /
> `Center::slots` / `Branch::children`）のどれかを読むか書くもの**の数。何もしない・
> 拒否するだけの番兵枝（`[]`）は数えない。
>
> **意味の腕** = 仕様が定めた場合分けの数（flipSide の資格 3 段など）。容器の異種性とは
> 無関係なので、殺す条件の物差しには入れない。

判定基準（契約 §11 からそのまま写す）:

- **合格** — 道具の容器の腕がすべて **3 以下** / 操作 3 本の容器の腕が **0** /
  回復 2 本の容器の腕が **0** / `Sub` を変換する場所が **1 か所** / 2 段包みが **1 本以下**
- **警告** — どれかの道具が **4 腕**になった（`Slot` に `mut branch` を足して 3 へ戻せるか
  検討する）/ 道具が **6 本目**になった（増えたのが読む道具か書く道具かを見る）
- **死** — どれかの道具が **5 腕**になった / 操作 3 本のどれかが `match path` を自前で
  持ち始めた / `Sub` を変換する場所が **2 か所以上**になった

逐語コメント 2 か所（`tool.mbt` の冒頭と `amend` の直前）は Task 80 と Task 83 で
契約 §11 の逐語をそのまま置いてある。**ここで書き替えない。**

### この群の完成時点の実測

- 道具は **5 本**（`resolve` / `kin_at` / `pluck` / `graft` / `amend`）。
  増えた 1 本（`kin_at`）は**読む道具**で、変換の住所は `graft` のまま 1 か所
- 容器の腕: `resolve` 0 / `find_in` 0 / `branch_at` 1 / `kin_at` 3 / `parent_at` 0 /
  `pluck` 3 / `graft` 3 / `amend` 3 / `set_side` 1
- 操作 3 本の容器の腕: **0**（`move_nodes` 0 / `flip_side` 0 / `delete_nodes` 0）
- 回復 2 本の容器の腕: **0**（`conform` は `kin_at` + `parent_at` + `amend` の合成、
  `sink` は `kin_at` + `amend` の合成、`prune` は木の走査で path を使わない）
- 2 段包み: **1 本**（`amend` の `[i, j]`）
- **判定: 合格**

- [ ] **Step 1: 往復テストの基準線を取る**

Run:
```
branch --test D:/1.atrium/mmm/.worktrees/feat/tree-core/test/roundtrip.test.ts
```
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`。別のワークツリーから叩くと旧 core を測る。
事前に `pnpm run core` が要る）
Expected: `ℹ fail 0`（この時点では `docs/ops.md` がまだ無いので通る）。
この結果が**基準線**で、Step 3 の後も同じでなければならない。

- [ ] **Step 2: いちばん危ない綴りだけ先に置いて、往復が壊れないことを確かめる**

`docs/ops.md` を、見出し 1 つと**畳みのタグを含む段落**だけの形で作る
（インラインコードのタグが旧 core の往復を壊さないことを、本文を書く前に確かめる）。

```md
# 操作

木の道（構造を変える者は文字列に触れない）の一覧。

## 注意: 手で書いた畳みの見出しは残らない

畳んだノードの `<details>` の直後に書かれた `<summary>` は読みで捨てられ、
書き出すときラベルから作り直される。
```

Run:
```
branch --test D:/1.atrium/mmm/.worktrees/feat/tree-core/test/roundtrip.test.ts
```
Expected: `ℹ fail 0`。ここで落ちたら、その綴りが旧 core の正規形と食い違っている
（`P1: parse→serialize がバイト同一` が落ちる）。疑う順は
「インラインコードのタグ」→「継ぎ目の空行が 2 本以上」→「末尾改行」。
**直すのは md のほうで、旧 core には手を入れない。**

- [ ] **Step 3: 本文を書く**

`docs/ops.md` を次の全文で置き換える。

```md
# 操作

木の道の一覧。構造を変える者は文字列に触れず、文字列に触れる者は必ず解釈を受ける。
設計の出どころは docs/superpowers/specs/2026-08-29-doc-model-design.md の 5 節。

## 3 つの操作

- move — ids を parent の at 番目へ。parent は id で、文書は番兵 1
- flipSide — center は鏡像、center 直下の枝はそのスロットだけ反転
- delete — サブツリーごと消す

3 本とも、複数選択は頂点集合に正規化してから適用する。子孫の選択は祖先に吸収され、
残ったものは文書順に並べ直されてから連続で挿さる。
flipSide も同じ規則に従うので、center とその直下の枝を同時に選んでも二重には反転しない。

at は枝の列そのものの番号で、右と左に分けた後の番号ではない。
右と左に分ける仕事は絵を描く側にあり、番号の翻訳もそちらの持ち物になる。

## 拒否は 3 つだけ

- 見つからない — その id のノードが文書に居ない
- 子孫へは動かせない — 行き先が、動かすものの中に居る（循環）
- 側を変えられるのは center と center 直下の枝だけ — 深いノードと文書への flipSide

拒否のとき、文書は 1 バイトも書き替わらない。編集は空で返る。

flipSide の複数選択では、資格の無い id は黙って飛ばす。1 つも効かなかったときだけ拒否になる。

## 回復（操作が直すもの）

型で殺せなかった関係的な不変条件は、操作が壊したその場で直す。直す場所は 2 つだけ。

抜いた側で壊れうるのは 1 つ。

- 子を失った Implicit が居残る — 消えてもらう。これは削除という出来事ではなく、
  飛びから導出されなくなるだけ。連鎖していれば連鎖ごと消える

挿した側で壊れうるのは 3 つ。どれも動かしたサブツリーの中で直り、周りには波及しない。

- 順序法則 — 見出しの兄弟の後ろに置かれた項目は、その頂点だけ見出しになる。
  子は項目のままで合法（単調性は見出しの下の項目を許す）
- 単調性 — 項目の親の下に置かれた見出しは、サブツリーごと項目になる
- 綴りが書けない位置 — 飛びで表現できない場所へ来た Implicit は骨格行を得て昇格する。
  項目として書かれるときは空ラベルの項目になり、深さは保たれる

回復は拒否ではない。どの綴りでも表現できない木を作らないための安全弁で、
form も綴りも行き先に従う。

## 反映

操作の結果は全文の正規形として書き出され、旧文書との差分だけが境界を渡る。
差分は行境界まで広げた 1 ハンクで、当ててから一致を確かめている。
合わなければ全文置換に落ちる。正しさは保たれ、カーソルだけが跳ぶ。

v0 では触っていない範囲も正規形になる。触った所だけを残すすげ替えは v1 で足す。

## 注意: rename はリンクを壊す

GitHub は見出しからアンカーを生成する。だから見出しのラベルを打ち替えると、
その見出しを指す外部のリンクが切れる。これは md の宿命で、mmm が直せるものではない。
外から参照されている見出しの打ち替えは、参照側も一緒に直すこと。

## 注意: 手で書いた畳みの見出しは残らない

畳んだノードの `<details>` の直後に書かれた `<summary>` は読みで捨てられ、
書き出すときラベルから作り直される。別の文言を書いても、そのノードを触った瞬間に
ラベル版へ置き換わる。ラベルと違う見出しを畳みに付けたい、という要求は
この設計では表現できない。

## 殺す条件の物差し

この設計が生きているかどうかは、道具の腕の数で測る。

腕とは、その関数が 3 つの容器のどれを触るかで分かれた枝のこと。容器は 3 つしかない。
文書が持つ center の列、center が持つスロットの列、ノードが持つ子の列。
何もしないだけの枝は数えない。仕様が定めた場合分け（flipSide の資格 3 段など）も数えない。

合格の線は 4 つ。

- 道具の腕がすべて 3 以下
- 操作 3 本の腕が 0
- 回復 2 本の腕が 0
- 運搬の通貨を変換する場所が 1 か所

警告の線は 2 つ。

- 道具のどれかが 4 腕になった。スロットの包みに可変の口を 1 つ開ければ 3 に戻る
- 道具が 6 本目になった。増えたのが書く道具なら、変換の住所が割れていないか疑う

死の線は 3 つ。

- 道具のどれかが 5 腕になった
- 操作が自分で場所の場合分けを始めた
- 変換する場所が 2 か所以上になった

2026-08-31 の実測では、道具は 5 本（居場所を測る・兄弟の列を読む・抜く・挿す・書き替える）で、
腕は最大 3、操作と回復の腕は 0、変換の住所は 1 か所。判定は合格。
増えた 1 本は読む道具で、書く道具は増えていない。
```

- [ ] **Step 4: 往復と群の締めが緑であることを確認**

Run:
```
branch --test D:/1.atrium/mmm/.worktrees/feat/tree-core/test/roundtrip.test.ts
```
Expected: `ℹ fail 0`（Step 1 の基準線と同じ）。
落ちたら `docs/ops.md` の綴りが旧 core の正規形と食い違っている。
疑う順は「継ぎ目の空行が 2 本以上」→「末尾改行」→「リストの入れ子の字下げ」。
直すのは md のほうで、**旧 core には手を入れない**。

続けて群の締め（ここだけ `-p`。契約 §17）:
```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree
```
Expected:
- `Total tests: 293, passed: 293, failed: 0.`
  （内訳 — 旧 core `mmm-app/core` が **192**（`out/repo.md` の実測）+ 新パッケージ
  `mmm-app/core/tree` が **101**（G1 25 + G2 23 + G3 21 + G5 32。契約 §16）。
  **`Total tests: 0` なら `-p` の綴り間違い**。契約 §17 の罠）
- `moon fmt --check tree` は EXIT=0（失敗は EXIT=127）。
  **`tree/js` は対象に入れない** — 裁定 3 の依存順で G5 は G4 より前に走り、
  `core/tree/js/` はまだ存在しない。`doc tree/js` は G4 Task 71 の持ち物

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add docs/ops.md
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "docs: 📝 操作の回復・拒否と、殺す条件の判定を書き残す"
```

---

## この群の終わりの形

- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree` が `0 errors`
- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree`
  が `failed: 0`。**G5 が足したのは 32 本**（tool 6 / op 19 / diff 7。契約 §16 と一致）
- `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree` が EXIT=0
- `docs/ops.md` が旧 core の往復テスト（P1: バイト同一）を通っている
- **殺す条件の判定は合格** — 道具 5 本・腕は最大 3・操作と回復の腕は 0・変換の住所は 1 か所
- **他群のファイルに 1 バイトも書いていない。** `parse.mbt` / `serialize.mbt` / `json.mbt` /
  `test/` は触っていない

### 次に走る群への引き継ぎ（G4 が受け取るもの）

- `pub fn reflect(md, op) -> Reflection` と `pub(all) struct Reflection`。
  **JSON にするのは G4 の `reflect_json`**（契約 §13 の逐語）
- `pub fn move_nodes` / `pub fn flip_side` / `pub fn delete_nodes` の 3 本と、
  拒否の文言 3 つ（契約 §10 の逐語）
- `test/treeOps.test.ts`（操作の性質のファズ）の設計 — 見る性質は 5 つ:
  拒否は無編集 / 適用後も健全 / 当てれば一致 / 反映の先は不動 / 側の反転は対合。
  **書くのは G4 Task 72**（契約 §19 の G4 の表に、delete をノード数で見ることと、
  左の枝が居る文書を飛ばすことの 2 つの直しが入っている）

### スコープ外（この群では作らない。契約 §21）

すげ替え v1 / add / rename / fold / setForm / indent / outdent / content 系 /
convert / format コマンド / UI 接続 / `src/` の書き換え / `reflect_json`（G4）/
`test/treeOps.test.ts`（G4 Task 72）。
`amend` はスコープ外の fold・setForm のための住所でもあるが、G5 では `conform` が呼ぶので
未使用にはならない。

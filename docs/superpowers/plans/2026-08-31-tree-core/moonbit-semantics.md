実測完了（`moon test` 28/28 pass、`moon check` 0 errors）。doc-model リポジトリは無変更（`git status --porcelain` 出力なし、`core/_build` も未生成）。

---

# MoonBit 意味論の実測結果

環境: `moon 0.1.20260803 (c19f78e 2026-08-03)`、`preferred_target = "js"`
使い捨てモジュール: `C:\Users\taker\AppData\Local\Temp\claude\D--1-atrium-mmm--claude-worktrees-dnd-ux-improvement-1ebfc6\954c84b6-8b11-46ca-bd0f-361864110df4\scratchpad\v2\probe-a\`
（`moon.mod` + `lib/`（library）+ `user/`（library、`import { "probe-a/lib", }`））

---

## 10. 型定義の全文 — **そのまま通る。1 バイトも直す必要がない**

`lib/types.mbt` に憲法 §2 の型定義を逐語で写して `moon check`:

```
Finished. moon: ran 2 tasks, now up to date (19 warnings, 0 errors)
```

19 warning は全部 `struct_never_constructed` / `unused_constructor`（構築子を一度でも使えば消える。実際 `lib/useall.mbt` で全構築子を触ったら 0 warning になった）。相互再帰（Center → Array[Branch] → Branch → Node → Array[Node]、Skeleton → Array[Block] → Content）は前方参照も含めて**宣言順に関係なく通る**。

---

## 1. struct は**参照**。取り出した先の変更は元に届く

```moonbit
let doc = sample()          // centers[0].branches に 1 要素
let r = doc.centers[0]
r.branches.push({ side: Left, node: leaf(30) })
```
```
P1a doc.centers[0].branches.length = 2
P1a r.branches.length = 2
P1b physical_equal(a, b) = true                      // let a = doc.centers[0]; let b = doc.centers[0]
P1b physical_equal(a.branches, b.branches) = true
P1c after grow = 2                                   // fn grow(r : Center) に渡しても同じ
```

**struct 値そのものが同一実体**（`physical_equal` が `true`）。コピーは起きない。Array フィールドは当然共有。関数引数として渡しても同じ。

---

## 3. 関数の戻り値を経由した変更も**元の木に届く**

```moonbit
fn at(doc : Doc, path : Array[Int]) -> Node {
  let mut node = doc.centers[path[0]].branches[path[1]].node
  for k in 2..<path.length() { node = node.children[k] }
  node
}
let n = at(doc, [0, 0])
n.children.push(leaf(40))
```
```
P3 via return value = 1        // doc.centers[0].branches[0].node.children.length()
```

4 段の深さでも同じ（`5x`）:
```
5x removed id = 40             // doc.centers[0].branches[0].node.children[0].children.remove(0)
5x owner len  = 0
5x 元の doc に届いた = 0
5x branches len = 2            // doc.centers[0].branches.insert(0, { side: Left, node: taken })
5x branches[0].node.id = 40
```

→ **pluck / graft の「配列を掴んで remove / insert」は、深さに関係なく元の doc に直接効く。木の再構築は一切不要。**

---

## 2. 入れ子の代入 — **`doc.centers[i].branches[j] = { ..b, side: Left }` は書ける**

```moonbit
let b = doc.centers[0].branches[0]
doc.centers[0].branches[0] = { ..b, side: Left }
```
```
P2a side = Left
P2a node id kept = 20
```

対して**フィールドへの直接代入は不可**（`lib/neg1.mbt`、その後削除）:
```moonbit
doc.centers[0].branches[0].side = Left
```
```
Error: [4087]
 3 │   doc.centers[0].branches[0].side = Left
   │   ──────────────────┬─────────────────
   │                     ╰─────────────────── The record field side is immutable.
Failed with 0 warnings, 1 errors.
```

→ **不変フィールドを差し替える正しい書き方は「所有している配列 + index を掴んで、その要素に struct-update を代入する」の一択**（`mut` は不要、再構築も不要）。3 種の配列すべてで動くことを実測（`5c`）:
```
5c deep  = n40/true      // amend_slot(doc, [0,0,0,0], set_folded)
5c 中間は無傷 = n30/false
5c slot  = n20/true      // amend_slot(doc, [0,0], ...)
5c center  = (implicit)    // amend_slot(doc, [0], ...) — center は Implicit なので変化なし
```

---

## 4. `mut` フィールド — できること / できないこと

対照型 `MBranch { mut side; mut node }` / `MRoot { mut skeleton; branches }` / `MNode { mut skeleton; children }` を作って比較。

| | 不変 `{ side : Side }` | `{ mut side : Side }` |
|---|---|---|
| 同一パッケージ・フィールド代入 | **不可** `[4087] The record field side is immutable.` | 可 |
| 同一パッケージ・要素代入 `arr[j] = { ..b, side: Left }` | 可 | 可 |
| 別パッケージ（`pub`）・読み / match | 可 | 可 |
| 別パッケージ（`pub`）・フィールド代入 | — | **不可** `Cannot modify a read-only field: side` |
| 別パッケージ（`pub(all)`）・フィールド代入 | — | 可（0 errors） |
| 別パッケージ（`pub`）・構築 / struct-update | **不可**（下記） | 同左 |
| 別パッケージ（`pub(all)`）・構築 / struct-update / 要素代入 | 可（0 errors） | 可 |

`pub` のまま別パッケージから組み立てようとした逐語（`user/neg.mbt`）:
```
Error: [4036]
 8 │   { ..b, side: Left }
   │   ─────────┬─────────
   │            ╰─────────── Cannot create values of the read-only type: @probe-a/lib.Branch.
Error: [4021]
 8 │   { ..b, side: Left }
   │                ──┬─
   │                  ╰─── The value identifier Left is unbound.
Error: [4036]
14 │   doc.centers[0].branches[0] = { ..b, side: Left }
   │                              ─────────┬─────────
   │                                       ╰─────────── Cannot create values of the read-only type: @probe-a/lib.Branch.
Failed with 6 warnings, 9 errors.
```
```
Error: [4094]（`pub struct MBranch` の mut フィールドへの別パッケージからの書き込み）
 3 │   b.side = @lib.Left
   │   ─────────┬────────
   │            ╰────────── Cannot modify a read-only field: side
```

`pub(all)` に変えた後（`user/neg.mbt` + `user/mutwrite.mbt` とも）:
```
Finished. moon: ran 6 tasks, now up to date (2 warnings, 0 errors)
```

**別パッケージからは列挙子を `@lib.Left` / `@lib.Implicit` と修飾しなければならない**（式の位置。フィールドの型が確定していても `[4021] The value identifier Left is unbound.`）。**match のパターン位置では無修飾で通る**（`Right => …` / `Explicit(label~, ..) => …` が動作）。

一方、**Array フィールドの破壊的操作は `pub` のままで別パッケージからできる**（`user/read_wbtest.mbt`）:
```
X2 branches after remove = 1     // doc.centers[0].branches.remove(0)
```
→ `pub` は「読み取り専用」を意味しない。**配列の中身は素通し**。

---

## 5. 木の奥を書き替える 3 パターン — 実測比較

### (a) 純粋な再構築（`amend_pure` + `amend_node_pure`）
```moonbit
[i, j, .. rest] => {
  let centers = doc.centers.copy()
  let r = centers[i]
  let branches = r.branches.copy()
  let b = branches[j]
  branches[j] = { ..b, node: amend_node_pure(b.node, rest, f) }
  centers[i] = { ..r, branches, }
  { ..doc, centers, }
}
```
```
5a before(元の doc) = n40/false     ← 元は無傷
5a after (戻り値)   = n40/true
5a 兄弟の共有 physical_equal(...) = false
```
書き味: 関数が 2 本に割れる（`Array[Int]` の match と `ArrayView[Int]` の match）。`.copy()` の書き忘れが**そのまま静かな共有バグ**になる。落とし穴: 元の doc と戻り値が別物なので、id 表・履歴・JS 側の参照が全部差し替わる。

### (b) `mut`（`amend_mut` / `amend_m`）
```moonbit
match path {
  [] => ()
  [i] => doc.centers[i].skeleton = f(doc.centers[i].skeleton)
  _ => { let n = mnode_at(doc, path[:]); n.skeleton = f(n.skeleton) }
}
```
```
5b deep  = n40/true
5b 中間  = n30/false
```
書き味: **最短（腕 3 本、深部は 2 行）**。落とし穴 3 つ:
- `Center` と `Node` の両方に `mut skeleton` が要る＝**型が「書き替えられる」と宣言してしまう**
- 定義パッケージ内で一度も書かないと `Error: [0015] unused_mut` でビルドが止まる（`moonbit-probe.md §3(f)` の再確認）
- 別パッケージから書くには `pub(all)` が必須

### (c) 配列要素への代入（採用候補、`lib/ops.mbt` の `amend`）
```moonbit
[.. head, last] => {
  let owner = node_at(doc, head)
  let n = owner.children[last]
  owner.children[last] = { ..n, skeleton: f(n.skeleton) }
}
```
```
O6 center  = r1!/true
O6 slot  = n2!/true
O6 深部  = n4!/true
O6 中間は無傷 = n3/false
```
書き味: `mut` ゼロ、戻り値なし（`Unit`）、元の doc がその場で更新される。落とし穴は 1 つだけ — **`[i, j]`（スロット）の腕だけは Branch と Node の 2 段を包み直す**:
```moonbit
[i, j] => {
  let b = doc.centers[i].branches[j]
  doc.centers[i].branches[j] = { ..b, node: { ..b.node, skeleton: f(b.node.skeleton) } }
}
```

**腕数の実測差**: (c) は `amend` が **4 腕**（`[]` / `[i]` / `[i, j]` / `[.. head, last]`）、(b) は **3 腕**（`[]` / `[i]` / `_`）。差は上の 1 腕ぶん。

---

## 6. 配列パターン — **書ける。`[.. head, last]` も `[i, j, .. rest]` も通る**

```moonbit
match path { [] => "doc"; [_] => "center"; [_, _] => "slot"; _ => "deep" }
match path { []; [i]; [i, j]; [i, j, .. rest] }
```
```
6 kind_of([]) = doc
6 kind_of([0]) = center
6 kind_of([0,1]) = slot
6 kind_of([0,1,2]) = deep
6b split_path([0,1,2,3]) = deep:0,1+2
6b split_path([5]) = center:5
```

**`.. rest` で束縛される `rest` の型は `ArrayView[Int]`**（`Array[Int]` ではない）。`Array[Int]` を取る関数に渡すときは `path[:]` でビューに落とす。`ArrayView` に対しても同じ配列パターンが使える（`amend_node_pure` / `mnode_at` で実測）。`rest[0:rest.length() - 1]` のビューの再スライスも通る。

**末尾束縛 `[.. head, last]` が通ることが今回の最大の収穫** — pluck の深部の腕がこれ 1 行になる:
```moonbit
[.. head, last] => Some(Limb(node_at(doc, head).children.remove(last)))
```

---

## 7. `guard ... is ... else` — **書ける。綴りはそのまま**

```moonbit
guard find_id(doc, id) is Some(p) else { return "notfound" }
guard pluck(doc, [0, 0]) is Some(sub) else { fail("no sub") }   // テスト本文
```
```
7 hit  = path:1
7 miss = notfound
```

`else` を省くと**コンパイルは通るが warning**:
```
Warning: [0087]
 48 │   guard path is [i, j, .. rest]
    │         ───────────┬───────────
    │                    ╰───────────── Warning (guard_inexhaustive): This `guard` pattern is not exhaustive and will panic when it does not match. Missing cases:
[]
To fix: add an `else { ... }` clause after the condition to handle those cases, or write `guard!` if the panic is intended.
```
→ **意図的な panic は `guard!`**（`guard! path is [i, j, .. rest]` で warning が消えることを実測）。

`if` の条件としても書ける: `if resolve_in(c, id) is Some(tail) { ... }`（`lib/ops.mbt` の `resolve`）。

---

## 8. `Array` API — **全部実在。`.mbti` からの正確なシグネチャ**

```
pub fn[T] Array::filter(Self[T], (T) -> Bool raise?) -> Self[T] raise?
pub fn[T, U] Array::map(Self[T], (T) -> U raise?) -> Self[U] raise?
pub fn[T] Array::insert(Self[T], Int, T) -> Unit
pub fn[T] Array::remove(Self[T], Int) -> T          ← 抜いた要素を返す（pluck に直結）
pub fn[T] Array::swap(Self[T], Int, Int) -> Unit
pub fn[T] Array::copy(Self[T]) -> Self[T]
pub fn[T] Array::each(Self[T], (T) -> Unit raise?) -> Unit raise?
pub fn[T] Array::eachi(Self[T], (Int, T) -> Unit raise?) -> Unit raise?
pub fn[T] Array::retain(Self[T], (T) -> Bool raise?) -> Unit          ← 破壊的 filter
pub fn[T] Array::extract_if(Self[T], (T) -> Bool raise?) -> Self[T]   ← 抜きながら集める
pub fn[T : Eq] Array::search(Self[T], T) -> Int?
```
実行:
```
8 filter = 3      8 map = 2
8 insert = 4 b[1]=9
8 remove returns = 1 len=3
8 swap = 3,1      8 is_empty = true      8 searchi = Some(1)
```

**`insert` の範囲外は `abort` で panic し、`try?` では捕まらない**（len=3 に `insert(5, 9)`）:
```
[probe-a] test lib/edge_wbtest.mbt:9 ("E2: insert 範囲外") failed: Error
    at @moonbitlang/core/abort.abort (C:\Users\taker\.moon\lib\core\abort\abort.mbt:29:3)
    at Array::insert (C:\Users\taker\.moon\lib\core\builtin\arraycore_js.mbt:448:5)
```
末尾ちょうど（`insert(len, v)`）は通る: `E1 insert(len) = 4 last=9`。
→ **graft は `at` を自分で clamp する責任がある。**

deprecated: `Option::or` → `unwrap_or`、`Option::to_string()` は `Warning (deprecated): Option does not have a meaningful string representation`。

---

## 9. 関数を引数に取る — **`f : (Skeleton) -> Skeleton` の綴りがそのまま通る**

```moonbit
fn amend_sk(sk : Skeleton, f : (Skeleton) -> Skeleton) -> Skeleton { f(sk) }
amend_sk(sk, fold_on)                 // トップレベル関数を名前で渡す
amend_sk(sk, fn(s) { s })             // 匿名関数
let fold = fn(s : Skeleton) -> Skeleton { ... }   // let 束縛（型注釈は要る）
```
```
9 out = H/hello/true/1
9 identity closure ok = true
```
`Array::map` / `filter` へのクロージャ、再帰関数を名前で渡す形（`n.children.map(clone_node)`）も動く。

---

## 11. 3 つの型を歩く再帰関数（trait 無し）— **素直に書ける**

`Doc → Center → Branch → Node → Node` を型ごとに関数を分ける形（`sig_center` / `sig_node`）で通る。

```
O1 shape = doc(R1[>2(3(4))] R5[<6])
O1 resolve(1) = [0]
O1 resolve(2) = [0,0]
O1 resolve(3) = [0,0,0]
O1 resolve(4) = [0,0,0,0]
O1 resolve(5) = [1]
O1 resolve(6) = [1,0]
O1 resolve(99) = -
```

`for i, r in doc.centers` のインデックス付き for-in と、その中からの `return Some(p)` の早期脱出が両方使える。`StringBuilder::new()` / `.write_string()` / `.to_string()` も動作。

---

## 12. `Explicit` の構築と分解 — **`moonbit-probe.md §4` を再確認、punning も通る**

```moonbit
// 構築（呼び出し側は `=`）
Explicit(form=Heading, label="hello", folded=false, body=[Rule])
// 分解（`~`）
Explicit(form~, label~, folded~, body~) => ...
Explicit(label~, folded~, ..) => ...            // 一部だけ取って残りは `..`
// punning（同名の局所変数から組み直す）
Explicit(form~, label~, folded=true, body~)
```
```
9 out = H/hello/true/1
O6 center = r1!/true
```
struct 側の punning も通る: `{ side, node: as_node(sub) }` / `{ ..doc, centers, }` / `{ ..b, side, }`（**末尾のカンマが要る** — `{ ..doc, centers }` は書けるが `moon fmt` が `{ ..doc, centers, }` に寄せる）。

---

## 13. `String?` と空判定

```moonbit
pub struct Doc { frontmatter : String?  ... }     // ← そのまま通る
match doc.frontmatter { Some(s) => ...; None => ... }
let empty : String? = None
empty.unwrap_or("(fallback)")
doc.body.is_empty()
```
```
13 frontmatter = some:7
13 none unwrap_or = (fallback)
13 body empty = true
```
`Option::or` は deprecated（`unwrap_or` が正）。

---

## 追加で踏んだ、計画に効く 3 件

### A. **エイリアシングの罠**（struct が参照であることの直接の帰結）

同じ `Sub` を 2 回 graft すると、**中の Node が物理的に共有される**:
```
A1 shape = doc(R2[>3(4)] R2[>3(4)] R1[] R5[<6])
A1 深部ノードは共有 physical_equal = true
A1 片方を空にすると もう一方 = doc(R2[>3 <77] R2[>3] R1[] R5[<6])   ← 両方から 4 が消えた
```
（`as_center` / `as_node` が新しい struct と `.map` の新配列を作る層だけは隔離される: `A1 physical_equal(centers[0], centers[1]) = false`、`A1 centers[1].branches len = 1`。**1 段だけ守られて 2 段目から共有**という一番危ない形。）

隔離が要るなら明示の深いコピーが要る（`{ ..n, children: n.children.map(clone_node) }`、3 関数で書ける）:
```
A2 元 = doc(R1[>2(3(4))] R5[<6])
A2 複 = doc(R1[] R5[<6])
```

### B. **pluck は即座に doc を壊す**
```
E4 = doc(R1[] R5[<6])      // pluck しただけで graft していない
O2 after pluck  = doc(R1[>2] R5[<6])
O2 after graft  = doc(R1[>2] R5[>3(4) <6])
```
`Sub` は「運搬の通貨」だが、**発行した瞬間に doc から消える**。pluck と graft の間で例外が飛ぶ／`at` の clamp に失敗すると木を落とす。op の外に `Sub` を出さない規律は、可視性のためだけでなく**破損の窓を閉じるため**に必須。

### C. wbtest しか使っていない import は `unused_package` 警告
```
Warning: [0029]
 4 │   "probe-a/lib",
   │   ──────┬──────
   │         ╰──────── Warning (unused_package): Unused package 'probe-a/lib'
```
（`moon check` は wbtest を勘定に入れない。同じ理由で、wbtest でしか構築していない列挙子は `unused_constructor` 警告が残り続ける。）

---

# 設計に影響する発見

- **struct は参照。コピーは一度も起きない。**（`physical_equal(doc.centers[0], doc.centers[0]) == true`）関数の戻り値・引数を経由しても同一実体。→ `resolve` が返す `Path` の代わりに「ノードそのもの」を返す設計も物理的には成立するが、**不変フィールドの差し替えに親の配列 + index が要る**ので Path のままが正しい。
- **不変 struct + 可変 Array の組み合わせで、道具 4 つは全部書ける。`mut` は 1 つも要らない。** `lib/ops.mbt`（`resolve` / `pluck` / `graft` / `amend` / `set_side`）が `mut` ゼロで `moon check` 0 errors、`moon test` 28/28 pass。
- **腕数は 3 で止まった。** `pluck` 3 腕（centers / branches / children）、`graft` 3 腕 + 変換 2 関数（`as_center` / `as_node`）、`resolve` 腕なし。move の 9 組合せのうち代表 4 本を実測して全部通った:
  ```
  O2 深い枝 → 別 center のスロット   = doc(R1[>2] R5[>3(4) <6])
  O3 スロット → doc 直下（Limb→Center 化） = doc(R2[>3(4)] R1[] R5[<6])
  O4 center → スロット（Tree 解体）  = doc(R1[>2(3(4)) <5(6)])
  O5 center の並べ替え（Tree 無変換） = doc(R5[<6] R1[>2(3(4))])
  O7 set_side                      = doc(R1[<2(3(4))] R5[<6])
  ```
  O4 が `<5(6)` になっている＝**Tree 解体で side が消え、行き先の `side` 引数（Left）が採られた**。「側は場所の属性」が型と実装の両方で成立している。
- **`amend` だけが 4 腕**（`[]` / `[i]` / `[i, j]` / `[.. head, last]`）。原因は 1 つ — **スロットのノードは `Array[Node]` ではなく `Branch` の中に居る**。`Branch` に `mut node : Node` を 1 つ足すだけで 3 腕になる（`opsmut.mbt` の `amend_m` で実測）。**これが「殺す条件」の唯一のきしみ**。今は 4 腕で止まっているので許容範囲だが、`amend` に 5 本目が生えたらこの `mut` 1 個を検討する順序が正しい。
- **`pub` では別パッケージから組み立てられない。** テストを別パッケージ（blackbox）に置く／JS エクスポート層が `Doc` を作るなら、**全型を `pub(all)` にする以外にない**（`[4036] Cannot create values of the read-only type`）。一方で `pub` のままでも**配列の中身は素通しで壊せる**ので、`pub` に封じ込めの効果を期待してはならない。
- **`insert` の範囲外は catch 不能な panic。** graft は `at` を `[0, len]` に clamp する契約を持つこと。
- **エイリアシングは型で防げない。** 同じ `Sub` の二重 graft、あるいは pluck 前の `Sub` の保持で木が物理共有される（実測: 片方を空にすると両方から消える）。**`Sub` は「一度だけ使える通貨」という不変条件を op.mbt 内で守る必要がある**（graft が `Sub` を消費する API 形か、graft 後の再利用を型で禁じる工夫）。id 一意性の check がここを拾える保険にはなる（二重 graft で id 2/3/4 が重複した）。
- `.. rest` の束縛は `ArrayView[Int]`。内部ヘルパのシグネチャは `ArrayView[Int]` で受け、公開 API の `Array[Int]` からは `path[:]` で落とす。

---

# 推奨する実装パターン: **(c) 配列要素への代入**

**理由**:

1. **`mut` が 1 つも要らない。** 型が「書き替えられる場所」を宣言しないので、憲法の「型で殺す」方針と衝突しない。`unused_mut` の地雷（`[0015]`、定義パッケージ内で一度書かないとビルドが止まる）も、`pub(all)` 強制の連鎖も踏まない。
2. **pluck / graft と同じ地面に立っている。** pluck/graft は「所有する配列 + index」で書く以外にない（`Array::remove` / `insert`）。amend も同じ座標系で書けるので、`node_at(doc, head)` という**ヘルパ 1 本を 4 つの道具全部が共有する**。(a) 純粋形はここで座標系が割れる（doc を作り直すので pluck/graft と混ぜられない）。
3. **元の doc がその場で更新される。** 戻り値は `Unit`。JS 側が保持する参照、id 表、履歴の基準点が差し替わらない。(a) は毎回 `Doc` が別物になるので、統一サイクル（md が変わった → projectJson → render）の入口で誰が最新の `Doc` を持つかという問いを新たに生む。
4. **腕は 3 で止まった。** amend の 4 腕目はスロット 1 箇所だけで、しかもそれは (b) でも (a) でも構造的に同じ場所（Branch という包み）に生じるコストであり、(c) 固有の負債ではない。

**採るべき綴り**（`lib/ops.mbt` そのまま、`moon check` 0 errors / `moon test` 28/28 pass）:

```moonbit
fn node_at(doc : Doc, path : ArrayView[Int]) -> Node {
  guard! path is [i, j, .. rest]
  let mut n = doc.centers[i].branches[j].node
  for k in rest { n = n.children[k] }
  n
}

pub fn pluck(doc : Doc, path : Array[Int]) -> Sub? {
  match path {
    [] => None
    [i] => Some(Whole(doc.centers.remove(i)))
    [i, j] => Some(Limb(doc.centers[i].branches.remove(j).node))
    [.. head, last] => Some(Limb(node_at(doc, head).children.remove(last)))
  }
}

pub fn graft(doc : Doc, parent : Array[Int], at : Int, sub : Sub, side : Side) -> Unit {
  match parent {
    [] => doc.centers.insert(at, as_center(sub))
    [i] => doc.centers[i].branches.insert(at, { side, node: as_node(sub) })
    _ => node_at(doc, parent[:]).children.insert(at, as_node(sub))
  }
}
```

**併せて計画に書くべき制約**: (i) `graft` は `at` を clamp する（`insert` の範囲外は catch 不能）、(ii) `Sub` は一度しか graft してはならない（エイリアシング）、(iii) 型は `pub(all)`（別パッケージのテスト / JS 層が構築するなら必須）、(iv) `Center` / `Node` の `skeleton` を `mut` にする誘惑は `amend` に 5 本目の腕が生えるまで保留。

---

**実測に使ったファイル**（すべて scratchpad/v2 配下）:
`.../scratchpad/v2/probe-a/moon.mod` / `lib/moon.pkg` / `lib/types.mbt`（憲法の型の逐語）/ `lib/useall.mbt` / `lib/mutable.mbt`（mut 対照型）/ `lib/ops.mbt`（道具 4 つ・mut ゼロ）/ `lib/opsmut.mbt`（mut 版 amend の腕数対照）/ `lib/value_wbtest.mbt`（項目 1〜3）/ `lib/patterns_wbtest.mbt`（項目 5）/ `lib/syntax_wbtest.mbt`（項目 6〜9・12・13）/ `lib/ops_wbtest.mbt`（項目 11 + move 掃引）/ `lib/alias_wbtest.mbt` / `lib/edge_wbtest.mbt` / `user/moon.pkg` / `user/read_wbtest.mbt` / `user/neg.mbt` / `user/mutwrite.mbt`
# T1 — 型と parse の骨格（Task 1〜9）

## この群の概要

**担当**: T1 — 型・綴りの定数・行の走査・行 → かたまり（`scan`）まで。**木は作らない**（`build` / `parse` は T2、`serialize` は T3）。

**所有ファイル**（正誤表 §B-1 / §B-2）:
`core/doc/moon.pkg` / `tree.mbt` / `spell.mbt` / `line.mbt` / `scan.mbt` / `block.mbt`（仮置き `classify` の Create のみ。本実装は T2 が Modify）／ `fixture_wbtest.mbt` / `tree_wbtest.mbt` / `line_wbtest.mbt` / `scan_wbtest.mbt`。

**この群が新設する、正誤表 §C-3 の表に無い名前**: `atx_writable`（Task 9）の 1 つだけ。**着手前に §C-3 の T1 `scan.mbt` の行へ足して全員へ共有する** — §C はパッケージ内でトップレベルの名前が一意であることを執行する唯一の根拠であり、二重定義は `Error: [4051]` でテストが 1 本も走らなくなる。

**前提**: 起点。誰も待たない。**旧 core（`core/*.mbt`・`core/js/`）・`src/`・既存 `test/*.test.ts` 26 本・仕様・カタログは 1 バイトも触らない。**

**着手順**: Task 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 の直列。**Task 1 のコミットが T2 Task 10 / T3 Task 20 / T5 Task 40 の着手条件**、**Task 2 のコミット（`fixture_wbtest.mbt`）が T3 Task 21〜26 / T4 Task 33 / T5 Task 41〜48 の着手条件**、**Task 8 のコミット（`scan` と `block.mbt` の仮置き）が T2 Task 12〜17 の着手条件**である。

**テストの累計**（各 Task の Step 4 はこの「T1 の累計」を逐語で書く）:

| Task | 追加 | T1 の累計 |
|---|---|---|
| 1 | 1 | **1** |
| 2 | 10 | **11** |
| 3 | 15 | **26** |
| 4 | 13 | **39** |
| 5 | 15 | **54** |
| 6 | 6 | **60** |
| 7 | 13 | **73** |
| 8 | 21 | **94** |
| 9 | 6 | **100** |

**Step 4 の Expected の読み方**: `moon test` が出す `Total tests: N` の N には、**並行して進んでいる他群（T2・T3・T5）のテストも入る**。T1 が固定するのは「T1 の累計ぶんがすべて passed に入り、`failed: 0` であること」であって N の絶対値ではない。**ただし `Total tests: 0` は緑ではない** — `-p mmm-app/core/doc` の綴り間違いは黙って EXIT=0 になるので、0 を見たら必ず綴りを疑う。

**この群で守る裁定**: 裁定 1（不変条件 11「implied ⇒ side = Right」）／裁定 2（`- - -` は飾りの水平線）／裁定 4（`spell.mbt` は T1 が完全版を作る・`fixture_wbtest.mbt` に wbtest ヘルパを集約・`block.mbt` は T1 が Create）／裁定 5（`chunks_sig` は Body を展開せず `body` とだけ出す）／裁定 6（コマンドの綴り）／裁定 7（`scan_head` の EOL 正規化・summary の読み捨ては details の直後だけ）／裁定 8（Task の分割）。

**統括の裁定（最終版で反映済み）**:

- **裁定 A（単調性は parse の attach で強制する）** — 実装は T2 の `push_skel`（Heading を積む前に開いている Item を全部閉じる）。**T1 の `scan` は変わらない**。項目の領土の中の ATX 見出しを Opaque にする Task 9 (a) はそのまま残る（`- a` + `  # h` は Body、`- a` + `## h` は `1I:a|2H:h|` を吐いて木の形は T2 が決める）
- **裁定 B（implied の位置制約の一般化）** — 不変条件 8 を「implied ⇒ 親の children の先頭」から「**implied ⇒ その前に見出しの兄弟が居ない**」へ改める。見出しが居ると飛びをその見出しが飲み込んでしまうが、項目の後ろは吸収されないので置ける。違反メッセージは `implied の前に見出しが居る: <id>`。**Task 3 の `visit` がこれを見張る**（T5 の `spellable` も同じ言葉に揃う）
- **裁定 E（文書頭の `---` の裁定）** — 仕様 §4 の frontmatter の行が「**直後が空行でなく、かつ閉じの `---` があるとき**だけ封筒」に改訂された。**Task 7 の `scan_head` に「開き `---` の直後が空行なら封筒ではない」の 1 条件を足す**。これが無いと、先頭トグルで始まりトグルをもう 1 本持つ文書が丸ごと封筒に飲まれて法則 1 が破れる（往復の固定は T4 Task 33 の法則 1 ファズ（seed 199）が、方言表の行は T4 Task 36 が持つ）

**実測由来の綴りの規律**: `pub(all)` を使わない／`not(x)` を使わない（`!x` か `!=`）／`rev_inplace` `to_array` を使わない／ラベル付きペイロードの呼び出しは `Image(alt="a", src="b.png")`（`~=` は `Error: [3016]`）／`mut` フィールドはパッケージ内で必ず一度書く／`s[a:b]` はサロゲートの途中で切ると panic する。

---

## Task 1: パッケージ・木の型・綴りの定数

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/moon.pkg`
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree.mbt`
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/spell.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree_wbtest.mbt`

**Interfaces:**
- Consumes: なし（起点）
- Produces:
  - 型 `Tree` / `Node` / `Form` / `Side` / `Block` / `Content` / `Eol`（正誤表 §A-2 の全文。**5 人の共有物**）
  - `pub fn is_implied(nd : Node) -> Bool` / `pub fn empty(id : Int, form : Form) -> Node` / `pub fn promote(nd : Node, label : String) -> Node`
  - `spell.mbt` の 11 定数 `item_mark` / `heading_mark` / `nest_step` / `fence_mark` / `fence_min` / `rule_mark` / `toggle_mark` / `fold_open` / `fold_close` / `summary_open` / `summary_close`（正誤表 §A-6。**T2・T3 は読むだけ。作らない**）

**カバーする要件:** R009〜R020（型の全構成要素）、R022〜R024（implied）、R027（昇格）、R013（form 2 値）、R016〜R018（Block の 2 種別）、R019（綴りを持たない）、R093（EOL のダイヤル）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/moon.pkg`:

```
pkgtype(kind: "library")
```

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree_wbtest.mbt`:

```moonbit
// 型は木の中を直接組んで確かめるので whitebox テスト。

///|
test "空のノードは右側の Heading で、implied ではない" {
  // R012 R013 R014 R022
  let nd = empty(1, Heading)
  assert_eq((nd.id, nd.form, nd.side, nd.implied), (1, Heading, Right, false))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `tree.mbt` がまだ無いのでコンパイルエラー。1 行目 `Error: [4021]`、本文 `The value identifier empty is unbound.`（`Heading` / `Right` も同じく未定義として続く）。**`Total tests:` の行は出ない**（EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree.mbt`（正誤表 §A-2 の全文）:

```moonbit
// 文書の木。綴りは持たない — 綴りは serialize が所有する。
// オフセットも持たない（法則 1 の比較対象を増やさないため）。
// 反映 v1 のすげ替えで骨格スパンが要るようになったら `implied : Bool` を
// `skel : Span?` に替えるが、読みは常に `is_implied` を通すので呼ぶ側は変わらない。

///|
/// 文書ひとつ。head は封筒（中は解釈しない）、doc は木そのもの（深さ 0）。
pub struct Tree {
  head : String? // frontmatter の逐語。開き `---` 行頭から閉じ `---` 行末まで（末尾改行を含まない・改行は "\n" に畳む）
  eol : Eol // 原文の流儀。serialize が全行をこれで書く
  doc : Node // 深さ 0 のノード。body = 最初の骨格行より前、children = 木の列
}

///|
pub enum Eol {
  Lf
  Crlf
} derive(Eq, Debug)

///|
/// ノード。**level は持たない — level は木の深さそのもの**（飛びは implied が
/// 埋めるので親子の差は常に 1）。持つと深さと食い違う状態が書けてしまう。
pub struct Node {
  id : Int // セッション限り。parse が文書順に 1 から振る（doc が 1）
  form : Form // 意味。見出しか項目か
  label : String // 骨格行の中身。implied は必ず ""
  implied : Bool // 骨格行を持たない（level 飛びが綴り）。存在条件は check が見張る
  folded : Bool // 畳み。綴りは details
  side : Side // **深さ 2（root 直下のスロット）だけが意味を持つ**。他は必ず Right。
  //           **implied は深さによらず必ず Right**（飛びには側を書く場所が無い）
  body : Array[Block] // 骨格行の後・最初の子の前の中身
  children : Array[Node] // 子。Item が先、Heading が後（順序法則）
}

///|
pub enum Form {
  Heading
  Item
} derive(Eq, Debug)

///|
pub enum Side {
  Right
  Left
} derive(Eq, Debug)

///|
/// 中身のかたまり 1 つ。
pub enum Block {
  Content(Content) // 認定ブロック。serialize が同じ綴りを書き戻せる形だけがここへ来る
  Rule // 飾りの水平線。綴りは `***` に正規化（トグルの `---` とはチャンネルが違う）
  Opaque(String) // 散文・引用・表・HTML・謎。逐語
} derive(Eq, Debug)

///|
/// 認定ブロック。**疑わしきは Opaque** — ここに来るのは
/// 「serialize が書き戻した綴りを parse すると同じ値に戻る」形だけ。
pub enum Content {
  Image(alt~ : String, src~ : String) // ![alt](src)
  Link(text~ : String, href~ : String) // [text](href)
  Code(info~ : String, text~ : String) // ```info … ```（インデントコードもここへ読む）
  Svg(String) // <svg …>…</svg> 逐語
} derive(Eq, Debug)

///|
/// 骨格行を持たないか。**implied の判定は必ずこれを通す**（v1 で中身が替わる）。
pub fn is_implied(nd : Node) -> Bool {
  nd.implied
}

///|
/// 空のノード 1 つ。
pub fn empty(id : Int, form : Form) -> Node {
  {
    id,
    form,
    label: "",
    implied: false,
    folded: false,
    side: Right,
    body: [],
    children: [],
  }
}

///|
/// 骨格行を書く = 昇格。implied はこの瞬間に普通のノードになる。
pub fn promote(nd : Node, label : String) -> Node {
  { ..nd, label, implied: false }
}
```

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/spell.mbt`（正誤表 §A-6 の全文。11 定数）:

```moonbit
// 正規形の綴りの定数。**綴りのリテラルはこのファイルにだけ置く。**
// Image / Link の `![` `](` `)` は綴りの選択肢が無い記法そのものなので置かない
// （ここは「選べる綴り」の置き場）。

///|
let item_mark : String = "-" // 項目のマーカー（`*` `+` は読みのみ）

///|
let heading_mark : String = "#" // 見出しの印（setext は書かない）

///|
let nest_step : Int = 2 // 入れ子 1 段の字下げ

///|
let fence_mark : String = "`" // コードのフェンス（`~` は読みのみ）

///|
let fence_min : Int = 3 // フェンスの最小の本数

///|
let rule_mark : String = "***" // 飾りの水平線

///|
let toggle_mark : String = "---" // 側の変わり目

///|
let fold_open : String = "<details>"

///|
let fold_close : String = "</details>"

///|
let summary_open : String = "<summary>"

///|
let summary_close : String = "</summary>"
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core check
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 1 本**で、そのすべてが passed に入り `failed: 0` であること（N には並行して進む他群のテストも含まれる）。`Total tests: 0` が出たら `-p` の綴りを疑うこと。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**掲載コードは折り返し前の姿なので、`fmt doc` が 80 桁を超える行を複数行へ展開する。これは正常であり、展開後の姿でコミットする**（`fmt --check` の失敗は EXIT=127 で、0 でも 1 でもない）。／check は `Finished. …（N warnings, 0 errors）` で EXIT=0。**`spell.mbt` の 11 定数はまだ 1 つも使われないので `Warning (unused_value)` が 11 件出るが、ビルドは止まらない**（`--deny-warn` は付けない）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/moon.pkg core/doc/tree.mbt core/doc/spell.mbt core/doc/tree_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 新 core のパッケージと文書の木の型を置く"
```

**このコミットが T2 Task 10 / T3 Task 20 / T5 Task 40 の着手条件である。**

---

## Task 2: 手で木を組む道具と、指紋

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/fixture_wbtest.mbt`
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree.mbt`（`promote` の後ろへ `esc` / `block_sig` / `node_sig` / `sig` を追記）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: `Tree` / `Node` / `Form` / `Side` / `Block` / `Content` / `Eol`、`empty` / `promote` / `is_implied`（Task 1）
- Produces:
  - `pub fn sig(tree : Tree) -> String` — **id を含まない**木の指紋。法則 1・2 の比較子はこれ 1 本（T4 の `sig_of`・T5 の操作テストが使う）
  - `fn esc(s : String) -> String` / `fn block_sig(b : Block, sb : StringBuilder) -> Unit` / `fn node_sig(nd : Node, sb : StringBuilder) -> Unit` — パッケージ内の部品（T1 自身が `scan_wbtest.mbt` で `esc` を再利用する）
  - **`fixture_wbtest.mbt` の 8 関数** `node(id, form, label, kids) -> Node` / `heading(id, label, kids) -> Node` / `item(id, label, kids) -> Node` / `slot(id, label, left) -> Node` / `doc_of(kids) -> Node` / `tree_of(kids) -> Tree` / `chain(n) -> Node` / `chain_tree(n) -> Tree`
    （**T3・T4・T5 はこれを使う。自前で定義しない**。`*_wbtest.mbt` はパッケージ内でトップレベルの名前空間を共有し、同名定義は `Error: [4051]` でテストが 1 本も走らなくなる）

**カバーする要件:** R062・R063（法則 1・2 の比較子）、R020（id はモデルの同一性に入らない）。カタログ C16（裁定 1 の昇格した結果の指紋）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/fixture_wbtest.mbt`（新規。正誤表 §C-2。**`done` / `rejected` はここでは書かない** — `Outcome` は T5 Task 43 で初めて存在するので、書くと未定義で全テストが落ちる）:

```moonbit
// wbtest が共有する、手で木を組む道具。
// *_wbtest.mbt はパッケージ内で 1 つの名前空間を共有するので、
// **手組みのヘルパはこのファイルにだけ置く**（各 wbtest で作り直さない）。
// T3・T4・T5 はここのものを使う。末尾には T5 Task 43 が
// `done` / `rejected` の 2 本だけを追記する。

///|
/// ノード 1 つ。
fn node(id : Int, form : Form, label : String, kids : Array[Node]) -> Node {
  { ..empty(id, form), label, children: kids }
}

///|
/// 見出し 1 つ。
fn heading(id : Int, label : String, kids : Array[Node]) -> Node {
  node(id, Heading, label, kids)
}

///|
/// 項目 1 つ。
fn item(id : Int, label : String, kids : Array[Node]) -> Node {
  node(id, Item, label, kids)
}

///|
/// 深さ 2 のスロット 1 つ（側を指定できる）。
fn slot(id : Int, label : String, left : Bool) -> Node {
  { ..empty(id, Heading), label, side: if left { Left } else { Right } }
}

///|
/// 深さ 0 の文書ノード（id 1・Heading・空ラベル）に木を吊るす。
fn doc_of(kids : Array[Node]) -> Node {
  { ..empty(1, Heading), children: kids }
}

///|
/// 文書ひとつ（head 無し・LF）。
fn tree_of(kids : Array[Node]) -> Tree {
  { head: None, eol: Lf, doc: doc_of(kids) }
}

///|
/// 深さ n の見出しの一本鎖（ラベルは深さの数字・id は深さ + 1）。
/// 返すのは鎖の頭（深さ 1 のノード）。
fn chain(n : Int) -> Node {
  let mut cur = heading(n + 1, n.to_string(), [])
  for i = n - 1; i >= 1; i = i - 1 {
    cur = heading(i + 1, i.to_string(), [cur])
  }
  cur
}

///|
/// 深さ n の一本鎖を吊るした文書。
fn chain_tree(n : Int) -> Tree {
  tree_of([chain(n)])
}
```

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree_wbtest.mbt` の末尾へ追記:

```moonbit
///|
/// 正誤表 §A-4 の固定の例その 5: `# r` + `- x`（左・画像 1 枚）。
fn sample() -> Tree {
  let x = {
    ..empty(3, Item),
    label: "x",
    side: Left,
    body: [Content(Image(alt="a", src="b.png"))],
  }
  tree_of([heading(2, "r", [x])])
}

///|
test "空文書の指紋は doc ひとつ" {
  assert_eq(sig(tree_of([])), "head:-\nlf\n[H]")
}

///|
test "見出し 1 つの指紋" {
  assert_eq(sig(tree_of([heading(2, "r", [])])), "head:-\nlf\n[H[Hr]]")
}

///|
test "親子の指紋は入れ子になる" {
  let r = heading(2, "r", [heading(3, "a", [])])
  assert_eq(sig(tree_of([r])), "head:-\nlf\n[H[Hr[Ha]]]")
}

///|
test "implied の 2 段は ~ が 2 つ並ぶ" {
  // `# r` + `#### b` の綴り。R024
  let b = heading(5, "b", [])
  let g2 = { ..empty(4, Heading), implied: true, children: [b] }
  let g1 = { ..empty(3, Heading), implied: true, children: [g2] }
  assert_eq(sig(tree_of([heading(2, "r", [g1])])), "head:-\nlf\n[H[Hr[H~[H~[Hb]]]]]")
}

///|
test "指紋は正誤表の実例どおりに出る" {
  assert_eq(sig(sample()), "head:-\nlf\n[H[Hr[I<x|img:a|b.png]]]")
}

///|
test "C16 昇格したスロットは側を持ち、その下に implied が並ぶ" {
  // 裁定 1。implied スロットへの flipSide の行き先（T5 Task 46 が作る木の形）
  let b = heading(5, "b", [])
  let g = { ..empty(4, Heading), implied: true, children: [b] }
  let s = { ..slot(3, "", true), children: [g] }
  assert_eq(sig(tree_of([heading(2, "r", [s])])), "head:-\nlf\n[H[Hr[H<[H~[Hb]]]]]")
}

///|
test "指紋は id を含まない" {
  // R020。id はモデルの同一性に入らない
  let a = sample()
  let b = { ..a, doc: { ..a.doc, id: 99 } }
  assert_eq(sig(a), sig(b))
}

///|
test "指紋は ^ を逃がす（畳みのフラグと取り違えない）" {
  // 逃がさないと label が "^x" の畳んでいないノードと
  // label が "x" の畳んだノードが同じ指紋になる（法則 1 の比較子の穴）
  assert_eq(sig(tree_of([heading(2, "^x", [])])), "head:-\nlf\n[H[H\\^x]]")
}

///|
test "指紋は ~ と < も逃がす" {
  // "~" は implied のフラグ、"<" は左のフラグと衝突する
  assert_eq(sig(tree_of([heading(2, "~<", [])])), "head:-\nlf\n[H[H\\~\\<]]")
}

///|
test "指紋は区切り文字と改行を逃がし、封筒と流儀を頭に置く" {
  let a = heading(2, "a|b[c]d\\e\nf", [])
  let tree = {
    head: Some("---\nk: v\n---"),
    eol: Crlf,
    doc: doc_of([a]),
  }
  assert_eq(
    sig(tree),
    "head:---\\nk: v\\n---\ncrlf\n[H[Ha\\|b\\[c\\]d\\\\e\\nf]]",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier sig is unbound.`。Task 1 の 1 本も含めて 1 本も走らない（`Total tests:` の行が出ない・EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree.mbt` の末尾（`promote` の後ろ）へ追記:

```moonbit
///|
/// 指紋の中で意味を持つ文字を `\` で逃がし、改行は見える形に畳む。
/// **`~` `^` `<` を逃がすのは必須** — 逃がさないとフラグと label が
/// 取り違えられ、別の木が同じ指紋になる。`\r` は落とさず見えるようにする
/// （逐語文字列に `\r` は入らない約束なので、出たら畳みの漏れが即分かる）。
fn esc(s : String) -> String {
  let sb = StringBuilder::new()
  for ch in s.iter() {
    let c = ch.to_int()
    if c == 92 || c == 124 || c == 91 || c == 93 || c == 126 || c == 94 || c == 60 {
      sb.write_string("\\")
      sb.write_char(ch)
    } else if c == 10 {
      sb.write_string("\\n")
    } else if c == 13 {
      sb.write_string("\\r")
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn block_sig(b : Block, sb : StringBuilder) -> Unit {
  match b {
    Rule => sb.write_string("rule")
    Opaque(t) => {
      sb.write_string("o:")
      sb.write_string(esc(t))
    }
    Content(Image(alt~, src~)) => {
      sb.write_string("img:")
      sb.write_string(esc(alt))
      sb.write_string("|")
      sb.write_string(esc(src))
    }
    Content(Link(text~, href~)) => {
      sb.write_string("link:")
      sb.write_string(esc(text))
      sb.write_string("|")
      sb.write_string(esc(href))
    }
    Content(Code(info~, text~)) => {
      sb.write_string("code:")
      sb.write_string(esc(info))
      sb.write_string("|")
      sb.write_string(esc(text))
    }
    Content(Svg(t)) => {
      sb.write_string("svg:")
      sb.write_string(esc(t))
    }
  }
}

///|
/// フラグは implied → folded → 左 の順。立っているものだけを書く。
fn node_sig(nd : Node, sb : StringBuilder) -> Unit {
  sb.write_string("[")
  sb.write_string(if nd.form == Heading { "H" } else { "I" })
  if nd.implied {
    sb.write_string("~")
  }
  if nd.folded {
    sb.write_string("^")
  }
  if nd.side == Left {
    sb.write_string("<")
  }
  sb.write_string(esc(nd.label))
  for b in nd.body {
    sb.write_string("|")
    block_sig(b, sb)
  }
  for kid in nd.children {
    node_sig(kid, sb)
  }
  sb.write_string("]")
}

///|
/// 木の指紋。**id を含まない** — 法則 1・2 の比較子はこれ 1 本。
/// id は parse が振り直すので、モデルの同一性に id は入らない。
pub fn sig(tree : Tree) -> String {
  let sb = StringBuilder::new()
  sb.write_string("head:")
  match tree.head {
    Some(h) => sb.write_string(esc(h))
    None => sb.write_string("-")
  }
  sb.write_string("\n")
  sb.write_string(if tree.eol == Lf { "lf" } else { "crlf" })
  sb.write_string("\n")
  node_sig(tree.doc, sb)
  sb.to_string()
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 11 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**この Task の掲載コードは `esc` の 7 項の `||` 連鎖（84 桁）と `implied の 2 段` の `assert_eq`（81 桁）が 80 桁を超えるので、`fmt doc` が複数行へ展開する。展開後の姿でコミットする。**／`fixture_wbtest.mbt` の `item` / `slot`（Task 2 では未使用のもの）に `Warning (unused_value)` が出るが、ビルドは止まらない。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/tree.mbt core/doc/tree_wbtest.mbt core/doc/fixture_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 木の指紋を、手で組んだ木で確かめる"
```

**このコミットが T3 Task 21〜26 / T4 Task 33 / T5 Task 41〜48 の着手条件である。**

---

## Task 3: 不変条件の検査（11 個）

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree.mbt`（`sig` の後ろへ `visit` / `check` を追記）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: Task 1 の型と `empty` / `promote` / `is_implied`、Task 2 の `sig` と `fixture_wbtest.mbt` の 8 関数
- Produces: `pub fn check(tree : Tree) -> Array[String]` — 不変条件の違反。空なら健全（T4 の `check_of` が `"\n"` 区切りで JS へ出し、T5 の `normalize` がこれを満たす木しか返さない）

**カバーする要件:** R011（doc は深さ 0 の錨）、R039（単調性）、R041（順序法則）、**R042（順序法則は doc 直下にも効く）**、R024（implied の存在条件）、R014（side は深さ 2 だけ）、R020（id の一意）。**裁定 1 の不変条件 11**（仕様 §2 の改訂・カタログ C16）。**裁定 B の不変条件 8**（「先頭」ではなく「前に見出しが居ない」）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree_wbtest.mbt` の末尾へ追記:

```moonbit
///|
test "健全な木の検査は空を返す" {
  assert_eq(check(sample()).length(), 0)
}

///|
test "条件 1: 汚れた doc は違反として挙がる" {
  // R011
  let tree = { head: None, eol: Lf, doc: { ..empty(1, Heading), label: "x" } }
  assert_eq(check(tree)[0], "doc が汚れている")
}

///|
test "条件 2: id の重複は違反として挙がる" {
  // R020
  let tree = tree_of([heading(2, "a", []), heading(2, "b", [])])
  assert_eq(check(tree)[0], "id が重複: 2")
}

///|
test "条件 3: Item の下の Heading は単調性の違反になる" {
  // R039
  let tree = tree_of([item(2, "i", [heading(3, "h", [])])])
  assert_eq(check(tree)[0], "Item の下に Heading: 3")
}

///|
test "条件 4: Heading の後ろの Item は順序法則の違反になる" {
  // R041
  let r = heading(2, "r", [heading(3, "h", []), item(4, "i", [])])
  assert_eq(check(tree_of([r]))[0], "順序法則の違反: 4")
}

///|
test "条件 4 は doc 直下にも効く" {
  // R042。doc も「同じ親」の 1 つである
  let tree = tree_of([heading(2, "h", []), item(3, "i", [])])
  assert_eq(check(tree)[0], "順序法則の違反: 3")
}

///|
test "条件 5: implied が Item なら違反になる" {
  let g = { ..empty(2, Item), implied: true, children: [item(3, "b", [])] }
  assert_eq(check(tree_of([g]))[0], "implied が Item: 2")
}

///|
test "条件 6: 中身を持った implied は違反になる" {
  let g = { ..empty(2, Heading), implied: true, label: "x", children: [heading(3, "b", [])] }
  assert_eq(check(tree_of([g]))[0], "implied が中身を持つ: 2")
}

///|
test "条件 7: 子の居ない implied は存在条件の違反になる" {
  // R024
  let g = { ..empty(2, Heading), implied: true }
  assert_eq(check(tree_of([g]))[0], "implied に子が居ない: 2")
}

///|
test "条件 8: 見出しの後ろの implied は綴れないので違反になる" {
  // 裁定 B。前に見出しが居ると、その見出しが飛びを飲み込んでしまう
  let g = { ..empty(3, Heading), implied: true, children: [heading(4, "b", [])] }
  let tree = tree_of([heading(2, "a", []), g])
  assert_eq(check(tree)[0], "implied の前に見出しが居る: 3")
}

///|
test "条件 8: 項目 root のあとの implied は綴れるので違反にならない" {
  // 裁定 B。直前の兄弟が Item なら飛びは吸収されない（Item は Heading の子を持てない）。
  // 裁定 A で `- a` + `## h` が生む木がこれである
  let g = { ..empty(3, Heading), implied: true, children: [heading(4, "h", [])] }
  assert_eq(check(tree_of([item(2, "a", []), g])).length(), 0)
}

///|
test "条件 9: implied が Item の子を持てば飛びで綴れないので違反になる" {
  let g = { ..empty(2, Heading), implied: true, children: [item(3, "b", [])] }
  assert_eq(check(tree_of([g]))[0], "implied が Item の子を持つ: 2")
}

///|
test "条件 10: 深さ 2 でない側は違反として挙がる" {
  // R014
  let deep = { ..empty(4, Heading), label: "d", side: Left }
  let r = heading(2, "r", [heading(3, "x", [deep])])
  assert_eq(check(tree_of([r]))[0], "深さ 2 でない側: 4")
}

///|
test "条件 11: 側を持たされた implied は違反になる" {
  // 裁定 1。深さ 2 なので条件 10 は通り、ここで落ちる。
  // この穴が塞がるまで、飛びでは綴れない状態が木に書けてしまっていた
  let g = { ..empty(3, Heading), implied: true, side: Left, children: [heading(4, "b", [])] }
  assert_eq(check(tree_of([heading(2, "r", [g])]))[0], "implied が側を持つ: 3")
}

///|
test "promote は implied を普通のノードにする" {
  // R027
  let g = promote({ ..empty(2, Heading), implied: true }, "x")
  assert_eq(is_implied(g), false)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier check is unbound.`。Task 1・2 の 11 本も含めて 1 本も走らない（`Total tests:` の行が出ない・EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/tree.mbt` の末尾（`sig` の後ろ）へ追記:

```moonbit
///|
/// 1 ノードぶんの検査。深さ・親の form・前に見出しの兄弟が居たか・順序法則の
/// 破れは親しか知らないので引数で受け取る。
fn visit(
  nd : Node,
  depth : Int,
  parent_form : Form,
  heading_before : Bool,
  order_bad : Bool,
  seen : Array[Int],
  out : Array[String],
) -> Unit {
  if seen.contains(nd.id) {
    out.push("id が重複: " + nd.id.to_string())
  }
  seen.push(nd.id)
  if parent_form == Item && nd.form == Heading {
    out.push("Item の下に Heading: " + nd.id.to_string())
  }
  if order_bad {
    out.push("順序法則の違反: " + nd.id.to_string())
  }
  if nd.implied {
    if nd.form == Item {
      out.push("implied が Item: " + nd.id.to_string())
    }
    if nd.label != "" || nd.body.length() > 0 || nd.folded {
      out.push("implied が中身を持つ: " + nd.id.to_string())
    }
    if nd.children.length() == 0 {
      out.push("implied に子が居ない: " + nd.id.to_string())
    }
    // 裁定 B。飛びは直前の見出しに飲み込まれるので、前に見出しの兄弟が居ると
    // 書いても読み戻せない。項目の後ろは吸収されないので置ける
    if heading_before {
      out.push("implied の前に見出しが居る: " + nd.id.to_string())
    }
    for kid in nd.children {
      if kid.form == Item {
        out.push("implied が Item の子を持つ: " + nd.id.to_string())
        break
      }
    }
  }
  if depth != 2 && nd.side == Left {
    out.push("深さ 2 でない側: " + nd.id.to_string())
  }
  // 裁定 1。飛びには側を書く場所が無いので、implied は側を持てない。
  // 条件 10 とは独立である（深さ 2 の implied は 10 を通ってここで落ちる）
  if nd.implied && nd.side == Left {
    out.push("implied が側を持つ: " + nd.id.to_string())
  }
  let mut seen_heading = false
  for kid in nd.children {
    // この子から見た「前に見出しが居たか」は、この子より前だけを数えた値。
    // **引数の `heading_before` を影にしない名前を使う**（どちらの値かを
    // 読む側が迷わないように — 自分のではなく、子のための値である）
    let before_kid = seen_heading
    let bad = seen_heading && kid.form == Item
    if kid.form == Heading {
      seen_heading = true
    }
    visit(kid, depth + 1, nd.form, before_kid, bad, seen, out)
  }
}

///|
/// 不変条件の違反。空なら健全。テストと debug の assert がこれを見る。
/// **メッセージは改行を含まない**（wire.mbt が "\n" で綴じ、TS が split で戻す）。
pub fn check(tree : Tree) -> Array[String] {
  let out : Array[String] = []
  let d = tree.doc
  if d.form != Heading || d.label != "" || d.implied || d.folded {
    out.push("doc が汚れている")
  }
  let seen : Array[Int] = []
  visit(d, 0, Heading, false, false, seen, out)
  out
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 26 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**この Task の掲載コードは「条件 6」「条件 11」の struct リテラル（92 桁前後）が 80 桁を超えるので `fmt doc` が複数行へ展開する。展開後の姿でコミットする。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/tree.mbt core/doc/tree_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 木の不変条件を 11 個ぶん見張る"
```

---

## Task 4: 行の走査と、文字・空白の道具

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/line.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/line_wbtest.mbt`

**Interfaces:**
- Consumes: `Eol` / `Lf` / `Crlf`（Task 1）
- Produces（すべてパッケージ内の道具。Task 5〜9 と T2 が使う）:
  - `priv struct Line { start : Int; end : Int; next : Int }`
  - `fn scan_lines(text : String) -> Array[Line]`
  - `fn code_at(s : String, i : Int) -> Int` / `fn slice(s : String, a : Int, b : Int) -> String` / `fn is_space(c : Int) -> Bool`
  - `fn trim_range(text : String, a : Int, b : Int) -> (Int, Int)` / `fn trimmed_span(text : String, l : Line) -> (Int, Int)` / `fn is_blank(text : String, l : Line) -> Bool`
  - `fn indent_of(text : String, l : Line) -> (Int, Int)`（列, オフセット）
  - `fn eol_of(text : String) -> Eol` / `fn dedent(text : String, l : Line, drop : Int) -> String`
  - **`fn lead_spaces(s : String) -> Int` / `fn blank_line(s : String) -> Bool`** — **T2 の `block.mbt` がこの 2 本を呼ぶ。T2 は `indent_of(line : String)` / `is_blank(line : String)` を定義しない**（正誤表 §C-1。二重定義は `Error: [4051]` でテストが 1 本も走らなくなる）

**カバーする要件:** R093（EOL の保存）、R103（行頭の飾り字下げ）の材料、R146（オフセットは UTF-16 コード単位）。移植元は `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/parser.mbt:14-41, 123-125, 398-414` と `core/doc.mbt:6-13`。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/line_wbtest.mbt`:

```moonbit
// Line と scan_lines は private（かたまりになる前の、行の並びだけの結果）。
// それを直接見たいので whitebox テスト。

///|
/// 行の並びを「start-end-next」の列に畳む。
fn lines_sig(text : String) -> String {
  let sb = StringBuilder::new()
  for l in scan_lines(text) {
    sb.write_string(l.start.to_string())
    sb.write_string("-")
    sb.write_string(l.end.to_string())
    sb.write_string("-")
    sb.write_string(l.next.to_string())
    sb.write_string("|")
  }
  sb.to_string()
}

///|
test "空文書は 1 行として読む" {
  assert_eq(lines_sig(""), "0-0-0|")
}

///|
test "末尾の改行は行を増やさない" {
  assert_eq(lines_sig("a\nb\n"), "0-1-2|2-3-4|")
}

///|
test "末尾に改行が無くても最後の行は読む" {
  assert_eq(lines_sig("a\nb"), "0-1-2|2-3-3|")
}

///|
test "CRLF の \\r は行末に数えない" {
  assert_eq(lines_sig("a\r\nb\r\n"), "0-1-3|3-4-6|")
}

///|
test "改行の流儀は最初の改行で決まる" {
  // R093
  assert_eq(eol_of("a\r\nb\n"), Crlf)
}

///|
test "改行が無ければ流儀は Lf" {
  assert_eq(eol_of("a"), Lf)
}

///|
test "タブの字下げは 4 桁のタブ位置まで進む" {
  let t = "\tx"
  let (col, _) = indent_of(t, scan_lines(t)[0])
  assert_eq(col, 4)
}

///|
test "空白 2 つのあとのタブも 4 桁のタブ位置まで進む" {
  let t = "  \tx"
  let (col, _) = indent_of(t, scan_lines(t)[0])
  assert_eq(col, 4)
}

///|
test "dedent は指定した列ぶんだけ字下げを落とす" {
  let t = "    code"
  assert_eq(dedent(t, scan_lines(t)[0], 2), "  code")
}

///|
test "dedent は行末の \\r を落とす" {
  // 逐語の文字列に \r を残さないのは T1 の責務（正誤表 §A-7 前提 1）
  let t = "  x\r\n"
  assert_eq(dedent(t, scan_lines(t)[0], 2), "x")
}

///|
test "空白しか無い行は空行" {
  let t = "  \t \nx\n"
  let ls = scan_lines(t)
  assert_eq((is_blank(t, ls[0]), is_blank(t, ls[1])), (true, false))
}

///|
test "lead_spaces は行頭の半角空白だけを数える" {
  // T2 の block.mbt が呼ぶ。タブは数えない
  assert_eq((lead_spaces("   x"), lead_spaces("\tx"), lead_spaces("x")), (3, 0, 0))
}

///|
test "blank_line は空白とタブだけの文字列に true" {
  // T2 の block.mbt が呼ぶ
  assert_eq((blank_line("  \t "), blank_line(""), blank_line("  x")), (true, true, false))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier scan_lines is unbound.`（`eol_of` / `indent_of` / `dedent` / `is_blank` / `lead_spaces` / `blank_line` も続く）。1 本も走らない（EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/line.mbt`:

```moonbit
// 行の走査と、文字・空白の道具。木も綴りも知らない層。
// 旧 core/parser.mbt:14-41, 123-125, 398-414 と core/doc.mbt:6-13 からの移植。
// オフセットはすべて **UTF-16 コード単位**（CodeMirror と同じ空間なので変換層は要らない）。

///|
/// 行 1 つ。end は改行の手前、next は次の行頭。
priv struct Line {
  start : Int
  end : Int
  next : Int
}

///|
/// i 番目のコード単位。**Char ではなく UInt16 なので to_int() で受ける**。
fn code_at(s : String, i : Int) -> Int {
  s[i].to_int()
}

///|
/// [a, b) を切り出す。
/// **a・b は行境界かコードポイント境界であること。サロゲートの途中で切ると
/// `String::sub` の guard で panic する**（検査なしが要るなら
/// `String::unsafe_substring(s, start~, end~)`）。この層が渡すオフセットは
/// 常に行境界か ASCII の印の直後なので、ペアを割ることはない。
fn slice(s : String, a : Int, b : Int) -> String {
  s[a:b].to_owned()
}

///|
/// 半角空白かタブか。
fn is_space(c : Int) -> Bool {
  c == 32 || c == 9
}

///|
/// 行に割る。CRLF も、末尾改行なしも、空文書も同じ式で扱う。
fn scan_lines(text : String) -> Array[Line] {
  let lines : Array[Line] = []
  let n = text.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if code_at(text, i) == 10 {
      let mut e = i
      if e > start && code_at(text, e - 1) == 13 {
        e = e - 1
      }
      lines.push({ start, end: e, next: i + 1 })
      start = i + 1
    }
    i = i + 1
  }
  if start < n || n == 0 {
    lines.push({ start, end: n, next: n })
  }
  lines
}

///|
/// [a, b) の前後から空白（と行末に残った \r）を落とした範囲。
fn trim_range(text : String, a : Int, b : Int) -> (Int, Int) {
  let mut s = a
  let mut e = b
  while s < e && is_space(code_at(text, s)) {
    s = s + 1
  }
  while e > s && (is_space(code_at(text, e - 1)) || code_at(text, e - 1) == 13) {
    e = e - 1
  }
  (s, e)
}

///|
/// 行の中身（前後の空白を落とした範囲）。
fn trimmed_span(text : String, l : Line) -> (Int, Int) {
  trim_range(text, l.start, l.end)
}

///|
/// 空白しか無い行か。
fn is_blank(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  a >= b
}

///|
/// 行頭の空白を飛ばして (列, オフセット) を返す。
/// タブは CommonMark と同じく 4 桁のタブ位置まで進める。
fn indent_of(text : String, l : Line) -> (Int, Int) {
  let mut p = l.start
  let mut col = 0
  while p < l.end && is_space(code_at(text, p)) {
    col = if code_at(text, p) == 9 { col + 4 - col % 4 } else { col + 1 }
    p = p + 1
  }
  (col, p)
}

///|
/// 原文の改行の流儀。最初に見つかった改行で決める（無ければ Lf）。
fn eol_of(text : String) -> Eol {
  let n = text.length()
  for i = 0; i < n; i = i + 1 {
    if code_at(text, i) == 10 {
      return if i > 0 && code_at(text, i - 1) == 13 { Crlf } else { Lf }
    }
  }
  Lf
}

///|
/// 行から `drop` 列ぶんの字下げを落とした中身。行末の \r も落とす。
/// Body の逐語は「所属するコンテナの中身の列から見た姿」で持つ。
fn dedent(text : String, l : Line, drop : Int) -> String {
  let mut p = l.start
  let mut col = 0
  while p < l.end && col < drop && is_space(code_at(text, p)) {
    col = if code_at(text, p) == 9 { col + 4 - col % 4 } else { col + 1 }
    p = p + 1
  }
  let mut e = l.end
  while e > p && code_at(text, e - 1) == 13 {
    e = e - 1
  }
  slice(text, p, e)
}

///|
/// 文字列の行頭にある半角空白の数。**T2 の block.mbt がこれを呼ぶ**
/// （`indent_of(line : String)` を自分で定義しない — 二重定義は [4051]）。
fn lead_spaces(s : String) -> Int {
  let mut i = 0
  while i < s.length() && code_at(s, i) == 32 {
    i = i + 1
  }
  i
}

///|
/// 空白とタブだけの文字列か（空文字列も真）。**T2 の block.mbt がこれを呼ぶ**。
fn blank_line(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    if !is_space(code_at(s, i)) {
      return false
    }
    i = i + 1
  }
  true
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 39 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**`lead_spaces` / `blank_line` の 2 本の `assert_eq`（80 桁超）は `fmt doc` が複数行へ展開する。展開後の姿でコミットする。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/line.mbt core/doc/line_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 行の走査と、文字と空白の道具を移す"
```

---

## Task 5: 見出しと項目の行

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt`（中間表現の型 + `atx_at` + `bullet_at` まで）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Form` / `Heading` / `Item` / `Block` / `Eol`（Task 1）、`Line` / `scan_lines` / `code_at` / `slice` / `is_space` / `trim_range` / `trimmed_span` / `indent_of`（Task 4）
- Produces:
  - `pub struct Scan { head : String?; eol : Eol; chunks : Array[Chunk] }`
  - `pub struct Chunk { depth : Int; kind : Kind }`
  - `pub enum Kind { Skel(Form, String); Break(Bool); Fold(Bool); Body(Block) }` — **T2 の `build` が読む中間表現**
  - `fn atx_at(text : String, l : Line) -> (Int, String)?`
  - `fn bullet_at(text : String, l : Line) -> (Int, Int, String)?`
  - `fn first_line(md : String) -> Line`（`scan_wbtest.mbt`）

**カバーする要件:** R071・R072・R097（`#` は無制限）、R102（`*` `+` は読みのみ）、R104（順序リスト `1.` `1)`）、R103（飾り字下げ 0〜3）。カタログ C9（閉じシーケンス）。

**このタスクでは `- - -` を扱わない**（`break_at` が Task 6 で入るまで判定できない）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt`:

```moonbit
// 行 1 本の認定は private（かたまりになる前の、行だけの判断）。
// それを直接見たいので whitebox テスト。

///|
/// md の 1 行目だけを取り出す。
fn first_line(md : String) -> Line {
  scan_lines(md)[0]
}

///|
test "ATX 見出しは # の数を深さにする" {
  // R071
  assert_eq(atx_at("### a", first_line("### a")), Some((3, "a")))
}

///|
test "ATX 見出しの # に上限は無い" {
  // R072 R097
  assert_eq(atx_at("####### d", first_line("####### d")), Some((7, "d")))
}

///|
test "C9 ATX の閉じシーケンスと余白は落とす" {
  assert_eq(atx_at("##   b   ##", first_line("##   b   ##")), Some((2, "b")))
}

///|
test "飾り字下げ 3 までは見出しとして読む" {
  // R103
  assert_eq(atx_at("   # a", first_line("   # a")), Some((1, "a")))
}

///|
test "字下げ 4 は見出しではない" {
  // R105 のインデントコードの領分
  assert_eq(atx_at("    # a", first_line("    # a")), None)
}

///|
test "# の直後に空白が無ければ見出しではない" {
  assert_eq(atx_at("#foo", first_line("#foo")), None)
}

///|
test "空ラベルの見出しも読む" {
  assert_eq(atx_at("## ", first_line("## ")), Some((2, "")))
}

///|
test "箇条書きは印の列と中身の列とラベルを返す" {
  assert_eq(bullet_at("- x", first_line("- x")), Some((0, 2, "x")))
}

///|
test "字下げた箇条書きは列がずれる" {
  assert_eq(bullet_at("  - x", first_line("  - x")), Some((2, 4, "x")))
}

///|
test "* と + も読みでは箇条書き" {
  // R102。綴りは serialize が `-` に揃える
  assert_eq(bullet_at("* x", first_line("* x")), Some((0, 2, "x")))
}

///|
test "順序リストも箇条書きとして読む" {
  // R104
  assert_eq(bullet_at("1. x", first_line("1. x")), Some((0, 3, "x")))
}

///|
test "丸括弧の順序リストも読む" {
  // R104
  assert_eq(bullet_at("12) x", first_line("12) x")), Some((0, 4, "x")))
}

///|
test "印の直後に空白が無ければ箇条書きではない" {
  assert_eq(bullet_at("-x", first_line("-x")), None)
}

///|
test "3 本の水平線は箇条書きではない" {
  assert_eq(bullet_at("---", first_line("---")), None)
}

///|
test "中身の無い項目の中身の列は印 + 空白 1 つ" {
  assert_eq(bullet_at("-", first_line("-")), Some((0, 2, "")))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier atx_at is unbound.`（`bullet_at` も同じく `[4021]` で続く。`Line` / `scan_lines` は Task 4 で定義済みなので未定義にはならない）。1 本も走らない（`Total tests:` の行が出ない・EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt`:

```moonbit
// 行 → かたまり（Chunk）の並び。md の読みの全部がここに居る（木は知らない）。
//
// この層の要は Chunk.depth の定義 —「その行の字下げを飲み込んでいる、いちばん
// 内側のコンテナの深さ」であって、直前の骨格行の深さではない。旧 core の
// 単一変数 content_col はこれを表せず偽陽性を出していたので、
// **コンテナのスタック**（開いている項目の (印の列, 中身の列)）に置き換える。

///|
/// 走査の結果。行の並びだけで分かることの全部。
pub struct Scan {
  head : String? // frontmatter の封筒（逐語。改行は "\n"、末尾改行なし）
  eol : Eol // 最初に見つかった改行の流儀
  chunks : Array[Chunk] // 文書順
}

///|
/// かたまり 1 つ。**空行は落とす**（空行の本数はモデルに存在しない情報）。
pub struct Chunk {
  depth : Int // 骨格行なら自分の深さ。それ以外は「所属する構造の深さ」（文書直下は 0）
  kind : Kind
}

///|
pub enum Kind {
  Skel(Form, String) // 骨格行。form と label（深さは Chunk.depth）
  Break(Bool) // 水平線。true = 空白を 1 つも含まない `---`（トグル候補）／false = それ以外（必ず飾り）
  Fold(Bool) // true = <details> ／ false = </details>
  Body(Block) // 中身のかたまり 1 つ
}

// ---- 行 1 本の認定（どれも木もスタックも知らない） ----

///|
/// ATX 見出しなら (深さ, ラベル)。先頭空白は 3 まで、`#` の数に上限は無い。
/// 閉じシーケンス `## b ##` の `#` は落とす。
fn atx_at(text : String, l : Line) -> (Int, String)? {
  let (col, p) = indent_of(text, l)
  if col > 3 || p >= l.end || code_at(text, p) != 35 {
    return None
  }
  let mut q = p
  while q < l.end && code_at(text, q) == 35 {
    q = q + 1
  }
  // `#` の直後は空白か行末。`#foo` は見出しではない
  if q < l.end && !is_space(code_at(text, q)) {
    return None
  }
  let (a, b0) = trim_range(text, q, l.end)
  let mut b = b0
  // 閉じシーケンス: 空白に前置きされた `#` の連なりが行末まで続く形だけ
  let mut e = b
  while e > a && code_at(text, e - 1) == 35 {
    e = e - 1
  }
  if e < b && (e == a || is_space(code_at(text, e - 1))) {
    b = e
    while b > a && is_space(code_at(text, b - 1)) {
      b = b - 1
    }
  }
  Some((q - p, slice(text, a, b)))
}

///|
/// リスト項目なら (印の列, 中身の列, ラベル)。
/// `-` `*` `+` と順序リスト `1.` `1)` を読む（綴りは serialize が `-` に揃える）。
fn bullet_at(text : String, l : Line) -> (Int, Int, String)? {
  let (col, p) = indent_of(text, l)
  if p >= l.end {
    return None
  }
  let c = code_at(text, p)
  let mut q = p
  if c == 45 || c == 42 || c == 43 {
    q = p + 1
  } else if c >= 48 && c <= 57 {
    let mut d = p
    while d < l.end && code_at(text, d) >= 48 && code_at(text, d) <= 57 {
      d = d + 1
    }
    // 番号は 9 桁まで（CommonMark）。区切りは `.` か `)`
    if d - p > 9 || d >= l.end {
      return None
    }
    let m = code_at(text, d)
    if m != 46 && m != 41 {
      return None
    }
    q = d + 1
  } else {
    return None
  }
  // 印の直後は空白か行末。`---` や `**強調**` はここで落ちる
  if q < l.end && !is_space(code_at(text, q)) {
    return None
  }
  let mut ls = q
  let mut lc = col + (q - p)
  while ls < l.end && is_space(code_at(text, ls)) {
    lc = if code_at(text, ls) == 9 { lc + 4 - lc % 4 } else { lc + 1 }
    ls = ls + 1
  }
  // 中身が空の項目の中身の列は「印 + 空白 1 つ」と決める
  if ls >= l.end {
    lc = col + (q - p) + 1
  }
  let (a, b) = trim_range(text, ls, l.end)
  Some((col, lc, slice(text, a, b)))
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 54 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**80 桁を超える行は `fmt doc` が展開する。展開後の姿でコミットする。**／`Scan` / `Chunk` / `Break` / `Fold` / `Body` はまだ誰も作らないので `never constructed` の警告が並ぶが、ビルドは止まらない。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/scan.mbt core/doc/scan_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 見出しと項目の行を認定する"
```

---

## Task 6: 水平線と setext の行、そして `- - -` の裁定

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt`（`bullet_at` の中へ guard を 1 つ挿し、末尾へ `break_at` / `setext_at` を追記）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: Task 4 の `indent_of` / `code_at` / `is_space` / `trim_range`、Task 5 の `bullet_at`
- Produces:
  - `fn break_at(text : String, l : Line, base : Int) -> Int` — 水平線の印の文字コード（`-`=45 / `*`=42 / `_`=95）。違えば 0。**同じ印が、空白を挟んでもよいので 3 つ以上**
  - `fn setext_at(text : String, l : Line, base : Int) -> Int` — setext の下線の深さ（`=` は 1、`-` は 2）。違えば 0
  - `bullet_at` の意味の変更: **水平線の行はもう箇条書きではない**（`- - -` を含む）

**カバーする要件:** R080・R081（`---` と `***` の 2 チャンネル）、R095（setext を読む）、R103（飾り字下げ）。**裁定 2**（`- - -` は CommonMark どおりの飾りの水平線。旧 core の「前から箇条書き」方言は捨てる）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt` の末尾へ追記:

```moonbit
///|
test "`---` はトグルのチャンネル" {
  // R080
  assert_eq(break_at("---", first_line("---"), 0), 45)
}

///|
test "`***` と `___` は飾りのチャンネル" {
  // R081
  assert_eq(
    (
      break_at("***", first_line("***"), 0),
      break_at("___", first_line("___"), 0),
    ),
    (42, 95),
  )
}

///|
test "水平線は 3 本未満では成立しない" {
  assert_eq(break_at("--", first_line("--"), 0), 0)
}

///|
test "水平線かどうかは中身の列から数える" {
  // R103。中身の列より 4 つ下がればインデントコード、上げれば水平線
  assert_eq(
    (
      break_at("    ---", first_line("    ---"), 0),
      break_at("    ---", first_line("    ---"), 4),
    ),
    (0, 45),
  )
}

///|
test "setext の下線は = が深さ 1、- が深さ 2" {
  // R095
  assert_eq(
    (
      setext_at("===", first_line("==="), 0),
      setext_at("---", first_line("---"), 0),
    ),
    (1, 2),
  )
}

///|
test "`- - -` は水平線であって箇条書きではない" {
  // 裁定 2。CommonMark どおり。旧 core の「前から箇条書き」方言は捨てた
  assert_eq(bullet_at("- - -", first_line("- - -")), None)
  assert_eq(break_at("- - -", first_line("- - -"), 0), 45)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier break_at is unbound.`（`setext_at` も同じ）。1 本も走らない（EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

**(a) `bullet_at` に guard を 1 つ挿す。** `let c = code_at(text, p)` の**次の行**に、次の 3 行を挿入する:

```moonbit
  if break_at(text, l, col) != 0 {
    return None
  }
```

挿入後の該当箇所は次の姿になる（前後の文脈込み）:

```moonbit
  let c = code_at(text, p)
  // 裁定 2。`- - -` も `***` も CommonMark の thematic break であって
  // 箇条書きではない。base はこの行自身の字下げ（自分の列から数える）
  if break_at(text, l, col) != 0 {
    return None
  }
  let mut q = p
  if c == 45 || c == 42 || c == 43 {
```

**(b) `scan.mbt` の末尾（`bullet_at` の後ろ）へ `break_at` と `setext_at` を追記する:**

```moonbit
///|
/// thematic break の行なら印の文字コード（`-`=45 / `*`=42 / `_`=95）。違えば 0。
/// **同じ印が、空白を挟んでもよいので 3 つ以上**（裁定 2 — `- - -` も水平線）。
/// 印と空白以外が 1 文字でも現れたら 0。行頭の空白は base 列からさらに 3 つまで。
fn break_at(text : String, l : Line, base : Int) -> Int {
  let (col, p) = indent_of(text, l)
  if col > base + 3 || p >= l.end {
    return 0
  }
  let c = code_at(text, p)
  if c != 45 && c != 42 && c != 95 {
    return 0
  }
  let (a, b) = trim_range(text, p, l.end)
  let mut n = 0
  for q = a; q < b; q = q + 1 {
    let d = code_at(text, q)
    if d == c {
      n = n + 1
    } else if !is_space(d) {
      return 0
    }
  }
  if n < 3 {
    return 0
  }
  c
}

///|
/// setext の下線なら見出しの深さ（`=` は 1、`-` は 2）。違えば 0。
/// 下線は間に空白を挟めない（CommonMark）ので break_at とは別式である。
fn setext_at(text : String, l : Line, base : Int) -> Int {
  let (col, p) = indent_of(text, l)
  if col > base + 3 || p >= l.end {
    return 0
  }
  let c = code_at(text, p)
  if c != 61 && c != 45 {
    return 0
  }
  let (a, b) = trim_range(text, p, l.end)
  for q = a; q < b; q = q + 1 {
    if code_at(text, q) != c {
      return 0
    }
  }
  if c == 61 {
    1
  } else {
    2
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 60 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**80 桁を超える行は `fmt doc` が展開する。展開後の姿でコミットする。**／**Task 5 の `bullet_at` のテスト 8 本は guard を挿しても全部緑のまま**（`- x` `  - x` `* x` `1. x` `12) x` はどれも印と空白以外の文字を含むので `break_at` が 0 を返し、`-` 単独は本数が 1 で 0 を返す）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/scan.mbt core/doc/scan_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 水平線の 2 チャンネルと setext を認定する"
```

---

## Task 7: フェンス・畳み・封筒の行

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt`（末尾へ追記）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: Task 4 の `scan_lines` / `indent_of` / `trim_range` / `trimmed_span` / `slice` / `dedent` / **`is_blank`**（封筒の「中身の形」を見る）
- Produces:
  - `fn fence_open(text : String, l : Line, base : Int) -> (Int, Int)?`（印の文字コード, 本数）
  - `fn fence_close_len(text : String, l : Line, ch : Int, base : Int) -> Int`
  - `fn is_tag(text : String, l : Line, tag : String) -> Bool`
  - `fn is_summary(text : String, l : Line) -> Bool`
  - `fn is_head_marker(text : String, l : Line) -> Bool`
  - `fn scan_head(text : String, lines : Array[Line]) -> (String, Int)?` — **逐語と「次に走査を始める行の添字」。逐語の改行は必ず `"\n"`、末尾改行を含まない、`\r` を含まない**（正誤表 §A-7 前提 1 の履行者は T1）。**封筒と認めるのは「直後が空行でなく、かつ閉じの `---` がある」ときだけ**（裁定 E）

**カバーする要件:** R088・R089（フェンス）、R083〜R086（details と summary の綴り）、R107（手書き summary の材料）、R108（封筒は逐語で切り出す）、R109（閉じが無ければ封筒ではない）。カタログ C11。**裁定 E**（文書頭の `---` の裁定 — 仕様 §4 の frontmatter の行）。

**裁定 E（封筒の「中身の形」）:** 仕様 §4 はこう書く —

> 文書頭の `---` が封筒の開きなのは、**直後が空行でなく、かつ閉じの `---` があるとき**。
> 該当しなければ先頭トグル（左開始）と読む — mmm が書く先頭トグルは空行規律により
> 必ず直後が空行になるので、両者は綴りで分かれる。

閉じの有無だけで裁定すると、**先頭トグルで始まり、あとにもう 1 本トグルを持つ文書**（serialize が
「doc.children[0] が implied root で、その先頭スロットが左」の木に書く綴り）を読み直したときに、
1 本目から 2 本目までが丸ごと head に飲まれて木が消える。この木は `check` を 1 つも破らないので
T4 Task 33 のファズが普通に生成し（seed 199）、`---` + `## a` の実文書に move で兄弟を 1 つ足すだけで
製品としても再現する。`scan_head` の guard に条件を 1 つ足すだけで塞がり、**既存の期待値は 1 つも動かない**。

**`scan` への結線は Task 8 で行う**（`scan` は Task 8 で生まれるので、その初版に封筒が入った姿で書く。**Task 9 には残さない**）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt` の末尾へ追記:

```moonbit
///|
test "フェンスは印と本数を返す" {
  // R088
  assert_eq(fence_open("```ts", first_line("```ts"), 0), Some((96, 3)))
}

///|
test "チルダのフェンスも読む" {
  assert_eq(fence_open("~~~~", first_line("~~~~"), 0), Some((126, 4)))
}

///|
test "バッククォートのフェンスは情報文字列にバッククォートを許さない" {
  assert_eq(fence_open("``` a ` b", first_line("``` a ` b"), 0), None)
}

///|
test "閉じフェンスは開きと同じ本数以上で閉じる" {
  assert_eq(fence_close_len("````", first_line("````"), 96, 0), 4)
}

///|
test "閉じフェンスに情報文字列は書けない" {
  assert_eq(fence_close_len("``` ts", first_line("``` ts"), 96, 0), 0)
}

///|
test "details の開閉は行ちょうどで認定する" {
  // R083
  assert_eq(
    (
      is_tag("<details>", first_line("<details>"), "<details>"),
      is_tag("<details open>", first_line("<details open>"), "<details>"),
    ),
    (true, false),
  )
}

///|
test "summary の行は認定できる" {
  // R107 の材料。読み捨てるかどうかは Task 9 が決める
  assert_eq(
    (
      is_summary("<summary>r</summary>", first_line("<summary>r</summary>")),
      is_summary("summary", first_line("summary")),
    ),
    (true, false),
  )
}

///|
test "C11 封筒は逐語と次の行の添字を返す" {
  // R108
  let md = "---\nk: v\n---\n\n# r\n"
  assert_eq(scan_head(md, scan_lines(md)), Some(("---\nk: v\n---", 3)))
}

///|
test "CRLF の封筒は \\n に畳んで持つ" {
  // 逐語に \r を残すと serialize が行末に積み、parse のたびに文書が伸びる
  // （法則 2 が破れる）。正誤表 §A-7 前提 1
  let md = "---\r\nk: v\r\n---\r\n\r\n# r\r\n"
  assert_eq(scan_head(md, scan_lines(md)), Some(("---\nk: v\n---", 3)))
}

///|
test "閉じない封筒は封筒ではない" {
  // R109。先頭の `---` は区切りに戻る
  let md = "---\n\n# r\n"
  assert_eq(scan_head(md, scan_lines(md)), None)
}

///|
test "先頭が `---` でなければ封筒ではない" {
  let md = "# r\n"
  assert_eq(scan_head(md, scan_lines(md)), None)
}

///|
test "開き `---` の直後が空行なら封筒ではない（先頭トグル）" {
  // 裁定 E。仕様 §4 の frontmatter の行 —「文書頭の `---` が封筒の開きなのは、
  // 直後が空行でなく、かつ閉じの `---` があるとき」。
  // 先頭トグルの直後には serialize が空行規律で必ず空行を挟むので、
  // ここを封筒と読むと 2 本目のトグルまでが丸ごと head に飲まれ、
  // 木が消えて法則 1 が破れる
  let md = "---\n\n## a\n\n---\n\n## b\n"
  assert_eq(scan_head(md, scan_lines(md)), None)
}

///|
test "直後が空行でなければ、途中に空行があっても封筒のまま" {
  // 裁定 E の裏側。見るのは 2 行目だけなので、YAML の途中の空行は封筒に残る
  //（T3 Task 20 の head の実例と同じ形）
  let md = "---\nk: v\n\nx: 1\n---\n\n# r\n"
  assert_eq(scan_head(md, scan_lines(md)), Some(("---\nk: v\n\nx: 1\n---", 5)))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier fence_open is unbound.`（`fence_close_len` / `is_tag` / `is_summary` / `scan_head` も同じ）。1 本も走らない（EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt` の末尾（`setext_at` の後ろ）へ追記:

```moonbit
///|
/// 行の中身が tag ちょうどか（`<details>` / `</details>` の認定）。
fn is_tag(text : String, l : Line, tag : String) -> Bool {
  let (a, b) = trimmed_span(text, l)
  b - a == tag.length() && slice(text, a, b) == tag
}

///|
/// `<summary>` で始まる行か。serialize が label から作り直す装飾。
/// **読み捨てるのは details の直後の 1 行だけ**（裁定 7。判断は駆動部が持つ）。
fn is_summary(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  b - a >= 9 && slice(text, a, a + 9) == "<summary>"
}

///|
/// ちょうど 3 本の `-` だけの行か（frontmatter の delimiter）。
fn is_head_marker(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  b - a == 3 &&
  code_at(text, a) == 45 &&
  code_at(text, a + 1) == 45 &&
  code_at(text, a + 2) == 45
}

///|
/// 先頭の封筒を読む。逐語と「次に走査を始める行の添字」を返す。
/// 先頭が `---` でない / **直後が空行** / 閉じが無い なら None
///（そのときの先頭の `---` は区切り = 先頭トグルに戻る）。
/// **逐語は行ごとに `\r` を落として `"\n"` で綴じる** — 原文をそのまま切ると
/// CRLF 文書の head に `\r` が残り、serialize が毎回 1 文字ずつ積む（法則 2 の破れ）。
fn scan_head(text : String, lines : Array[Line]) -> (String, Int)? {
  if lines.length() == 0 || !is_head_marker(text, lines[0]) {
    return None
  }
  // 中身の形（裁定 E。仕様 §4 の frontmatter の行）。開き `---` の直後が
  // 空行なら封筒ではない — serialize は先頭トグルの直後に必ず空行を挟むので、
  // これで「先頭トグル + もう 1 本のトグル」を封筒と誤読しなくなる。
  // 見るのは 2 行目だけなので、YAML の途中の空行は封筒の中に残せる
  if lines.length() < 2 || is_blank(text, lines[1]) {
    return None
  }
  for i = 1; i < lines.length(); i = i + 1 {
    if is_head_marker(text, lines[i]) {
      let sb = StringBuilder::new()
      for j = 0; j <= i; j = j + 1 {
        if j > 0 {
          sb.write_string("\n")
        }
        sb.write_string(dedent(text, lines[j], 0))
      }
      return Some((sb.to_string(), i + 1))
    }
  }
  None
}

///|
/// 開きフェンスなら (印の文字コード, 本数)。3 本以上、base 相対で 3 まで字下げ可。
fn fence_open(text : String, l : Line, base : Int) -> (Int, Int)? {
  let (col, p) = indent_of(text, l)
  if col > base + 3 || p >= l.end {
    return None
  }
  let c = code_at(text, p)
  if c != 96 && c != 126 {
    return None
  }
  let mut q = p
  while q < l.end && code_at(text, q) == c {
    q = q + 1
  }
  let len = q - p
  if len < 3 {
    return None
  }
  // バッククォートのフェンスは情報文字列にバッククォートを含めない
  if c == 96 {
    for r = q; r < l.end; r = r + 1 {
      if code_at(text, r) == 96 {
        return None
      }
    }
  }
  Some((c, len))
}

///|
/// 閉じフェンスの本数。閉じでなければ 0（同種・開き以上の本数・後ろは空白のみ）。
fn fence_close_len(text : String, l : Line, ch : Int, base : Int) -> Int {
  let (col, p) = indent_of(text, l)
  if col > base + 3 {
    return 0
  }
  let mut q = p
  while q < l.end && code_at(text, q) == ch {
    q = q + 1
  }
  let len = q - p
  if len < 3 {
    return 0
  }
  while q < l.end {
    if !is_space(code_at(text, q)) {
      return 0
    }
    q = q + 1
  }
  len
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
```
Expected: 最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 73 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**80 桁を超える行は `fmt doc` が展開する。展開後の姿でコミットする。**／`setext_at` と `is_summary` はまだ駆動部が呼ばないので `Warning (unused_value)` が出るが、ビルドは止まらない（Task 9 で使う）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/scan.mbt core/doc/scan_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ フェンス・details・封筒を認定する"
```

---

## Task 8: かたまりの駆動 — コンテナのスタック

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt`（末尾へ駆動部を追記）
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt`（**仮置き `classify` 1 本だけ**。所有者は T2 で、T2 が Modify で本実装に差し替える。**T2 は Create しない**）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: Task 5〜7 の述語すべて、Task 4 の `scan_lines` / `eol_of` / `indent_of` / `is_blank` / `dedent` / `code_at` / `is_space` / `trimmed_span`、Task 2 の `esc`
- Produces:
  - `pub fn scan(md : String) -> Scan` — **T2 の `build` の唯一の入口**。封筒の結線・インデントコードの読み・水平線の 2 チャンネルはこの初版で入っている
  - `pub fn classify(text : String) -> Block`（仮置き。常に `Opaque(text)`）
  - `fn chunks_sig(md : String) -> String` / `fn body_text(md : String, at : Int) -> String`（`scan_wbtest.mbt`）

**カバーする要件:** R037・R038（見出しは絶対記法・リストは相対記法）、R051（doc は深さ 0）、R052・R053（深さ = level の全域一致）、R054（level は無制限）、R057（top-level の Item は深さ 1 の root）、R091（空行はモデルに残らない）、R105（インデントコードは読める）、R080・R081（2 チャンネル）、R108（封筒）。カタログ C6・C8・C9・C11・C15。**裁定 2**（駆動部は `break_at` を `bullet_at` より先に見る）／**裁定 5**（`chunks_sig` は Body の中身を展開しない）。

**このタスクの核心:** `Chunk.depth` は「その行の字下げを飲み込んでいる、いちばん内側のコンテナの深さ」。旧 `parser.mbt` の単一変数 `content_col` はこれを表せず、`- a` の後に列 0 の散文が来ても content indent が残り `    ---` を区切りと読む偽陽性を出していた。`settle` がその根を断つ。

**`chunks_sig` は Body を `body` とだけ出す**（裁定 5）。これで T2 が `classify` を本実装しても T1 のテストは 1 本も落ちない。**`body_text` で Body の中身を覗いてよいのは、本実装でも `Opaque` のまま残る散文だけである**（インデントコード・フェンス・画像・リンクは T2 の `classify` が `Content` にするので、覗くと T2 の統合で落ちる）。**T2 は `scan_wbtest.mbt` を触らない。**

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt` の末尾へ追記:

```moonbit
///|
/// かたまりの並びを 1 本の文字列に畳む（深さ + 種別）。
/// **Body の中身は展開しない**（裁定 5 — T2 が classify を本実装しても
/// この期待値は動かない）。中身が要るところは body_text で見る。
fn chunks_sig(md : String) -> String {
  let sc = scan(md)
  let sb = StringBuilder::new()
  for c in sc.chunks {
    sb.write_string(c.depth.to_string())
    match c.kind {
      Skel(Heading, label) => {
        sb.write_string("H:")
        sb.write_string(esc(label))
      }
      Skel(Item, label) => {
        sb.write_string("I:")
        sb.write_string(esc(label))
      }
      Break(dash) => sb.write_string(if dash { "B-" } else { "B*" })
      Fold(open) => sb.write_string(if open { "F+" } else { "F-" })
      Body(_) => sb.write_string("body")
    }
    sb.write_string("|")
  }
  sb.to_string()
}

///|
/// at 番目のかたまりの逐語。**散文（T2 が本実装しても Opaque のまま残る形）にだけ使う** —
/// コード・画像・リンク・svg は classify が Content にするので、ここで覗くと T2 の
/// 統合で落ちる。「字下げをどこまで落として持つか」の固定はこの 1 本で足りる。
fn body_text(md : String, at : Int) -> String {
  match scan(md).chunks[at].kind {
    Body(Opaque(t)) => t
    _ => abort("Body(Opaque) ではない")
  }
}

///|
test "空文書はかたまりを 1 つも作らない" {
  assert_eq(chunks_sig(""), "")
}

///|
test "C6 見出しの飛びは深さの飛びとして出る" {
  // R052 R053
  assert_eq(chunks_sig("# r\n\n## a\n\n#### b\n"), "1H:r|2H:a|4H:b|")
}

///|
test "見出しは 7 個以上の # も深さとして読む" {
  // R054
  assert_eq(chunks_sig("####### deep\n"), "7H:deep|")
}

///|
test "C9 閉じシーケンスと余白は落として読む" {
  assert_eq(chunks_sig("##   b   ##\n"), "2H:b|")
}

///|
test "C15 項目の root と中身の列のトグルが深さで分かれる" {
  // R057 R038
  assert_eq(
    chunks_sig("- center\n\n  - a\n\n  - b\n\n  ---\n\n  - c\n"),
    "1I:center|2I:a|2I:b|1B-|2I:c|",
  )
}

///|
test "入れ子の字下げは深さになり、戻れば兄弟になる" {
  // R038。相対記法 — 前の項目より深ければ子、浅ければ戻る
  assert_eq(chunks_sig("- a\n  - b\n- c\n"), "1I:a|2I:b|1I:c|")
}

///|
test "順序リストも構造として読む" {
  // R104
  assert_eq(chunks_sig("1. x\n2) y\n"), "1I:x|1I:y|")
}

///|
test "見出しはリストの入れ子を断ち切る" {
  // R037。見出しは絶対記法なので、来た瞬間に項目のスタックが空になる
  assert_eq(chunks_sig("- a\n  - b\n\n# h\n\n- c\n"), "1I:a|2I:b|1H:h|2I:c|")
}

///|
test "列 0 に戻った散文は項目の領土を閉じる" {
  // 旧 core の単一変数 content_col が表せず、`    ---` を区切りと誤っていた形
  assert_eq(chunks_sig("- a\n\nprose\n\n    ---\n"), "1I:a|0body|0body|")
}

///|
test "フェンスの中の見出しは構造にならない" {
  assert_eq(chunks_sig("# a\n\n```\n## inside\n```\n"), "1H:a|1body|")
}

///|
test "閉じないフェンスは文書末まで飲み込む" {
  assert_eq(chunks_sig("# a\n\n```\n## inside\n"), "1H:a|1body|")
}

///|
test "水平線は 2 つのチャンネルに分かれ、`- - -` は飾りへ落ちる" {
  // R080 R081。裁定 2
  assert_eq(chunks_sig("# a\n\n---\n\n***\n\n- - -\n"), "1H:a|1B-|1B*|1B*|")
}

///|
test "C8 details の開閉はかたまりとして出る" {
  assert_eq(
    chunks_sig("# r\n\n## a\n\n<details>\n\n### b\n\n</details>\n"),
    "1H:r|2H:a|2F+|3H:b|3F-|",
  )
}

///|
test "空行は落ちるので本数はモデルに残らない" {
  // R091
  assert_eq(chunks_sig("# a\n\n\n\n## b\n"), chunks_sig("# a\n\n## b\n"))
}

///|
test "CRLF でも同じかたまりに落ちる" {
  // R093。流儀はダイヤルで持ち、かたまりは同じ
  assert_eq(chunks_sig("# a\r\n\r\n## b\r\n"), chunks_sig("# a\n\n## b\n"))
}

///|
test "散文は 1 つのかたまりに畳まれる" {
  assert_eq(chunks_sig("# a\n\none\ntwo\n"), "1H:a|1body|")
}

///|
test "項目の中身の散文は中身の列まで字下げを落として持つ" {
  // 散文は T2 が classify を本実装しても Opaque のままなので body_text で覗いてよい
  assert_eq(body_text("- a\n\n  text\n", 1), "text")
}

///|
test "C9 インデントコードは 1 つのかたまりとして溜まる" {
  // R105。構造の認定は一切しない。**中身の綴りは T2 の classify が決める**ので、
  // ここでは「4 スペースの行が Body 1 つに畳まれる」ことだけを見る
  //（body_text で覗くと T2 Task 11 が classify を本実装した瞬間に
  //  Opaque でなくなって落ちる）。字下げを保ったまま渡していることは
  //  T2 Task 17 の md_sig("# r\n\n    code\n") が固定する
  assert_eq(chunks_sig("# r\n\n    code\n"), "1H:r|1body|")
}

///|
test "C11 封筒は逐語で切り出され、木には出ない" {
  // R108
  let sc = scan("---\nimage-folder: img\n---\n\n# r\n\n## a\n")
  assert_eq(sc.head, Some("---\nimage-folder: img\n---"))
}

///|
test "C11 封筒の後ろの行はふつうに読む" {
  assert_eq(chunks_sig("---\nimage-folder: img\n---\n\n# r\n\n## a\n"), "1H:r|2H:a|")
}

///|
test "閉じない封筒は封筒ではない" {
  // R109。先頭の `---` は区切りに戻る
  assert_eq(scan("---\n\n# r\n").head, None)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 1 行目 `Error: [4021]`、本文 `The value identifier scan is unbound.`。1 本も走らない（EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt`（新規。**T2 の持ち物の足場**）:

```moonbit
// 逐語のかたまりを Block にする層。**この仮置きは T1 が置いた足場**で、
// 認定の中身（Image / Link / Code / Svg）は T2 が Modify で入れる。
// このファイルを Create するのは T1 だけである（正誤表 §B-1）。

///|
/// 逐語のかたまり 1 つを Block にする。**疑わしきは Opaque**。
pub fn classify(text : String) -> Block {
  Opaque(text)
}
```

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt` の末尾（`fence_close_len` の後ろ）へ追記:

```moonbit
// ---- 駆動部。コンテナのスタックを回しながら行をかたまりへ落とす ----

///|
/// 走査の途中の状態。開いている項目のスタックと、溜めている逐語の行。
priv struct Sc {
  chunks : Array[Chunk]
  items : Array[(Int, Int)] // (印の列, 中身の列)
  mut head_depth : Int
  buf : Array[String] // 溜めている逐語の行
  mut buf_depth : Int
  mut buf_code : Bool // 溜めているのがインデントコードか
}

///|
/// 溜めた逐語を 1 つの Body として吐く。
fn flush(sc : Sc) -> Unit {
  if sc.buf.length() == 0 {
    sc.buf_code = false
    return
  }
  let sb = StringBuilder::new()
  for i = 0; i < sc.buf.length(); i = i + 1 {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(sc.buf[i])
  }
  sc.chunks.push({ depth: sc.buf_depth, kind: Body(classify(sb.to_string())) })
  sc.buf.clear()
  sc.buf_code = false
}

///|
/// col の行が居られない項目を閉じ、残った項目の中身の列を返す。
/// **字下げが浅くなった時点でその項目の領土は終わる** — 旧 core が単一変数で
/// 表せず、`- a` のあとの列 0 の散文でも領土が残っていた偽陽性の根。
fn settle(sc : Sc, col : Int) -> Int {
  while sc.items.length() > 0 && col < sc.items[sc.items.length() - 1].1 {
    ignore(sc.items.unsafe_pop())
  }
  if sc.items.length() > 0 {
    sc.items[sc.items.length() - 1].1
  } else {
    0
  }
}

///|
/// いま開いているコンテナの深さ（Body・Break・Fold の所属先）。
fn owner_depth(sc : Sc) -> Int {
  sc.head_depth + sc.items.length()
}

///|
/// 逐語の 1 行を溜める。所属か種別が変わっていたら先に吐く。
fn keep(
  sc : Sc,
  text : String,
  l : Line,
  base : Int,
  depth : Int,
  code : Bool,
) -> Unit {
  if sc.buf.length() > 0 && (sc.buf_depth != depth || sc.buf_code != code) {
    flush(sc)
  }
  sc.buf_depth = depth
  sc.buf_code = code
  sc.buf.push(dedent(text, l, base))
}

///|
/// 行から区間へ。**md の読みの全部がここに居る**（木は知らない）。
pub fn scan(md : String) -> Scan {
  let lines = scan_lines(md)
  let eol = eol_of(md)
  // 封筒は行走査より先に決める。中は解釈しないので走査はその次の行から
  let (head, first) = match scan_head(md, lines) {
    Some((h, next)) => (Some(h), next)
    None => (None, 0)
  }
  let sc = {
    chunks: [],
    items: [],
    head_depth: 0,
    buf: [],
    buf_depth: 0,
    buf_code: false,
  }
  // フェンスの区間。中の `#` は見出しではない
  let mut in_fence = false
  let mut fence_ch = 0
  let mut fence_len = 0
  let mut fence_base = 0
  let mut idx = first
  while idx < lines.length() {
    let l = lines[idx]
    idx = idx + 1
    if in_fence {
      sc.buf.push(dedent(md, l, fence_base))
      if fence_close_len(md, l, fence_ch, fence_base) >= fence_len {
        flush(sc)
        in_fence = false
      }
      continue
    }
    if is_blank(md, l) {
      flush(sc)
      continue
    }
    let (col, _) = indent_of(md, l)
    let base = settle(sc, col)
    let depth = owner_depth(sc)
    // 中身の列から 4 つ以上下がった行はインデントコード。
    // 構造の認定は一切せず、逐語のまま溜める（綴りは classify が読む）
    if col - base >= 4 {
      keep(sc, md, l, base, depth, true)
      continue
    }
    if sc.buf_code {
      flush(sc)
    }
    match fence_open(md, l, base) {
      Some((c, n)) => {
        flush(sc)
        in_fence = true
        fence_ch = c
        fence_len = n
        fence_base = base
        sc.buf_depth = depth
        sc.buf.push(dedent(md, l, base))
        continue
      }
      None => ()
    }
    match atx_at(md, l) {
      Some((d, label)) => {
        flush(sc)
        sc.head_depth = d
        sc.items.clear()
        sc.chunks.push({ depth: d, kind: Skel(Heading, label) })
        continue
      }
      None => ()
    }
    // **break を bullet より先に見る**（裁定 2）。`- - -` は飾りの水平線
    let bc = break_at(md, l, base)
    if bc != 0 {
      flush(sc)
      // 空白を 1 つも含まない `---` だけがトグルの候補。他は必ず飾り
      let (a, b) = trimmed_span(md, l)
      let mut hard = bc == 45
      for q = a; q < b; q = q + 1 {
        if is_space(code_at(md, q)) {
          hard = false
        }
      }
      sc.chunks.push({ depth, kind: Break(hard) })
      continue
    }
    match bullet_at(md, l) {
      Some((mc, cc, label)) => {
        flush(sc)
        sc.items.push((mc, cc))
        sc.chunks.push({ depth: owner_depth(sc), kind: Skel(Item, label) })
        continue
      }
      None => ()
    }
    if is_tag(md, l, "<details>") {
      flush(sc)
      sc.chunks.push({ depth, kind: Fold(true) })
      continue
    }
    if is_tag(md, l, "</details>") {
      flush(sc)
      sc.chunks.push({ depth, kind: Fold(false) })
      continue
    }
    keep(sc, md, l, base, depth, false)
  }
  flush(sc)
  { head, eol, chunks: sc.chunks }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core
```
Expected: 新パッケージは最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 94 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**80 桁を超える行は `fmt doc` が展開する。展開後の姿でコミットする。**／**旧 core（`-p mmm-app/core`）は `Total tests: 192, passed: 192, failed: 0.` のまま無傷**（こちらは T1 だけのパッケージではないので絶対数で固定する）。`setext_at` / `is_summary` の `unused_value` はまだ残る（Task 9 で消える）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/scan.mbt core/doc/block.mbt core/doc/scan_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ かたまりの駆動をコンテナのスタックで書く"
```

**このコミットが T2 Task 12〜17 の着手条件である。**

---

## Task 9: 方言の仕上げ — 項目の領土・setext・summary

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan.mbt`（**`atx_writable` の追記 1 か所 + 局所的な Edit 3 か所**。`scan` の全文差し替えは禁止）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: Task 8 の `scan` / `Sc` / `flush` / `keep`、Task 6 の `setext_at`、Task 7 の `is_summary`、Task 4 の `code_at` / `is_space`
- Produces:
  - `fn atx_writable(s : String) -> Bool` — その文字列を ATX の骨格行として書き戻せるか（setext の認定の門番）。**正誤表 §C-3 の表に無い名前なので、着手前に §C-3 の T1 `scan.mbt` の行へ足して全員へ共有する**（§C はパッケージ内でトップレベルの名前が一意であることを執行する唯一の根拠。二重定義は `Error: [4051]` でテストが 1 本も走らなくなる）
  - **`scan` のシグネチャの変更は無い。** 読みが 3 点変わる —
    ① 項目の領土の中の ATX 見出しは構造にならず `Body` へ落ちる
    ② 段落の直後の `===` / `---` は setext 見出しとして `Skel(Heading, …)` になる（**ATX で書き戻せる行だけ**）
    ③ `<details>` の直後の `<summary>` 行だけを読み捨てる（**本文の `<summary>` は消さない**）

**カバーする要件:** R040・R101（項目の領土内の見出しは Opaque）、R039（単調性の parse 側の担保）、R095（setext を読む）、R065（法則 4 の材料 — 多行段落の setext は最終行だけが見出しになる）、**R107（手書き summary を parse は無視する）**。カタログ C9。**裁定 7**（summary の読み捨ては details の直後だけに限定する — 本文の消失を防ぐ）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/scan_wbtest.mbt` の末尾へ追記:

```moonbit
///|
test "項目の領土の中の見出しは Opaque になる" {
  // R040 R101。絶対記法を相対容器に入れると level が嘘になる
  assert_eq(chunks_sig("- a\n\n  # h\n"), "1I:a|1body|")
}

///|
test "C9 setext の下線は見出しとして読む" {
  // R095。`---` は break より先にここで捕まる
  assert_eq(chunks_sig("# r\n\na\n---\n"), "1H:r|2H:a|")
}

///|
test "多行の段落の setext は最終行だけが見出しになる" {
  // R065。label は 1 行の文字列なので段落全体を中身にできない。
  // 残りは Opaque で残るので意味は失われない（R001）。
  // CommonMark との差分は T4 Task 36 の方言表が持つ
  assert_eq(chunks_sig("# r\n\none\ntwo\n---\n"), "1H:r|1body|2H:two|")
}

///|
test "ATX で書き戻せない行は setext にしない" {
  // 前後空白・末尾の `#` は再読みで消える（法則 1・2 が破れる）ので段落のまま残す。
  // **このテストは Task 8 の実装でも通る**（(b) の素朴な実装を止める見張り）
  assert_eq(chunks_sig("# r\n\n  a  \n---\n"), "1H:r|1body|1B-|")
}

///|
test "details の直後の summary は読み捨てる" {
  // R107。serialize が label から作り直す装飾
  assert_eq(
    chunks_sig("# r\n\n<details>\n<summary>r</summary>\n\n</details>\n"),
    "1H:r|1F+|1F-|",
  )
}

///|
test "本文の summary は消えない" {
  // 裁定 7。読み捨てを details の直後に限らないと、本文が黙って消える。
  // **このテストは Task 8 の実装でも通る**（回帰の見張りとして先に置く）
  assert_eq(chunks_sig("# r\n\n<summary>x</summary>\n"), "1H:r|1body|")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: **コンパイルは通る**（6 本とも既存の関数しか使わない）。最終行 `Total tests: N, passed: N-4, failed: 4.`（EXIT=2）。落ちるのは次の 4 本で、`assert_eq` が実際の値との差を出す:

| テスト | 実際 | 期待 |
|---|---|---|
| 項目の領土の中の見出しは Opaque になる | `"1I:a|1H:h|"` | `"1I:a|1body|"` |
| C9 setext の下線は見出しとして読む | `"1H:r|1body|1B-|"` | `"1H:r|2H:a|"` |
| 多行の段落の setext は最終行だけが見出しになる | `"1H:r|1body|1B-|"` | `"1H:r|1body|2H:two|"` |
| details の直後の summary は読み捨てる | `"1H:r|1F+|1body|1F-|"` | `"1H:r|1F+|1F-|"` |

残る 2 本（「ATX で書き戻せない行は setext にしない」「本文の summary は消えない」）は Task 8 の実装でも通る。**通っているから不要なのではない** — 前者は (b) を `atx_writable` 抜きで書いた瞬間に赤くなり（そのとき出る値は `"1H:r|2H:  a  |"`）、後者は (c) を「summary を無条件に捨てる」と書いた瞬間に赤くなる。どちらも Step 3 の実装を素朴に書かせないための見張りである。

- [ ] **Step 3: 最小の実装を書く**

`core/doc/scan.mbt` に**追記を 1 か所と、局所的な Edit を 3 か所**入れる。`scan` の全文差し替えはしない。

**(a) 項目の領土の中の見出しは Opaque。** `scan` の中の `match atx_at(md, l) { … }` ブロックを `if sc.items.length() == 0 { … }` で包む。

差し替え前:

```moonbit
    match atx_at(md, l) {
      Some((d, label)) => {
        flush(sc)
        sc.head_depth = d
        sc.items.clear()
        sc.chunks.push({ depth: d, kind: Skel(Heading, label) })
        continue
      }
      None => ()
    }
```

差し替え後:

```moonbit
    // 項目の領土の中の見出しは Opaque（絶対記法を相対容器に入れると
    // level が嘘になり、単調性が parse の時点で破れる）
    if sc.items.length() == 0 {
      match atx_at(md, l) {
        Some((d, label)) => {
          flush(sc)
          sc.head_depth = d
          sc.items.clear()
          sc.chunks.push({ depth: d, kind: Skel(Heading, label) })
          continue
        }
        None => ()
      }
    }
```

**(b-1) setext の門番を足す。** `setext_at` の直後（Task 7 が置いた `is_tag` の直前）へ追記する:

```moonbit
///|
/// ATX の骨格行として書き戻せる文字列か。前後に空白があると再読み時に
/// trim で消え、末尾が `#` の連なり（直前が空白）だと閉じシーケンスとして
/// 落ちる。どちらも法則 1・2 を破るので、setext と認定せず段落のまま残す。
fn atx_writable(s : String) -> Bool {
  let n = s.length()
  if n == 0 {
    return false
  }
  if is_space(code_at(s, 0)) || is_space(code_at(s, n - 1)) {
    return false
  }
  let mut e = n
  while e > 0 && code_at(s, e - 1) == 35 {
    e = e - 1
  }
  e != 0 && (e == n || !is_space(code_at(s, e - 1)))
}
```

**(b-2) setext を読む。** `scan` の中の `let bc = break_at(md, l, base)` の**直前**に、次のブロックを挿入する（`---` が break より先に setext として捕まるように、必ず break の前）:

```moonbit
    // setext は段落が開いているときだけ。`---` は break より先にここで捕まる。
    // ATX で書き戻せない行は見出しにしない（法則 1・2 を守る）
    if sc.buf.length() > 0 && sc.items.length() == 0 {
      let sd = setext_at(md, l, base)
      if sd > 0 && atx_writable(sc.buf[sc.buf.length() - 1]) {
        let label = sc.buf[sc.buf.length() - 1]
        ignore(sc.buf.unsafe_pop())
        flush(sc)
        sc.head_depth = sd
        sc.chunks.push({ depth: sd, kind: Skel(Heading, label) })
        continue
      }
    }
```

**`atx_writable` を挟まないと何が起きるか**: `  a  ` のような行が下線を得ると label が `"  a  "` のまま見出しになり、serialize は `##   a  ` を書く。それを読み直すと `atx_at` の `trim_range` が前後の空白を落として label が `"a"` に変わる — **法則 1（読み書きの往復）と法則 2（format の冪等）が同時に破れる**。`foo #` も同じで、`## foo #` の `#` は閉じシーケンスとして落ち、label が `"foo"` に変わる。T4 Task 35 の `randomMd` の LABELS にはこの形が入っており、setext 分岐は約 10% で選ばれるので、門番が無いと 600 seed のファズで必ず赤になる。

**(c) summary の読み捨ては details の直後だけ。** 次の 4 点を入れる。

(c-1) `priv struct Sc` の `mut buf_code : Bool` の直後へ 1 行:

```moonbit
  mut after_fold : Bool // 直前に積んだかたまりが <details> か（裁定 7）
```

(c-2) `scan` の中の `sc` のリテラルへ 1 行足す。差し替え前:

```moonbit
  let sc = {
    chunks: [],
    items: [],
    head_depth: 0,
    buf: [],
    buf_depth: 0,
    buf_code: false,
  }
```

差し替え後:

```moonbit
  let sc = {
    chunks: [],
    items: [],
    head_depth: 0,
    buf: [],
    buf_depth: 0,
    buf_code: false,
    after_fold: false,
  }
```

(c-3) `scan` の中の `let depth = owner_depth(sc)` の**直後**へ 4 行を挿入する:

```moonbit
    // summary の読み捨ては <details> の直後の 1 行だけ（裁定 7）。
    // 空行では旗を落とさない（`<details>` と `<summary>` の間の空行を許す）
    let after_fold = sc.after_fold
    sc.after_fold = false
```

(c-4) `<details>` の腕で旗を立て、`keep` の直前で summary を捨てる。差し替え前:

```moonbit
    if is_tag(md, l, "<details>") {
      flush(sc)
      sc.chunks.push({ depth, kind: Fold(true) })
      continue
    }
    if is_tag(md, l, "</details>") {
      flush(sc)
      sc.chunks.push({ depth, kind: Fold(false) })
      continue
    }
    keep(sc, md, l, base, depth, false)
```

差し替え後:

```moonbit
    if is_tag(md, l, "<details>") {
      flush(sc)
      sc.chunks.push({ depth, kind: Fold(true) })
      sc.after_fold = true
      continue
    }
    if is_tag(md, l, "</details>") {
      flush(sc)
      sc.chunks.push({ depth, kind: Fold(false) })
      continue
    }
    // 開いた details の直後の summary だけが装飾。それ以外は本文である
    if after_fold && is_summary(md, l) {
      continue
    }
    keep(sc, md, l, base, depth, false)
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core check
```
Expected: 新パッケージは最終行 `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T1 の累計は 100 本**で、そのすべてが passed に入り `failed: 0` であること（N には他群のテストも含まれる）。`Total tests: 0` を見たら `-p` の綴りを疑う。／`fmt doc` が整形を当てて EXIT=0、続く `fmt --check doc` が `Finished. moon: ran N tasks, now up to date`（EXIT=0）。**80 桁を超える行は `fmt doc` が展開する。展開後の姿でコミットする。**／**旧 core（`-p mmm-app/core`）は `Total tests: 192, passed: 192, failed: 0.` のまま無傷**／check は EXIT=0。`setext_at` / `is_summary` / `atx_writable` の `unused_value` は消える。残る警告は `spell.mbt` の未使用定数（T2・T3 が使う）と `Scan` / `Chunk` の未読フィールド（T2 が読む）だけ。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/scan.mbt core/doc/scan_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 項目の領土・setext・summary の裁定を仕上げる"
```

---

## T1 完了時に他タスクへ渡るもの（申し送り）

| 渡すもの | 受け取る側 |
|---|---|
| `Tree` / `Node` / `Form` / `Side` / `Block` / `Content` / `Eol`、`is_implied` / `empty` / `promote`（Task 1） | **全員。型を変えたくなったら、書き換える前に全員へ共有すること** |
| `spell.mbt` の 11 定数（Task 1） | T2 Task 16（`fold_open` / `fold_close`）、T3 Task 20〜26（全部）。**読むだけ。作らない** |
| `sig(tree) -> String`（Task 2） | T4（法則 1 のファズ・`sig_of`）、T5（操作テスト）。綴りは正誤表 §A-4。`doc-law.test.ts` の受け口が `"head:-\nlf\n[H[Hr[Ha]]]"` で固定する |
| `check(tree) -> Array[String]`（Task 3。**11 条件**。条件 8 は裁定 B の「implied の前に見出しが居る」） | T4（`check_of`）、T5（`normalize` はこれを満たす木しか返さない。`spellable` の第 2 引数も `heading_before : Bool`） |
| `fixture_wbtest.mbt` の `node` / `heading` / `item` / `slot` / `doc_of` / `tree_of` / `chain` / `chain_tree`（Task 2） | T3（`ser(doc_of([...]))` / `chain(7)` / `chain(200)`）、T4（`chain_tree(200)`）、T5（`tree_of(...)` / `node(...)`）。**自前で定義しない**（`Error: [4051]`）。T5 Task 43 だけが `done` / `rejected` の 2 本を末尾に追記してよい |
| `lead_spaces(s : String) -> Int` / `blank_line(s : String) -> Bool`（Task 4） | T2 の `block.mbt`。**`indent_of(line : String)` / `is_blank(line : String)` を再定義しない** |
| `scan(md) -> Scan`、`Scan` / `Chunk` / `Kind`（Task 8・9） | T2 の `build` の唯一の入口 |
| `block.mbt` の仮置き `classify`（Task 8） | T2 Task 10 が**同じファイルを Modify** で本実装に差し替える（Create しない） |

**この群が確定させた読みの裁定（全員が前提にしてよい）**

1. **`- - -` は `Break(false)` = 飾りの水平線**（裁定 2）。`Break(true)` になるのは**空白を 1 つも含まない `---` だけ**。T2 の区切りの帰属規則も T4 の方言表もこれに従う
2. **`head` / `Opaque` / `Code.text` / `Svg` の逐語は、改行が `"\n"`・末尾改行なし・`\r` を含まない**（正誤表 §A-7 前提 1。履行者は T1 の `scan_head` と `dedent`）
3. **`<summary>` を落とすのは `<details>` の直後の 1 行だけ**（裁定 7）。本文の `<summary>…</summary>` は `Body` として残る
4. **項目の領土の中の ATX 見出しは構造にならない**（`Body` へ落ちる）。ただし `- a` + 列 0 の `## h` は領土の外なので `1I:a|2H:h|` を吐く — **その木の形を決めるのは T2 の `push_skel`**（裁定 A。項目を全部閉じてから飛びを implied で埋める）
5. **`Chunk.depth` は「その行の字下げを飲み込んでいる、いちばん内側のコンテナの深さ」**（骨格行だけは自分の深さ）。`build` はこれを木の深さにそのまま使ってよい
6. **setext は「ATX で書き戻せる行」だけが見出しになる**（`atx_writable`）。前後に空白がある行・末尾が空白 + `#` の行は段落のまま残る。多行の段落は**最終行だけ**が見出しになり、残りは `Body` に落ちる（R065。CommonMark との差分は T4 Task 36 の方言表が持つ）
7. **`body_text` は散文にしか使わない**。インデントコード／フェンス／画像の中身は T2 Task 10・11 の `block_wbtest.mbt` が固定する（`chunks_sig` は Body を `body` としか出さないので、T2 が `classify` を本実装しても T1 のテストは 1 本も落ちない）
8. **文書頭の `---` が封筒なのは「直後が空行でなく、かつ閉じの `---` がある」ときだけ**（裁定 E。仕様 §4 の frontmatter の行）。該当しなければ先頭トグル（左開始）として `Break(true)` に落ちる — mmm が書く先頭トグルの直後には空行規律で必ず空行が入るので、封筒と先頭トグルは綴りで一意に分かれる。**往復の固定は T4 Task 33 の法則 1 ファズ（`gen_tree` の seed 199 がこの形を吐く）、CommonMark との差分の記録は T4 Task 36 の方言表 18 行目が持つ**（T2 Task 17 の期待値はこの裁定で 1 つも動かないので、T2 に見張りは置かない）
9. **この時点で `parse` はまだ無い**（T2 の持ち物）。`scan` は木を知らないので、implied の導出・側の割り当て・区切りの帰属・畳みの対応付けはすべて T2 の `build` が行う

**実施者向けの注意（実測）**

- **掲載コードは `moon fmt` を通す前の姿である。Step 4 の `moon fmt doc` が当てた差分をそのままコミットすること**（80 桁を超える `||` 連鎖・struct リテラル・`assert_eq` は必ず折り返される）
- **`let (a, mut b) = tuple` は書けない**（`Parse error, unexpected token 'mut'`）。`let (a, b0) = …` の後に `let mut b = b0` と分ける（`atx_at` が該当）
- **`mut` を付けたフィールドを一度も書き換えないと `Error: [0015] Warning (unused_mut)` でビルドが止まる**。Task 8 の `buf_code` は `flush` と `keep` の両方で、Task 9 の `after_fold` は `scan` の 2 か所で必ず書く
- **バックスラッシュを含む MoonBit コードをシェルのヒアドキュメントで書かない**（`"\\n"` が `"\n"` に化ける）。ファイル書き込みは Write / Edit を使う
- `moon fmt` の対象は **`doc` だけ**にする。`js` を巻き込むと `core/js/moon.pkg` の `@core` が剥がされて必ず EXIT=127 になる
- `moon fmt --check` の失敗は **EXIT=127**（0 でも 1 でもない）。`moon test` の失敗は **EXIT=2**
- **`Total tests: 0` を見たら緑ではない。** `-p mmm-app/core/doc` の綴りを疑うこと（綴り間違いは EXIT=0 で「成功」する）
- `derive(Show)` は使わない（deprecated）。`derive(Debug)` は `to_string` を生やさない
- `s[i]` の型は `UInt16`（`Char` ではない）。`String::charcodes` は存在しない
- `rev_inplace` → `rev_in_place`、ArrayView の `to_array` → `to_owned`

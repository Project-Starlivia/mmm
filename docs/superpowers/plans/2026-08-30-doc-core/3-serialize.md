# T3 — serialize（Task 20〜26）

## この群の概要

**担当範囲**: 木 → 正規形の md。`core/doc/serialize.mbt` と `core/doc/serialize_wbtest.mbt` の 2 ファイルだけを書く（正誤表 §B-1 / §B-2）。`serialize` は mmm のフォーマッタそのもので、決定的・冪等（法則 2）であり、T4 の法則 1・2 と T5 の `reflect` が土台にする唯一の書き手である。

**T3 が作らないもの**（正誤表 §B / 裁定 4。以前の草稿から削除した）:

- `core/doc/spell.mbt` — **T1 Task 1 の所有物**。§A-6 の 11 定数の完全版を T1 が作る。T3 は読むだけで、1 バイトも書かない
- `core/doc/tree.mbt` / `core/doc/moon.pkg` — **T1 Task 1 の所有物**。「まだ無ければ §2 を写して着手する」は**禁止**。T1 のコミットを待つ
- `doc_of` / `chain` / `heading` / `item` / `slot` — **T1 Task 2 の `core/doc/fixture_wbtest.mbt`** にある。`*_wbtest.mbt` はパッケージ内で 1 つの名前空間を共有する（実測 2）ので、再定義は `Error: [4051] ... is declared twice` でパッケージのテストが 1 本も走らなくなる

**T3 が新しく置くトップレベル名**（正誤表 §C-3 の T3 の行のとおり。この表に無い名前を新設しない）:

`serialize.mbt` → `serialize` / `Out` / `repeat` / `indent` / `push_text` / `join_lines` / `feed` / `hashes` / `inner_pad` / `write_node` / `write_children` / `write_body` / `write_block` / `fence_len` / `write_code` / `is_left` / `write_toggle` / `open_fold` / `close_fold` / `nl_count`
`serialize_wbtest.mbt` → `ser`

> `nl_count` は §C-3 が T3 の所有名として挙げているもの。**置き場はテスト専用なので `serialize_wbtest.mbt`** にする（同じパッケージなので名前空間は共有され、衝突も二重定義も起きない。実装ファイルに実装から呼ばれない関数を置かない）。

**着手条件（依存。正誤表 §H-2）**

- Task 20 — **T1 Task 1 のコミット `feat: ✨ 新 core のパッケージと文書の木の型を置く` を待って着手する**（`moon.pkg` / `tree.mbt` / `spell.mbt` が揃う）
- Task 21〜26 — 上に加えて **T1 Task 2 のコミット `feat: ✨ 木の指紋を、手で組んだ木で確かめる` を待つ**（`fixture_wbtest.mbt` が揃う）
- T2（parse 側）は**待たない**。T3 は `tree.mbt` と `spell.mbt` にしか依存せず、Task 20 から Task 26 まで単独で完走できる

**着手順**: Task 20 → 21 → 22 → 23 → 24 → 25 → 26（1 本道。並列にしない）。

**実施者向けの注意（実測）**: 掲載コードは `moon fmt` を通す前の姿である。Step 4 の `moon fmt doc` が当てた差分をそのままコミットすること（80 桁を超える `assert_eq` や struct リテラルは必ず折り返される。文字列リテラルは折られないのでそのまま残る）。

## 統合の前提（他タスクと共有する取り決め）

1. **逐語の文字列（`Tree.head` / `Opaque` / `Code.text` / `Svg`）の改行は `"\n"` に畳んで保持し、末尾改行を含まない。`\r` を 1 つも含まない。** head も**行ごとに `\r` を落として `\n` で綴じる**（**履行者は T1 Task 7 の `scan_head`**。正誤表 §A-7 前提 1）。serialize は `tree.eol` の流儀で全行を書き戻すだけで、逐語の中身を 1 バイトも直さない。これが無いと CRLF 文書で `---\r\r\n` が出て、parse のたびに文字列が伸び、法則 2（R093）が破れる
2. **parse は `<summary>` 行を落とす**（R107）。落とすのは `<details>` の直後の 1 行だけ（裁定 7）。serialize は毎回 label から作り直す。法則 1 はこの取り決めの上に立つ
3. **`spell.mbt` の 11 定数は T1 Task 1 の所有物**（`item_mark` / `heading_mark` / `nest_step` / `fence_mark` / `fence_min` / `rule_mark` / `toggle_mark` / `fold_open` / `fold_close` / `summary_open` / `summary_close`）。綴りのリテラルはそこにしか無い。T3 は**読むだけ**
4. **`implied` は side を持たない**（不変条件 11。裁定 1）。よって serialize には「側を書く場所が無い implied」が到達せず、`write_children` の区切りの書き分けは「実在するスロットの側の列」だけを見ればよい（§A-7 規則 11）
5. `fixture_wbtest.mbt` の **`chain(n : Int) -> Node`** は「深さ 1〜n の見出しの一本鎖を返し、深さ i のノードのラベルは `i.to_string()`・id は `i + 1`」であることを前提にする。**T3 のテスト 2 本（Task 21 の `chain(7)`・Task 26 の `chain(200)`）がこの綴りに依存する。** T1 Task 2 が別の綴りを採るなら、書く前に共有すること
6. `push_text` / `fence_len` の添字操作は UTF-16 コード単位で回るが、**切る位置は必ず行境界**（直前が `\n` か文字列の端）なので `s[a:b]` のサロゲート guard（実測 8）に当たらない。行境界以外で切らないこと
7. `priv struct Out` の `mut gap` は**このパッケージ内で必ず書く**（`write_node` / `write_block` / `write_code` が書く）。書かない設計に変えると `Error: [0015] Warning (unused_mut)` でビルドが止まる（実測 3-e）
8. **見出しのラベルは、ATX の骨格行として書き戻せる形しか到達しない**（T1 Task 9 の `atx_writable`）。前後に空白のある行・末尾が `#` の連なりで終わる行は setext と認定されず段落のまま残るので、serialize が `hashes(depth) + " " + nd.label` をそのまま書いても、読み直したとき `atx_at` の `trim_range` と閉じシーケンス落としで label が変わることはない。**serialize はラベルを一切エスケープしない**（する必要が無い）。この前提が崩れると `##   leading` / `## trailing  ` が出て法則 1・2 が同時に破れる
9. **単調性は parse の attach が強制する**（裁定 A。T2 Task 13 の `push_skel` が Heading を積む前に開いている Item を全部閉じる）。よって **Heading に Item の祖先は無い** — `inner_pad` の Heading 腕が受け取った pad を捨てて列 0 を返せる根拠はこれである。`- a` + `## h` は `doc.children = [a(Item), implied(1)[h]]`（木 2 本）になり、serialize は implied root の骨格行を書かずに子を深さ 2 で書く（C17。Task 26）
10. **implied が置ける位置は「その前に見出しの兄弟が居ない」**（裁定 B。不変条件 8 の改訂。違反メッセージは `implied の前に見出しが居る: <id>`）。**先頭に限らない**ので、`write_children` が implied の手前にトグルを立てないことは、位置だけでは保証されない。保証するのは normalize の `spellable`（T5 Task 44）の 4 つ目の引き金「深さ 2 で、直前のスロットと側が違う implied は昇格させる」である。この引き金が消えると、左のスロットの次に居る implied の手前に `---` が立ち、読み直したとき帰属先の骨格行が無くて飾りの水平線に化ける

---

## Task 20: 封筒・改行・空文書

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Create）

**Interfaces:**
- Consumes: `pub struct Tree { head : String?, eol : Eol, doc : Node }` / `pub enum Eol { Lf; Crlf }` / `pub fn empty(id : Int, form : Form) -> Node` / `pub enum Form { Heading; Item }`（すべて `core/doc/tree.mbt`。T1 Task 1）
- Produces: `pub fn serialize(tree : Tree) -> String` / `priv struct Out { lines : Array[String], mut gap : Bool }` / `fn repeat(s : String, n : Int) -> String` / `fn indent(n : Int) -> String` / `fn push_text(o : Out, pad : Int, text : String) -> Unit` / `fn join_lines(lines : Array[String], eol : Eol) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt` を新規作成:

```moonbit
// serialize は正規形の綴りそのもの。木を手で組んで md 文字列と直接比べたいので
// whitebox テスト（Out や fence_len など、綴りの内側の道具も直に見る）。
// 手で木を組む道具（doc_of / heading / item / slot / chain）は fixture_wbtest.mbt
// （T1 Task 2）のものを使う。ここでは定義しない。

///|
test "封筒だけの文書は、封筒を逐語で書いて改行で終わる" {
  // R108 / C11 の書き。head は開き `---` から閉じ `---` まで（末尾改行を含まない）
  let tree : Tree = {
    head: Some("---\nimage-folder: img\n---"),
    eol: Lf,
    doc: empty(1, Heading),
  }
  assert_eq(serialize(tree), "---\nimage-folder: img\n---\n")
}

///|
test "何も無い文書は 1 バイトも書かない" {
  // R208（無操作は無編集）の土台。空の木に空行や改行を生やさない
  let tree : Tree = { head: None, eol: Lf, doc: empty(1, Heading) }
  assert_eq(serialize(tree), "")
}

///|
test "改行は原文の流儀で全行に書かれる" {
  // R093 EOL は原文の流儀を保存するダイヤル。逐語の head は "\n" 区切りで持ち、
  // 書き出しで初めて eol の流儀になる
  let tree : Tree = { head: Some("---\na: 1\n---"), eol: Crlf, doc: empty(1, Heading) }
  assert_eq(serialize(tree), "---\r\na: 1\r\n---\r\n")
}

///|
test "CRLF で書いても改行が二重にならない" {
  // 統合の前提 1 の見張り。join_lines か push_text が行末に改行を持ち込むと
  // `\r\r\n` が出て、次の parse で head が伸び続ける（法則 2 が破れる）
  let tree : Tree = {
    head: Some("---\nk: v\n\nx: 1\n---"),
    eol: Crlf,
    doc: empty(1, Heading),
  }
  assert_eq(serialize(tree).contains("\r\r"), false)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `Error: [4021]` / `The value identifier serialize is unbound.`（`Tree` / `Eol` / `empty` / `Heading` は T1 Task 1 で定義済みなので、未定義なのは `serialize` だけ）。1 本も走らない（`Total tests:` の行が出ない・EXIT=1）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt` を新規作成:

```moonbit
// 木 → 正規形の md。**mmm のフォーマッタそのもの**。決定的・冪等。
// 綴りのリテラルは持たない（spell.mbt の定数だけを使う）。

///|
/// 書き出しの途中経過。行の並びと、「直前の単位が後ろに空行を求めているか」。
priv struct Out {
  lines : Array[String]
  mut gap : Bool
}

///|
/// s を n 回つないだ文字列。
fn repeat(s : String, n : Int) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < n; i = i + 1 {
    sb.write_string(s)
  }
  sb.to_string()
}

///|
/// n 桁の字下げ。
fn indent(n : Int) -> String {
  repeat(" ", n)
}

///|
/// 逐語のかたまりを行に割って積む（空行は字下げしない）。
/// 逐語の改行は必ず "\n"・`\r` を含まない（統合の前提 1）ので、割る印は 10 だけ。
/// 切る位置は常に行境界なので、サロゲートの途中を切ることはない。
fn push_text(o : Out, pad : Int, text : String) -> Unit {
  let ind = indent(pad)
  let mut from = 0
  for i = 0; i <= text.length(); i = i + 1 {
    if i == text.length() || text[i].to_int() == 10 {
      let line = text[from:i].to_owned()
      o.lines.push(if line.length() == 0 { "" } else { ind + line })
      from = i + 1
    }
  }
}

///|
/// 行を EOL の流儀でつなぐ。空でなければ必ず改行で終わる。
fn join_lines(lines : Array[String], eol : Eol) -> String {
  if lines.length() == 0 {
    return ""
  }
  let nl = match eol {
    Lf => "\n"
    Crlf => "\r\n"
  }
  let sb = StringBuilder::new()
  for s in lines {
    sb.write_string(s)
    sb.write_string(nl)
  }
  sb.to_string()
}

///|
/// 木を正規形の md にする。
pub fn serialize(tree : Tree) -> String {
  let o : Out = { lines: [], gap: false }
  match tree.head {
    Some(h) => {
      push_text(o, 0, h)
      o.gap = true
    }
    None => ()
  }
  join_lines(o.lines, tree.eol)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
```
Expected: `Total tests: N, passed: N, failed: 0.`（N はパッケージ内の総本数で、他群のテストも含まれる。**T3 の担当分は累計 4 本**で、そのすべてが passed に入り `failed: 0` であること）。**`Total tests: 0` を見たら緑ではない — `-p` の綴りを疑う**（実測 7-1 罠 A）。`spell.mbt` の定数は T3 がまだ 1 つも使っていないので `Warning (unused_value)` が並ぶが、ビルドは止まらない。`fmt doc` は整形を当てて EXIT=0。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 封筒と改行だけを書く serialize を置く"
```

---

## Task 21: 骨格行 — 見出しと項目、implied、空行の継ぎ目

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Modify）

**Interfaces:**
- Consumes: `Out` / `repeat` / `indent` / `push_text` / `join_lines`（Task 20）／ `pub struct Node { id, form, label, implied, folded, side, body, children }` / `pub fn is_implied(nd : Node) -> Bool` / `pub fn empty(id : Int, form : Form) -> Node`（`tree.mbt`。T1 Task 1）／ `item_mark` / `heading_mark` / `nest_step`（`spell.mbt`。T1 Task 1）／ `doc_of(kids : Array[Node]) -> Node` / `heading(id : Int, label : String, kids : Array[Node]) -> Node` / `item(id : Int, label : String, kids : Array[Node]) -> Node` / `chain(n : Int) -> Node`（`fixture_wbtest.mbt`。T1 Task 2）
- Produces: `fn feed(o : Out, before : Bool) -> Unit` / `fn hashes(n : Int) -> String` / `fn inner_pad(nd : Node, pad : Int) -> Int` / `fn write_node(o : Out, nd : Node, depth : Int, pad : Int) -> Unit` / `fn write_children(o : Out, nd : Node, depth : Int, pad : Int) -> Unit` / `fn ser(doc : Node) -> String`（テスト側）

- [ ] **Step 1: 失敗するテストを書く**

`core/doc/serialize_wbtest.mbt` の末尾に追記:

```moonbit
///|
/// 木 1 つを LF・封筒なしの文書にして綴る。
/// 手で組む道具は fixture_wbtest.mbt のもの（doc_of / heading / item / slot / chain）を使う。
fn ser(doc : Node) -> String {
  let tree : Tree = { head: None, eol: Lf, doc, }
  serialize(tree)
}

///|
test "空ラベルの見出しにも空白 1 つを書く" {
  // C2 の綴り。`### `（空ラベル・普通のノード）。R070 R071 R090
  let md = ser(doc_of([heading(2, "r", [heading(3, "a", [heading(4, "", [])])])]))
  assert_eq(md, "# r\n\n## a\n\n### \n")
}

///|
test "リストは常に tight で、空ラベルにも空白 1 つを書く" {
  // C1 の綴り。R073 R077 R081
  let a = heading(3, "a", [item(4, "b", []), item(5, "c", []), item(6, "", [])])
  assert_eq(ser(doc_of([heading(2, "r", [a])])), "# r\n\n## a\n\n- b\n- c\n- \n")
}

///|
test "入れ子の項目は 1 段 2 スペースで字下げする" {
  // R074。項目の字下げは祖先の連続する Item の数 × nest_step
  let deep = item(4, "x", [])
  let md = ser(doc_of([item(2, "center", [item(3, "a", [deep])])]))
  assert_eq(md, "- center\n  - a\n    - x\n")
}

///|
test "implied は何も書かず、飛びだけが綴りとして残る" {
  // C6 / R026。深さ 3 の implied を挟むと `####` の飛びになる
  let gap = { ..empty(4, Heading), implied: true, children: [heading(5, "b", [])] }
  let md = ser(doc_of([heading(2, "r", [heading(3, "a", [gap])])]))
  assert_eq(md, "# r\n\n## a\n\n#### b\n")
}

///|
test "見出しの深さに上限は無く、7 個以上の # も書く" {
  // R072。lezer は段落と読むが、mmm は書く（方言表の対価）
  // chain(n) は深さ i のラベルが i.to_string()（fixture_wbtest.mbt。統合の前提 5）
  assert_eq(
    ser(doc_of([chain(7)])),
    "# 1\n\n## 2\n\n### 3\n\n#### 4\n\n##### 5\n\n###### 6\n\n####### 7\n",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: コンパイルは通り（`serialize` も `doc_of` / `heading` / `item` / `chain` も既に在る）、**値の差で落ちる**。`serialize` はまだ木を 1 ノードも書かないので、新しい 5 本すべてが空文字列 `""` と期待の md 全文の差を出す。最終行は `Total tests: N, passed: N-5, failed: 5.`（EXIT=2）。

- [ ] **Step 3: 最小の実装を書く**

`core/doc/serialize.mbt` の `join_lines` の後・`serialize` の前に追記:

```moonbit
///|
/// 単位を書く直前に呼ぶ。前後どちらかが空行を求めていれば 1 本だけ挟む。
fn feed(o : Out, before : Bool) -> Unit {
  if o.lines.length() > 0 && (o.gap || before) {
    o.lines.push("")
  }
}

///|
/// 見出しの印を n 個。深さがそのまま本数（level は木の深さそのもの）。
fn hashes(n : Int) -> String {
  repeat(heading_mark, n)
}

///|
/// 中身と子が並ぶ列。項目なら 1 段深く、見出しなら列 0。
/// 見出しに項目の祖先は無い（単調性。裁定 A — parse の `push_skel` は Heading を
/// 積む前に開いている Item を全部閉じる）ので、Heading の腕は受け取った pad を
/// 捨ててよい。統合の前提 9。
fn inner_pad(nd : Node, pad : Int) -> Int {
  match nd.form {
    Item => pad + nest_step
    Heading => 0
  }
}

///|
/// ノード 1 つ。骨格行 → 子。implied は骨格行を書かない（飛びが綴り）。
/// ラベルはそのまま書いてよい — 前後に空白のある行や末尾が `#` の連なりで終わる行は
/// setext と認定されない（T1 Task 9 の `atx_writable`。統合の前提 8）ので、
/// 書き戻した `#### label` を読み直すと必ず同じ label に戻る。逃がしは持たない。
fn write_node(o : Out, nd : Node, depth : Int, pad : Int) -> Unit {
  if is_implied(nd) {
    write_children(o, nd, depth, pad)
    return
  }
  match nd.form {
    Heading => {
      feed(o, true)
      o.lines.push(hashes(depth) + " " + nd.label)
      o.gap = true
    }
    Item => {
      feed(o, false)
      o.lines.push(indent(pad) + item_mark + " " + nd.label)
      o.gap = false
    }
  }
  write_children(o, nd, depth, pad)
}

///|
/// 子の列。
fn write_children(o : Out, nd : Node, depth : Int, pad : Int) -> Unit {
  let inner = inner_pad(nd, pad)
  for kid in nd.children {
    write_node(o, kid, depth + 1, inner)
  }
}
```

`serialize` を次の全文に差し替える:

```moonbit
///|
/// 木を正規形の md にする。
pub fn serialize(tree : Tree) -> String {
  let o : Out = { lines: [], gap: false }
  match tree.head {
    Some(h) => {
      push_text(o, 0, h)
      o.gap = true
    }
    None => ()
  }
  write_children(o, tree.doc, 0, 0)
  join_lines(o.lines, tree.eol)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
```
Expected: `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 9 本**で、そのすべてが passed に入り `failed: 0` であること）。**`Total tests: 0` を見たら `-p` の綴りを疑う。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 見出しと項目の骨格行を、飛びと空行の規律ごと書く"
```

---

## Task 22: 中身のかたまり — 逐語・飾り・画像・リンク・コード

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Modify）

**Interfaces:**
- Consumes: `feed` / `push_text` / `indent` / `inner_pad` / `write_node` / `write_children` / `repeat`（Task 20・21）／ `pub enum Block { Content(Content); Rule; Opaque(String) }` / `pub enum Content { Image(alt~, src~); Link(text~, href~); Code(info~, text~); Svg(String) }`（`tree.mbt`）／ `rule_mark` / `fence_mark` / `fence_min`（`spell.mbt`。T1 Task 1）
- Produces: `fn write_body(o : Out, body : Array[Block], pad : Int) -> Unit` / `fn write_block(o : Out, b : Block, pad : Int) -> Unit` / `fn fence_len(text : String) -> Int` / `fn write_code(o : Out, pad : Int, info : String, text : String) -> Unit`

- [ ] **Step 1: 失敗するテストを書く**

`core/doc/serialize_wbtest.mbt` の末尾に追記:

```moonbit
///|
test "散文と飾りの水平線は中身ごとノードに付いて書かれる" {
  // C5 の新 md。R081 飾りは `***`（トグルの `---` とチャンネルが違う）
  let head = {
    ..heading(4, "head", []),
    body: [Opaque("content01"), Rule, Opaque("content02")],
  }
  let md = ser(doc_of([heading(2, "r", [heading(3, "head2", [head])])]))
  assert_eq(md, "# r\n\n## head2\n\n### head\n\ncontent01\n\n***\n\ncontent02\n")
}

///|
test "リスト形ノードの中身は内側の列へ字下げし、loose を強制する" {
  // R078。段落は段落を中断できないので、md の規則が空行を強制する
  let center = { ..item(2, "center", [item(3, "a", [])]), body: [Opaque("text")] }
  assert_eq(ser(doc_of([center])), "- center\n\n  text\n\n  - a\n")
}

///|
test "画像とリンクは認定された綴りで書き戻される" {
  // R017。書き戻した綴りを読み直すと同じ値に戻る形だけが認定ブロック
  // ラベル付き引数の呼び出しは `=`（`alt~=` は Error: [3016]）
  let d = {
    ..doc_of([]),
    body: [
      Content(Image(alt="a", src="./sub/deep.png")),
      Content(Link(text="t", href="https://example.com/x")),
    ],
  }
  assert_eq(ser(d), "![a](./sub/deep.png)\n\n[t](https://example.com/x)\n")
}

///|
test "svg は逐語のまま、行ごとに字下げされる" {
  // R018 / R110。逐語の中身は 1 バイトも変えない
  let x = {
    ..item(2, "x", []),
    body: [Content(Svg("<svg>\n  <circle r=\"5\"/>\n</svg>"))],
  }
  assert_eq(ser(doc_of([x])), "- x\n\n  <svg>\n    <circle r=\"5\"/>\n  </svg>\n")
}

///|
test "逐語の中の改行も、書き出しで eol の流儀になる" {
  // R093 / 統合の前提 1。Opaque は "\n" で持ち、CRLF 文書では全行が \r\n で出る
  let d = { ..doc_of([]), body: [Opaque("one\ntwo")] }
  let tree : Tree = { head: None, eol: Crlf, doc: d }
  assert_eq(serialize(tree), "one\r\ntwo\r\n")
}

///|
test "コードは常にフェンスで書く" {
  // C9 / R088。インデントコードは読めるが書かない
  let b = { ..heading(3, "b", []), body: [Content(Code(info="", text="code"))] }
  assert_eq(ser(doc_of([heading(2, "r", [b])])), "# r\n\n## b\n\n```\ncode\n```\n")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: コンパイルは通り（`Block` / `Content` は `tree.mbt` に在る）、**値の差で落ちる**。`write_node` はまだ `body` を 1 行も書かないので、新しい 6 本すべてが「骨格行だけの md」と期待の差を出す。最終行は `Total tests: N, passed: N-6, failed: 6.`（EXIT=2）。

- [ ] **Step 3: 最小の実装を書く**

`core/doc/serialize.mbt` の `write_children` の後に追記:

```moonbit
///|
/// 中身のかたまりの列。
fn write_body(o : Out, body : Array[Block], pad : Int) -> Unit {
  for b in body {
    write_block(o, b, pad)
  }
}

///|
/// かたまり 1 つ。段落系（逐語・飾り・画像・リンク・svg）は前後に空行が要る。
/// コードだけはフェンスが段落を中断できるので tight のまま（R079）。
fn write_block(o : Out, b : Block, pad : Int) -> Unit {
  match b {
    Rule => {
      feed(o, true)
      o.lines.push(indent(pad) + rule_mark)
      o.gap = true
    }
    Opaque(text) => {
      feed(o, true)
      push_text(o, pad, text)
      o.gap = true
    }
    Content(Svg(text)) => {
      feed(o, true)
      push_text(o, pad, text)
      o.gap = true
    }
    Content(Image(alt~, src~)) => {
      feed(o, true)
      o.lines.push(indent(pad) + "![" + alt + "](" + src + ")")
      o.gap = true
    }
    Content(Link(text~, href~)) => {
      feed(o, true)
      o.lines.push(indent(pad) + "[" + text + "](" + href + ")")
      o.gap = true
    }
    Content(Code(info~, text~)) => write_code(o, pad, info, text)
  }
}

///|
/// フェンスの本数。中身に現れる最長の連なり + 1 と、最小の本数の大きい方（R089）。
fn fence_len(text : String) -> Int {
  let mark = fence_mark[0].to_int()
  let mut best = 0
  let mut run = 0
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == mark {
      run = run + 1
      if run > best {
        best = run
      }
    } else {
      run = 0
    }
  }
  if best + 1 > fence_min {
    best + 1
  } else {
    fence_min
  }
}

///|
/// コードは常にフェンス。フェンスは段落を中断できるので、前後の空行は要らない。
/// 中身が空ならフェンス 2 行だけ（空行を挟むと読み直したとき中身が改行 1 つになる）。
fn write_code(o : Out, pad : Int, info : String, text : String) -> Unit {
  let fence = repeat(fence_mark, fence_len(text))
  feed(o, false)
  o.lines.push(indent(pad) + fence + info)
  if text.length() > 0 {
    push_text(o, pad, text)
  }
  o.lines.push(indent(pad) + fence)
  o.gap = false
}
```

`write_node` を次の全文に差し替える（骨格行 → 中身 → 子の順にする）:

```moonbit
///|
/// ノード 1 つ。骨格行 → 中身 → 子。implied は骨格行を書かない（飛びが綴り）。
/// ラベルはそのまま書いてよい（`atx_writable`。統合の前提 8）。
fn write_node(o : Out, nd : Node, depth : Int, pad : Int) -> Unit {
  if is_implied(nd) {
    write_children(o, nd, depth, pad)
    return
  }
  match nd.form {
    Heading => {
      feed(o, true)
      o.lines.push(hashes(depth) + " " + nd.label)
      o.gap = true
    }
    Item => {
      feed(o, false)
      o.lines.push(indent(pad) + item_mark + " " + nd.label)
      o.gap = false
    }
  }
  write_body(o, nd.body, inner_pad(nd, pad))
  write_children(o, nd, depth, pad)
}
```

`serialize` を次の全文に差し替える（doc の body を子より先に書く）:

```moonbit
///|
/// 木を正規形の md にする。
pub fn serialize(tree : Tree) -> String {
  let o : Out = { lines: [], gap: false }
  match tree.head {
    Some(h) => {
      push_text(o, 0, h)
      o.gap = true
    }
    None => ()
  }
  write_body(o, tree.doc.body, 0)
  write_children(o, tree.doc, 0, 0)
  join_lines(o.lines, tree.eol)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
```
Expected: `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 15 本**で、そのすべてが passed に入り `failed: 0` であること）。**`Total tests: 0` を見たら `-p` の綴りを疑う。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 中身のかたまりを、逐語と飾りとコードのチャンネルを分けて書く"
```

---

## Task 23: フェンスの本数・tight・空のコードを固定する

> Task 22 で `fence_len` / `write_code` を**正しい形で**書き切ったので、このタスクは**規則の網を張る回帰タスク**である（意図的に誤った実装を入れて次で捨てる、はしない）。落ちたら Step 3 の差し替えコードで直す。

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`（落ちたときだけ）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Modify）

**Interfaces:**
- Consumes: `write_code` / `fence_len` / `write_block`（Task 22）／ `fence_mark` / `fence_min`（`spell.mbt`。T1 Task 1）／ `ser` / `doc_of` / `heading` / `item`
- Produces: 無し（T3 の綴りのうち「コード」を固定する網。T4 の法則 2 がこの出力を土台にする）

- [ ] **Step 1: テストを書く**

`core/doc/serialize_wbtest.mbt` の末尾に追記:

```moonbit
///|
test "フェンスは中身の最長の連なりより 1 本長い" {
  // R089。エスケープは serialize の責務
  let b = {
    ..heading(3, "b", []),
    body: [Content(Code(info="", text="```\nx\n```"))],
  }
  assert_eq(
    ser(doc_of([heading(2, "r", [b])])),
    "# r\n\n## b\n\n````\n```\nx\n```\n````\n",
  )
}

///|
test "フェンスは段落を中断できるので、リストの上でも tight のまま" {
  // R079。Code だけは前後の空行を要らない
  let x = {
    ..item(2, "x", [item(3, "y", [])]),
    body: [Content(Code(info="ts", text="const n = 1;"))],
  }
  assert_eq(ser(doc_of([x])), "- x\n  ```ts\n  const n = 1;\n  ```\n  - y\n")
}

///|
test "中身の無いコードはフェンス 2 行だけを書く" {
  // 空行を 1 本挟むと読み直したとき中身が改行 1 つになるので、挟まない
  let d = { ..doc_of([]), body: [Content(Code(info="", text=""))] }
  assert_eq(ser(d), "```\n```\n")
}
```

- [ ] **Step 2: テストを走らせて現状を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: 実装は Task 22 で出そろっているので `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 18 本**）になるはず。落ちた場合は最終行が `Total tests: N, passed: N-F, failed: F.`（EXIT=2）となり、`[mmm-app] test core/doc/serialize_wbtest.mbt:<行> ("<テスト名>") failed: Error` が落ちた本数ぶん出る。**テストを緩めず、Step 3 で実装を直す。**

- [ ] **Step 3: 落ちたら実装を直す（差し替えコード）**

落ち方は 3 通りしかない。該当する関数を次の全文に差し替える。

(a) **フェンスの本数が足りない／多い**（1 本目が落ちた）— `fence_len` の走り数えを次に差し替える:

```moonbit
///|
/// フェンスの本数。中身に現れる最長の連なり + 1 と、最小の本数の大きい方（R089）。
fn fence_len(text : String) -> Int {
  let mark = fence_mark[0].to_int()
  let mut best = 0
  let mut run = 0
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == mark {
      run = run + 1
      if run > best {
        best = run
      }
    } else {
      run = 0
    }
  }
  if best + 1 > fence_min {
    best + 1
  } else {
    fence_min
  }
}
```

（`run` を印以外の文字で 0 に戻し忘れると連なりが繋がって数え過ぎる。`best` の更新を `else` 側に置くと最後の連なりを取りこぼす。）

(b) **リストの上に空行が入る**（2 本目が落ちた）— `write_code` の `feed` は必ず `false` で呼ぶ:

```moonbit
///|
/// コードは常にフェンス。フェンスは段落を中断できるので、前後の空行は要らない。
/// 中身が空ならフェンス 2 行だけ（空行を挟むと読み直したとき中身が改行 1 つになる）。
fn write_code(o : Out, pad : Int, info : String, text : String) -> Unit {
  let fence = repeat(fence_mark, fence_len(text))
  feed(o, false)
  o.lines.push(indent(pad) + fence + info)
  if text.length() > 0 {
    push_text(o, pad, text)
  }
  o.lines.push(indent(pad) + fence)
  o.gap = false
}
```

（`feed(o, true)` になっていると `- x` の直後に空行が入って loose 化する。書き終わりの `o.gap = false` を忘れると次の子の前に空行が入る。）

(c) **空のコードに空行が入る**（3 本目が落ちた）— 同じ `write_code` の `if text.length() > 0` の guard が無いと、`push_text` が空文字列に対して `""` を 1 行積む。(b) の全文で直る。

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
```
Expected: `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 18 本**で、そのすべてが passed に入り `failed: 0` であること）。**`Total tests: 0` を見たら `-p` の綴りを疑う。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: ✅ フェンスの本数と tight の規則を固定する"
```

---

## Task 24: 側のトグル — 変わり目に 1 本、先頭に 1 本

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Modify）

**Interfaces:**
- Consumes: `write_children` / `inner_pad` / `feed` / `indent`（Task 21）／ `pub enum Side { Right; Left }` / `pub fn is_implied(nd : Node) -> Bool`（`tree.mbt`）／ `toggle_mark`（`spell.mbt`。T1 Task 1）／ `slot(id : Int, label : String, left : Bool) -> Node`（`fixture_wbtest.mbt`。T1 Task 2）
- Produces: `fn is_left(s : Side) -> Bool` / `fn write_toggle(o : Out, pad : Int) -> Unit`、および側を見る `write_children`

- [ ] **Step 1: 失敗するテストを書く**

`core/doc/serialize_wbtest.mbt` の末尾に追記:

```moonbit
///|
test "先頭のスロットが左なら、木の前に区切りを 1 本置く" {
  // C4 / R082。側の列 (左, 右) を一意に書く（N30 の解決）
  let r = heading(2, "r", [slot(3, "a", true), slot(4, "b", false)])
  assert_eq(ser(doc_of([r])), "# r\n\n---\n\n## a\n\n---\n\n## b\n")
}

///|
test "側が揃っていれば区切りは 1 本も書かれない" {
  // C3 / R080 R184。区切りは常に側の列から導出される帰結
  let r = heading(2, "r", [slot(3, "a", false), slot(4, "c", false)])
  assert_eq(ser(doc_of([r])), "# r\n\n## a\n\n## c\n")
}

///|
test "項目形の root の区切りは、中身の列に置かれる" {
  // C15 の書き / R058。子リストがそこで割れるので読み書き一意
  let center = item(2, "center", [
    item(3, "a", []),
    item(4, "b", []),
    { ..item(5, "c", []), side: Left },
  ])
  assert_eq(ser(doc_of([center])), "- center\n  - a\n  - b\n\n  ---\n\n  - c\n")
}

///|
test "木と木の間には区切りが立たない" {
  // R056。doc 直下の隙間は側を持たない
  let r1 = heading(2, "r1", [slot(3, "a", true)])
  let r2 = heading(4, "r2", [])
  assert_eq(ser(doc_of([r1, r2])), "# r1\n\n---\n\n## a\n\n# r2\n")
}

///|
test "段落の直後のトグルは必ず空行を挟む" {
  // R092 / §A-7 規則 10。`text` の次行に `---` を置くと setext に化けて
  // 読み直したとき見出しになる（法則 1 が破れる）。空行 1 本が安全装置
  let r = { ..heading(2, "r", [slot(3, "a", true)]), body: [Opaque("text")] }
  assert_eq(ser(doc_of([r])), "# r\n\ntext\n\n---\n\n## a\n")
}

///|
test "implied のスロットの前にはトグルが立たない" {
  // 裁定 1 / 不変条件 11。implied は側を持たないので既定の右として扱われ、
  // 先頭（手前は右）の implied には変わり目が生まれない。ここでトグルが立つと、
  // 読み直したとき直後が深さ 4 なので帰属先の骨格行が消える
  let gap2 = { ..empty(4, Heading), implied: true, children: [heading(5, "b", [])] }
  let gap = { ..empty(3, Heading), implied: true, children: [gap2] }
  assert_eq(ser(doc_of([heading(2, "r", [gap])])), "# r\n\n#### b\n")
}

///|
test "昇格したスロットは骨格行を得てから左へ回る" {
  // C16 の書き（裁定 1）。flip_side が implied を promote した後の木を綴る。
  // 空ラベルの `## ` が生え、その前にトグルが立つ
  let gap = { ..empty(4, Heading), implied: true, children: [heading(5, "b", [])] }
  let slot2 = { ..empty(3, Heading), side: Left, children: [gap] }
  assert_eq(
    ser(doc_of([heading(2, "r", [slot2])])),
    "# r\n\n---\n\n## \n\n#### b\n",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: コンパイルは通り、**値の差で落ちる**。区切りが 1 本も書かれないので、落ちるのは「先頭のスロットが左なら…」「項目形の root の区切りは…」「木と木の間には…」「段落の直後のトグルは…」「昇格したスロットは…」の **5 本**。「側が揃っていれば…」と「implied のスロットの前には…」は区切りを求めないので先に通る。最終行は `Total tests: N, passed: N-5, failed: 5.`（EXIT=2）。

- [ ] **Step 3: 最小の実装を書く**

`core/doc/serialize.mbt` の `inner_pad` の後に追記:

```moonbit
///|
/// 側が左か。
fn is_left(s : Side) -> Bool {
  s is Left
}

///|
/// 側の変わり目の 1 本。段落の直後には絶対に置かない（setext に化けるため
/// feed が必ず空行を挟む）。
fn write_toggle(o : Out, pad : Int) -> Unit {
  feed(o, true)
  o.lines.push(indent(pad) + toggle_mark)
  o.gap = true
}
```

`write_children` を次の全文に差し替える:

```moonbit
///|
/// 子の列。深さ 1（root）の子だけがスロットで、側の変わり目に区切りが立つ。
/// 先頭スロットの手前は「右から始まる」を既定とするので、左なら 1 本書かれる。
/// root が implied でも同じ — 骨格行を書かないだけで列の入れ物としては透けるので、
/// その子はやはり深さ 2 のスロットであり、ここで側を見る。
///
/// **骨格行を書かないノードの手前にトグルを立ててはいけない** — 立ってしまうと
/// 読み直したとき区切りの帰属先（深さ 2 の骨格行）が無く、飾りの水平線として
/// 読まれて法則 1 が破れる。implied は側を持てない（不変条件 11）ので既定の右と
/// して扱われ、その手前に変わり目が生まれるのは「直前のスロットが左」のときだけ。
/// 位置の制約（不変条件 8）は裁定 B で「前に見出しの兄弟が居ない」へ一般化され、
/// implied は先頭に限らなくなったので、この形を防ぐのは normalize の `spellable`
/// （T5 Task 44）の引き金「深さ 2 で、直前のスロットと側が違う implied は昇格させる」
/// だけである（統合の前提 10）。引き金を消すなら、ここに書き分けが要る。
fn write_children(o : Out, nd : Node, depth : Int, pad : Int) -> Unit {
  let inner = inner_pad(nd, pad)
  let kids = nd.children
  let mut left = false // 直前のスロットの側（先頭の手前は右）
  for i = 0; i < kids.length(); i = i + 1 {
    let kid = kids[i]
    if depth == 1 {
      let side = is_left(kid.side)
      if side != left {
        write_toggle(o, inner)
      }
      left = side
    }
    write_node(o, kid, depth + 1, inner)
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
```
Expected: `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 25 本**で、そのすべてが passed に入り `failed: 0` であること）。**`Total tests: 0` を見たら `-p` の綴りを疑う。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 側の列から区切りを導出し、先頭トグルまで一意に書く"
```

---

## Task 25: 畳み — details は骨格行の外、本文と子だけを包む

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Modify）

**Interfaces:**
- Consumes: `write_node` / `write_body` / `write_children` / `inner_pad` / `feed` / `indent`（Task 21・22）／ `fold_open` / `fold_close` / `summary_open` / `summary_close`（`spell.mbt`。T1 Task 1）
- Produces: `fn open_fold(o : Out, pad : Int, label : String) -> Unit` / `fn close_fold(o : Out, pad : Int) -> Unit`、および畳みを包む `write_node`

- [ ] **Step 1: 失敗するテストを書く**

`core/doc/serialize_wbtest.mbt` の末尾に追記:

```moonbit
///|
test "畳みは骨格行の外に置かれ、本文と子だけを包む" {
  // C8 / R083 R084 R085。summary は毎回 label から作り直す装飾
  let a = { ..heading(3, "a", [heading(4, "b", [])]), folded: true }
  assert_eq(
    ser(doc_of([heading(2, "r", [a])])),
    "# r\n\n## a\n\n<details>\n<summary>a</summary>\n\n### b\n\n</details>\n",
  )
}

///|
test "内側の畳みは吸収されず、そのまま入れ子になる" {
  // C8 / R087。details はネスト可能（HTML コメントと違う）
  let b = { ..heading(4, "b", [heading(5, "c", [])]), folded: true }
  let a = { ..heading(3, "a", [b]), folded: true }
  assert_eq(
    ser(doc_of([heading(2, "r", [a])])),
    "# r\n\n## a\n\n<details>\n<summary>a</summary>\n\n### b\n\n<details>\n<summary>b</summary>\n\n#### c\n\n</details>\n\n</details>\n",
  )
}

///|
test "項目形の畳みは中身の列まで字下げする" {
  // 追補予定 2（Item form ノードの fold）の綴りを、本文の規則から決める
  let x = { ..item(2, "x", [item(3, "y", [])]), folded: true }
  assert_eq(
    ser(doc_of([x])),
    "- x\n\n  <details>\n  <summary>x</summary>\n\n  - y\n\n  </details>\n",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: コンパイルは通り、**値の差で落ちる**。`folded` がまだ読まれず `<details>` が 1 行も出ないので、新しい 3 本すべてが落ちる。最終行は `Total tests: N, passed: N-3, failed: 3.`（EXIT=2）。

- [ ] **Step 3: 最小の実装を書く**

`core/doc/serialize.mbt` の `write_toggle` の後に追記:

```moonbit
///|
/// 畳みを開く。summary は label から毎回作り直す装飾（真実は骨格行）。
fn open_fold(o : Out, pad : Int, label : String) -> Unit {
  feed(o, true)
  o.lines.push(indent(pad) + fold_open)
  o.lines.push(indent(pad) + summary_open + label + summary_close)
  o.gap = true
}

///|
/// 畳みを閉じる。
fn close_fold(o : Out, pad : Int) -> Unit {
  feed(o, true)
  o.lines.push(indent(pad) + fold_close)
  o.gap = true
}
```

`write_node` を次の全文に差し替える:

```moonbit
///|
/// ノード 1 つ。骨格行 → 畳みの開き → 中身 → 子 → 畳みの閉じ。
/// implied は骨格行を書かない（飛びが綴り。不変条件より中身も畳みも側も持たない）。
/// ラベルはそのまま書いてよい（`atx_writable`。統合の前提 8）。
fn write_node(o : Out, nd : Node, depth : Int, pad : Int) -> Unit {
  if is_implied(nd) {
    write_children(o, nd, depth, pad)
    return
  }
  match nd.form {
    Heading => {
      feed(o, true)
      o.lines.push(hashes(depth) + " " + nd.label)
      o.gap = true
    }
    Item => {
      feed(o, false)
      o.lines.push(indent(pad) + item_mark + " " + nd.label)
      o.gap = false
    }
  }
  let inner = inner_pad(nd, pad)
  if nd.folded {
    open_fold(o, inner, nd.label)
  }
  write_body(o, nd.body, inner)
  write_children(o, nd, depth, pad)
  if nd.folded {
    close_fold(o, inner)
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
```
Expected: `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 28 本**で、そのすべてが passed に入り `failed: 0` であること）。**`Total tests: 0` を見たら `-p` の綴りを疑う。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 畳みを details で書き、骨格行を外に出して入れ子を保つ"
```

---

## Task 26: 正規形の全文を固定する（C9・C11・C5・C17 と深さ 200）

> Task 20〜25 で規則は出そろっている。このタスクは**カタログのケースで全文を焼き込む回帰の網**であり、落ちたら Step 3 の差し替えコードで直す（**テストは 1 文字も緩めない**）。

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt`（落ちたときだけ）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt`（Modify）

**Interfaces:**
- Consumes: `serialize`（Task 20〜25 の全規則）／ `hashes`（Task 21）／ `ser`（Task 21）／ `doc_of` / `heading` / `item` / `slot` / `chain` / `empty`（`fixture_wbtest.mbt` と `tree.mbt`）
- Produces: `fn nl_count(s : String) -> Int`（テスト側の物差し。§C-3 の T3 所有名）

- [ ] **Step 1: テストを書く**

`core/doc/serialize_wbtest.mbt` の末尾に追記:

```moonbit
///|
/// 改行の数（= 行数）。深い木で全文を目で比べずに済ませるための物差し。
fn nl_count(s : String) -> Int {
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == 10 {
      n = n + 1
    }
  }
  n
}

///|
test "format は setext も閉じ # もインデントコードも正規形に均す" {
  // C9 の新 md。意味は 1 ビットも変わらず、form にも触らない
  let b = { ..heading(4, "b", []), body: [Content(Code(info="", text="code"))] }
  let md = ser(doc_of([heading(2, "r", [heading(3, "a", []), b])]))
  assert_eq(md, "# r\n\n## a\n\n## b\n\n```\ncode\n```\n")
}

///|
test "封筒の後・木の前に先頭トグルが書かれる" {
  // C11 / R200。frontmatter の `---` と衝突しない（封筒の内側は隙間ではない）
  let tree : Tree = {
    head: Some("---\nimage-folder: img\n---"),
    eol: Lf,
    doc: doc_of([heading(2, "r", [slot(3, "a", true)])]),
  }
  assert_eq(serialize(tree), "---\nimage-folder: img\n---\n\n# r\n\n---\n\n## a\n")
}

///|
test "動かした先の深さで書かれ、散文は中身ごと付いてくる" {
  // C5 の新 md。level は木の深さそのものなので付け直しが要らない
  let head = {
    ..heading(4, "head", []),
    body: [Opaque("content01"), Rule, Opaque("content02")],
  }
  let head2 = heading(3, "head2", [head])
  assert_eq(
    ser(doc_of([heading(2, "r", [head2])])),
    "# r\n\n## head2\n\n### head\n\ncontent01\n\n***\n\ncontent02\n",
  )
}

///|
test "C17 項目 root のあとの見出しは、implied root の木として書き戻される" {
  // 裁定 A / R039 R042 R057。md では見出しがリストを終わらせるので、parse は
  // 開いている項目を全部閉じてから implied root を立てる（木が 2 本になる）。
  // serialize はその木を `- a` + 空行 + `## h` に戻す（往復して同じ木になる）。
  // implied root の子は深さ 2 のスロットなので、右のままなら区切りは立たない
  let gap = { ..empty(3, Heading), implied: true, children: [heading(4, "h", [])] }
  assert_eq(ser(doc_of([item(2, "a", []), gap])), "- a\n\n## h\n")
}

///|
test "深さ 200 の一本鎖も再帰で書き切る" {
  // 木が真の再帰型になったので反復に落とす理由は無い。deep.md が見張り
  let md = ser(doc_of([chain(200)]))
  assert_eq(nl_count(md), 399)
}

///|
test "深さ 200 の見出しは # を 200 個書く" {
  // R072。深さに上限を設けない設計の見張り
  let md = ser(doc_of([chain(200)]))
  assert_eq(md.contains(hashes(200) + " 200\n"), true)
}
```

- [ ] **Step 2: テストを走らせて現状を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `nl_count` は Step 1 で定義したのでコンパイルは通り、規則が出そろっているので `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 34 本**）になるはず。落ちた場合は `Total tests: N, passed: N-F, failed: F.`（EXIT=2）で、`[mmm-app] test core/doc/serialize_wbtest.mbt:<行> ("<テスト名>") failed: Error` が出る。**期待値は緩めず Step 3 で直す。**

- [ ] **Step 3: 落ちたら実装を直す（差し替えコード）**

落ち先は `serialize.mbt` の中の 3 か所しかない（**操作側の場合分けは 1 つも増やさない** — 増やしたくなったら設計が死につつある合図）。

(a) **空行が多い／少ない** — `feed` の判定を次の全文に差し替える（空行は「直前が後ろに求めている」か「これから書く単位が前に求めている」ときに **1 本だけ**。文書の先頭には絶対に置かない）:

```moonbit
///|
/// 単位を書く直前に呼ぶ。前後どちらかが空行を求めていれば 1 本だけ挟む。
fn feed(o : Out, before : Bool) -> Unit {
  if o.lines.length() > 0 && (o.gap || before) {
    o.lines.push("")
  }
}
```

呼ぶ側の `before` と書いた後の `o.gap` は次で固定する（Heading は前後とも要る／Item は前後とも要らない／段落系は前後とも要る／Code は前後とも要らない）:

| 単位 | `feed` の `before` | 書いた後の `o.gap` |
|---|---|---|
| 見出しの骨格行 | `true` | `true` |
| 項目の骨格行 | `false` | `false` |
| `Rule` / `Opaque` / `Svg` / `Image` / `Link` | `true` | `true` |
| コード（`write_code`） | `false` | `false` |
| トグル / `<details>` / `</details>` | `true` | `true` |

(b) **区切りが余る／足りない** — `write_children` を次の全文に差し替える:

```moonbit
///|
/// 子の列。深さ 1（root）の子だけがスロットで、側の変わり目に区切りが立つ。
/// 先頭スロットの手前は「右から始まる」を既定とするので、左なら 1 本書かれる。
/// root が implied でも同じ（骨格行を書かないだけで、その子は深さ 2 のスロット）。
///
/// **骨格行を書かないノードの手前にトグルを立ててはいけない**。implied は側を
/// 持てない（不変条件 11）ので既定の右として扱われ、手前に変わり目が生まれるのは
/// 「直前のスロットが左」のときだけ。その形を防ぐのは normalize の `spellable`
/// （T5 Task 44）の引き金であって、位置の制約ではない（裁定 B で implied は
/// 先頭に限らなくなった。統合の前提 10）。
fn write_children(o : Out, nd : Node, depth : Int, pad : Int) -> Unit {
  let inner = inner_pad(nd, pad)
  let kids = nd.children
  let mut left = false // 直前のスロットの側（先頭の手前は右）
  for i = 0; i < kids.length(); i = i + 1 {
    let kid = kids[i]
    if depth == 1 {
      let side = is_left(kid.side)
      if side != left {
        write_toggle(o, inner)
      }
      left = side
    }
    write_node(o, kid, depth + 1, inner)
  }
}
```

（`depth == 1` は「自分が root（深さ 1）で、子が深さ 2 のスロット」の意味。`depth == 2` にすると木と木の間に区切りが立つ。`left` の持ち回りを忘れると変わり目が二重に立つ。C17 の implied root も深さ 1 なので、ここを `!is_implied(nd) && depth == 1` に狭めると、implied root の下のスロットが左でも区切りが書かれず法則 1 が破れる。）

(c) **字下げが合わない** — `inner_pad` を次の全文に差し替える:

```moonbit
///|
/// 中身と子が並ぶ列。項目なら 1 段深く、見出しなら列 0。
/// 見出しに項目の祖先は無い（単調性。裁定 A の `push_skel` が Heading を積む前に
/// 開いている Item を全部閉じる）ので、Heading の腕は受け取った pad を捨ててよい。
fn inner_pad(nd : Node, pad : Int) -> Int {
  match nd.form {
    Item => pad + nest_step
    Heading => 0
  }
}
```

（`Heading => pad` にすると、項目の領土の中に見出しを書いたときだけ字下げが残る。裁定 A より Heading に Item の祖先は無いので、見出しの中身の列は常に 0。）

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt --check doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core check doc
```
Expected:
- テスト: `Total tests: N, passed: N, failed: 0.`（**T3 の担当分は累計 34 本**。**`Total tests: 0` を見たら `-p` の綴りを疑う**）
- `fmt doc`: 整形を当てて EXIT=0。**掲載コードは折り返し前の姿なので差分が出るのが正常であり、展開後の姿でコミットする**
- `fmt --check doc`: 差分なしで `Finished. moon: ran <n> tasks, now up to date`（EXIT=0）。差分があると `git diff` の色付き出力 + `Error: failed when formatting project` で **EXIT=127**
- `check doc`: `Finished. moon: ran <n> tasks, now up to date (<n> warnings, 0 errors)`（EXIT=0）。未使用の警告は可、**エラーは 0**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/serialize_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: ✅ 正規形の全文をカタログのケースで固定する"
```

---

## T3 完了時に他タスクへ渡るもの

- **`pub fn serialize(tree : Tree) -> String`** — T4 の法則 1・2（`format_of` / `law_wbtest.mbt`）と T5 の `reflect` が土台にする、唯一の書き手
- `fence_len` / `hashes` / `indent` / `repeat` / `push_text` / `join_lines` — 同じパッケージ内の道具（T5 の `diff` が行を扱うときに再利用してよい。**再定義しないこと**）
- **綴りの帰結として他タスクが守るもの**:
  - **parse は `<summary>` 行を落とす**（T1 Task 9 / T2）。落とさないと、serialize が毎回 label から書き直す `<summary>` が二重になって法則 1 が破れる
  - **逐語（head / `Opaque` / `Code.text` / `Svg`）に `\r` を入れない・末尾改行を付けない**（T1 Task 7・8）。serialize は逐語を 1 バイトも直さないので、`\r` が居残れば法則 2 が破れる
  - **`- - -` は飾りの水平線 = `Block::Rule`**（裁定 2。T1 Task 6 で実装済み）。serialize は `Rule` を必ず `rule_mark`（`***`）で書く
  - **見出しの label は ATX で書き戻せる形に限る**（T1 Task 9 の `atx_writable`。裁定 D で追加）。前後空白や末尾 `#` を持つ行を setext と認定すると、serialize は `##   leading` / `## trailing  ` を書き、読み直しで label が変わって法則 1・2 が同時に破れる。**serialize 側にラベルの逃がしは無い**
  - **深さ 2 の implied の直前に、側が左のスロットを置かない**（T5 Task 44 の `spellable` の 4 つ目の引き金）。裁定 B で implied の位置が「先頭」から「前に見出しの兄弟が居ない」へ広がったので、骨格行を書かないノードの手前にトグルが立つ形を防いでいるのはこの引き金だけである（統合の前提 10）
  - **単調性は parse の attach で守る**（裁定 A。T2 Task 13 の `push_skel`）。`- a` + `## h` は `doc.children = [a(Item), implied(1)[h]]` になる。serialize はこの木を C17 のテストで固定しており、Heading の中身の列が常に 0 であることの根拠もここにある

## T3 が綴りについて決めた 2 点（変えるなら書き換える前に全員へ共有すること）

1. **`<summary>` を書く。** 仕様 §4（R085・R086）に従った。カタログ C8 の md には summary が現れないが、C8 の map（`c 〔畳〕`）と md（details が `#### c` を包む = 畳んでいるのは b）自体が食い違っており、カタログ側が仕様に追いついていないと判断した。**5 人とも仕様とカタログは書き換えない**ので、この判断は T3 の実装とテストの中でだけ効く
2. **項目形ノードの畳みは、骨格行の後に空行 1 本を挟んで中身の列に `<details>` を書く**（追補予定 2 の未ケース化部分）。本文の規則（畳みは中身の列・段落系は前後に空行）から導いた形であり、新しい規則を足していない
